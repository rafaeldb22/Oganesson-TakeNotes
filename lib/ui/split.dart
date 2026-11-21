import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'anim.dart';
import 'theme.dart';

/// Dos paneles lado a lado con un separador que se arrastra para cambiar
/// el ancho del panel izquierdo. El ancho elegido se recuerda.
///
/// Optimizado: al arrastrar solo cambia el ancho; los paneles son los mismos
/// widgets, así que no se reconstruyen, solo se recolocan.
class ResizableSplit extends StatefulWidget {
  const ResizableSplit({
    super.key,
    required this.storageKey,
    required this.left,
    required this.right,
    this.initialFraction = 0.34,
    this.minLeft = 280,
    this.maxLeft = 560,
    this.minRight = 320,
  });

  final String storageKey;
  final Widget left;
  final Widget right;
  final double initialFraction;
  final double minLeft;
  final double maxLeft;
  final double minRight;

  @override
  State<ResizableSplit> createState() => _ResizableSplitState();
}

class _ResizableSplitState extends State<ResizableSplit> {
  double? _width; // ancho guardado del panel izquierdo
  bool _hover = false;
  bool _dragging = false;

  String get _key => 'split_${widget.storageKey}';

  @override
  void initState() {
    super.initState();
    SharedPreferences.getInstance().then((p) {
      final w = p.getDouble(_key);
      if (w != null && mounted) setState(() => _width = w);
    }).catchError((_) {});
  }

  void _save() {
    final w = _width;
    if (w == null) return;
    SharedPreferences.getInstance()
        .then((p) => p.setDouble(_key, w))
        .catchError((_) => false);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      final maxAllowed =
          (c.maxWidth - widget.minRight).clamp(widget.minLeft, widget.maxLeft);
      final w = (_width ?? c.maxWidth * widget.initialFraction)
          .clamp(widget.minLeft, maxAllowed);
      final active = _hover || _dragging;
      final accent = Palette.accent(context);

      return Row(
        children: [
          SizedBox(width: w, child: widget.left),
          MouseRegion(
            cursor: SystemMouseCursors.resizeColumn,
            onEnter: (_) => setState(() => _hover = true),
            onExit: (_) => setState(() => _hover = false),
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onHorizontalDragStart: (_) => setState(() => _dragging = true),
              onHorizontalDragUpdate: (d) => setState(() {
                _width = (w + d.delta.dx).clamp(widget.minLeft, maxAllowed);
              }),
              onHorizontalDragEnd: (_) {
                setState(() => _dragging = false);
                _save();
              },
              onDoubleTap: () {
                setState(() => _width = c.maxWidth * widget.initialFraction);
                _save();
                HapticFeedback.selectionClick();
              },
              child: SizedBox(
                width: 9,
                child: Center(
                  child: AnimatedContainer(
                    duration: Anim.fast,
                    width: active ? 3 : 1,
                    decoration: BoxDecoration(
                      color: active ? accent : Palette.separator(context),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
              ),
            ),
          ),
          Expanded(child: widget.right),
        ],
      );
    });
  }
}
