import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../models/note.dart';
import 'anim.dart';
import 'format.dart';
import 'i18n.dart';
import 'smooth_scroll.dart';
import 'theme.dart';
import 'urgency.dart';

DateTime _d(DateTime x) => DateTime(x.year, x.month, x.day);

/// Color de una nota en el calendario (el suyo o el de su mecha).
Color calendarColor(BuildContext context, Note n) => n.done
    ? Palette.secondary(context)
    : (n.color != null
        ? Color(n.color!)
        : fuseForTheme(context, notePalette(n)).first);

bool _activeOn(Note n, DateTime day) {
  final s = _d(n.periodStart.toLocal());
  final e = _d(n.dueAt!.toLocal());
  return !day.isBefore(s) && !day.isAfter(e);
}

/// Selector de vista (Meses · Semanas · Días) con una pastilla que se desliza.
class CalendarViewSwitch extends StatelessWidget {
  const CalendarViewSwitch(
      {super.key, required this.value, required this.onChanged});
  final int value;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final labels = [tr('Meses'), tr('Semanas'), tr('Días')];
    final icons = [
      Icons.calendar_view_month_rounded,
      Icons.calendar_view_week_rounded,
      Icons.view_day_rounded,
    ];
    return Container(
      height: 40,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: p.searchFill,
        borderRadius: BorderRadius.circular(13),
      ),
      child: LayoutBuilder(builder: (context, c) {
        final w = c.maxWidth / 3;
        return Stack(children: [
          AnimatedPositioned(
            duration: Anim.medium,
            curve: Curves.easeOutBack,
            left: w * value,
            top: 0,
            bottom: 0,
            width: w,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: p.card,
                borderRadius: BorderRadius.circular(10),
                boxShadow: [
                  BoxShadow(
                      color: Colors.black.withValues(alpha: 0.10),
                      blurRadius: 8,
                      offset: const Offset(0, 2)),
                ],
              ),
            ),
          ),
          Row(children: [
            for (var i = 0; i < 3; i++)
              Expanded(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => onChanged(i),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(icons[i],
                          size: 17, color: i == value ? p.accent : p.secondary),
                      const SizedBox(width: 6),
                      Flexible(
                        child: AnimatedDefaultTextStyle(
                          duration: Anim.fast,
                          style: TextStyle(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w700,
                              color: i == value ? p.accent : p.secondary),
                          child: Text(labels[i],
                              maxLines: 1, overflow: TextOverflow.ellipsis),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ]),
        ]);
      }),
    );
  }
}

// ---------------------------------------------------------------- meses

/// Todos los meses del rango de un vistazo: cada uno con sus días y un punto
/// de color en los que tienen algo. Tocar un mes lo abre en "Semanas".
class MonthsOverview extends StatelessWidget {
  const MonthsOverview({
    super.key,
    required this.months,
    required this.notes,
    required this.onPick,
    this.scroll,
  });

  final List<DateTime> months;
  final List<Note> notes;
  final ValueChanged<DateTime> onPick;
  final ScrollController? scroll;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      final cols = c.maxWidth >= 1000
          ? 4
          : c.maxWidth >= 700
              ? 3
              : 2;
      final now = DateTime.now();
      // Empieza en el mes actual (los anteriores quedan arriba).
      final first =
          months.indexWhere((m) => m.year == now.year && m.month == now.month);
      return GridView.builder(
        controller: scroll ??
            SmoothScrollController(
                initialScrollOffset: math.max(0, (first ~/ cols) * 230.0 - 20)),
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: cols,
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          mainAxisExtent: 218,
        ),
        itemCount: months.length,
        itemBuilder: (context, i) => _MonthCard(
          month: months[i],
          notes: notes,
          onTap: () => onPick(months[i]),
        )
            .animate(delay: (25 * (i - first).abs().clamp(0, 12)).ms)
            .fadeIn(duration: Anim.medium)
            .scale(
                begin: const Offset(0.94, 0.94),
                curve: Curves.easeOutCubic,
                duration: Anim.medium),
      );
    });
  }
}

