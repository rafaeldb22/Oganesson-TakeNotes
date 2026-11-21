import 'package:flutter/material.dart';

import 'anim.dart';
import 'theme.dart';

/// Zona donde soltar una nota arrastrada (cabecera de "Fijadas",
/// "Sin carpeta", principio o final de la lista). No dibuja recuadros: al
/// pasar una nota por encima solo aparece la línea de inserción, igual que
/// entre notas. Sin [child] es una franja fija de [height] de alto.
class DropZone extends StatefulWidget {
  const DropZone({
    super.key,
    required this.onDrop,
    this.child,
    this.height = 14,
  });

  final void Function(String noteId) onDrop;
  final Widget? child;
  final double height;

  @override
  State<DropZone> createState() => _DropZoneState();
}

class _DropZoneState extends State<DropZone> {
  bool _over = false;

  @override
  Widget build(BuildContext context) {
    final line = AnimatedContainer(
      duration: Anim.fast,
      curve: Anim.curve,
      height: _over ? 3 : 0,
      margin: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: Palette.accent(context),
        borderRadius: BorderRadius.circular(2),
      ),
    );
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
      builder: (context, _, __) => widget.child == null
          ? SizedBox(
              height: widget.height,
              child: Center(child: line),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [widget.child!, line],
            ),
    );
  }
}
