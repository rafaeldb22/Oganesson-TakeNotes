import 'package:flutter/material.dart';

import '../models/note.dart';
import 'calendar_widget_image.dart' show WidgetTaskRow;
import 'format.dart';
import 'i18n.dart';
import 'theme.dart';
import 'urgency.dart';

/// Contenidos de los widgets de Android que se dibujan como imagen (igual
/// que el del calendario): Tareas, Próxima tarea y Notas fijadas. Solo usan
/// widgets simples (sin animaciones ni Material) porque se pintan fuera de
/// pantalla.

/// Una imagen de widget: tamaño lógico en el que se dibuja y clave con la
/// que se guarda (la lee el proveedor de Kotlin).
class WidgetImageSpec {
  const WidgetImageSpec(this.key, this.size);
  final String key;
  final Size size;
}

class WidgetSpecs {
  static const tareasS = WidgetImageSpec('tareas_img_s', Size(170, 170));
  static const tareasM = WidgetImageSpec('tareas_img_m', Size(360, 180));
  static const tareasL = WidgetImageSpec('tareas_img_l', Size(360, 380));
  static const proximaW = WidgetImageSpec('proxima_img_w', Size(260, 110));
  static const proximaS = WidgetImageSpec('proxima_img_s', Size(180, 180));
  static const fijadasM = WidgetImageSpec('fijadas_img_m', Size(360, 180));
  static const fijadasL = WidgetImageSpec('fijadas_img_l', Size(360, 380));
}

DateTime _d(DateTime x) => DateTime(x.year, x.month, x.day);

/// Tarjeta base de los widgets: fondo del tema y esquinas redondeadas.
Widget _card(NotasColors colors, Widget child,
        {EdgeInsets padding = const EdgeInsets.fromLTRB(14, 12, 14, 10)}) =>
    Directionality(
      textDirection: TextDirection.ltr,
      child: Container(
        padding: padding,
        decoration: BoxDecoration(
          color: colors.card,
          borderRadius: BorderRadius.circular(22),
        ),
        child: child,
      ),
    );

Widget _header(String title, String? trailing, Color fg, NotasColors colors,
        {IconData? icon}) =>
    Row(
      children: [
        if (icon != null) ...[
          Icon(icon, size: 14, color: colors.accent),
          const SizedBox(width: 5),
        ],
        Expanded(
          child: Text(title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  color: fg, fontSize: 13, fontWeight: FontWeight.w800)),
        ),
        if (trailing != null)
          Text(trailing,
              style: TextStyle(
                  color: colors.accent,
                  fontSize: 11,
                  fontWeight: FontWeight.w800)),
      ],
    );

Color _fg(bool dark) => dark ? Colors.white : const Color(0xFF151515);

// ------------------------------------------------------------- Tareas

/// Widget "Tareas": las de hoy primero y después las próximas, con su
/// mecha. Se adapta al alto disponible (mete tantas filas como quepan).
class TasksWidgetImage extends StatelessWidget {
  const TasksWidgetImage({
    super.key,
    required this.notes,
    required this.colors,
    required this.dark,
  });

  final List<Note> notes; // temporales sin completar
  final NotasColors colors;
  final bool dark;

  @override
  Widget build(BuildContext context) {
    final fg = _fg(dark);
    final today = _d(DateTime.now());
    final pending = notes.toList()
      ..sort((a, b) => a.dueAt!.compareTo(b.dueAt!));
    bool activeToday(Note n) =>
        !today.isBefore(_d(n.periodStart.toLocal())) &&
        !today.isAfter(_d(n.dueAt!.toLocal()));
    final todays = pending.where(activeToday).toList();
    final rest = pending.where((n) => !activeToday(n)).toList();

    return _card(
      colors,
      LayoutBuilder(builder: (context, c) {
        const rowH = 39.0, headH = 24.0, labelH = 16.0;
        var room = c.maxHeight - headH;
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
        void addRows(List<Note> list) {
          for (final n in list) {
            if (room < rowH) return;
            rows.add(Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: WidgetTaskRow(note: n, fg: fg, colors: colors),
            ));
            room -= rowH;
          }
        }

        if (pending.isEmpty) {
          rows.add(Expanded(
            child: Center(
              child: Text(tr('Sin tareas pendientes'),
                  style: TextStyle(color: colors.secondary, fontSize: 11)),
            ),
          ));
        } else {
          if (todays.isEmpty) {
            rows.add(Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(tr('Nada para hoy'),
                  style: TextStyle(color: colors.secondary, fontSize: 10.5)),
            ));
            room -= labelH;
          }
          addRows(todays);
          if (rest.isNotEmpty && room >= rowH + labelH) {
            rows.add(label(tr('Próximas')));
            room -= labelH;
            addRows(rest);
          }
        }
        return ClipRect(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _header(tr('Tareas'), '${pending.length}', fg, colors,
                  icon: Icons.task_alt_rounded),
              const SizedBox(height: 8),
              ...rows,
            ],
          ),
        );
      }),
    );
  }
}

// ------------------------------------------------------ Próxima tarea

