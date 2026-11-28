import 'dart:convert';

import 'package:cryptography/dart.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../models/note.dart';
import '../ui/i18n.dart';
import 'recurrence.dart';

/// Máximo de eventos que se importan de un archivo.
const icsMaxEvents = 2000;

/// Evento de un `.ics` ya convertido a las fechas de una nota.
class IcsEvent {
  IcsEvent({
    required this.uid,
    required this.content,
    required this.remindAt,
    required this.dueAt,
    this.repeat,
  });

  final String uid;
  final String content;
  final DateTime remindAt;
  final DateTime dueAt;
  final String? repeat;
}

class IcsFile {
  IcsFile(this.events, this.skipped, this.simplified);
  final List<IcsEvent> events;

  /// Eventos pasados, cancelados, inválidos o por encima del máximo.
  final int skipped;

  /// Eventos importados sin repetición porque su regla no existe en la app.
  final int simplified;
}

/// Id estable por cuenta: reimportar no duplica, y dos cuentas con el mismo
/// archivo no chocan en la clave primaria de `notes`.
String icsNoteId(String userId, String uid) {
  final b = const DartSha256()
      .hashSync(utf8.encode('oganesson-ics|$userId|$uid'))
      .bytes
      .sublist(0, 16);
  b[6] = (b[6] & 0x0f) | 0x50;
  b[8] = (b[8] & 0x3f) | 0x80;
  final h = b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
  return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-'
      '${h.substring(16, 20)}-${h.substring(20)}';
}

// ------------------------------------------------------------------ exportar

/// Notas que salen en el calendario. El Vault nunca sale.
List<Note> calendarNotes(Iterable<Note> notes) => notes
    .where((n) =>
        n.isTemporal &&
        !n.isEmpty &&
        !n.vault &&
        !n.done &&
        !n.deleted &&
        !n.archived)
    .toList();

String notesToIcs(Iterable<Note> notes) {
  final out = <String>[
    'BEGIN:VCALENDAR',
    'VERSION:2.0',
    'PRODID:-//Oganesson//TakeNotes//ES',
    'CALSCALE:GREGORIAN',
  ];
  for (final n in calendarNotes(notes)) {
    final due = n.dueAt!;
    final String from, to;
    if (n.isAllDay) {
      final last = due.toLocal();
      from = 'DTSTART;VALUE=DATE:${_date((n.remindAt ?? due).toLocal())}';
      // En los `.ics` el fin de un día completo es exclusivo.
      to = 'DTEND;VALUE=DATE:'
          '${_date(DateTime(last.year, last.month, last.day + 1))}';
    } else {
      final punctual = n.isSingleDay || n.remindAt == null;
      final start = punctual ? due : n.periodStart;
      var end = due;
      if (punctual || !end.isAfter(start)) {
        // Sin pasar de medianoche, para que al reimportar siga siendo de un día.
        final d = start.toLocal();
        final midnight = DateTime(d.year, d.month, d.day + 1).toUtc();
        final hour = start.add(const Duration(hours: 1));
        end = hour.isAfter(midnight) ? midnight : hour;
      }
      from = 'DTSTART:${_stamp(start)}';
      to = 'DTEND:${_stamp(end)}';
    }
    final text = n.content.replaceAll('￼', '').trim();
    final cut = text.indexOf('\n');
    final details = cut < 0 ? '' : text.substring(cut + 1).trim();
    final rule = _toRrule(n.repeat);
    out.addAll([
      'BEGIN:VEVENT',
      'UID:${n.id}@oganesson',
      'DTSTAMP:${_stamp(n.updatedAt)}',
      from,
      to,
      'SUMMARY:${_escape(n.title)}',
      if (details.isNotEmpty) 'DESCRIPTION:${_escape(details)}',
      if (rule != null) 'RRULE:$rule',
      'END:VEVENT',
    ]);
  }
  out.add('END:VCALENDAR');
  return '${out.map(_fold).join('\r\n')}\r\n';
}

