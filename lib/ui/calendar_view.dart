import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../data/notes_repository.dart';
import '../models/note.dart';
import 'anim.dart';
import 'format.dart';
import 'theme.dart';
import 'urgency.dart';

DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);

/// Calendario mensual: este mes, los 3 anteriores y los 3 siguientes.
/// Cada nota temporal se dibuja como una barra desde que empieza hasta su
/// fecha límite, con el color según el tiempo que queda.
class CalendarView extends StatefulWidget {
  const CalendarView({
    super.key,
    required this.repo,
    required this.onOpenNote,
    required this.onNewOnDay,
    required this.onEditDates,
  });

  final NotesRepository repo;
  final void Function(String id) onOpenNote;
  final void Function(DateTime day) onNewOnDay;
  final void Function(String id) onEditDates;

  @override
  State<CalendarView> createState() => _CalendarViewState();
}

class _CalendarViewState extends State<CalendarView> {
  static const _monthsBefore = 3;
  late final PageController _pages =
      PageController(initialPage: _monthsBefore);
  int _page = _monthsBefore;
  DateTime _selected = _day(DateTime.now());

  DateTime _monthAt(int page) {
    final now = DateTime.now();
    return DateTime(now.year, now.month - _monthsBefore + page, 1);
  }

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  void _goTo(int page) {
    _pages.animateToPage(page,
        duration: Anim.slow, curve: Curves.easeInOutCubic);
  }

  List<Note> _activeOn(List<Note> notes, DateTime day) => notes.where((n) {
        final s = _day(n.periodStart.toLocal());
        final e = _day(n.dueAt!.toLocal());
        return !day.isBefore(s) && !day.isAfter(e);
      }).toList();

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.repo,
      builder: (context, _) {
        final notes = widget.repo.temporales;
        final month = _monthAt(_page);
        final accent = Palette.accent(context);

        final header = Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 8, 4),
          child: Row(
            children: [
              Expanded(
                child: AnimatedSwitcher(
                  duration: Anim.medium,
                  transitionBuilder: (c, a) => FadeTransition(
                    opacity: a,
                    child: SlideTransition(
                      position: Tween(
                              begin: const Offset(0, 0.4), end: Offset.zero)
                          .animate(a),
                      child: c,
                    ),
                  ),
                  child: Text(
                    nombreMes(month.month, month.year),
                    key: ValueKey(month),
                    style: const TextStyle(
                        fontSize: 22, fontWeight: FontWeight.w800),
                  ),
                ),
              ),
              if (_page != _monthsBefore)
                TextButton(
                  onPressed: () {
                    setState(() => _selected = _day(DateTime.now()));
                    _goTo(_monthsBefore);
                  },
                  child: const Text('Hoy'),
                ).animate().fadeIn().scale(begin: const Offset(0.8, 0.8)),
              IconButton(
                tooltip: 'Mes anterior',
                onPressed: _page > 0 ? () => _goTo(_page - 1) : null,
                icon: const Icon(Icons.chevron_left),
              ),
              IconButton(
                tooltip: 'Mes siguiente',
                onPressed:
                    _page < _monthsBefore * 2 ? () => _goTo(_page + 1) : null,
                icon: const Icon(Icons.chevron_right),
              ),
            ],
          ),
        );

        const dias = ['L', 'M', 'X', 'J', 'V', 'S', 'D'];
        final weekdays = Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Row(
            children: [
              for (final d in dias)
                Expanded(
                  child: Center(
                    child: Text(d,
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: Palette.secondary(context))),
                  ),
                ),
            ],
          ),
        );

        final selectedNotes = _activeOn(notes, _selected);

        final dayPanel = _DayPanel(
          day: _selected,
          notes: selectedNotes,
          onOpen: widget.onOpenNote,
          onEditDates: widget.onEditDates,
          onNew: () => widget.onNewOnDay(_selected),
          onToggleDone: widget.repo.toggleDone,
        );

        return LayoutBuilder(builder: (context, c) {
          final side = c.maxWidth >= 860;
          final gridWidth = side ? c.maxWidth * 0.62 : c.maxWidth;
          final cellH = ((gridWidth - 16) / 7 * 0.92).clamp(68.0, 104.0);
          final gridHeight = cellH * 6 + 8;

          final grid = SizedBox(
            height: gridHeight,
            child: PageView.builder(
              controller: _pages,
              itemCount: _monthsBefore * 2 + 1,
              onPageChanged: (p) => setState(() => _page = p),
              itemBuilder: (context, p) => RepaintBoundary(
                child: _MonthGrid(
                  month: _monthAt(p),
                  notes: notes,
                  selected: _selected,
                  cellHeight: cellH,
                  accent: accent,
                  onSelect: (d) => setState(() => _selected = d),
                ),
              ),
            ),
          );

          final calendar = Column(
            mainAxisSize: MainAxisSize.min,
            children: [header, weekdays, const SizedBox(height: 4), grid],
          );

          if (side) {
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                    width: gridWidth,
                    child: SingleChildScrollView(child: calendar)),
                VerticalDivider(width: 1, color: Palette.separator(context)),
                Expanded(child: dayPanel),
              ],
            );
          }
          return CustomScrollView(
            slivers: [
              SliverToBoxAdapter(child: calendar),
              SliverToBoxAdapter(
                  child: Divider(height: 1, color: Palette.separator(context))),
              SliverFillRemaining(hasScrollBody: true, child: dayPanel),
            ],
          );
        });
      },
    );
  }
}

