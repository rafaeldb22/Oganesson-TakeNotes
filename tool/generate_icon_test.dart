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
  LogoPainter(
      {this.background = true,
      this.glyphScale = 1,
      this.fitRadius,
      this.strokeScale = 1});

  /// Grosor del trazo respecto al de la app (el icono del móvil lo lleva más
  /// grueso para que se vea más grande y con más presencia).
  final double strokeScale;

  /// false = solo el trazo (primer plano del icono adaptable).
  final bool background;

  /// Escala del trazo respecto al lienzo (el adaptable lo necesita menor).
  final double glyphScale;

  /// Si se da, el trazo (con su grosor) se centra y se escala para que
  /// quepa justo en un círculo de este radio (fracción del lado). Es lo que
  /// necesita el icono adaptable de Android: la máscara es un círculo o un
  /// squircle, y el trazo es diagonal, así que su caja no sirve de medida.
  final double? fitRadius;

  /// Círculo mínimo (aprox., algoritmo de Ritter) que contiene el trazo
  /// dibujado a tamaño [g], incluido el grosor de la línea.
  static (Offset, double) _enclosing(double g, double strokeScale) {
    final pts = <Offset>[];
    for (final m in glyphPath(Size(g, g)).computeMetrics()) {
      for (var d = 0.0; d <= m.length; d += g / 400) {
        pts.add(m.getTangentForOffset(d)!.position);
      }
    }
    Offset far(Offset from) => pts
        .reduce((a, b) => (a - from).distance >= (b - from).distance ? a : b);
    final a = far(pts.first), b = far(a);
    var c = (a + b) / 2;
    var r = (a - b).distance / 2;
    for (final p in pts) {
      final d = (p - c).distance;
      if (d > r) {
        final nr = (r + d) / 2;
        c = c + (p - c) * ((nr - r) / d);
        r = nr;
      }
    }
    return (c, r + g * logoStroke * strokeScale / 2);
  }

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

    var g = size.width * glyphScale;
    var offset = Offset((size.width - g) / 2, (size.height - g) / 2);
    if (fitRadius != null) {
      final (c, r) = _enclosing(size.width, strokeScale);
      final k = fitRadius! * size.width / r;
      g = size.width * k;
      offset = size.center(Offset.zero) - c * k;
    }
    canvas.save();
    canvas.translate(offset.dx, offset.dy);
    final path = glyphPath(Size(g, g));
    final stroke = g * logoStroke * strokeScale;
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

/// Radio del círculo visible del icono adaptable (72 / 108 / 2 = 0,333),
/// con un pequeño margen para la sombra.
const _fit = 0.322;

void main() {
  testWidgets('generar logo', (tester) async {
    final preview = Platform.environment['ICON_PREVIEW'];
    if (preview != null) {
      await _save(tester, LogoPainter(), 512, '$preview/logo.png');
      await _save(
          tester,
          LogoPainter(background: false, fitRadius: _fit, strokeScale: 1.55),
          512,
          '$preview/foreground.png');
      return;
    }
    await _save(tester, LogoPainter(), 1024, 'assets/icon/icon.png');
    await _save(tester, LogoPainter(), 512, 'docs/icon.png');
    // Icono adaptable: el trazo lo más grande posible sin que la máscara
    // (círculo de 72 dp de los 108 dp del lienzo) recorte ninguna punta.
    await _save(
        tester,
        LogoPainter(background: false, fitRadius: _fit, strokeScale: 1.55),
        1024,
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
