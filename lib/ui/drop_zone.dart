import 'package:flutter/material.dart';

import 'anim.dart';
import 'theme.dart';

/// Zona donde soltar una nota arrastrada (cabecera de "Fijadas",
/// "Sin carpeta"…). Se ilumina al pasar una nota por encima.
class DropZone extends StatefulWidget {
  const DropZone({
    super.key,
    required this.active,
    required this.onDrop,
    required this.child,
    this.hint,
  });

  /// Hay una nota arrastrándose (muestra la zona aunque esté vacía).
  final bool active;
  final void Function(String noteId) onDrop;
  final Widget child;

  /// Texto cuando la zona no tiene notas ("Suelta aquí").
  final String? hint;

  @override
  State<DropZone> createState() => _DropZoneState();
}

class _DropZoneState extends State<DropZone> {
  bool _over = false;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return DragTarget<String>(
      onWillAcceptWithDetails: (_) {
        setState(() => _over = true);
        return true;
      },
      onLeave: (_) => setState(() => _over = false),
      onAcceptWithDetails: (d) {
        setState(() => _over = false);
        widget.onDrop(d.data);
      },
      builder: (context, _, __) => AnimatedContainer(
        duration: Anim.fast,
        curve: Anim.curve,
        decoration: BoxDecoration(
          color: _over ? p.accent.withValues(alpha: 0.12) : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: _over
                ? p.accent.withValues(alpha: 0.6)
                : (widget.active ? p.separator : Colors.transparent),
            width: 1.2,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            widget.child,
            if (widget.active && widget.hint != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
                child: Text(widget.hint!,
                    style: TextStyle(fontSize: 12.5, color: p.secondary)),
              ),
          ],
        ),
      ),
    );
  }
}