class _MonthGrid extends StatelessWidget {
  const _MonthGrid({
    required this.month,
    required this.notes,
    required this.selected,
    required this.cellHeight,
    required this.accent,
    required this.onSelect,
  });

  final DateTime month;
  final List<Note> notes;
  final DateTime selected;
  final double cellHeight;
  final Color accent;
  final void Function(DateTime) onSelect;

  @override
  Widget build(BuildContext context) {
    final first = DateTime(month.year, month.month, 1);
    final gridStart = first.subtract(Duration(days: first.weekday - 1));
    final gridEnd = gridStart.add(const Duration(days: 41));
    final today = _day(DateTime.now());

    // Carriles: cada nota ocupa siempre la misma fila de barras para que
    // la barra se vea continua de un día a otro.
    final visible = notes.where((n) {
      final s = _day(n.periodStart.toLocal());
      final e = _day(n.dueAt!.toLocal());
      return !e.isBefore(gridStart) && !s.isAfter(gridEnd);
    }).toList()
      ..sort((a, b) => a.periodStart.compareTo(b.periodStart));
    final laneEnds = <DateTime>[];
    final lanes = <String, int>{};
    for (final n in visible) {
      final s = _day(n.periodStart.toLocal());
      final e = _day(n.dueAt!.toLocal());
      var lane = laneEnds.indexWhere((end) => end.isBefore(s));
      if (lane == -1) {
        laneEnds.add(e);
        lane = laneEnds.length - 1;
      } else {
        laneEnds[lane] = e;
      }
      lanes[n.id] = lane;
    }
    const maxLanes = 3;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Column(
        children: [
          for (var w = 0; w < 6; w++)
            SizedBox(
              height: cellHeight,
              child: Row(
                children: [
                  for (var d = 0; d < 7; d++)
                    Expanded(
                      child: Builder(builder: (context) {
                        final day = DateTime(gridStart.year, gridStart.month,
                            gridStart.day + w * 7 + d);
                        final inMonth = day.month == month.month;
                        final isToday = day == today;
                        final isSel = day == selected;
                        final dayNotes = visible.where((n) {
                          final s = _day(n.periodStart.toLocal());
                          final e = _day(n.dueAt!.toLocal());
                          return !day.isBefore(s) && !day.isAfter(e);
                        }).toList();
                        final extra = dayNotes
                            .where((n) => (lanes[n.id] ?? 0) >= maxLanes)
                            .length;

                        return GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () => onSelect(day),
                          child: AnimatedContainer(
                            duration: Anim.fast,
                            margin: const EdgeInsets.all(1.5),
                            decoration: BoxDecoration(
                              color: isSel
                                  ? accent.withValues(alpha: 0.14)
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(10),
                              border: isSel
                                  ? Border.all(color: accent, width: 1.5)
                                  : null,
                            ),
                            child: Column(
                              children: [
                                const SizedBox(height: 4),
                                Container(
                                  width: 26,
                                  height: 26,
                                  alignment: Alignment.center,
                                  decoration: BoxDecoration(
                                    color: isToday ? accent : null,
                                    shape: BoxShape.circle,
                                  ),
                                  child: Text(
                                    '${day.day}',
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: isToday || isSel
                                          ? FontWeight.w800
                                          : FontWeight.w500,
                                      color: isToday
                                          ? Palette.of(context).onAccent
                                          : (inMonth
                                              ? null
                                              : Palette.secondary(context)
                                                  .withValues(alpha: 0.5)),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 3),
                                for (var lane = 0; lane < maxLanes; lane++)
                                  _laneBar(context, day, dayNotes, lanes, lane,
                                      inMonth),
                                if (extra > 0)
                                  Text('+$extra',
                                      style: TextStyle(
                                          fontSize: 9,
                                          color: Palette.secondary(context))),
                              ],
                            ),
                          ),
                        );
                      }),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _laneBar(BuildContext context, DateTime day, List<Note> dayNotes,
      Map<String, int> lanes, int lane, bool inMonth) {
    Note? n;
    for (final x in dayNotes) {
      if (lanes[x.id] == lane) n = x;
    }
    if (n == null) return const SizedBox(height: 7);
    final s = _day(n.periodStart.toLocal());
    final e = _day(n.dueAt!.toLocal());
    final isStart = day == s || day.weekday == DateTime.monday;
    final isEnd = day == e || day.weekday == DateTime.sunday;
    final color = urgencyColor(context, n);
    // Parte ya consumida en tono fuerte, lo que queda más suave.
    final passed = day.isBefore(_day(DateTime.now()));
    return Padding(
      padding: EdgeInsets.only(
          left: isStart ? 3 : 0, right: isEnd ? 3 : 0, bottom: 2),
      child: Container(
        height: 5,
        decoration: BoxDecoration(
          color: color.withValues(
              alpha: (passed ? 0.95 : 0.45) * (inMonth ? 1 : 0.5)),
          borderRadius: BorderRadius.horizontal(
            left: Radius.circular(isStart ? 3 : 0),
            right: Radius.circular(isEnd ? 3 : 0),
          ),
        ),
      ),
    );
  }
}

class _DayPanel extends StatelessWidget {
  const _DayPanel({
    required this.day,
    required this.notes,
    required this.onOpen,
    required this.onEditDates,
    required this.onNew,
    required this.onToggleDone,
  });

  final DateTime day;
  final List<Note> notes;
  final void Function(String) onOpen;
  final void Function(String) onEditDates;
  final VoidCallback onNew;
  final void Function(String) onToggleDone;

  @override
  Widget build(BuildContext context) {
    final label =
        '${day.day} de ${mesesNombre[day.month - 1]}${day.year != DateTime.now().year ? ' de ${day.year}' : ''}';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 8, 6),
          child: Row(
            children: [
              Expanded(
                child: Text(label,
                    style: const TextStyle(
                        fontSize: 18, fontWeight: FontWeight.w700)),
              ),
              Bouncy(
                child: FilledButton.tonalIcon(
                  onPressed: onNew,
                  icon: const Icon(Icons.add_alarm, size: 18),
                  label: const Text('Nueva'),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: AnimatedSwitcher(
            duration: Anim.medium,
            child: notes.isEmpty
                ? Center(
                    key: ValueKey('vacio-$day'),
                    child: Text('Nada pendiente este día',
                        style: TextStyle(color: Palette.secondary(context))),
                  )
                : ListView.separated(
                    key: ValueKey('lista-$day'),
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                    itemCount: notes.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (context, i) => _TempCard(
                      note: notes[i],
                      onOpen: () => onOpen(notes[i].id),
                      onEditDates: () => onEditDates(notes[i].id),
                      onToggleDone: () => onToggleDone(notes[i].id),
                    )
                        .animate(delay: (40 * i).ms)
                        .fadeIn(duration: Anim.medium)
                        .slideY(begin: 0.15, curve: Anim.curve),
                  ),
          ),
        ),
      ],
    );
  }
}

/// Tarjeta de una nota temporal con su barra de tiempo.
class TempCard extends StatelessWidget {
  const TempCard({
    super.key,
    required this.note,
    required this.onOpen,
    required this.onEditDates,
    required this.onToggleDone,
  });

  final Note note;
  final VoidCallback onOpen;
  final VoidCallback onEditDates;
  final VoidCallback onToggleDone;

  @override
  Widget build(BuildContext context) => _TempCard(
      note: note,
      onOpen: onOpen,
      onEditDates: onEditDates,
      onToggleDone: onToggleDone);
}

class _TempCard extends StatelessWidget {
  const _TempCard({
    required this.note,
    required this.onOpen,
    required this.onEditDates,
    required this.onToggleDone,
  });

  final Note note;
  final VoidCallback onOpen;
  final VoidCallback onEditDates;
  final VoidCallback onToggleDone;

  @override
  Widget build(BuildContext context) {
    final color = urgencyColor(context, note);
    return Bouncy(
      pressedScale: 0.98,
      child: Material(
        color: Palette.card(context),
        borderRadius: BorderRadius.circular(14),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onOpen,
          onLongPress: onEditDates,
          onSecondaryTap: onEditDates,
          child: Container(
            decoration: BoxDecoration(
              border: Border(left: BorderSide(color: color, width: 4)),
            ),
            padding: const EdgeInsets.fromLTRB(8, 10, 12, 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                IconButton(
                  visualDensity: VisualDensity.compact,
                  tooltip: note.done ? 'Marcar pendiente' : 'Completar',
                  onPressed: onToggleDone,
                  icon: AnimatedSwitcher(
                    duration: Anim.medium,
                    transitionBuilder: (c, a) => ScaleTransition(
                        scale: CurvedAnimation(
                            parent: a, curve: Curves.easeOutBack),
                        child: c),
                    child: Icon(
                      note.done
                          ? Icons.check_circle
                          : Icons.radio_button_unchecked,
                      key: ValueKey(note.done),
                      color: note.done ? color : Palette.secondary(context),
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        note.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          decoration:
                              note.done ? TextDecoration.lineThrough : null,
                        ),
                      ),
                      const SizedBox(height: 8),
                      TimeBar(note: note),
                    ],
                  ),
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  tooltip: 'Cambiar fechas',
                  onPressed: onEditDates,
                  icon: Icon(Icons.edit_calendar_outlined,
                      color: Palette.secondary(context), size: 20),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
