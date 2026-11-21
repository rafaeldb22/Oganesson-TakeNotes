// Genera el logo de Oganesson con Flutter (sin herramientas externas):
//   flutter test tool/generate_icon_test.dart
// Escribe assets/icon/icon.png (icono completo), assets/icon/foreground.png
// (trazo para el icono adaptable de Android), assets/icon/background.png y
// docs/icon.png. Con ICON_PREVIEW=<carpeta> solo guarda vistas previas.
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notas/ui/logo.dart';

// Trazo y colores compartidos con la animación de inicio.
const navyTop = logoNavyTop;
const navyBottom = logoNavyBottom;
const goldStops = logoGold;
Path glyphPath(Size s) => logoGlyphPath(s);

class LogoPainter extends CustomPainter {
  LogoPainter({this.background = true, this.glyphScale = 1});

  /// false = solo el trazo (primer plano del icono adaptable).
  final bool background;

  /// Escala del trazo respecto al lienzo (el adaptable lo necesita menor).
  final double glyphScale;

  @override
  void paint(Canvas canvas, Size size) {
    final r = Offset.zero & size;
    if (background) {
      final rr =
          RRect.fromRectAndRadius(r, Radius.circular(size.width * 0.225));
      canvas.drawRRect(
          rr,
          Paint()
            ..shader = const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [navyTop, navyBottom],
            ).createShader(r));
      // Brillo suave arriba.
      canvas.save();
      canvas.clipRRect(rr);
      canvas.drawCircle(
          Offset(size.width * 0.5, -size.height * 0.15),
          size.width * 0.75,
          Paint()
            ..shader = RadialGradient(colors: [
              Colors.white.withValues(alpha: 0.10),
              Colors.white.withValues(alpha: 0),
            ]).createShader(Rect.fromCircle(
                center: Offset(size.width * 0.5, -size.height * 0.15),
                radius: size.width * 0.75)));
      canvas.restore();
    }

    final g = size.width * glyphScale;
    final offset = Offset((size.width - g) / 2, (size.height - g) / 2);
    canvas.save();
    canvas.translate(offset.dx, offset.dy);
    final path = glyphPath(Size(g, g));
    final stroke = g * logoStroke;
    // Sombra suave para dar relieve.
    canvas.drawPath(
        path.shift(Offset(0, stroke * 0.35)),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..color = Colors.black.withValues(alpha: 0.28)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, stroke * 0.45));
    canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..shader = LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: goldStops,
            transform: GradientRotation(math.pi / 16),
          ).createShader(Offset.zero & Size(g, g)));
    canvas.restore();
  }

  @override
  bool shouldRepaint(LogoPainter old) => false;
}

Future<void> _save(
    WidgetTester tester, CustomPainter painter, int px, String path) async {
  await tester.runAsync(() async {
    final rec = ui.PictureRecorder();
    final canvas = Canvas(rec);
    painter.paint(canvas, Size(px.toDouble(), px.toDouble()));
    final img = await rec.endRecording().toImage(px, px);
    final data = await img.toByteData(format: ui.ImageByteFormat.png);
    File(path)
      ..createSync(recursive: true)
      ..writeAsBytesSync(data!.buffer.asUint8List());
  });
}

void main() {
  testWidgets('generar logo', (tester) async {
    final preview = Platform.environment['ICON_PREVIEW'];
    if (preview != null) {
      await _save(tester, LogoPainter(), 512, '$preview/logo.png');
      await _save(tester, LogoPainter(background: false, glyphScale: 0.62), 512,
          '$preview/foreground.png');
      return;
    }
    await _save(tester, LogoPainter(), 1024, 'assets/icon/icon.png');
    await _save(tester, LogoPainter(), 512, 'docs/icon.png');
    // Icono adaptable: el trazo dentro de la zona segura (66 % central).
    await _save(tester, LogoPainter(background: false, glyphScale: 0.62), 1024,
        'assets/icon/foreground.png');
    await _save(tester, _Background(), 1024, 'assets/icon/background.png');
  });
}

class _Background extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
        Offset.zero & size,
        Paint()
          ..shader = const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [navyTop, navyBottom],
          ).createShader(Offset.zero & size));
  }

  @override
  bool shouldRepaint(_Background old) => false;
}
