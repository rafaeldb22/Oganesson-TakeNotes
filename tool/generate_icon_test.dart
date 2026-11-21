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

/// Fondo del logo: azul marino con degradado.
const navyTop = Color(0xFF243049);
const navyBottom = Color(0xFF0E1420);

/// Dorado del trazo: claro → oro → bronce.
const goldStops = [Color(0xFFFBE6A8), Color(0xFFE2B866), Color(0xFFB07C2E)];

/// El trazo: una sola línea continua con dos bucles unidos por una curva
/// (como una "e" doble manuscrita), en coordenadas de 0 a 1.
Path glyphPath(Size s) {
  final p = Path();
  Offset o(double x, double y) => Offset(x * s.width, y * s.height);
  void c(double x1, double y1, double x2, double y2, double x, double y) {
    final a = o(x1, y1), b = o(x2, y2), e = o(x, y);
    p.cubicTo(a.dx, a.dy, b.dx, b.dy, e.dx, e.dy);
  }

  final start = o(0.225, 0.270);
  p.moveTo(start.dx, start.dy);
  // Entrada y primer bucle (alto y estrecho, inclinado a la derecha).
  c(0.215, 0.335, 0.255, 0.405, 0.305, 0.405);
  c(0.355, 0.405, 0.402, 0.335, 0.396, 0.280);
  c(0.390, 0.228, 0.338, 0.222, 0.330, 0.282);
  // Bajada en curva hasta la base.
  c(0.320, 0.350, 0.332, 0.475, 0.392, 0.560);
  c(0.452, 0.645, 0.565, 0.668, 0.642, 0.600);
  // Segundo bucle.
  c(0.722, 0.533, 0.775, 0.420, 0.750, 0.368);
  c(0.726, 0.318, 0.664, 0.342, 0.660, 0.420);
  // Cola larga hacia abajo a la derecha.
  c(0.655, 0.520, 0.715, 0.690, 0.790, 0.770);
  return p;
}

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
    final stroke = g * 0.043;
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
      await _save(tester, LogoPainter(background: false, glyphScale: 0.70), 512,
          '$preview/foreground.png');
      return;
    }
    await _save(tester, LogoPainter(), 1024, 'assets/icon/icon.png');
    await _save(tester, LogoPainter(), 512, 'docs/icon.png');
    // Icono adaptable: el trazo dentro de la zona segura (66 % central).
    await _save(tester, LogoPainter(background: false, glyphScale: 0.70), 1024,
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
