import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../data/notes_repository.dart';
import '../models/note.dart';
import 'anim.dart';
import 'format.dart';
import 'split.dart';
import 'theme.dart';
import 'urgency.dart';

DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);

const _diasSemana = [
  'lunes', 'martes', 'miércoles', 'jueves', 'viernes', 'sábado', 'domingo'
];

/// Calendario mensual: este mes, los 3 anteriores y los 3 siguientes.
/// Cada nota temporal es una barra desde que empieza hasta su fecha límite,
/// coloreada como la mecha (menta → rojo) según el punto del periodo.
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
  static const _before = 3;
  late final PageController _pages = PageController(initialPage: _before);
  int _page = _before;
  DateTime _selected = _day(DateTime.now());

  DateTime _monthAt(int page) {
    final now = DateTime.now();
    return DateTime(now.year, now.month - _before + page, 1);
  }

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  void _goTo(int page) => _pages.animateToPage(page,
      duration: Anim.slow, curve: Curves.easeInOutCubic);

  static List<Note> activeOn(List<Note> notes, DateTime day) => notes.where((n) {
        final s = _day(n.periodStart.toLocal());
        final e = _day(n.dueAt!.toLocal());
        return !day.isBefore(s) && !day.isAfter(e);
      }).toList();

  Widget _header(BuildContext context) {
    final month = _monthAt(_page);
    final name = mesesNombre[month.month - 1];
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 12, 8),
      child: Row(
        children: [
          Expanded(
            child: AnimatedSwitcher(
              duration: Anim.medium,
              layoutBuilder: (current, previous) => Stack(
                alignment: Alignment.centerLeft,
                children: [...previous, if (current != null) current],
              ),
              transitionBuilder: (c, a) => FadeTransition(
                opacity: a,
                child: SlideTransition(
                  position: Tween(begin: const Offset(0, 0.3), end: Offset.zero)
                      .animate(a),
                  child: c,
                ),
              ),
              child: RichText(
                key: ValueKey(month),
                text: TextSpan(
                  style: DefaultTextStyle.of(context).style,
                  children: [
                    TextSpan(
                      text: '${name[0].toUpperCase()}${name.substring(1)} ',
                      style: const TextStyle(
                          fontSize: 24, fontWeight: FontWeight.w800),
                    ),
                    TextSpan(
                      text: '${month.year}',
                      style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w400,
                          color: Palette.secondary(context)),
                    ),
                  ],
                ),
              ),
            ),
          ),
          AnimatedOpacity(
            duration: Anim.fast,
            opacity: _page == _before ? 0 : 1,
            child: TextButton(
              onPressed: _page == _before
                  ? null
                  : () {
                      setState(() => _selected = _day(DateTime.now()));
                      _goTo(_before);
                    },
              child: const Text('Hoy'),
            ),
          ),
          const SizedBox(width: 4),
          Container(
            decoration: BoxDecoration(
              color: Palette.searchFill(context),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  visualDensity: VisualDensity.compact,
                  tooltip: 'Mes anterior',
                  onPressed: _page > 0 ? () => _goTo(_page - 1) : null,
                  icon: const Icon(Icons.chevron_left),
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  tooltip: 'Mes siguiente',
                  onPressed: _page < _before * 2 ? () => _goTo(_page + 1) : null,
                  icon: const Icon(Icons.chevron_right),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _weekdays(BuildContext context) {
    const d = ['L', 'M', 'X', 'J', 'V', 'S', 'D'];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          for (var i = 0; i < 7; i++)
            Expanded(
              child: Center(
                child: Text(d[i],
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.5,
                        color: Palette.secondary(context)
                            .withValues(alpha: i >= 5 ? 0.6 : 1))),
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.repo,
      builder: (context, _) {
        final notes = widget.repo.temporales;
        final accent = Palette.accent(context);

        Widget grid({required double cellHeight}) => SizedBox(
              height: cellHeight * 6,
              child: PageView.builder(
                controller: _pages,
                itemCount: _before * 2 + 1,
                onPageChanged: (p) => setState(() => _page = p),
                itemBuilder: (context, p) => RepaintBoundary(
                  child: _MonthGrid(
                    month: _monthAt(p),
                    notes: notes,
                    selected: _selected,
                    cellHeight: cellHeight,
                    accent: accent,
                    onSelect: (d) => setState(() => _selected = d),
                  ),
                ),
              ),
            );

        final dayPanel = _DayPanel(
          day: _selected,
          notes: activeOn(notes, _selected),
          onOpen: widget.onOpenNote,
          onEditDates: widget.onEditDates,
          onNew: () => widget.onNewOnDay(_selected),
          onToggleDone: widget.repo.toggleDone,
        );

        return LayoutBuilder(builder: (context, c) {
          final side = c.maxWidth >= 640;

          if (side) {
            // Calendario a la izquierda (llena el alto disponible) y las
            // tareas del día a la derecha, con separador ajustable.
            final calendar = LayoutBuilder(builder: (context, cc) {
              final cellH = ((cc.maxHeight - 96) / 6).clamp(72.0, 130.0);
              return SingleChildScrollView(
                child: Column(
                  children: [
                    _header(context),
                    _weekdays(context),
                    const SizedBox(height: 6),
                    grid(cellHeight: cellH),
                    const SizedBox(height: 8),
                  ],
                ),
              );
            });
            return ColoredBox(
              color: Palette.card(context),
              child: ResizableSplit(
                storageKey: 'calendario',
                initialFraction: 0.64,
                minLeft: 380,
                maxLeft: 1100,
                minRight: 240,
                left: RepaintBoundary(child: calendar),
                right: RepaintBoundary(child: dayPanel),
              ),
            );
          }

          // Estrecho (móvil): todo en un único desplazamiento, sin capas
          // que se monten unas encima de otras.
          final cellH = ((c.maxWidth - 24) / 7 * 0.95).clamp(70.0, 88.0);
          final dayNotes = activeOn(notes, _selected);
          return ColoredBox(
            color: Palette.card(context),
            child: ListView(
              padding: const EdgeInsets.only(bottom: 32),
              children: [
                _header(context),
                _weekdays(context),
                const SizedBox(height: 6),
                grid(cellHeight: cellH),
                const SizedBox(height: 8),
                Divider(height: 1, color: Palette.separator(context)),
                _DayHeader(
                  day: _selected,
                  count: dayNotes.length,
                  onNew: () => widget.onNewOnDay(_selected),
                ),
                if (dayNotes.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 28),
                    child: Center(
                      child: Text('Día libre',
                          style:
                              TextStyle(color: Palette.secondary(context))),
                    ),
                  )
                else
                  for (var i = 0; i < dayNotes.length; i++)
                    Padding(
                      key: ValueKey('m-${dayNotes[i].id}'),
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                      child: TempCard(
                        onCard: true,
                        note: dayNotes[i],
                        onOpen: () => widget.onOpenNote(dayNotes[i].id),
                        onEditDates: () => widget.onEditDates(dayNotes[i].id),
                        onToggleDone: () =>
                            widget.repo.toggleDone(dayNotes[i].id),
                      )
                          .animate(delay: (40 * i).ms)
                          .fadeIn(duration: Anim.medium)
                          .slideY(begin: 0.12, curve: Anim.curve),
                    ),
              ],
            ),
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

  static const _maxLanes = 3;

  @override
  Widget build(BuildContext context) {
    final first = DateTime(month.year, month.month, 1);
    final gridStart = first.subtract(Duration(days: first.weekday - 1));
    final gridEnd = gridStart.add(const Duration(days: 41));
    final today = _day(DateTime.now());

    // Carriles: cada nota ocupa siempre la misma fila para que su barra
    // se vea continua de un día a otro.
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

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Column(
        children: [
          for (var w = 0; w < 6; w++)
            SizedBox(
              height: cellHeight,
              child: Row(
                children: [
                  for (var d = 0; d < 7; d++)
                    Expanded(
                      child: _cell(
                        context,
                        DateTime(gridStart.year, gridStart.month,
                            gridStart.day + w * 7 + d),
                        today,
                        visible,
                        lanes,
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _cell(BuildContext context, DateTime day, DateTime today,
      List<Note> visible, Map<String, int> lanes) {
    final inMonth = day.month == month.month;
    final isToday = day == today;
    final isSel = day == selected;
    final dayNotes = _CalendarViewState.activeOn(visible, day);
    final extra =
        dayNotes.where((n) => (lanes[n.id] ?? 0) >= _maxLanes).length;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => onSelect(day),
      child: AnimatedContainer(
        duration: Anim.fast,
        margin: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          color: isSel ? accent.withValues(alpha: 0.12) : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSel ? accent.withValues(alpha: 0.7) : Colors.transparent,
            width: 1.5,
          ),
        ),
        child: Column(
          children: [
            const SizedBox(height: 6),
            AnimatedContainer(
              duration: Anim.fast,
              width: 28,
              height: 28,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: isToday ? accent : Colors.transparent,
                shape: BoxShape.circle,
              ),
              child: Text(
                '${day.day}',
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight:
                      isToday || isSel ? FontWeight.w800 : FontWeight.w500,
                  color: isToday
                      ? Palette.of(context).onAccent
                      : (inMonth
                          ? null
                          : Palette.secondary(context).withValues(alpha: 0.45)),
                ),
              ),
            ),
            const Spacer(),
            for (var lane = 0; lane < _maxLanes; lane++)
              _laneBar(context, day, dayNotes, lanes, lane, inMonth),
            SizedBox(
              height: 12,
              child: extra > 0
                  ? Text('+$extra',
                      style: TextStyle(
                          fontSize: 9.5,
                          fontWeight: FontWeight.w700,
                          color: Palette.secondary(context)))
                  : null,
            ),
          ],
        ),
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
    final total = e.difference(s).inDays;
    final t = total <= 0 ? 1.0 : day.difference(s).inDays / total;
    final passed = !day.isAfter(_day(DateTime.now()));
    final color =
        n.done ? Palette.secondary(context) : paletteAt(fusePalette(n.color), t);
    return Padding(
      padding: EdgeInsets.only(
          left: isStart ? 4 : 0, right: isEnd ? 4 : 0, bottom: 2),
      child: Container(
        height: 5,
        decoration: BoxDecoration(
          // Lo ya consumido en color pleno, lo que queda más suave.
          color: color.withValues(
              alpha: (passed ? 0.95 : 0.38) * (inMonth ? 1 : 0.45)),
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _DayHeader(day: day, count: notes.length, onNew: onNew),
        Expanded(
          child: AnimatedSwitcher(
            duration: Anim.medium,
            child: notes.isEmpty
                ? Center(
                    key: ValueKey('vacio-$day'),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.event_available_outlined,
                            size: 44,
                            color: Palette.secondary(context)
                                .withValues(alpha: 0.5)),
                        const SizedBox(height: 8),
                        Text('Día libre',
                            style:
                                TextStyle(color: Palette.secondary(context))),
                      ],
                    ),
                  )
                : ListView.separated(
                    key: ValueKey('lista-$day'),
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                    itemCount: notes.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (context, i) => TempCard(
                      onCard: true,
                      note: notes[i],
                      onOpen: () => onOpen(notes[i].id),
                      onEditDates: () => onEditDates(notes[i].id),
                      onToggleDone: () => onToggleDone(notes[i].id),
                    )
                        .animate(delay: (40 * i).ms)
                        .fadeIn(duration: Anim.medium)
                        .slideY(begin: 0.12, curve: Anim.curve),
                  ),
          ),
        ),
      ],
    );
  }
}

/// Tarjeta de una nota temporal con su mecha de tiempo.
class TempCard extends StatelessWidget {
  const TempCard({
    super.key,
    required this.note,
    required this.onOpen,
    required this.onEditDates,
    required this.onToggleDone,
    this.onCard = false,
  });

  final Note note;
  final VoidCallback onOpen;
  final VoidCallback onEditDates;
  final VoidCallback onToggleDone;

  /// true si va encima de un panel blanco (calendario): se usa el gris suave.
  final bool onCard;

  @override
  Widget build(BuildContext context) {
    final color = urgencyColor(context, note);
    return Bouncy(
      pressedScale: 0.985,
      child: Material(
        color: onCard ? Palette.background(context) : Palette.card(context),
        borderRadius: BorderRadius.circular(16),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onOpen,
          onLongPress: onEditDates,
          onSecondaryTap: onEditDates,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(6, 10, 10, 12),
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
                const SizedBox(width: 2),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 4),
                      Text(
                        note.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 15.5,
                          fontWeight: FontWeight.w600,
                          decoration:
                              note.done ? TextDecoration.lineThrough : null,
                          color: note.done ? Palette.secondary(context) : null,
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
                      color: Palette.secondary(context), size: 19),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}


/// Cabecera del día seleccionado: día de la semana, fecha, nº de tareas y
/// botón para crear una tarea ese día. El botón va en su propia fila para
/// que nunca se monte sobre la fecha.
class _DayHeader extends StatelessWidget {
  const _DayHeader(
      {required this.day, required this.count, required this.onNew});
  final DateTime day;
  final int count;
  final VoidCallback onNew;

  @override
  Widget build(BuildContext context) {
    final year = day.year != DateTime.now().year ? ' de ${day.year}' : '';
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 16, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_diasSemana[day.weekday - 1].toUpperCase(),
                    style: TextStyle(
                        fontSize: 11.5,
                        letterSpacing: 1.2,
                        fontWeight: FontWeight.w700,
                        color: Palette.accent(context))),
                const SizedBox(height: 2),
                Text('${day.day} de ${mesesNombre[day.month - 1]}$year',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 20, fontWeight: FontWeight.w800)),
                const SizedBox(height: 2),
                Text(
                  count == 0
                      ? 'Sin tareas'
                      : (count == 1 ? '1 tarea' : '$count tareas'),
                  style: TextStyle(
                      color: Palette.secondary(context), fontSize: 13),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Bouncy(
            child: IconButton.filledTonal(
              tooltip: 'Nueva tarea este día',
              onPressed: onNew,
              icon: const Icon(Icons.add_rounded),
            ),
          ),
        ],
      ),
    );
  }
}
