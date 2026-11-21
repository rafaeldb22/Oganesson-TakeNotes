import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../data/notes_repository.dart';
import '../data/reminders.dart';
import 'anim.dart';
import 'format.dart';
import 'theme.dart';
import 'urgency.dart';
import 'i18n.dart';

/// Hoja para poner las fechas de una nota temporal: un calendario pequeño
/// para marcar el día de inicio y el de fin, y una rueda para la hora.
Future<void> showScheduleSheet(
    BuildContext context, NotesRepository repo, String noteId,
    {DateTime? initialDue}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    constraints: const BoxConstraints(maxWidth: 520),
    builder: (_) =>
        _ScheduleSheet(repo: repo, noteId: noteId, initialDue: initialDue),
  );
}

enum _Edge { start, end }

DateTime _d(DateTime x) => DateTime(x.year, x.month, x.day);

/// Redondea a múltiplos de 5 min (lo exige la rueda de la hora).
DateTime _round5(DateTime x) {
  final m = (x.minute / 5).round() * 5;
  return DateTime(x.year, x.month, x.day, x.hour).add(Duration(minutes: m));
}

class _ScheduleSheet extends StatefulWidget {
  const _ScheduleSheet(
      {required this.repo, required this.noteId, this.initialDue});
  final NotesRepository repo;
  final String noteId;
  final DateTime? initialDue;

  @override
  State<_ScheduleSheet> createState() => _ScheduleSheetState();
}

class _ScheduleSheetState extends State<_ScheduleSheet> {
  late DateTime _start; // local
  late DateTime _end; // local
  _Edge _editing = _Edge.end;
  late DateTime _month;

  @override
  void initState() {
    super.initState();
    final n = widget.repo.byId(widget.noteId);
    final now = DateTime.now();
    _start = _round5(n?.remindAt?.toLocal() ?? now);
    _end = _round5(n?.dueAt?.toLocal() ??
        widget.initialDue ??
        DateTime(now.year, now.month, now.day + 1, 20));
    if (_end.isBefore(_start)) _end = _start.add(const Duration(hours: 1));
    _month = DateTime(_end.year, _end.month);
  }

  DateTime get _current => _editing == _Edge.start ? _start : _end;

  void _setCurrent(DateTime v) {
    setState(() {
      if (_editing == _Edge.start) {
        _start = v;
        if (_end.isBefore(_start)) _end = _start.add(const Duration(hours: 1));
      } else {
        _end = v;
        if (_end.isBefore(_start)) _start = _end;
      }
    });
  }

  void _pickDay(DateTime day) {
    final c = _current;
    _setCurrent(DateTime(day.year, day.month, day.day, c.hour, c.minute));
    // Tras elegir el inicio, pasamos directamente a elegir el fin.
    if (_editing == _Edge.start) setState(() => _editing = _Edge.end);
  }

  void _save() {
    widget.repo.setSchedule(widget.noteId, remindAt: _start, dueAt: _end);
    Reminders.instance.askPermission();
    Navigator.pop(context);
  }

