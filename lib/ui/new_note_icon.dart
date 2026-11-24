import 'package:flutter/material.dart';

/// Pósit con la esquina doblada y un + dentro: "crear una nota".
class NewNoteIcon extends StatelessWidget {
  const NewNoteIcon({super.key, this.size = 24, this.color});

  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) => CustomPaint(
        size: Size.square(size),
        painter: _PostItPainter(color ?? IconTheme.of(context).color!),
      );
}

class _PostItPainter extends CustomPainter {
  const _PostItPainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width;
    final a = s * 0.13, b = s - a, r = s * 0.1, fold = s * 0.29;
    final sheet = Path()
      ..moveTo(a + r, a)
      ..lineTo(b - r, a)
      ..arcToPoint(Offset(b, a + r), radius: Radius.circular(r))
      ..lineTo(b, b - fold)
      ..lineTo(b - fold, b)
      ..lineTo(a + r, b)
      ..arcToPoint(Offset(a, b - r), radius: Radius.circular(r))
      ..lineTo(a, a + r)
      ..arcToPoint(Offset(a + r, a), radius: Radius.circular(r))
      ..close();
    final corner = Path()
      ..moveTo(b, b - fold)
      ..lineTo(b - fold, b - fold)
      ..lineTo(b - fold, b)
      ..close();
    final line = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = s * 0.08
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(sheet, Paint()..color = color.withValues(alpha: 0.16));
    canvas.drawPath(corner, Paint()..color = color.withValues(alpha: 0.45));
    canvas.drawPath(sheet, line);
    canvas.drawPath(corner, line);
    final c = Offset(s * 0.44, s * 0.44), arm = s * 0.15;
    canvas.drawLine(c - Offset(arm, 0), c + Offset(arm, 0), line);
    canvas.drawLine(c - Offset(0, arm), c + Offset(0, arm), line);
  }

  @override
  bool shouldRepaint(_PostItPainter old) => old.color != color;
}