/// Widget "Próxima tarea": la que vence antes, con una cuenta atrás grande
/// y su mecha.
class NextTaskWidgetImage extends StatelessWidget {
  const NextTaskWidgetImage({
    super.key,
    required this.note,
    required this.colors,
    required this.dark,
    required this.wide,
  });

  final Note? note;
  final NotasColors colors;
  final bool dark;

  /// true = 2x1 (apaisado), false = 2x2.
  final bool wide;

  @override
  Widget build(BuildContext context) {
    final fg = _fg(dark);
    final n = note;
    if (n == null) {
      return _card(
        colors,
        Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.celebration_rounded, color: colors.accent, size: 26),
            const SizedBox(height: 6),
            Text(tr('Sin tareas pendientes'),
                textAlign: TextAlign.center,
                style: TextStyle(color: colors.secondary, fontSize: 12)),
          ],
        ),
      );
    }
    final stops = fusePalette(n.color);
    final p = n.progress();
    final color = readableOn(
        n.isOverdue() ? stops.last : paletteAt(stops, p),
        light: !dark);
    final remaining = tiempoRestante(n.dueAt!);

    final bar = ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: SizedBox(
        height: wide ? 6 : 7,
        child: Stack(
          children: [
            Container(color: colors.secondary.withValues(alpha: 0.2)),
            FractionallySizedBox(
              widthFactor: p.clamp(0.04, 1.0),
              child: Container(
                decoration:
                    BoxDecoration(gradient: LinearGradient(colors: stops)),
              ),
            ),
          ],
        ),
      ),
    );

    return _card(
      colors,
      padding: EdgeInsets.fromLTRB(14, wide ? 10 : 14, 14, wide ? 10 : 14),
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.local_fire_department_rounded, size: 13, color: color),
              const SizedBox(width: 4),
              Expanded(
                child: Text(tr('Próxima tarea').toUpperCase(),
                    maxLines: 1,
                    style: TextStyle(
                        color: colors.secondary,
                        fontSize: 8.5,
                        letterSpacing: 0.8,
                        fontWeight: FontWeight.w800)),
              ),
              Text(fechaMedia(n.dueAt!),
                  style: TextStyle(color: colors.secondary, fontSize: 9)),
            ],
          ),
          SizedBox(height: wide ? 4 : 8),
          Text(n.title,
              maxLines: wide ? 1 : 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  color: fg,
                  fontSize: wide ? 14 : 15,
                  fontWeight: FontWeight.w700,
                  height: 1.15)),
          const Spacer(),
          Text(remaining,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  color: color,
                  fontSize: wide ? 16 : 20,
                  fontWeight: FontWeight.w800)),
          SizedBox(height: wide ? 5 : 8),
          bar,
        ],
      ),
    );
  }
}

// ------------------------------------------------------ Notas fijadas

/// Widget "Notas fijadas": título y comienzo de las notas fijadas (o de
/// las más recientes si no hay ninguna fijada).
class PinnedWidgetImage extends StatelessWidget {
  const PinnedWidgetImage({
    super.key,
    required this.notes,
    required this.pinned,
    required this.colors,
    required this.dark,
  });

  final List<Note> notes;

  /// true si [notes] son las fijadas; false si son las recientes.
  final bool pinned;
  final NotasColors colors;
  final bool dark;

  @override
  Widget build(BuildContext context) {
    final fg = _fg(dark);
    return _card(
      colors,
      LayoutBuilder(builder: (context, c) {
        const rowH = 40.0, headH = 26.0;
        final fit = ((c.maxHeight - headH) / rowH).floor().clamp(1, 20);
        final shown = notes.take(fit).toList();
        return ClipRect(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _header(pinned ? tr('Fijadas') : tr('Recientes'),
                  '${notes.length}', fg, colors,
                  icon:
                      pinned ? Icons.push_pin_rounded : Icons.history_rounded),
              const SizedBox(height: 8),
              if (shown.isEmpty)
                Expanded(
                  child: Center(
                    child: Text(tr('Sin notas todavía'),
                        style:
                            TextStyle(color: colors.secondary, fontSize: 11)),
                  ),
                )
              else
                for (final (i, n) in shown.indexed) ...[
                  if (i > 0)
                    Container(
                        height: 1,
                        margin: const EdgeInsets.only(bottom: 5),
                        color: colors.separator.withValues(alpha: 0.6)),
                  SizedBox(
                    height: rowH - 6,
                    child: Row(
                      children: [
                        Container(
                          width: 3,
                          height: 26,
                          margin: const EdgeInsets.only(right: 8),
                          decoration: BoxDecoration(
                            color: n.color != null
                                ? Color(n.color!)
                                : colors.accent.withValues(alpha: 0.6),
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(n.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                      color: fg,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700)),
                              if (n.hasPreview)
                                Text(n.preview,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                        color: colors.secondary, fontSize: 10)),
                            ],
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(fechaCorta(n.updatedAt),
                            style: TextStyle(
                                color: colors.secondary, fontSize: 9)),
                      ],
                    ),
                  ),
                ],
            ],
          ),
        );
      }),
    );
  }
}
