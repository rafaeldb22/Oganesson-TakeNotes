import 'package:flutter/material.dart';

import '../models/note.dart';
import 'format.dart';
import 'theme.dart';
import 'urgency.dart';

/// Contenido del widget "Calendario" de Android (4x2): mes actual a la
/// izquierda y tareas ordenadas por fecha límite a la derecha.
/// Se dibuja fuera de pantalla y se guarda como imagen para el widget,
/// así que solo usa widgets simples (sin animaciones ni Material).
class CalendarWidgetImage extends StatelessWidget {
  const CalendarWidgetImage({
    super.key,
    required this.notes,
    required this.colors,
    required this.dark,
  });

  final List<Note> notes; // temporales pendientes
  final NotasColors colors;
  final bool dark;

  static DateTime _d(DateTime x) => DateTime(x.year, x.month, x.day);

  @override
  Widget build(BuildContext context) {
    final fg = dark ? Colors.white : const Color(0xFF151515);
    final now = DateTime.now();
    final today = _d(now);
    final first = DateTime(now.year, now.month, 1);
    final gridStart = first.subtract(Duration(days: first.weekday - 1));
    final name = mesesNombre[now.month - 1];
    final pending = notes.where((n) => !n.done).toList()
      ..sort((a, b) => a.dueAt!.compareTo(b.dueAt!));

    // Días con alguna tarea activa → color de la más urgente ese día.
    Color? dayColor(DateTime day) {
      for (final n in pending) {
        final s = _d(n.periodStart.toLocal());
        final e = _d(n.dueAt!.toLocal());
        if (!day.isBefore(s) && !day.isAfter(e)) {
          final total = e.difference(s).inDays;
          final t = total <= 0 ? 1.0 : day.difference(s).inDays / total;
          return paletteAt(fusePalette(n.color), t);
        }
      }
      return null;
    }

    const dias = ['L', 'M', 'X', 'J', 'V', 'S', 'D'];

    final calendar = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${name[0].toUpperCase()}${name.substring(1)}',
          style: TextStyle(
              color: colors.accent, fontSize: 13, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            for (final d in dias)
              Expanded(
                child: Center(
                  child: Text(d,
                      style: TextStyle(
                          fontSize: 7.5,
                          fontWeight: FontWeight.w700,
                          color: colors.secondary)),
                ),
              ),
          ],
        ),
        const SizedBox(height: 2),
        for (var w = 0; w < 6; w++)
          Expanded(
            child: Row(
              children: [
                for (var i = 0; i < 7; i++)
                  Expanded(
                    child: Builder(builder: (_) {
                      final day = DateTime(gridStart.year, gridStart.month,
                          gridStart.day + w * 7 + i);
                      final inMonth = day.month == now.month;
                      final isToday = day == today;
                      final c = inMonth ? dayColor(day) : null;
                      return Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            width: 15,
                            height: 15,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: isToday ? colors.accent : null,
                              shape: BoxShape.circle,
                            ),
                            child: Text(
                              '${day.day}',
                              style: TextStyle(
                                fontSize: 8,
                                fontWeight:
                                    isToday ? FontWeight.w800 : FontWeight.w500,
                                color: isToday
                                    ? colors.onAccent
                                    : (inMonth
                                        ? fg
                                        : colors.secondary
                                            .withValues(alpha: 0.4)),
                              ),
                            ),
                          ),
                          Container(
                            width: 12,
                            height: 2.5,
                            decoration: BoxDecoration(
                              color: c ?? Colors.transparent,
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                        ],
                      );
                    }),
                  ),
              ],
            ),
          ),
      ],
    );

    final tasks = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('Tareas',
                style: TextStyle(
                    color: fg, fontSize: 13, fontWeight: FontWeight.w800)),
            const Spacer(),
            Text('${pending.length}',
                style: TextStyle(
                    color: colors.secondary,
                    fontSize: 11,
                    fontWeight: FontWeight.w700)),
          ],
        ),
        const SizedBox(height: 6),
        if (pending.isEmpty)
          Expanded(
            child: Center(
              child: Text('Sin tareas pendientes',
                  style: TextStyle(color: colors.secondary, fontSize: 10)),
            ),
          )
        else
          for (final n in pending.take(4))
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: _TaskRow(note: n, fg: fg, colors: colors),
            ),
        if (pending.length > 4)
          Text('+${pending.length - 4} más',
              style: TextStyle(color: colors.secondary, fontSize: 9)),
      ],
    );

    return Directionality(
      textDirection: TextDirection.ltr,
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
        decoration: BoxDecoration(
          color: colors.card,
          borderRadius: BorderRadius.circular(22),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(flex: 10, child: calendar),
            Container(
              width: 1,
              margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              color: colors.separator,
            ),
            Expanded(flex: 11, child: tasks),
          ],
        ),
      ),
    );
  }
}

class _TaskRow extends StatelessWidget {
  const _TaskRow({required this.note, required this.fg, required this.colors});
  final Note note;
  final Color fg;
  final NotasColors colors;

  @override
  Widget build(BuildContext context) {
    final stops = fusePalette(note.color);
    final p = note.progress();
    final c = note.isOverdue() ? stops.last : paletteAt(stops, p);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(note.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      color: fg, fontSize: 10.5, fontWeight: FontWeight.w600)),
            ),
            const SizedBox(width: 4),
            Text(fechaMedia(note.dueAt!).split(',').first,
                style: TextStyle(color: colors.secondary, fontSize: 8.5)),
          ],
        ),
        const SizedBox(height: 3),
        // Mecha estática: degradado hasta el punto actual.
        ClipRRect(
          borderRadius: BorderRadius.circular(3),
          child: SizedBox(
            height: 3.5,
            child: Stack(
              children: [
                Container(color: colors.secondary.withValues(alpha: 0.18)),
                FractionallySizedBox(
                  widthFactor: p.clamp(0.04, 1.0),
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(colors: stops),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 2),
        Text(tiempoRestante(note.dueAt!),
            style: TextStyle(
                color: c, fontSize: 8.5, fontWeight: FontWeight.w700)),
      ],
    );
  }
}
