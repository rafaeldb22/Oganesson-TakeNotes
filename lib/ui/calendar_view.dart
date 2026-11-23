import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../data/notes_repository.dart';
import '../models/note.dart';
import 'anim.dart';
import 'context_menu.dart';
import 'format.dart';
import 'split.dart';
import 'smooth_scroll.dart';
import 'theme.dart';
import 'urgency.dart';
import 'i18n.dart';

DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);

const _diasSemana = [
  'lunes',
  'martes',
  'miércoles',
  'jueves',
  'viernes',
  'sábado',
  'domingo'
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
  /// Desplazamiento suave con la rueda del ratón.
  final _calScroll = SmoothScrollController();
  final _listScroll = SmoothScrollController();

  /// Alto mínimo de una celda: número del día (34) + 7 líneas (32) + "+N"
  /// (13) + márgenes. Si no cabe, el calendario se desplaza.
  static const _minCell = 86.0;

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
    _calScroll.dispose();
    _listScroll.dispose();
    super.dispose();
  }

  void _goTo(int page) => _pages.animateToPage(page,
      duration: Anim.slow, curve: Curves.easeInOutCubic);

  static List<Note> activeOn(List<Note> notes, DateTime day) =>
      notes.where((n) {
        final s = _day(n.periodStart.toLocal());
        final e = _day(n.dueAt!.toLocal());
        return !day.isBefore(s) && !day.isAfter(e);
      }).toList()
        ..sort(Note.calendarOrder);

  Widget _header(BuildContext context) {
    final month = _monthAt(_page);
    final name = tr(mesesNombre[month.month - 1]);
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
              child: Text(tr('Hoy')),
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
                  tooltip: tr('Mes anterior'),
                  onPressed: _page > 0 ? () => _goTo(_page - 1) : null,
                  icon: const Icon(Icons.chevron_left),
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  tooltip: tr('Mes siguiente'),
                  onPressed:
                      _page < _before * 2 ? () => _goTo(_page + 1) : null,
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
    final d = diasIniciales;
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
        final notes = widget.repo.calendarItems;
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
                    onNewOnDay: widget.onNewOnDay,
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
          onToggleDone: (id) => completeTask(context, widget.repo, id),
        );

        return LayoutBuilder(builder: (context, c) {
          final side = c.maxWidth >= 640;

          if (side) {
            // Calendario a la izquierda (llena el alto disponible) y las
            // tareas del día a la derecha, con separador ajustable.
            final calendar = LayoutBuilder(builder: (context, cc) {
              final cellH = ((cc.maxHeight - 96) / 6).clamp(_minCell, 130.0);
              return SingleChildScrollView(
                controller: _calScroll,
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
          final cellH = ((c.maxWidth - 24) / 7 * 0.95).clamp(_minCell, 96.0);
          final dayNotes = activeOn(notes, _selected);
          return ColoredBox(
            color: Palette.card(context),
            child: ListView(
              controller: _listScroll,
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
                      child: Text(tr('Día libre'),
                          style: TextStyle(color: Palette.secondary(context))),
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
                            completeTask(context, widget.repo, dayNotes[i].id),
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

/// Qué se pinta en un día: una nota (o nada) por fila y cuántas no caben.
class DaySlots {
  DaySlots(int lanes) : notes = List<Note?>.filled(lanes, null);
  final List<Note?> notes;
  int extra = 0;
}

/// Fila de cada nota en todo el mes. Se reparte por orden de inicio, que usa
/// el mínimo de filas posible: con hasta 7 a la vez, cada línea conserva su
/// fila de principio a fin.
Map<String, int> assignLanes(List<Note> notes) {
  final items = [
    for (final n in notes)
      (n, _day(n.periodStart.toLocal()), _day(n.dueAt!.toLocal())),
  ]..sort((x, y) {
      final byStart = x.$2.compareTo(y.$2);
      if (byStart != 0) return byStart;
      if (x.$1.isSingleDay != y.$1.isSingleDay) {
        return x.$1.isSingleDay ? -1 : 1;
      }
      final byEnd = y.$3.compareTo(x.$3);
      return byEnd != 0 ? byEnd : x.$1.id.compareTo(y.$1.id);
    });
  final laneEnds = <DateTime>[];
  final out = <String, int>{};
  for (final (n, s, e) in items) {
    var lane = laneEnds.indexWhere((end) => end.isBefore(s));
    if (lane == -1) {
      laneEnds.add(e);
      lane = laneEnds.length - 1;
    } else {
      laneEnds[lane] = e;
    }
    out[n.id] = lane;
  }
  return out;
}

/// Reparte las notas de una semana en filas. Si una no cabe en la suya y ese
/// día hay un hueco, lo ocupa: "+N" solo sale cuando hay más notas que filas.
Map<DateTime, DaySlots> layoutWeek(DateTime monday, List<Note> notes,
    {int lanes = 7, Map<String, int>? assigned}) {
  final rows = assigned ?? assignLanes(notes);
  final days = [
    for (var i = 0; i < 7; i++)
      DateTime(monday.year, monday.month, monday.day + i)
  ];
  final overflow = List.generate(7, (_) => <Note>[]);
  final out = {for (final d in days) d: DaySlots(lanes)};
  for (final n in notes) {
    final s = _day(n.periodStart.toLocal());
    final e = _day(n.dueAt!.toLocal());
    if (e.isBefore(days.first) || s.isAfter(days.last)) continue;
    final a = s.isBefore(days.first) ? 0 : days.indexOf(s);
    final b = e.isAfter(days.last) ? 6 : days.indexOf(e);
    final lane = rows[n.id] ?? lanes;
    for (var d = a; d <= b; d++) {
      if (lane < lanes) {
        out[days[d]]!.notes[lane] = n;
      } else {
        overflow[d].add(n);
      }
    }
  }
  for (var d = 0; d < 7; d++) {
    final slots = out[days[d]]!;
    for (final n in overflow[d]) {
      final free = slots.notes.indexOf(null);
      if (free == -1) {
        slots.extra++;
      } else {
        slots.notes[free] = n;
      }
    }
  }
  return out;
}

class _MonthGrid extends StatelessWidget {
  const _MonthGrid({
    required this.month,
    required this.notes,
    required this.selected,
    required this.cellHeight,
    required this.accent,
    required this.onSelect,
    required this.onNewOnDay,
  });

  final DateTime month;
  final List<Note> notes;
  final DateTime selected;
  final double cellHeight;
  final Color accent;
  final void Function(DateTime) onSelect;
  final void Function(DateTime) onNewOnDay;

  static const _maxLanes = 7;
  static const _barHeight = 3.0;
  static const _barGap = 1.5;

  /// Clic derecho en un día: crear una nota ahí.
  Future<void> _dayMenu(
      BuildContext context, DateTime day, Offset position) async {
    onSelect(day);
    final choice = await showContextMenu(context,
        position: position,
        title: trf('{0} de {1}', [day.day, tr(mesesNombre[day.month - 1])]),
        entries: [
          MenuEntry(
              'nueva', Icons.note_add_outlined, tr('Nueva nota este día')),
        ]);
    if (choice == 'nueva') onNewOnDay(day);
  }

  @override
  Widget build(BuildContext context) {
    final first = DateTime(month.year, month.month, 1);
    // Por calendario, no restando horas: un cambio de hora movería el día.
    final gridStart =
        DateTime(first.year, first.month, 1 - (first.weekday - 1));
    final gridEnd =
        DateTime(gridStart.year, gridStart.month, gridStart.day + 41);
    final today = _day(DateTime.now());
    final visible = notes.where((n) {
      final s = _day(n.periodStart.toLocal());
      final e = _day(n.dueAt!.toLocal());
      return !e.isBefore(gridStart) && !s.isAfter(gridEnd);
    }).toList();
    // Filas de todo el mes: una línea no cambia de fila al pasar de semana.
    final rows = assignLanes(visible);
    final weeks = [
      for (var w = 0; w < 6; w++)
        layoutWeek(
            DateTime(gridStart.year, gridStart.month, gridStart.day + w * 7),
            visible,
            lanes: _maxLanes,
            assigned: rows),
    ];

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
                      child: Builder(builder: (context) {
                        final day = DateTime(gridStart.year, gridStart.month,
                            gridStart.day + w * 7 + d);
                        return _cell(context, day, today, weeks[w][day]!);
                      }),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _cell(
      BuildContext context, DateTime day, DateTime today, DaySlots slots) {
    final inMonth = day.month == month.month;
    final isToday = day == today;
    final isSel = day == selected;
    final extra = slots.extra;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => onSelect(day),
      onSecondaryTapUp: (d) => _dayMenu(context, day, d.globalPosition),
      child: Stack(
        // La columna ocupa toda la celda: el número y el círculo de hoy
        // quedan centrados (antes, sin tareas, se iban a la izquierda).
        fit: StackFit.expand,
        children: [
          Positioned.fill(
            child: AnimatedContainer(
              duration: Anim.fast,
              margin: const EdgeInsets.all(2),
              decoration: BoxDecoration(
                color:
                    isSel ? accent.withValues(alpha: 0.12) : Colors.transparent,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isSel
                      ? accent.withValues(alpha: 0.7)
                      : Colors.transparent,
                  width: 1.5,
                ),
              ),
            ),
          ),
          Column(
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
                            : Palette.secondary(context)
                                .withValues(alpha: 0.45)),
                  ),
                ),
              ),
              const Spacer(),
              // La primera fila es la de abajo: las líneas crecen hacia arriba.
              for (var lane = _maxLanes - 1; lane >= 0; lane--)
                _laneBar(context, day, slots.notes[lane], inMonth),
              const SizedBox(height: 3),
            ],
          ),
          if (extra > 0)
            Positioned(
              top: 7,
              right: 7,
              child: Text('+$extra',
                  style: TextStyle(
                      fontSize: 9.5,
                      fontWeight: FontWeight.w700,
                      color: Palette.secondary(context))),
            ),
        ],
      ),
    );
  }

  /// Tarea de varios días: el primer y el último día son línea entera y los
  /// de en medio, discontinuos. La de un solo día es una línea entera.
  Widget _laneBar(BuildContext context, DateTime day, Note? n, bool inMonth) {
    if (n == null) return const SizedBox(height: _barHeight + _barGap);
    final s = _day(n.periodStart.toLocal());
    final e = _day(n.dueAt!.toLocal());
    final fade = inMonth ? 1.0 : 0.45;
    final color = n.done
        ? Palette.secondary(context).withValues(alpha: 0.6 * fade)
        : (n.color != null
                ? Color(n.color!)
                : fuseForTheme(context, notePalette(n)).first)
            .withValues(alpha: 0.95 * fade);
    return Padding(
      padding: EdgeInsets.only(
        left: day == s ? 4 : 0,
        right: day == e ? 4 : 0,
        bottom: _barGap,
      ),
      child: day == s || day == e
          ? Container(
              height: _barHeight,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.horizontal(
                  left: Radius.circular(day == s ? _barHeight / 2 : 0),
                  right: Radius.circular(day == e ? _barHeight / 2 : 0),
                ),
              ),
            )
          : CustomPaint(
              size: const Size(double.infinity, _barHeight),
              painter: _DashPainter(color),
            ),
    );
  }
}

/// Rayitas iguales que encajan en el ancho: el hueco del final de un día
/// continúa en el siguiente y la línea se ve seguida.
class _DashPainter extends CustomPainter {
  const _DashPainter(this.color);
  final Color color;

  static const _dash = 13.0, _gap = 8.0;

  @override
  void paint(Canvas canvas, Size size) {
    final count = (size.width / (_dash + _gap)).round().clamp(1, 1000);
    final step = size.width / count;
    final y = size.height / 2;
    final paint = Paint()
      ..color = color
      ..strokeWidth = size.height
      ..strokeCap = StrokeCap.round;
    // Las puntas redondas ya ocupan medio grosor a cada lado.
    final inset = (_gap + size.height) / 2;
    for (var i = 0; i < count; i++) {
      canvas.drawLine(Offset(i * step + inset, y),
          Offset((i + 1) * step - inset, y), paint);
    }
  }

  @override
  bool shouldRepaint(_DashPainter o) => o.color != color;
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
                        Text(tr('Día libre'),
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
    return _HoverCard(
      color: onCard ? Palette.background(context) : Palette.card(context),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          // Sin la mancha gris al pasar el ratón: lo hace _HoverCard.
          hoverColor: Colors.transparent,
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
                  tooltip: note.done ? tr('Marcar pendiente') : tr('Completar'),
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
                  tooltip: tr('Cambiar fechas'),
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
    final sameYear = day.year == DateTime.now().year;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 16, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(tr(_diasSemana[day.weekday - 1]).toUpperCase(),
                    style: TextStyle(
                        fontSize: 11.5,
                        letterSpacing: 1.2,
                        fontWeight: FontWeight.w700,
                        color: Palette.accent(context))),
                const SizedBox(height: 2),
                Text(
                    sameYear
                        ? trf('{0} de {1}',
                            [day.day, tr(mesesNombre[day.month - 1])])
                        : trf('{0} de {1} de {2}', [
                            day.day,
                            tr(mesesNombre[day.month - 1]),
                            day.year
                          ]),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 20, fontWeight: FontWeight.w800)),
                const SizedBox(height: 2),
                Text(
                  count == 0
                      ? tr('Sin tareas')
                      : trn(count, '{0} tarea', '{0} tareas'),
                  style: TextStyle(
                      color: Palette.secondary(context), fontSize: 13),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Bouncy(
            child: IconButton.filledTonal(
              tooltip: tr('Nueva tarea este día'),
              onPressed: onNew,
              icon: const Icon(Icons.add_rounded),
            ),
          ),
        ],
      ),
    );
  }
}

/// Tarjeta con un resaltado limpio al pasar el ratón: borde suave del color
/// del tema, sombra ligera y un poco de tinte (en vez del gris plano del
/// InkWell). Al pulsar encoge un poco.
class _HoverCard extends StatefulWidget {
  const _HoverCard({required this.color, required this.child});
  final Color color;
  final Widget child;

  @override
  State<_HoverCard> createState() => _HoverCardState();
}

class _HoverCardState extends State<_HoverCard> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final accent = Palette.accent(context);
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: Bouncy(
        pressedScale: 0.985,
        child: AnimatedContainer(
          duration: Anim.medium,
          curve: Anim.curve,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: _hover
                ? Color.alphaBlend(accent.withValues(alpha: 0.05), widget.color)
                : widget.color,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: _hover
                  ? accent.withValues(alpha: 0.45)
                  : accent.withValues(alpha: 0),
              width: 1.2,
            ),
            boxShadow: [
              BoxShadow(
                color: accent.withValues(alpha: _hover ? 0.14 : 0),
                blurRadius: _hover ? 16 : 0,
                offset: Offset(0, _hover ? 5 : 0),
              ),
            ],
          ),
          child: widget.child,
        ),
      ),
    );
  }
}
