import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'theme.dart';

/// "babunotes" en letra pixel (Pixelify Sans) con una ola lenta.
/// El movimiento va "a saltos" de píxel en píxel, como en una consola
/// antigua, y lleva una sombra dura desplazada estilo 8 bits.
class WaveTitle extends StatefulWidget {
  const WaveTitle({super.key, this.text = 'babunotes', this.fontSize = 28});

  final String text;
  final double fontSize;

  @override
  State<WaveTitle> createState() => _WaveTitleState();
}

class _WaveTitleState extends State<WaveTitle>
    with SingleTickerProviderStateMixin {
  // Ciclo de 3,6 s: lento y relajado.
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 3600),
  )..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final accent = Palette.accent(context);
    final dark = Theme.of(context).brightness == Brightness.dark;
    final shadow = dark
        ? Color.lerp(accent, Colors.black, 0.65)!
        : Color.lerp(accent, Colors.black, 0.45)!.withValues(alpha: 0.55);
    final letters = widget.text.characters.toList();
    // Tamaño del "píxel" de la fuente: los saltos se hacen en múltiplos.
    final px = (widget.fontSize / 10).roundToDouble().clamp(2.0, 6.0);
    final style = TextStyle(
      fontFamily: 'PixelifySans',
      fontWeight: FontWeight.w700,
      fontSize: widget.fontSize,
      height: 1.1,
      letterSpacing: 1,
    );

    // RepaintBoundary: la ola se repinta sola sin arrastrar al resto.
    return RepaintBoundary(
      child: Semantics(
        label: widget.text,
        child: AnimatedBuilder(
          animation: _c,
          builder: (context, _) {
            final t = _c.value * 2 * math.pi;
            return Padding(
              padding: EdgeInsets.only(top: px * 2, right: px),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  for (var i = 0; i < letters.length; i++)
                    Builder(builder: (_) {
                      final phase = t - i * 0.62;
                      final wave = math.sin(phase);
                      // Cuantizado: 0, 1 o 2 "píxeles" de altura.
                      final dy = (wave.clamp(0.0, 1.0) * 2).round() * px;
                      final lit = wave > 0.55; // la cresta brilla
                      final color = lit
                          ? Color.lerp(accent, Colors.white, dark ? 0.35 : 0.25)!
                          : accent;
                      return Transform.translate(
                        offset: Offset(0, -dy),
                        child: Text(
                          letters[i],
                          style: style.copyWith(
                            color: color,
                            shadows: [
                              Shadow(color: shadow, offset: Offset(px, px)),
                            ],
                          ),
                        ),
                      );
                    }),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}
