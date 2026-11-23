import 'package:flutter/material.dart';

import 'i18n.dart';
import '../models/note.dart';
import 'format.dart';
import 'theme.dart';
import 'urgency.dart';

/// Tamaños del widget "Calendario" de Android.
enum CalendarWidgetSize {
  /// 2x2: solo el mes.
  small(Size(170, 170), 'calendario_img_s'),

  /// 4x2: mes a la izquierda y tareas a la derecha.
  medium(Size(360, 180), 'calendario_img_m'),

  /// 4x4: mes arriba y lista de tareas debajo.
  large(Size(360, 380), 'calendario_img_l');

  const CalendarWidgetSize(this.logicalSize, this.key);
  final Size logicalSize;

  /// Clave con la que se guarda la imagen (la lee CalendarioWidget.kt).
  final String key;
}

/// Contenido del widget "Calendario" de Android en el tamaño [size]:
/// mes actual y tareas ordenadas por fecha límite.
/// Se dibuja fuera de pantalla y se guarda como imagen para el widget,
/// así que solo usa widgets simples (sin animaciones ni Material).
class CalendarWidgetImage extends StatelessWidget {
  const CalendarWidgetImage({
    super.key,
    required this.notes,
    required this.colors,
    required this.dark,
    this.size = CalendarWidgetSize.medium,
  });

  final CalendarWidgetSize size;
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
    final name = tr(mesesNombre[now.month - 1]);
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

    final dias = diasIniciales;

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

    // Cuántas tareas caben: alto de cada fila con margen para fuentes
    // más altas que la de diseño (la imagen se dibuja en el móvil).
    const rowHeight = 39.0, headerHeight = 24.0, labelHeight = 16.0;
    // Tareas de hoy (activas este día) primero; después las próximas.
    bool activeToday(Note n) {
      final st = _d(n.periodStart.toLocal());
      final e = _d(n.dueAt!.toLocal());
      return !today.isBefore(st) && !today.isAfter(e);
    }

    final todayTasks = pending.where(activeToday).toList();
    final upcoming = pending.where((n) => !activeToday(n)).toList();
    final mes = tr(mesesNombre[now.month - 1]);

    final tasks = LayoutBuilder(builder: (context, c) {
      var room = c.maxHeight - headerHeight;
      final rows = <Widget>[];
      Widget label(String t) => Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(t.toUpperCase(),
                style: TextStyle(
                    color: colors.secondary,
                    fontSize: 8.5,
                    letterSpacing: 0.8,
                    fontWeight: FontWeight.w800)),
          );
      if (todayTasks.isEmpty) {
        rows.add(Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Text(tr('Nada para hoy'),
              style: TextStyle(color: colors.secondary, fontSize: 10)),
        ));
        room -= labelHeight;
      }
      for (final n in todayTasks) {
        if (room < rowHeight) break;
        rows.add(Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: WidgetTaskRow(note: n, fg: fg, colors: colors),
        ));
        room -= rowHeight;
      }
      if (upcoming.isNotEmpty && room >= rowHeight + labelHeight) {
        rows.add(label(tr('Próximas')));
        room -= labelHeight;
        for (final n in upcoming) {
          if (room < rowHeight) break;
          rows.add(Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: WidgetTaskRow(note: n, fg: fg, colors: colors),
          ));
          room -= rowHeight;
        }
      }
      if (pending.isEmpty) {
        rows
          ..clear()
          ..add(Expanded(
            child: Center(
              child: Text(tr('Sin tareas pendientes'),
                  style: TextStyle(color: colors.secondary, fontSize: 10)),
            ),
          ));
      }
      return ClipRect(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(tr('Hoy'),
                    style: TextStyle(
                        color: fg, fontSize: 13, fontWeight: FontWeight.w800)),
                const SizedBox(width: 6),
                Text('${now.day} ${mes.substring(0, 3)}',
                    style: TextStyle(
                        color: colors.secondary,
                        fontSize: 10.5,
                        fontWeight: FontWeight.w600)),
                const Spacer(),
                Text('${todayTasks.length}',
                    style: TextStyle(
                        color: colors.accent,
                        fontSize: 11,
                        fontWeight: FontWeight.w800)),
              ],
            ),
            const SizedBox(height: 6),
            ...rows,
          ],
        ),
      );
    });

    return Directionality(
      textDirection: TextDirection.ltr,
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
        decoration: BoxDecoration(
          color: colors.card,
          borderRadius: BorderRadius.circular(22),
        ),
        child: switch (size) {
          CalendarWidgetSize.small => calendar,
          // 4x2: las tareas del día a la izquierda y el mes a la derecha.
          CalendarWidgetSize.medium => Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(flex: 11, child: tasks),
                Container(
                  width: 1,
                  margin:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  color: colors.separator,
                ),
                Expanded(flex: 10, child: calendar),
              ],
            ),
          CalendarWidgetSize.large => Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(flex: 8, child: calendar),
                Container(
                  height: 1,
                  margin: const EdgeInsets.symmetric(vertical: 8),
                  color: colors.separator,
                ),
                Expanded(flex: 11, child: tasks),
              ],
            ),
        },
      ),
    );
  }
}

class WidgetTaskRow extends StatelessWidget {
  const WidgetTaskRow(
      {super.key, required this.note, required this.fg, required this.colors});
  final Note note;
  final Color fg;
  final NotasColors colors;

  @override
  Widget build(BuildContext context) {
    final stops = fusePalette(note.color);
    final p = note.progress();
    // Texto oscuro (fg) = widget en modo claro: color de aviso legible.
    final c = readableOn(note.isOverdue() ? stops.last : paletteAt(stops, p),
        light: fg.computeLuminance() < 0.5);
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
        if (note.showsBar())
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
          )
        else
          const SizedBox(height: 3.5),
        const SizedBox(height: 2),
        Text(tiempoRestante(note.dueAt!),
            style: TextStyle(
                color: c, fontSize: 8.5, fontWeight: FontWeight.w700)),
      ],
    );
  }
}
