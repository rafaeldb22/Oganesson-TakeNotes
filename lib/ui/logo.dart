import 'dart:io' show Platform;
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

/// Logo de Oganesson: una línea dorada continua con dos bucles sobre azul
/// marino. Lo usan la animación de inicio y el generador del icono
/// (tool/generate_icon_test.dart), así que siempre tienen la misma forma.

/// Fondo del logo: azul marino con degradado.
const logoNavyTop = Color(0xFF243049);
const logoNavyBottom = Color(0xFF0E1420);

/// Dorado del trazo: claro → oro → bronce.
const logoGold = [Color(0xFFFBE6A8), Color(0xFFE2B866), Color(0xFFB07C2E)];

/// Grosor del trazo respecto al lado del logo.
const logoStroke = 0.043;

/// Parte del cuadrado que ocupa el trazo (centrado según sus límites).
const logoFill = 0.74;

/// El trazo, en un cuadrado de lado [s]: una sola línea con dos bucles
/// unidos por una curva (como una "e" doble manuscrita). Se centra según
/// sus límites reales y se escala para ocupar [logoFill] del cuadro.
Path logoGlyphPath(Size s) {
  final raw = _rawGlyph();
  final b = raw.getBounds();
  final scale = logoFill * s.width / math.max(b.width, b.height);
  final m = Matrix4.identity()
    ..translateByDouble(s.width / 2, s.height / 2, 0, 1)
    ..scaleByDouble(scale, scale, 1, 1)
    ..translateByDouble(-b.center.dx, -b.center.dy, 0, 1);
  return raw.transform(m.storage);
}

/// El trazo en coordenadas de 0 a 1 (sin centrar).
Path _rawGlyph() {
  const s = Size(1, 1);
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

/// Pinta el trazo del logo hasta [progress] (0..1), como si lo escribiera
/// una pluma, con una chispa en la punta mientras se dibuja.
class LogoStrokePainter extends CustomPainter {
  LogoStrokePainter({required this.progress, this.glow = 0});

  final double progress;

  /// Brillo extra al terminar (0..1).
  final double glow;

  @override
  void paint(Canvas canvas, Size size) {
    if (progress <= 0) return;
    final path = logoGlyphPath(size);
    final metric = path.computeMetrics().first;
    final len = metric.length * progress.clamp(0.0, 1.0);
    final part = metric.extractPath(0, len);
    final stroke = size.width * logoStroke;
    final shader = LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: logoGold,
      transform: const GradientRotation(math.pi / 16),
    ).createShader(Offset.zero & size);

    if (glow > 0) {
      canvas.drawPath(
          part,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = stroke * 2.4
            ..strokeCap = StrokeCap.round
            ..color = logoGold[1].withValues(alpha: 0.28 * glow)
            ..maskFilter = MaskFilter.blur(BlurStyle.normal, stroke * 1.4));
    }
    canvas.drawPath(
        part,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..shader = shader);

    // Chispa en la punta de la pluma mientras se dibuja.
    if (progress < 1) {
      final tip = metric.getTangentForOffset(len)?.position;
      if (tip != null) {
        canvas.drawCircle(
            tip,
            stroke * 1.6,
            Paint()
              ..shader = ui.Gradient.radial(tip, stroke * 1.6, [
                logoGold[0].withValues(alpha: 0.9),
                logoGold[0].withValues(alpha: 0),
              ]));
      }
    }
  }

  @override
  bool shouldRepaint(LogoStrokePainter old) =>
      old.progress != progress || old.glow != glow;
}

/// Animación de inicio: el trazo dorado se dibuja sobre azul marino,
/// aparece el nombre y todo se desvanece hacia la app.
class StartupSplash extends StatefulWidget {
  const StartupSplash({super.key, required this.child});
  final Widget child;

  @override
  State<StartupSplash> createState() => _StartupSplashState();
}

class _StartupSplashState extends State<StartupSplash>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1850),
  );
  bool _done = false;

  @override
  void initState() {
    super.initState();
    _start();
  }

  /// En Windows la ventana aparece un poco después del primer dibujo:
  /// se espera a que sea visible y opaca para que la animación se vea entera.
  Future<void> _start() async {
    if (!kIsWeb && Platform.isWindows) {
      final until = DateTime.now().add(const Duration(seconds: 4));
      while (mounted && DateTime.now().isBefore(until)) {
        try {
          // Con tiempo máximo: si la consulta no respondiera, la pantalla de
          // inicio no se quedaría colgada.
          final visible = await windowManager.isVisible().timeout(
              const Duration(milliseconds: 300),
              onTimeout: () => true);
          // main.dart la enseña transparente y la vuelve opaca al tener imagen.
          final opaque = visible &&
              await windowManager.getOpacity().timeout(
                      const Duration(milliseconds: 300),
                      onTimeout: () => 1) >=
                  1;
          if (opaque) break;
        } catch (_) {
          break;
        }
        await Future<void>.delayed(const Duration(milliseconds: 40));
      }
      // Margen para que el primer fotograma ya esté en pantalla.
      await Future<void>.delayed(const Duration(milliseconds: 120));
    } else {
      await Future<void>.delayed(const Duration(milliseconds: 120));
    }
    if (!mounted) return;
    await _c.forward();
    if (mounted) setState(() => _done = true);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  /// Tramo [a, b] de la animación, con curva.
  double _seg(double a, double b, [Curve curve = Curves.easeInOutCubic]) =>
      curve.transform(((_c.value - a) / (b - a)).clamp(0.0, 1.0));

  @override
  Widget build(BuildContext context) {
    if (_done) return widget.child;
    return Stack(
      fit: StackFit.expand,
      children: [
        widget.child,
        AnimatedBuilder(
          animation: _c,
          builder: (context, _) {
            final draw = _seg(0.04, 0.62);
            final glow =
                _seg(0.55, 0.72, Curves.easeOut) * (1 - _seg(0.72, 0.9));
            final word = _seg(0.5, 0.72, Curves.easeOutCubic);
            final out = _seg(0.78, 1.0, Curves.easeInCubic);
            final side =
                math.min(MediaQuery.sizeOf(context).shortestSide * 0.42, 220.0);
            return IgnorePointer(
              ignoring: out > 0.5,
              child: Opacity(
                opacity: 1 - out,
                child: DecoratedBox(
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [logoNavyTop, logoNavyBottom],
                    ),
                  ),
                  child: Center(
                    child: Transform.scale(
                      scale: 1 + 0.08 * out,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox.square(
                            dimension: side,
                            child: CustomPaint(
                              painter:
                                  LogoStrokePainter(progress: draw, glow: glow),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Opacity(
                            opacity: word,
                            child: Transform.translate(
                              offset: Offset(0, -side * 0.06 + 10 * (1 - word)),
                              child: Text(
                                'oganesson',
                                style: TextStyle(
                                  fontFamily: 'Shrikhand',
                                  fontSize: side * 0.17,
                                  letterSpacing: 1,
                                  color: logoGold[1],
                                  decoration: TextDecoration.none,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ],
    );
  }
}
