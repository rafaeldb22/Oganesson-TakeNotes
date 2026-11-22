import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart' show DragStartBehavior;
import 'package:flutter/material.dart';

import 'anim.dart';
import 'i18n.dart';
import 'theme.dart';

/// Un trazo: puntos, color y grosor.
class Stroke {
  Stroke(this.color, this.width, [List<Offset>? points])
      : points = points ?? [];
  final Color color;
  final double width;
  final List<Offset> points;
}

/// Pinta los trazos con curvas suaves entre los puntos.
void paintStrokes(Canvas canvas, Iterable<Stroke> strokes) {
  for (final s in strokes) {
    final paint = Paint()
      ..color = s.color
      ..strokeWidth = s.width
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke
      ..isAntiAlias = true;
    final p = s.points;
    if (p.isEmpty) continue;
    if (p.length == 1) {
      canvas.drawCircle(
          p.first, s.width / 2, paint..style = PaintingStyle.fill);
      continue;
    }
    final path = Path()..moveTo(p.first.dx, p.first.dy);
    for (var i = 1; i < p.length - 1; i++) {
      final mid = (p[i] + p[i + 1]) / 2;
      path.quadraticBezierTo(p[i].dx, p[i].dy, mid.dx, mid.dy);
    }
    path.lineTo(p.last.dx, p.last.dy);
    canvas.drawPath(path, paint);
  }
}

/// ¿Pasa el trazo a menos de [radius] de [at]? (goma por trazos).
bool strokeHit(Stroke s, Offset at, double radius) {
  final r = radius + s.width / 2;
  final p = s.points;
  if (p.length == 1) return (p.first - at).distance <= r;
  for (var i = 0; i < p.length - 1; i++) {
    final a = p[i], ab = p[i + 1] - a;
    final len = ab.distanceSquared;
    final t = len == 0
        ? 0.0
        : (((at - a).dx * ab.dx + (at - a).dy * ab.dy) / len).clamp(0.0, 1.0);
    if ((a + ab * t - at).distance <= r) return true;
  }
  return false;
}

/// Abre el lienzo. Con [background] se dibuja encima de esa imagen.
/// Devuelve el PNG resultante, o null si se cancela.
Future<Uint8List?> showDrawingPad(BuildContext context,
    {Uint8List? background}) async {
  ui.Image? image;
  if (background != null) {
    try {
      final codec = await ui.instantiateImageCodec(background);
      image = (await codec.getNextFrame()).image;
    } catch (_) {}
  }
  if (!context.mounted) return null;
  final result = await Navigator.of(context).push<Uint8List>(
    PageRouteBuilder(
      opaque: true,
      transitionDuration: Anim.medium,
      reverseTransitionDuration: Anim.fast,
      pageBuilder: (_, __, ___) => DrawingPad(background: image),
      transitionsBuilder: (_, a, __, c) => FadeTransition(
        opacity: a,
        child: ScaleTransition(
          scale: Tween(begin: 0.97, end: 1.0)
              .animate(CurvedAnimation(parent: a, curve: Anim.curve)),
          child: c,
        ),
      ),
    ),
  );
  image?.dispose();
  return result;
}

class DrawingPad extends StatefulWidget {
  const DrawingPad({super.key, this.background});
  final ui.Image? background;

  @override
  State<DrawingPad> createState() => _DrawingPadState();
}

class _DrawingPadState extends State<DrawingPad> {
  static const _colors = [
    Color(0xFF1C1C1E),
    Color(0xFFE5484D),
    Color(0xFFF5A524),
    Color(0xFF30A46C),
    Color(0xFF3E8BFF),
    Color(0xFF8E4EC6),
    Colors.white,
  ];
  static const _widths = [2.5, 5.0, 10.0];

  final _strokes = <Stroke>[];
  final _undone = <Stroke>[];
  Color _color = _colors.first;
  double _width = _widths[1];
  bool _eraser = false;
  Stroke? _current;
  Size _canvas = Size.zero;
  bool _saving = false;

  /// De coordenadas de pantalla a las del dibujo (la imagen a tamaño real).
  double get _scale {
    final bg = widget.background;
    if (bg == null || _canvas.isEmpty) return 1;
    return bg.width / _canvas.width;
  }

  void _down(Offset at) {
    if (_eraser) return _erase(at);
    final s = Stroke(_color, _width * _scale, [at * _scale]);
    setState(() {
      _current = s;
      _strokes.add(s);
      _undone.clear();
    });
  }

  void _move(Offset at) {
    if (_eraser) return _erase(at);
    final s = _current;
    if (s == null) return;
    final p = at * _scale;
    if ((p - s.points.last).distance < 0.8 * _scale) return;
    setState(() => s.points.add(p));
  }

  void _erase(Offset at) {
    final p = at * _scale;
    final hit = _strokes.where((s) => strokeHit(s, p, 8 * _scale)).toList();
    if (hit.isEmpty) return;
    setState(() {
      _strokes.removeWhere(hit.contains);
      _undone.addAll(hit);
    });
  }

  void _undo() {
    if (_strokes.isEmpty) return;
    setState(() => _undone.add(_strokes.removeLast()));
  }

  void _redo() {
    if (_undone.isEmpty) return;
    setState(() => _strokes.add(_undone.removeLast()));
  }