String? _toRrule(String? repeat) => switch (RepeatRule.parse(repeat)) {
      RepeatRule.daily => 'FREQ=DAILY',
      RepeatRule.weekdays => 'FREQ=WEEKLY;BYDAY=MO,TU,WE,TH,FR',
      RepeatRule.weekly => 'FREQ=WEEKLY',
      RepeatRule.monthly => 'FREQ=MONTHLY',
      RepeatRule.yearly => 'FREQ=YEARLY',
      null => null,
    };

String _stamp(DateTime t) {
  final u = t.toUtc();
  String p(int v, [int w = 2]) => v.toString().padLeft(w, '0');
  return '${p(u.year, 4)}${p(u.month)}${p(u.day)}'
      'T${p(u.hour)}${p(u.minute)}${p(u.second)}Z';
}

String _date(DateTime d) => '${d.year.toString().padLeft(4, '0')}'
    '${d.month.toString().padLeft(2, '0')}${d.day.toString().padLeft(2, '0')}';

String _escape(String s) => s
    .replaceAll(r'\', r'\\')
    .replaceAll(';', r'\;')
    .replaceAll(',', r'\,')
    .replaceAll(RegExp(r'\r?\n'), r'\n');

/// Las líneas de un `.ics` no pueden pasar de 75 bytes.
String _fold(String line) {
  final out = StringBuffer();
  var used = 0;
  for (final r in line.runes) {
    final c = String.fromCharCode(r);
    final size = utf8.encode(c).length;
    if (used + size > 75) {
      out.write('\r\n ');
      used = 1;
    }
    out.write(c);
    used += size;
  }
  return out.toString();
}

// ------------------------------------------------------------------ importar

class _Prop {
  _Prop(this.value, this.params);
  final String value;
  final Map<String, String> params;
}

class _Time {
  _Time(this.at, this.allDay);
  final DateTime at;
  final bool allDay;
}

/// Lanza [FormatException] si el texto no es un calendario.
IcsFile parseIcs(String text, {DateTime? now}) {
  final src = text.startsWith('﻿') ? text.substring(1) : text;
  if (!src.toUpperCase().contains('BEGIN:VCALENDAR')) {
    throw const FormatException('not a calendar');
  }
  final at = now ?? DateTime.now();
  final events = <IcsEvent>[];
  var skipped = 0, simplified = 0;
  Map<String, _Prop>? current;
  var depth = 0;

  for (final line
      in src.replaceAll(RegExp(r'\r?\n[ \t]'), '').split(RegExp(r'\r?\n'))) {
    final upper = line.trim().toUpperCase();
    if (current == null) {
      if (upper == 'BEGIN:VEVENT') {
        current = {};
        depth = 0;
      }
      continue;
    }
    if (upper == 'END:VEVENT') {
      final e = events.length < icsMaxEvents ? _event(current, at) : null;
      if (e == null) {
        skipped++;
      } else {
        events.add(e.$1);
        if (e.$2) simplified++;
      }
      current = null;
    } else if (upper.startsWith('BEGIN:')) {
      depth++; // VALARM y similares tienen su propio SUMMARY/DESCRIPTION.
    } else if (upper.startsWith('END:')) {
      depth--;
    } else if (depth == 0) {
      final p = _parseLine(line);
      if (p != null) current.putIfAbsent(p.$1, () => p.$2);
    }
  }
  return IcsFile(events, skipped, simplified);
}

(String, _Prop)? _parseLine(String line) {
  var quoted = false, colon = -1;
  final cuts = <int>[];
  for (var i = 0; i < line.length; i++) {
    final c = line[i];
    if (c == '"') quoted = !quoted;
    if (quoted) continue;
    if (c == ';') cuts.add(i);
    if (c == ':') {
      colon = i;
      break;
    }
  }
  if (colon <= 0) return null;
  final nameEnd = cuts.isEmpty ? colon : cuts.first;
  final params = <String, String>{};
  for (var i = 0; i < cuts.length; i++) {
    final end = i + 1 < cuts.length ? cuts[i + 1] : colon;
    final part = line.substring(cuts[i] + 1, end);
    final eq = part.indexOf('=');
    if (eq > 0) {
      params[part.substring(0, eq).toUpperCase()] =
          part.substring(eq + 1).replaceAll('"', '');
    }
  }
  return (
    line.substring(0, nameEnd).toUpperCase(),
    _Prop(line.substring(colon + 1).trim(), params)
  );
}

/// El evento y si ha perdido su repetición. null = no se importa.
(IcsEvent, bool)? _event(Map<String, _Prop> p, DateTime now) {
  if (p.containsKey('RECURRENCE-ID') ||
      p['STATUS']?.value.toUpperCase() == 'CANCELLED') {
    return null;
  }
  final startProp = p['DTSTART'];
  final first = startProp == null ? null : _time(startProp);
  if (first == null) return null;
  final allDay = first.allDay;
  var start = first.at;

  var end = p['DTEND'] == null ? null : _time(p['DTEND']!)?.at;
  if (end == null && p['DURATION'] != null) {
    final d = _duration(p['DURATION']!.value);
    if (d != null) end = _plus(start, d, allDay);
  }
  end ??= allDay ? DateTime(start.year, start.month, start.day + 1) : start;
  if (end.isBefore(start)) end = start;
  if (allDay && !end.isAfter(start)) {
    end = DateTime(start.year, start.month, start.day + 1);
  }

  final rrule = p['RRULE']?.value;
  final repeat = rrule == null ? null : _repeatOf(rrule, start.toLocal());
  final rule = RepeatRule.parse(repeat);
  final span = end.difference(start);
  if (!end.isAfter(now)) {
    if (rule == null) return null;
    start = rule.next(start.toLocal(), after: now.subtract(span));
    end = _plus(start, span, allDay);
  }

  final DateTime remind, due;
  if (allDay) {
    final days = (span.inHours + 12) ~/ 24;
    remind = DateTime(start.year, start.month, start.day);
    due = DateTime(start.year, start.month, start.day + days - 1, 23, 59);
  } else {
    final last =
        end.isAfter(start) ? end.subtract(const Duration(seconds: 1)) : start;
    if (Note.dayStart(last) == Note.dayStart(start)) {
      remind = Note.dayStart(start);
      due = start.isAfter(now) ? start : end; // Ya empezado: vence al acabar.
    } else {
      remind = start;
      due = end;
    }
  }

  final title = _clip(_unescape(p['SUMMARY']?.value ?? ''), 300);
  final place = _clip(_unescape(p['LOCATION']?.value ?? ''), 300);
  final details = _clip(_unescape(p['DESCRIPTION']?.value ?? ''), 20000);
  final content = [
    title.isEmpty ? tr('Evento sin título') : title,
    if (place.isNotEmpty) place,
    if (details.isNotEmpty) details,
  ].join('\n');
  final uid = p['UID']?.value;
  return (
    IcsEvent(
      uid: uid == null || uid.isEmpty
          ? '${first.at.toUtc().toIso8601String()}|$title'
          : uid,
      content: content,
      remindAt: remind.toUtc(),
      dueAt: due.toUtc(),
      repeat: repeat,
    ),
    rrule != null && repeat == null
  );
}

/// Los eventos de día completo se suman por días para no moverse con el
/// cambio de hora.
DateTime _plus(DateTime t, Duration d, bool allDay) {
  if (!allDay) return t.add(d);
  return DateTime(t.year, t.month, t.day + (d.inHours + 12) ~/ 24);
}

String _clip(String s, int max) {
  final t = s.replaceAll('￼', '').trim();
  return t.length <= max ? t : t.substring(0, max);
}

String _unescape(String s) => s.replaceAllMapped(RegExp(r'\\([\\;,nN])'), (m) {
      final c = m[1]!;
      return c == 'n' || c == 'N' ? '\n' : c;
    });

_Time? _time(_Prop p) {
  final v = p.value.toUpperCase();
  final date = RegExp(r'^(\d{4})(\d{2})(\d{2})$').firstMatch(v);
  if (date != null) {
    final y = int.parse(date[1]!), m = int.parse(date[2]!);
    final d = int.parse(date[3]!);
    final t = DateTime(y, m, d);
    return t.month == m && t.day == d ? _Time(t, true) : null;
  }
  final full = RegExp(r'^(\d{4})(\d{2})(\d{2})T(\d{2})(\d{2})(\d{2})(Z?)$')
      .firstMatch(v);
  if (full == null) return null;
  final n = [for (var i = 1; i <= 6; i++) int.parse(full[i]!)];
  final check = DateTime.utc(n[0], n[1], n[2], n[3], n[4], n[5]);
  if (check.month != n[1] ||
      check.day != n[2] ||
      check.hour != n[3] ||
      check.minute != n[4]) {
    return null;
  }
  if (full[7] == 'Z') return _Time(check, false);
  final zone = _location(p.params['TZID']);
  // shortcut: un TZID que no es IANA (Outlook) se lee como hora local; añadir
  // el mapa de zonas de Windows si llegan calendarios de otros países.
  return _Time(
      zone == null
          ? DateTime(n[0], n[1], n[2], n[3], n[4], n[5]).toUtc()
          : tz.TZDateTime(zone, n[0], n[1], n[2], n[3], n[4], n[5]).toUtc(),
      false);
}

var _zonesReady = false;

tz.Location? _location(String? id) {
  if (id == null || id.isEmpty) return null;
  if (!_zonesReady) {
    tzdata.initializeTimeZones();
    _zonesReady = true;
  }
  try {
    return tz.getLocation(id);
  } catch (_) {
    return null;
  }
}

Duration? _duration(String v) {
  final m = RegExp(
          r'^\+?P(?:(\d+)W)?(?:(\d+)D)?(?:T(?:(\d+)H)?(?:(\d+)M)?(?:(\d+)S)?)?$')
      .firstMatch(v.toUpperCase());
  if (m == null) return null;
  int n(int i) => int.tryParse(m[i] ?? '') ?? 0;
  return Duration(
      days: n(1) * 7 + n(2), hours: n(3), minutes: n(4), seconds: n(5));
}

/// Regla de la app equivalente a un RRULE. null = no tiene equivalente.
String? _repeatOf(String rrule, DateTime start) {
  final p = <String, String>{};
  for (final part in rrule.toUpperCase().split(';')) {
    final eq = part.indexOf('=');
    if (eq > 0) p[part.substring(0, eq)] = part.substring(eq + 1);
  }
  const allowed = {'FREQ', 'INTERVAL', 'WKST', 'BYDAY', 'BYMONTHDAY'};
  if (p.keys.any((k) => !allowed.contains(k))) return null;
  if ((p['INTERVAL'] ?? '1') != '1') return null;
  final freq = p['FREQ'];
  final days = p['BYDAY']?.split(',').toSet();
  final monthDay = p['BYMONTHDAY'];
  if (days != null && freq != 'WEEKLY') return null;
  if (monthDay != null && (freq != 'MONTHLY' || monthDay != '${start.day}')) {
    return null;
  }
  const codes = ['MO', 'TU', 'WE', 'TH', 'FR', 'SA', 'SU'];
  switch (freq) {
    case 'DAILY':
      return RepeatRule.daily.id;
    case 'WEEKLY':
      if (days == null ||
          (days.length == 1 && days.first == codes[start.weekday - 1])) {
        return RepeatRule.weekly.id;
      }
      final work = codes.sublist(0, 5).toSet();
      return days.length == 5 &&
              days.containsAll(work) &&
              start.weekday <= DateTime.friday
          ? RepeatRule.weekdays.id
          : null;
    case 'MONTHLY':
      return RepeatRule.monthly.id;
    case 'YEARLY':
      return RepeatRule.yearly.id;
  }
  return null;
}
