import 'package:flutter_test/flutter_test.dart';
import 'package:notas/data/note_ics.dart';
import 'package:notas/data/notes_repository.dart';
import 'package:notas/models/note.dart';
import 'package:notas/ui/format.dart';
import 'package:notas/ui/i18n.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final _now = DateTime(2030, 3, 10, 12);

String _cal(String body) =>
    'BEGIN:VCALENDAR\r\nVERSION:2.0\r\n$body\r\nEND:VCALENDAR\r\n';

String _ev(String uid, String lines) =>
    'BEGIN:VEVENT\r\nUID:$uid\r\n$lines\r\nEND:VEVENT';

IcsEvent _one(String lines) {
  final f = parseIcs(_cal(_ev('a', lines)), now: _now);
  expect(f.events, hasLength(1));
  return f.events.single;
}

Note _note(String id, String text, DateTime? remind, DateTime? due) {
  final t = DateTime.utc(2030, 1, 1);
  return Note(
      id: id,
      content: text,
      createdAt: t,
      updatedAt: t,
      remindAt: remind?.toUtc(),
      dueAt: due?.toUtc());
}

void main() {
  setUp(() {
    appLanguage.code = 'es';
    SharedPreferences.setMockInitialValues({});
  });

  group('importar', () {
    test('un evento de un día es una nota de un solo día', () {
      final e = _one('DTSTART:20300315T100000\r\nDTEND:20300315T110000\r\n'
          r'SUMMARY:Peluquería\, centro');
      expect(e.content, 'Peluquería, centro');
      expect(e.dueAt, DateTime(2030, 3, 15, 10).toUtc());
      expect(e.remindAt, DateTime(2030, 3, 15).toUtc());
    });

    test('día completo: DTEND es exclusivo', () {
      final one = _one('DTSTART;VALUE=DATE:20300315\r\n'
          'DTEND;VALUE=DATE:20300316\r\nSUMMARY:Festivo');
      expect(one.remindAt, DateTime(2030, 3, 15).toUtc());
      expect(one.dueAt, DateTime(2030, 3, 15, 23, 59).toUtc());
      final three = _one('DTSTART;VALUE=DATE:20300315\r\n'
          'DTEND;VALUE=DATE:20300318\r\nSUMMARY:Viaje');
      expect(three.dueAt, DateTime(2030, 3, 17, 23, 59).toUtc());
    });

    test('varios días es un periodo, también con DURATION', () {
      final e = _one('DTSTART:20300315T100000Z\r\nDURATION:P2DT1H\r\nSUMMARY:X');
      expect(e.remindAt, DateTime.utc(2030, 3, 15, 10));
      expect(e.dueAt, DateTime.utc(2030, 3, 17, 11));
    });

    test('respeta la zona horaria del evento', () {
      final e = _one('DTSTART;TZID=America/New_York:20300701T120000\r\n'
          'DTEND;TZID=America/New_York:20300703T120000\r\nSUMMARY:NY');
      expect(e.remindAt, DateTime.utc(2030, 7, 1, 16));
    });

    test('líneas plegadas, texto escapado y alarmas', () {
      final e = _one('DTSTART:20300315T100000\r\nSUMMARY:Reunión la\r\n rga\r\n'
          r'DESCRIPTION:uno\ndos\;tres'
          '\r\nBEGIN:VALARM\r\nDESCRIPTION:alarma\r\nSUMMARY:mal\r\nEND:VALARM');
      expect(e.content, 'Reunión larga\nuno\ndos;tres');
    });

    test('omite pasados, cancelados, inválidos y excepciones', () {
      final f = parseIcs(
          _cal([
            _ev('p', 'DTSTART:20200101T100000\r\nSUMMARY:Pasado'),
            _ev('c', 'DTSTART:20300401T100000\r\nSTATUS:CANCELLED'),
            _ev('i', 'DTSTART:20301399T100000\r\nSUMMARY:Mal'),
            _ev('r', 'DTSTART:20300401T100000\r\nRECURRENCE-ID:20300401T100000'),
            _ev('ok', 'DTSTART:20300401T100000\r\nSUMMARY:Bien'),
          ].join('\r\n')),
          now: _now);
      expect(f.events.map((e) => e.uid), ['ok']);
      expect(f.skipped, 4);
    });

    test('una serie antigua salta a la próxima fecha', () {
      final e = _one('DTSTART:20200106T090000\r\nDTEND:20200106T100000\r\n'
          'RRULE:FREQ=WEEKLY;BYDAY=MO\r\nSUMMARY:Clase');
      expect(e.repeat, 'weekly');
      expect(e.dueAt, DateTime(2030, 3, 11, 9).toUtc());
    });

    test('una regla sin equivalente pierde la repetición y lo avisa', () {
      final f = parseIcs(
          _cal(_ev('a',
              'DTSTART:20300401T100000\r\nRRULE:FREQ=WEEKLY;INTERVAL=2\r\nSUMMARY:X')),
          now: _now);
      expect(f.events.single.repeat, isNull);
      expect(f.simplified, 1);
    });

    test('rechaza lo que no es un calendario', () {
      expect(() => parseIcs('hola'), throwsFormatException);
    });
  });

  group('exportar', () {
    test('ida y vuelta conserva el día, el periodo y la repetición', () {
      final due = DateTime(2030, 3, 15, 23, 30);
      final single = _note('s', 'Peluquería, centro\nCorte; barba',
          Note.dayStart(due), due)
        ..repeat = 'weekdays';
      final period = _note('p', 'Proyecto', DateTime(2030, 3, 12, 9),
          DateTime(2030, 3, 20, 18));
      final f = parseIcs(notesToIcs([single, period]), now: _now);
      expect(f.events, hasLength(2));
      final a = f.events[0], b = f.events[1];
      expect(a.content, single.content);
      expect(a.dueAt, single.dueAt);
      expect(a.remindAt, single.remindAt);
      expect(a.repeat, 'weekdays');
      expect(b.remindAt, period.remindAt);
      expect(b.dueAt, period.dueAt);
    });

    test('no saca Vault, hechas ni notas sin fecha', () {
      final due = DateTime(2030, 3, 15);
      final ics = notesToIcs([
        _note('v', 'SecretoVault', null, due)..vault = true,
        _note('d', 'Hecha', null, due)..done = true,
        _note('n', 'SinFecha', null, null),
      ]);
      expect(ics, isNot(contains('VEVENT')));
    });

    test('ninguna línea pasa de 75 bytes y usa CRLF', () {
      final ics = notesToIcs([
        _note('l', 'ñ' * 200, null, DateTime(2030, 3, 15)),
      ]);
      final lines = ics.split('\r\n');
      expect(lines.every((l) => l.codeUnits.length <= 75), isTrue);
      expect(ics.replaceAll('\r\n', ''), isNot(contains('\n')));
      expect(parseIcs(ics, now: _now).events.single.content, 'ñ' * 200);
    });
  });

  group('repositorio', () {
    NotesRepository repo(String user) => NotesRepository(
        SupabaseClient('http://127.0.0.1:9', 'clave-de-prueba',
            authOptions: const AuthClientOptions(autoRefreshToken: false)),
        user)
      ..loaded = true;

    test('reimportar no duplica ni pisa lo editado', () {
      final r = repo('demo');
      final f = parseIcs(
          _cal(_ev('a', 'DTSTART:20300401T100000\r\nSUMMARY:Cita')),
          now: _now);
      expect(r.importEvents(f.events), (added: 1, existing: 0));
      final n = r.allActive.single;
      expect(n.color, isNotNull);
      expect(n.ownerId, 'demo');
      r.updateContent(n.id, 'Cita editada');
      expect(r.importEvents(f.events), (added: 0, existing: 1));
      expect(r.allActive.single.content, 'Cita editada');
      r.dispose();
    });

    test('los eventos solo salen en el calendario', () {
      final r = repo('demo');
      final future = DateTime.now().add(const Duration(days: 2));
      final day = '${future.year}${future.month.toString().padLeft(2, '0')}'
          '${future.day.toString().padLeft(2, '0')}';
      final f = parseIcs(_cal(_ev('clase', 'DTSTART:${day}T100000\r\nSUMMARY:Clase')));
      r.importEvents(f.events);
      final normal = r.createNote(dueAt: future.toUtc());
      r.updateContent(normal.id, 'Tarea');
      final event = r.allActive.firstWhere((n) => n.isCalendarEvent);
      expect(r.notes.map((n) => n.id), [normal.id]);
      expect(r.temporales.map((n) => n.id), [normal.id]);
      expect(r.calendarItems.map((n) => n.id), containsAll([event.id, normal.id]));
      expect(normal.isCalendarEvent, isFalse);
      r.dispose();
    });

    test('borrar todo va a la papelera, se deshace y respeta el Vault', () {
      final r = repo('demo');
      final a = r.createNote();
      final v = r.createNote();
      r.updateContent(a.id, 'Normal');
      r.updateContent(v.id, 'Secreta');
      r.setVault(v.id, true);
      final f = parseIcs(
          _cal(_ev('e', 'DTSTART:20300401T100000\r\nSUMMARY:Clase')),
          now: _now);
      r.importEvents(f.events);
      final ids = r.deleteAllNotes();
      expect(ids, hasLength(2));
      expect(r.notes, isEmpty);
      expect(r.calendarItems, isEmpty);
      expect(r.byId(v.id)!.deleted, isFalse);
      // Reimportar devuelve los eventos que estaban en la papelera.
      expect(r.importEvents(f.events), (added: 1, existing: 0));
      for (final id in ids) {
        r.restore(id);
      }
      expect(r.byId(a.id)!.deleted, isFalse);
      r.dispose();
    });

    test('todo el día: sin hora y conserva el día al exportar', () {
      final day = DateTime(2030, 3, 15);
      final n = _note('a', 'Examen', Note.dayStart(day), Note.dayEnd(day));
      expect(n.isAllDay, isTrue);
      expect(n.isSingleDay, isTrue);
      expect(fechaNota(n), isNot(contains(':')));
      final ics = notesToIcs([n]);
      expect(ics, contains('DTSTART;VALUE=DATE:20300315'));
      expect(ics, contains('DTEND;VALUE=DATE:20300316'));
      final e = parseIcs(ics, now: _now).events.single;
      expect(e.dueAt, n.dueAt);
      expect(e.remindAt, n.remindAt);
      final timed =
          _note('b', 'Cita', Note.dayStart(day), DateTime(2030, 3, 15, 10));
      expect(timed.isAllDay, isFalse);
      expect(fechaNota(timed), contains('10:00'));
    });

    test('el mismo evento tiene otro id en otra cuenta', () {
      expect(icsNoteId('a', 'x'), isNot(icsNoteId('b', 'x')));
      expect(icsNoteId('a', 'x'), icsNoteId('a', 'x'));
      expect(
          icsNoteId('a', 'x'),
          matches(RegExp(
              r'^[0-9a-f]{8}-[0-9a-f]{4}-5[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$')));
    });
  });
}
