import 'package:flutter/material.dart';

import '../models/note.dart';
import 'anim.dart';
import 'format.dart';
import 'theme.dart';

/// Rango del calendario: este mes, los 3 anteriores y los 3 siguientes.
/// Se calcula siempre con la fecha de hoy, así que se actualiza solo.
({DateTime first, DateTime last}) calendarRange([DateTime? now]) {
  final n = now ?? DateTime.now();
  return (
    first: DateTime(n.year, n.month - 3, 1),
    last: DateTime(n.year, n.month + 4, 0, 23, 59),
  );
}

/// Verde → ámbar → rojo según el tiempo consumido.
Color urgencyColor(BuildContext context, Note n) {
  if (n.done) return Palette.secondary(context);
  if (n.isOverdue()) return const Color(0xFFE5484D);
  final p = n.progress();
  if (p < 0.5) return const Color(0xFF30A46C);
  if (p < 0.8) return const Color(0xFFF5A524);
  return const Color(0xFFF76B15);
}

/// Barra de tiempo: cuánto se ha consumido y cuánto queda.
class TimeBar extends StatelessWidget {
  const TimeBar({super.key, required this.note, this.compact = false});
  final Note note;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final color = urgencyColor(context, note);
    final p = note.done ? 1.0 : note.progress();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(99),
          child: Stack(
            children: [
              Container(
                height: compact ? 4 : 6,
                color: color.withValues(alpha: 0.18),
              ),
              TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: p),
                duration: Anim.slow,
                curve: Anim.curve,
                builder: (context, v, _) => FractionallySizedBox(
                  widthFactor: v.clamp(0.0, 1.0),
                  child: Container(height: compact ? 4 : 6, color: color),
                ),
              ),
            ],
          ),
        ),
        if (!compact) ...[
          const SizedBox(height: 4),
          Row(
            children: [
              Icon(
                note.done
                    ? Icons.check_circle
                    : (note.isOverdue()
                        ? Icons.warning_amber_rounded
                        : Icons.timer_outlined),
                size: 14,
                color: color,
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  tiempoRestante(note.dueAt!, done: note.done),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 12, color: color, fontWeight: FontWeight.w600),
                ),
              ),
              Text(fechaMedia(note.dueAt!),
                  style: TextStyle(
                      fontSize: 12, color: Palette.secondary(context))),
            ],
          ),
        ],
      ],
    );
  }
}