  Future<void> _save() async {
    if (_saving) return;
    final bg = widget.background;
    if (_strokes.isEmpty && bg == null) {
      Navigator.pop(context);
      return;
    }
    setState(() => _saving = true);
    final w = bg?.width ?? (_canvas.width * 2).round();
    final h = bg?.height ?? (_canvas.height * 2).round();
    final rec = ui.PictureRecorder();
    final c = Canvas(rec);
    if (bg != null) {
      c.drawImage(bg, Offset.zero, Paint());
    } else {
      c.drawRect(Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()),
          Paint()..color = Colors.white);
      c.scale(2);
    }
    paintStrokes(c, _strokes);
    final picture = rec.endRecording();
    final out = await picture.toImage(w, h);
    final data = await out.toByteData(format: ui.ImageByteFormat.png);
    picture.dispose();
    out.dispose();
    if (!mounted) return;
    Navigator.pop(context, data?.buffer.asUint8List());
  }

  Future<void> _close() async {
    if (_strokes.isEmpty) {
      Navigator.pop(context);
      return;
    }
    final leave = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('¿Descartar el dibujo?')),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(tr('Seguir dibujando'))),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(tr('Descartar'))),
        ],
      ),
    );
    if (leave == true && mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final bg = widget.background;
    Widget surface = LayoutBuilder(builder: (_, c) {
      _canvas = c.biggest;
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        dragStartBehavior: DragStartBehavior.down,
        onPanDown: (d) => _down(d.localPosition),
        onPanUpdate: (d) => _move(d.localPosition),
        onPanEnd: (_) => _current = null,
        onPanCancel: () => _current = null,
        child: RepaintBoundary(
          child: CustomPaint(
            key: const ValueKey('lienzo'),
            size: c.biggest,
            painter: _PadPainter(bg, _strokes, _strokes.length, _current),
          ),
        ),
      );
    });
    if (bg != null) {
      surface = Center(
          child:
              AspectRatio(aspectRatio: bg.width / bg.height, child: surface));
    }
    return PopScope(
      canPop: _strokes.isEmpty,
      onPopInvokedWithResult: (popped, _) {
        if (!popped) _close();
      },
      child: Scaffold(
        backgroundColor: p.background,
        appBar: AppBar(
          leading: IconButton(
              tooltip: tr('Cerrar'),
              icon: const Icon(Icons.close_rounded),
              onPressed: _close),
          title: Text(tr('Dibujo')),
          actions: [
            IconButton(
                tooltip: tr('Deshacer'),
                onPressed: _strokes.isEmpty ? null : _undo,
                icon: const Icon(Icons.undo_rounded)),
            IconButton(
                tooltip: tr('Rehacer'),
                onPressed: _undone.isEmpty ? null : _redo,
                icon: const Icon(Icons.redo_rounded)),
            Padding(
              padding: const EdgeInsets.only(left: 6, right: 10),
              child: FilledButton(
                  onPressed: _saving ? null : _save,
                  child: Text(tr('Guardar'))),
            ),
          ],
        ),
        body: SafeArea(
          child: Column(
            children: [
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(10),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: ColoredBox(
                        color: bg == null ? Colors.white : Colors.transparent,
                        child: surface),
                  ),
                ),
              ),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
                child: Row(
                  children: [
                    for (final c in _colors)
                      GestureDetector(
                        onTap: () => setState(() {
                          _color = c;
                          _eraser = false;
                        }),
                        child: AnimatedContainer(
                          duration: Anim.fast,
                          curve: Anim.curve,
                          width: _color == c && !_eraser ? 34 : 28,
                          height: _color == c && !_eraser ? 34 : 28,
                          margin: const EdgeInsets.symmetric(horizontal: 4),
                          decoration: BoxDecoration(
                            color: c,
                            shape: BoxShape.circle,
                            border: Border.all(
                                color: _color == c && !_eraser
                                    ? p.accent
                                    : p.separator,
                                width: _color == c && !_eraser ? 2.5 : 1),
                          ),
                        ),
                      ),
                    Container(
                        width: 1,
                        height: 26,
                        margin: const EdgeInsets.symmetric(horizontal: 8),
                        color: p.separator),
                    for (final w in _widths)
                      IconButton(
                        tooltip: tr('Grosor'),
                        isSelected: _width == w && !_eraser,
                        onPressed: () => setState(() {
                          _width = w;
                          _eraser = false;
                        }),
                        icon: Container(
                          width: w + 6,
                          height: w + 6,
                          decoration: BoxDecoration(
                            color: _width == w && !_eraser
                                ? p.accent
                                : p.secondary,
                            shape: BoxShape.circle,
                          ),
                        ),
                      ),
                    IconButton(
                      tooltip: tr('Goma'),
                      isSelected: _eraser,
                      color: _eraser ? p.accent : null,
                      onPressed: () => setState(() => _eraser = !_eraser),
                      icon: const Icon(Icons.auto_fix_normal_rounded),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PadPainter extends CustomPainter {
  _PadPainter(this.bg, this.strokes, this.count, this.current)
      : points = current?.points.length ?? 0;
  final ui.Image? bg;
  final List<Stroke> strokes;
  final int count;
  final Stroke? current;
  final int points;

  @override
  void paint(Canvas canvas, Size size) {
    final b = bg;
    if (b != null) {
      final src = Rect.fromLTWH(0, 0, b.width.toDouble(), b.height.toDouble());
      canvas.drawImageRect(b, src, Offset.zero & size, Paint());
      final k = size.width / b.width;
      canvas.scale(k);
    }
    paintStrokes(canvas, strokes);
  }

  @override
  bool shouldRepaint(_PadPainter o) =>
      o.count != count || o.points != points || o.current != current;
}
