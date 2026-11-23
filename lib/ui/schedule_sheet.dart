import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../data/notes_repository.dart';
import '../data/recurrence.dart';
import '../data/reminders.dart';
import '../models/note.dart';
import 'anim.dart';
import 'format.dart';
import 'smooth_scroll.dart';
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
    useSafeArea: true,
    isScrollControlled: true,
    constraints: BoxConstraints(
        maxWidth: 520, maxHeight: MediaQuery.sizeOf(context).height * 0.9),
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
  final _scroll = SmoothScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  late DateTime _start; // local
  late DateTime _end; // local
  _Edge _editing = _Edge.end;
  late DateTime _month;
  String? _repeat;
  bool _oneDay = false;
  bool _allDay = true;

  @override
  void initState() {
    super.initState();
    final n = widget.repo.byId(widget.noteId);
    _repeat = n?.repeat;
    _oneDay = n?.isSingleDay ?? false;
    // Sin hora clave salvo que la nota ya tenga una hora exacta.
    _allDay = n?.dueAt == null || n!.isAllDay;
    final now = DateTime.now();
    if (_allDay) {
      _start = _d(n?.remindAt?.toLocal() ?? now);
      _end = _d(n?.dueAt?.toLocal() ??
          widget.initialDue ??
          DateTime(now.year, now.month, now.day + 1));
      if (_end.isBefore(_start)) _start = _end;
    } else {
      _start = _round5(n?.remindAt?.toLocal() ?? now);
      _end = _round5(n!.dueAt!.toLocal());
      if (_end.isBefore(_start)) _end = _start.add(const Duration(hours: 1));
    }
    // Redondear puede pasar la hora al día siguiente.
    if (_oneDay) _start = _d(_end);
    _month = DateTime(_end.year, _end.month);
  }

  DateTime get _current => _editing == _Edge.start ? _start : _end;

  void _setCurrent(DateTime v) {
    setState(() {
      if (_editing == _Edge.start) {
        _start = v;
        if (_end.isBefore(_start)) {
          _end = _allDay ? _start : _start.add(const Duration(hours: 1));
        }
      } else {
        _end = v;
        if (_oneDay) {
          _start = _d(_end);
        } else if (_end.isBefore(_start)) {
          _start = _end;
        }
      }
    });
  }

  void _setOneDay(bool on) {
    setState(() {
      _oneDay = on;
      if (on) {
        _editing = _Edge.end;
        _start = _d(_end);
        _month = DateTime(_end.year, _end.month);
      } else {
        final now = _allDay ? _d(DateTime.now()) : _round5(DateTime.now());
        _start = now.isBefore(_end) ? now : _end;
      }
    });
  }

  void _setAllDay(bool on) {
    setState(() {
      _allDay = on;
      if (on) {
        _start = _d(_start);
        _end = _d(_end);
        if (_end.isBefore(_start)) _start = _end;
      } else {
        // Hora por defecto al pasar a una hora exacta.
        _end = DateTime(_end.year, _end.month, _end.day, 20);
      }
    });
  }

  DateTime get _savedStart => _allDay ? _d(_start) : _start;
  DateTime get _savedEnd => _allDay ? Note.dayEnd(_end) : _end;

  void _pickDay(DateTime day) {
    final c = _current;
    _setCurrent(DateTime(day.year, day.month, day.day, c.hour, c.minute));
    // Tras elegir el inicio, pasamos directamente a elegir el fin.
    if (_editing == _Edge.start) setState(() => _editing = _Edge.end);
  }

  void _save() {
    widget.repo
        .setSchedule(widget.noteId, remindAt: _savedStart, dueAt: _savedEnd);
    widget.repo.setRepeat(widget.noteId, _repeat);
    Reminders.instance.askPermission();
    Navigator.pop(context);
  }

  void _clear() {
    widget.repo.setSchedule(widget.noteId, remindAt: null, dueAt: null);
    widget.repo.setRepeat(widget.noteId, null);
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final hadSchedule = widget.repo.byId(widget.noteId)?.dueAt != null;
    final accent = Palette.accent(context);

    return SafeArea(
      child: SingleChildScrollView(
        controller: _scroll,
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(tr('Fechas'),
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(tr('Solo ese día')),
              subtitle: Text(tr('Sin barra hasta ese día y con un solo aviso')),
              value: _oneDay,
              onChanged: _setOneDay,
            ),
            SwitchListTile(
              key: const ValueKey('todo-el-dia'),
              contentPadding: EdgeInsets.zero,
              title: Text(tr('Todo el día')),
              subtitle: Text(tr('Desactívalo para poner una hora exacta')),
              value: _allDay,
              onChanged: _setAllDay,
            ),
            const SizedBox(height: 6),
            // Inicio / fin: tocar uno para editarlo.
            Row(
              children: [
                if (!_oneDay) ...[
                  Expanded(
                    child: _EdgeCard(
                      label: tr('Empieza'),
                      icon: Icons.play_arrow_rounded,
                      value: _start,
                      allDay: _allDay,
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
                ],
                Expanded(
                  child: _EdgeCard(
                    label: _oneDay ? tr('Día') : tr('Termina'),
                    icon: Icons.flag_rounded,
                    value: _end,
                    allDay: _allDay,
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
            const SizedBox(height: 12),
            _Presets(onPick: (day) {
              setState(() {
                _editing = _Edge.end;
                _month = DateTime(day.year, day.month);
              });
              _pickDay(day);
            }),
            const SizedBox(height: 12),
            _MiniCalendar(
              month: _month,
              start: _d(_start),
              end: _d(_end),
              accent: accent,
              onMonth: (m) => setState(() => _month = m),
              onPick: _pickDay,
            ),
            if (!_allDay) ...[
              const SizedBox(height: 10),
              _TimeWheel(
                key: ValueKey(_editing),
                value: _current,
                onChanged: (t) => _setCurrent(DateTime(_current.year,
                    _current.month, _current.day, t.hour, t.minute)),
              ),
            ],
            if (!_oneDay) ...[
              const SizedBox(height: 14),
              _Preview(start: _savedStart, end: _savedEnd),
            ],
            const SizedBox(height: 12),
            Text(tr('Repetir'),
                style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: Palette.secondary(context))),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                for (final (id, label) in <(String?, String)>[
                  (null, tr('Nunca')),
                  (RepeatRule.daily.id, tr('Cada día')),
                  (RepeatRule.weekdays.id, tr('Laborables')),
                  (RepeatRule.weekly.id, tr('Cada semana')),
                  (RepeatRule.monthly.id, tr('Cada mes')),
                  (RepeatRule.yearly.id, tr('Cada año')),
                ])
                  ChoiceChip(
                    label: Text(label),
                    selected: _repeat == id,
                    showCheckmark: false,
                    onSelected: (_) => setState(() => _repeat = id),
                  ),
              ],
            ),
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
    required this.allDay,
    required this.active,
    required this.color,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final DateTime value;
  final bool allDay;
  final bool active;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final d = value;
    final fecha = '${d.day} ${tr(mesesNombre[d.month - 1]).substring(0, 3)}';
    final hora = allDay
        ? tr('Todo el día')
        : '${d.hour}:${d.minute.toString().padLeft(2, '0')}';
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

/// Calendario compacto con el rango inicio→fin resaltado: los días
/// reaccionan al pasar el ratón, el cambio de mes se desliza y la franja del
/// rango tiene los extremos redondeados.
class _MiniCalendar extends StatefulWidget {
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
  State<_MiniCalendar> createState() => _MiniCalendarState();
}

class _MiniCalendarState extends State<_MiniCalendar> {
  DateTime? _hover;
  int _direction = 1; // 1 = mes siguiente, -1 = anterior

  @override
  void didUpdateWidget(_MiniCalendar old) {
    super.didUpdateWidget(old);
    if (old.month != widget.month) {
      _direction = widget.month.isAfter(old.month) ? 1 : -1;
    }
  }

  Widget _navButton(IconData icon, VoidCallback? onTap, String tip) {
    final p = Palette.of(context);
    return Tooltip(
      message: tip,
      child: Material(
        color: Colors.transparent,
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(6),
            child: Icon(icon,
                size: 20,
                color: onTap == null
                    ? p.secondary.withValues(alpha: 0.3)
                    : p.secondary),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final month = widget.month;
    final range = calendarRange();
    final firstMonth = DateTime(range.first.year, range.first.month);
    final lastMonth = DateTime(range.last.year, range.last.month);
    final canPrev = month.isAfter(firstMonth);
    final canNext = month.isBefore(lastMonth);
    final name = tr(mesesNombre[month.month - 1]);

    return Container(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
      decoration: BoxDecoration(
        color: p.background,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        children: [
          Row(
            children: [
              const SizedBox(width: 6),
              Expanded(
                child: AnimatedSwitcher(
                  duration: Anim.medium,
                  transitionBuilder: (c, a) => FadeTransition(
                    opacity: a,
                    child: SlideTransition(
                      position: Tween(
                              begin: Offset(0.15 * _direction, 0),
                              end: Offset.zero)
                          .animate(a),
                      child: c,
                    ),
                  ),
                  layoutBuilder: (cur, prev) => Stack(
                      alignment: Alignment.centerLeft,
                      children: [...prev, if (cur != null) cur]),
                  child: Text(
                    '${name[0].toUpperCase()}${name.substring(1)} ${month.year}',
                    key: ValueKey(month),
                    style: const TextStyle(
                        fontSize: 15.5, fontWeight: FontWeight.w800),
                  ),
                ),
              ),
              _navButton(
                  Icons.chevron_left_rounded,
                  canPrev
                      ? () =>
                          widget.onMonth(DateTime(month.year, month.month - 1))
                      : null,
                  tr('Mes anterior')),
              _navButton(
                  Icons.chevron_right_rounded,
                  canNext
                      ? () =>
                          widget.onMonth(DateTime(month.year, month.month + 1))
                      : null,
                  tr('Mes siguiente')),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              for (final (i, d) in diasIniciales.indexed)
                Expanded(
                  child: Center(
                    child: Text(d,
                        style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: p.secondary
                                .withValues(alpha: i >= 5 ? 0.6 : 1))),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 4),
          ClipRect(
            child: AnimatedSwitcher(
              duration: Anim.medium,
              switchInCurve: Anim.curve,
              switchOutCurve: Curves.easeIn,
              transitionBuilder: (c, a) {
                final incoming = c.key == ValueKey(month);
                return FadeTransition(
                  opacity: a,
                  child: SlideTransition(
                    position: Tween(
                      begin: Offset((incoming ? 0.25 : -0.25) * _direction, 0),
                      end: Offset.zero,
                    ).animate(a),
                    child: c,
                  ),
                );
              },
              layoutBuilder: (cur, prev) =>
                  Stack(children: [...prev, if (cur != null) cur]),
              child: KeyedSubtree(
                key: ValueKey(month),
                child: _grid(context, month, range),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _grid(BuildContext context, DateTime month,
      ({DateTime first, DateTime last}) range) {
    final p = Palette.of(context);
    final accent = widget.accent;
    final start = widget.start;
    final end = widget.end;
    final first = DateTime(month.year, month.month, 1);
    final gridStart = first.subtract(Duration(days: first.weekday - 1));
    final today = _d(DateTime.now());
    final rangeColor = accent.withValues(alpha: 0.14);

    Widget cell(DateTime day, int column) {
      final inMonth = day.month == month.month;
      final inWindow =
          !day.isBefore(_d(range.first)) && !day.isAfter(_d(range.last));
      final isStart = day == start;
      final isEnd = day == end;
      final inRange = !day.isBefore(start) && !day.isAfter(end);
      final edge = isStart || isEnd;
      final hover = _hover == day && inWindow && !edge;
      // La franja se redondea en los extremos del rango y al principio y
      // fin de cada semana.
      final roundLeft = isStart || column == 0;
      final roundRight = isEnd || column == 6;
      return MouseRegion(
        cursor: inWindow ? SystemMouseCursors.click : SystemMouseCursors.basic,
        onEnter: (_) => setState(() => _hover = day),
        onExit: (_) {
          if (_hover == day) setState(() => _hover = null);
        },
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: inWindow ? () => widget.onPick(day) : null,
          child: SizedBox(
            height: 40,
            child: Stack(
              alignment: Alignment.center,
              children: [
                if (inRange && start != end)
                  Positioned.fill(
                    top: 4,
                    bottom: 4,
                    left: isStart ? 6 : 0,
                    right: isEnd ? 6 : 0,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: rangeColor,
                        borderRadius: BorderRadius.horizontal(
                          left: Radius.circular(roundLeft ? 16 : 0),
                          right: Radius.circular(roundRight ? 16 : 0),
                        ),
                      ),
                    ),
                  ),
                AnimatedScale(
                  scale: hover ? 1.08 : 1,
                  duration: Anim.fast,
                  curve: Anim.curve,
                  child: AnimatedContainer(
                    duration: Anim.fast,
                    curve: Anim.curve,
                    width: 32,
                    height: 32,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: edge
                          ? accent
                          : (hover
                              ? accent.withValues(alpha: 0.16)
                              : Colors.transparent),
                      shape: BoxShape.circle,
                      border: day == today && !edge
                          ? Border.all(color: accent, width: 1.3)
                          : null,
                      boxShadow: edge
                          ? [
                              BoxShadow(
                                color: accent.withValues(alpha: 0.35),
                                blurRadius: 8,
                                offset: const Offset(0, 2),
                              )
                            ]
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
                            ? p.onAccent
                            : (!inWindow
                                ? p.secondary.withValues(alpha: 0.25)
                                : (inMonth
                                    ? null
                                    : p.secondary.withValues(alpha: 0.5))),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Column(
      children: [
        for (var w = 0; w < 6; w++)
          Row(
            children: [
              for (var i = 0; i < 7; i++)
                Expanded(
                  child: cell(
                      DateTime(gridStart.year, gridStart.month,
                          gridStart.day + w * 7 + i),
                      i),
                ),
            ],
          ),
      ],
    );
  }
}

/// Atajos para la fecha de fin: hoy, mañana, en una semana, en un mes.
class _Presets extends StatelessWidget {
  const _Presets({required this.onPick});
  final void Function(DateTime day) onPick;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final now = DateTime.now();
    final presets = [
      (tr('Hoy'), DateTime(now.year, now.month, now.day)),
      (tr('Mañana'), DateTime(now.year, now.month, now.day + 1)),
      (tr('En una semana'), DateTime(now.year, now.month, now.day + 7)),
      (tr('En un mes'), DateTime(now.year, now.month + 1, now.day)),
    ];
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final (label, day) in presets)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Bouncy(
                pressedScale: 0.94,
                child: ActionChip(
                  label: Text(label),
                  avatar: Icon(Icons.bolt_rounded, size: 16, color: p.accent),
                  shape: StadiumBorder(side: BorderSide(color: p.separator)),
                  backgroundColor: p.background,
                  onPressed: () => onPick(day),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Selector de hora tipo rueda (24 h, de 5 en 5 minutos). Dos columnas
/// que giran sin fin; con la rueda del ratón el giro se anima suavemente
/// en vez de saltar.
class _TimeWheel extends StatefulWidget {
  const _TimeWheel({super.key, required this.value, required this.onChanged});
  final DateTime value;
  final void Function(DateTime) onChanged;

  @override
  State<_TimeWheel> createState() => _TimeWheelState();
}

class _TimeWheelState extends State<_TimeWheel> {
  static const _itemExtent = 40.0;
  late final FixedExtentScrollController _hours;
  late final FixedExtentScrollController _minutes;

  @override
  void initState() {
    super.initState();
    final v = _round5(widget.value);
    // Índices lejos del 0 para poder girar hacia arriba sin tope.
    _hours = FixedExtentScrollController(initialItem: 24 * 50 + v.hour);
    _minutes =
        FixedExtentScrollController(initialItem: 12 * 50 + v.minute ~/ 5);
  }

  @override
  void dispose() {
    _hours.dispose();
    _minutes.dispose();
    super.dispose();
  }

  void _emit() {
    final h = _hours.selectedItem % 24;
    final m = (_minutes.selectedItem % 12) * 5;
    final v = widget.value;
    widget.onChanged(DateTime(v.year, v.month, v.day, h, m));
  }

  Widget _column(FixedExtentScrollController c, int count, int step) {
    final fg = Theme.of(context).colorScheme.onSurface;
    return _SmoothWheel(
      controller: c,
      child: ListWheelScrollView.useDelegate(
        controller: c,
        itemExtent: _itemExtent,
        diameterRatio: 1.6,
        perspective: 0.004,
        squeeze: 1.05,
        physics: const FixedExtentScrollPhysics(),
        onSelectedItemChanged: (_) => _emit(),
        childDelegate: ListWheelChildLoopingListDelegate(
          children: [
            for (var i = 0; i < count; i++)
              Center(
                child: Text((i * step).toString().padLeft(2, '0'),
                    style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w600,
                        fontFeatures: const [FontFeature.tabularFigures()],
                        color: fg)),
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Container(
      height: 136,
      decoration: BoxDecoration(
        color: p.background,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Franja de la hora elegida.
          Container(
            height: _itemExtent,
            margin: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: p.accent.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          Row(
            children: [
              const Spacer(),
              SizedBox(width: 70, child: _column(_hours, 24, 1)),
              Text(':',
                  style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      color: p.secondary)),
              SizedBox(width: 70, child: _column(_minutes, 12, 5)),
              const Spacer(),
            ],
          ),
        ],
      ),
    );
  }
}

/// Recoge la rueda del ratón sobre una columna y la gira con animación
/// (los pasos seguidos se acumulan), en vez del salto por defecto.
class _SmoothWheel extends StatefulWidget {
  const _SmoothWheel({required this.controller, required this.child});
  final FixedExtentScrollController controller;
  final Widget child;

  @override
  State<_SmoothWheel> createState() => _SmoothWheelState();
}

class _SmoothWheelState extends State<_SmoothWheel> {
  int? _target;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        widget.child,
        // Encima de la rueda para recibir el evento antes que ella (los
        // arrastres siguen llegando a la rueda).
        Positioned.fill(
          child: Listener(
            behavior: HitTestBehavior.translucent,
            onPointerSignal: (e) {
              if (e is! PointerScrollEvent) return;
              GestureBinding.instance.pointerSignalResolver.register(e, (ev) {
                final dy = (ev as PointerScrollEvent).scrollDelta.dy;
                if (dy == 0) return;
                final c = widget.controller;
                final from = _target ?? c.selectedItem;
                final target = from + (dy > 0 ? 1 : -1);
                _target = target;
                c
                    .animateToItem(target,
                        duration: const Duration(milliseconds: 320),
                        curve: Curves.easeOutCubic)
                    .whenComplete(() {
                  if (_target == target) _target = null;
                });
              });
            },
          ),
        ),
      ],
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
    final durTxt = duracionTexto(dur);
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
              if (dur.inMinutes > 0)
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