class _MonthCard extends StatefulWidget {
  const _MonthCard(
      {required this.month, required this.notes, required this.onTap});
  final DateTime month;
  final List<Note> notes;
  final VoidCallback onTap;

  @override
  State<_MonthCard> createState() => _MonthCardState();
}

class _MonthCardState extends State<_MonthCard> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final m = widget.month;
    final now = DateTime.now();
    final current = m.year == now.year && m.month == now.month;
    final first = DateTime(m.year, m.month, 1);
    final start = DateTime(m.year, m.month, 1 - (first.weekday - 1));
    final last = DateTime(m.year, m.month + 1, 0);
    final inMonth = widget.notes.where((n) {
      final s = _d(n.periodStart.toLocal());
      final e = _d(n.dueAt!.toLocal());
      return !e.isBefore(first) && !s.isAfter(last);
    }).toList();
    final name = tr(mesesNombre[m.month - 1]);
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: AnimatedScale(
        duration: Anim.fast,
        scale: _hover ? 1.02 : 1,
        child: Material(
          color: current ? p.accent.withValues(alpha: 0.08) : p.background,
          borderRadius: BorderRadius.circular(18),
          child: InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: widget.onTap,
            child: Container(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                    color: current
                        ? p.accent.withValues(alpha: 0.6)
                        : Colors.transparent,
                    width: 1.5),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Expanded(
                      child: Text(
                          '${name[0].toUpperCase()}${name.substring(1)}',
                          style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                              color: current ? p.accent : null)),
                    ),
                    if (m.year != now.year || m.month == 1)
                      Text('${m.year}',
                          style: TextStyle(fontSize: 12, color: p.secondary)),
                  ]),
                  const SizedBox(height: 6),
                  Expanded(
                    child: Column(children: [
                      for (var w = 0; w < 6; w++)
                        Expanded(
                          child: Row(children: [
                            for (var d = 0; d < 7; d++)
                              Expanded(
                                child: _MiniDay(
                                  day: DateTime(start.year, start.month,
                                      start.day + w * 7 + d),
                                  month: m.month,
                                  notes: inMonth,
                                ),
                              ),
                          ]),
                        ),
                    ]),
                  ),
                  const SizedBox(height: 4),
                  Text(
                      inMonth.isEmpty
                          ? tr('Sin tareas')
                          : trn(inMonth.length, '{0} tarea', '{0} tareas'),
                      style: TextStyle(fontSize: 11.5, color: p.secondary)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _MiniDay extends StatelessWidget {
  const _MiniDay({required this.day, required this.month, required this.notes});
  final DateTime day;
  final int month;
  final List<Note> notes;

  @override
  Widget build(BuildContext context) {
    if (day.month != month) return const SizedBox();
    final p = Palette.of(context);
    final today = _d(DateTime.now()) == day;
    final here = notes.where((n) => _activeOn(n, day)).take(3).toList();
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          width: 18,
          height: 18,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: today ? p.accent : Colors.transparent,
            shape: BoxShape.circle,
          ),
          child: Text('${day.day}',
              style: TextStyle(
                  fontSize: 10,
                  fontWeight: today ? FontWeight.w800 : FontWeight.w500,
                  color: today ? p.onAccent : null)),
        ),
        SizedBox(
          height: 4,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (final n in here)
                Container(
                  width: 4,
                  height: 4,
                  margin: const EdgeInsets.symmetric(horizontal: 0.5),
                  decoration: BoxDecoration(
                      color: calendarColor(context, n), shape: BoxShape.circle),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

// ----------------------------------------------------------------- días

/// Un día por horas: arriba lo que dura todo el día (o varios), y debajo
/// las tareas con hora en su sitio, con la hora actual marcada.
class DayTimeline extends StatefulWidget {
  const DayTimeline({
    super.key,
    required this.day,
    required this.notes,
    required this.onDay,
    required this.onOpen,
    required this.onNew,
  });

  final DateTime day;
  final List<Note> notes;
  final ValueChanged<DateTime> onDay;
  final void Function(String id) onOpen;
  final VoidCallback onNew;

  @override
  State<DayTimeline> createState() => _DayTimelineState();
}

class _DayTimelineState extends State<DayTimeline> {
  static const _hour = 64.0;
  late final _scroll = SmoothScrollController(
      initialScrollOffset: _hour * math.max(0, DateTime.now().hour - 2));
  Timer? _clock;

  @override
  void initState() {
    super.initState();
    // La línea de "ahora" avanza.
    _clock = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _clock?.cancel();
    _scroll.dispose();
    super.dispose();
  }

  /// ¿Tiene hora exacta ese día? (si no, va arriba como "todo el día").
  bool _timed(Note n) {
    final due = n.dueAt!.toLocal();
    return !n.isAllDay && _d(due) == widget.day;
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final day = widget.day;
    final here = widget.notes.where((n) => _activeOn(n, day)).toList()
      ..sort(Note.calendarOrder);
    final allDay = here.where((n) => !_timed(n)).toList();
    final timed = here.where(_timed).toList();
    final isToday = _d(DateTime.now()) == day;
    final wd = tr(const [
      'lunes',
      'martes',
      'miércoles',
      'jueves',
      'viernes',
      'sábado',
      'domingo'
    ][day.weekday - 1]);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 12, 8),
          child: Row(children: [
            IconButton(
              tooltip: tr('Día anterior'),
              onPressed: () =>
                  widget.onDay(DateTime(day.year, day.month, day.day - 1)),
              icon: const Icon(Icons.chevron_left_rounded),
            ),
            Expanded(
              child: AnimatedSwitcher(
                duration: Anim.medium,
                transitionBuilder: (c, a) => FadeTransition(
                    opacity: a,
                    child: SlideTransition(
                        position: Tween(
                                begin: const Offset(0.08, 0), end: Offset.zero)
                            .animate(a),
                        child: c)),
                child: Column(
                  key: ValueKey(day),
                  children: [
                    Text(wd.toUpperCase(),
                        style: TextStyle(
                            fontSize: 11.5,
                            letterSpacing: 1.2,
                            fontWeight: FontWeight.w800,
                            color: p.accent)),
                    Text(
                        trf('{0} de {1}',
                            [day.day, tr(mesesNombre[day.month - 1])]),
                        style: const TextStyle(
                            fontSize: 20, fontWeight: FontWeight.w800)),
                  ],
                ),
              ),
            ),
            IconButton(
              tooltip: tr('Día siguiente'),
              onPressed: () =>
                  widget.onDay(DateTime(day.year, day.month, day.day + 1)),
              icon: const Icon(Icons.chevron_right_rounded),
            ),
            IconButton.filledTonal(
              tooltip: tr('Nueva nota este día'),
              onPressed: widget.onNew,
              icon: const Icon(Icons.add_rounded),
            ),
          ]),
        ),
        if (allDay.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final (i, n) in allDay.indexed)
                  ActionChip(
                    avatar: Icon(
                        n.done
                            ? Icons.check_circle_rounded
                            : Icons.wb_sunny_outlined,
                        size: 16,
                        color: calendarColor(context, n)),
                    label: Text(n.title,
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                    side: BorderSide(
                        color:
                            calendarColor(context, n).withValues(alpha: 0.5)),
                    backgroundColor:
                        calendarColor(context, n).withValues(alpha: 0.10),
                    onPressed: () => widget.onOpen(n.id),
                  ).animate(delay: (30 * i).ms).fadeIn().slideY(begin: 0.2),
              ],
            ),
          ),
        Divider(height: 1, color: p.separator),
        Expanded(
          child: SingleChildScrollView(
            controller: _scroll,
            child: SizedBox(
              height: _hour * 24 + 16,
              child: LayoutBuilder(builder: (context, c) {
                const left = 56.0;
                final now = DateTime.now();
                return Stack(children: [
                  for (var h = 0; h < 24; h++)
                    Positioned(
                      top: 8 + h * _hour,
                      left: 0,
                      right: 0,
                      child: Row(children: [
                        SizedBox(
                          width: left,
                          child: Text('${h.toString().padLeft(2, '0')}:00',
                              textAlign: TextAlign.center,
                              maxLines: 1,
                              softWrap: false,
                              overflow: TextOverflow.visible,
                              style:
                                  TextStyle(fontSize: 11, color: p.secondary)),
                        ),
                        Expanded(
                            child: Divider(
                                height: 1,
                                color: p.separator.withValues(alpha: 0.6))),
                      ]),
                    ),
                  for (final (i, n) in timed.indexed)
                    _block(context, n, i, timed.length, c.maxWidth - left - 12,
                        left),
                  if (isToday)
                    Positioned(
                      top: 8 + (now.hour + now.minute / 60) * _hour - 1,
                      left: left - 4,
                      right: 8,
                      child: Row(children: [
                        Container(
                          width: 9,
                          height: 9,
                          decoration: const BoxDecoration(
                              color: Color(0xFFE5484D), shape: BoxShape.circle),
                        ),
                        Expanded(
                            child: Container(
                                height: 2, color: const Color(0xFFE5484D))),
                      ]),
                    ),
                  if (here.isEmpty)
                    Positioned(
                      top: 8 + 9 * _hour,
                      left: left,
                      right: 0,
                      child: Center(
                        child: Text(tr('Día libre'),
                            style: TextStyle(color: p.secondary)),
                      ),
                    ),
                ]);
              }),
            ),
          ),
        ),
      ],
    );
  }

  /// Bloque de una tarea con hora: va desde su inicio (si empieza ese día)
  /// hasta su hora límite; si no, una hora antes de que acabe.
  Widget _block(BuildContext context, Note n, int index, int count,
      double width, double left) {
    final due = n.dueAt!.toLocal();
    final start = n.periodStart.toLocal();
    final from = _d(start) == widget.day && start.isBefore(due)
        ? start
        : due.subtract(const Duration(hours: 1));
    final top = 8 + (from.hour + from.minute / 60) * _hour;
    final end = 8 + (due.hour + due.minute / 60) * _hour;
    final h = math.max(34.0, end - top);
    // Las que coinciden se reparten el ancho.
    final w = width / math.min(count, 3);
    final color = calendarColor(context, n);
    return Positioned(
      top: math.max(8, top),
      left: left + 4 + (index % 3) * w,
      width: w - 6,
      height: h,
      child: Material(
        color: color.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => widget.onOpen(n.id),
          child: Container(
            padding: const EdgeInsets.fromLTRB(10, 6, 8, 4),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border(left: BorderSide(color: color, width: 4)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(n.title,
                    maxLines: h > 50 ? 2 : 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                        decoration:
                            n.done ? TextDecoration.lineThrough : null)),
                if (h > 50)
                  Text(
                      '${from.hour}:${from.minute.toString().padLeft(2, '0')} – '
                      '${due.hour}:${due.minute.toString().padLeft(2, '0')}',
                      style: TextStyle(
                          fontSize: 11.5, color: Palette.secondary(context))),
              ],
            ),
          ),
        ),
      ),
    ).animate().fadeIn(duration: Anim.medium).slideX(begin: 0.05);
  }
}

/// "dic 2026 – dic 2029" para la cabecera de la vista de meses.
String monthsRangeLabel(DateTime a, DateTime b) =>
    '${tr(mesesNombre[a.month - 1]).substring(0, 3)} ${a.year} – '
    '${tr(mesesNombre[b.month - 1]).substring(0, 3)} ${b.year}';

/// Para que los textos de días también tengan formato corto.
String dayLabel(DateTime d) => fechaDia(d);