  void _clear() {
    widget.repo.setSchedule(widget.noteId, remindAt: null, dueAt: null);
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final hadSchedule = widget.repo.byId(widget.noteId)?.dueAt != null;
    final accent = Palette.accent(context);

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(tr('Fechas'),
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
            const SizedBox(height: 14),
            // Inicio / fin: tocar uno para editarlo.
            Row(
              children: [
                Expanded(
                  child: _EdgeCard(
                    label: tr('Empieza'),
                    icon: Icons.play_arrow_rounded,
                    value: _start,
                    active: _editing == _Edge.start,
                    color: fuseStops.first,
                    onTap: () => setState(() {
                      _editing = _Edge.start;
                      _month = DateTime(_start.year, _start.month);
                    }),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Icon(Icons.arrow_forward_rounded,
                      size: 18, color: Palette.secondary(context)),
                ),
                Expanded(
                  child: _EdgeCard(
                    label: tr('Termina'),
                    icon: Icons.flag_rounded,
                    value: _end,
                    active: _editing == _Edge.end,
                    color: fuseStops.last,
                    onTap: () => setState(() {
                      _editing = _Edge.end;
                      _month = DateTime(_end.year, _end.month);
                    }),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            _MiniCalendar(
              month: _month,
              start: _d(_start),
              end: _d(_end),
              accent: accent,
              onMonth: (m) => setState(() => _month = m),
              onPick: _pickDay,
            ),
            const SizedBox(height: 10),
            _TimeWheel(
              key: ValueKey(_editing),
              value: _current,
              onChanged: (t) => _setCurrent(DateTime(_current.year,
                  _current.month, _current.day, t.hour, t.minute)),
            ),
            const SizedBox(height: 14),
            _Preview(start: _start, end: _end),
            const SizedBox(height: 14),
            Row(
              children: [
                if (hadSchedule)
                  TextButton.icon(
                    onPressed: _clear,
                    style: TextButton.styleFrom(
                        foregroundColor: Palette.secondary(context)),
                    icon: const Icon(Icons.event_busy_outlined, size: 18),
                    label: Text(tr('Quitar fechas')),
                  ),
                const Spacer(),
                Bouncy(
                  child: FilledButton(
                    onPressed: _save,
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 26, vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                    ),
                    child: Text(tr('Guardar'),
                        style: TextStyle(fontWeight: FontWeight.w700)),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _EdgeCard extends StatelessWidget {
  const _EdgeCard({
    required this.label,
    required this.icon,
    required this.value,
    required this.active,
    required this.color,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final DateTime value;
  final bool active;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final d = value;
    final fecha = '${d.day} ${tr(mesesNombre[d.month - 1]).substring(0, 3)}';
    final hora = '${d.hour}:${d.minute.toString().padLeft(2, '0')}';
    return Bouncy(
      pressedScale: 0.97,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: Anim.medium,
          curve: Anim.curve,
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
          decoration: BoxDecoration(
            color: active
                ? color.withValues(alpha: 0.12)
                : Palette.background(context),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
                color: active ? color : Colors.transparent, width: 1.5),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(icon, size: 15, color: color),
                  const SizedBox(width: 4),
                  Text(label.toUpperCase(),
                      style: TextStyle(
                          fontSize: 10.5,
                          letterSpacing: 1,
                          fontWeight: FontWeight.w700,
                          color: Palette.secondary(context))),
                ],
              ),
              const SizedBox(height: 6),
              Text(fecha,
                  style: const TextStyle(
                      fontSize: 17, fontWeight: FontWeight.w800)),
              Text(hora,
                  style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: active ? color : Palette.secondary(context))),
            ],
          ),
        ),
      ),
    );
  }
}

/// Calendario compacto con el rango inicio→fin resaltado.
class _MiniCalendar extends StatelessWidget {
  const _MiniCalendar({
    required this.month,
    required this.start,
    required this.end,
    required this.accent,
    required this.onMonth,
    required this.onPick,
  });

  final DateTime month;
  final DateTime start;
  final DateTime end;
  final Color accent;
  final void Function(DateTime) onMonth;
  final void Function(DateTime) onPick;

  @override
  Widget build(BuildContext context) {
    final range = calendarRange();
    final firstMonth = DateTime(range.first.year, range.first.month);
    final lastMonth = DateTime(range.last.year, range.last.month);
    final canPrev = month.isAfter(firstMonth);
    final canNext = month.isBefore(lastMonth);
    final first = DateTime(month.year, month.month, 1);
    final gridStart = first.subtract(Duration(days: first.weekday - 1));
    final today = _d(DateTime.now());
    final name = tr(mesesNombre[month.month - 1]);
    final dias = diasIniciales;
    final rangeColor = accent.withValues(alpha: 0.14);

    return Container(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
      decoration: BoxDecoration(
        color: Palette.background(context),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        children: [
          Row(
            children: [
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '${name[0].toUpperCase()}${name.substring(1)} ${month.year}',
                  style: const TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w700),
                ),
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                onPressed: canPrev
                    ? () => onMonth(DateTime(month.year, month.month - 1))
                    : null,
                icon: const Icon(Icons.chevron_left),
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                onPressed: canNext
                    ? () => onMonth(DateTime(month.year, month.month + 1))
                    : null,
                icon: const Icon(Icons.chevron_right),
              ),
            ],
          ),
          Row(
            children: [
              for (final d in dias)
                Expanded(
                  child: Center(
                    child: Text(d,
                        style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: Palette.secondary(context))),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 4),
          for (var w = 0; w < 6; w++)
            Row(
              children: [
                for (var i = 0; i < 7; i++)
                  Expanded(
                    child: Builder(builder: (context) {
                      final day = DateTime(gridStart.year, gridStart.month,
                          gridStart.day + w * 7 + i);
                      final inMonth = day.month == month.month;
                      final inWindow = !day.isBefore(_d(range.first)) &&
                          !day.isAfter(_d(range.last));
                      final isStart = day == start;
                      final isEnd = day == end;
                      final inRange = !day.isBefore(start) && !day.isAfter(end);
                      final edge = isStart || isEnd;
                      return GestureDetector(
                        onTap: inWindow ? () => onPick(day) : null,
                        child: SizedBox(
                          height: 38,
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              // Franja del rango (une inicio y fin).
                              if (inRange && start != end)
                                Positioned.fill(
                                  top: 5,
                                  bottom: 5,
                                  left: isStart ? 19 : 0,
                                  right: isEnd ? 19 : 0,
                                  child: ColoredBox(color: rangeColor),
                                ),
                              AnimatedContainer(
                                duration: Anim.fast,
                                width: 32,
                                height: 32,
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  color: edge ? accent : Colors.transparent,
                                  shape: BoxShape.circle,
                                  border: day == today && !edge
                                      ? Border.all(color: accent, width: 1.2)
                                      : null,
                                ),
                                child: Text(
                                  '${day.day}',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: edge || day == today
                                        ? FontWeight.w800
                                        : FontWeight.w500,
                                    color: edge
                                        ? Palette.of(context).onAccent
                                        : (!inWindow
                                            ? Palette.secondary(context)
                                                .withValues(alpha: 0.25)
                                            : (inMonth
                                                ? null
                                                : Palette.secondary(context)
                                                    .withValues(alpha: 0.5))),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

/// Selector de hora tipo rueda (24 h, de 5 en 5 minutos).
class _TimeWheel extends StatelessWidget {
  const _TimeWheel({super.key, required this.value, required this.onChanged});
  final DateTime value;
  final void Function(DateTime) onChanged;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final fg = dark ? Colors.white : const Color(0xFF111111);
    return Container(
      height: 128,
      decoration: BoxDecoration(
        color: Palette.background(context),
        borderRadius: BorderRadius.circular(18),
      ),
      child: CupertinoTheme(
        data: CupertinoThemeData(
          brightness: dark ? Brightness.dark : Brightness.light,
          textTheme: CupertinoTextThemeData(
            dateTimePickerTextStyle:
                TextStyle(fontSize: 22, fontWeight: FontWeight.w600, color: fg),
          ),
        ),
        child: CupertinoDatePicker(
          mode: CupertinoDatePickerMode.time,
          use24hFormat: true,
          minuteInterval: 5,
          initialDateTime: _round5(value),
          onDateTimeChanged: onChanged,
        ),
      ),
    );
  }
}

/// Vista previa de la mecha con las fechas elegidas.
class _Preview extends StatelessWidget {
  const _Preview({required this.start, required this.end});
  final DateTime start;
  final DateTime end;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final total = end.difference(start).inSeconds;
    final p = total <= 0
        ? 1.0
        : (now.difference(start).inSeconds / total).clamp(0.0, 1.0);
    final dur = end.difference(start);
    final durTxt = dur.inDays >= 1
        ? '${dur.inDays} d ${dur.inHours % 24} h'
        : '${dur.inHours} h ${dur.inMinutes % 60} min';
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: Palette.background(context),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(tiempoRestante(end.toUtc()),
                  style: TextStyle(
                      color: fuseColor(p), fontWeight: FontWeight.w700)),
              const Spacer(),
              Text(trf('dura {0}', [durTxt]),
                  style: TextStyle(
                      color: Palette.secondary(context), fontSize: 12.5)),
            ],
          ),
          const SizedBox(height: 6),
          FuseBar(progress: p, height: 7, spark: p > 0 && p < 1),
        ],
      ),
    );
  }
}
