import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'theme.dart';

/// "babunotes" en letra retro (Shrikhand), en minúsculas, con una ola lenta:
/// cada letra sube y baja con un pequeño desfase y el color va pasando
/// del acento a un tono más claro, como un brillo que recorre la palabra.
class WaveTitle extends StatefulWidget {
  const WaveTitle({super.key, this.text = 'babunotes', this.fontSize = 30});

  final String text;
  final double fontSize;

  @override
  State<WaveTitle> createState() => _WaveTitleState();
}

class _WaveTitleState extends State<WaveTitle>
    with SingleTickerProviderStateMixin {
  // Ciclo de 3,2 s: lento y relajado.
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 3200),
  )..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final accent = Palette.accent(context);
    final glow = Color.lerp(accent, Colors.white, 0.45)!;
    final letters = widget.text.characters.toList();
    final style = TextStyle(
      fontFamily: 'Shrikhand',
      fontSize: widget.fontSize,
      height: 1.15,
      letterSpacing: 0.5,
    );

    // RepaintBoundary: la ola se repinta sola sin arrastrar al resto.
    return RepaintBoundary(
      child: Semantics(
        label: widget.text,
        child: AnimatedBuilder(
          animation: _c,
          builder: (context, _) {
            final t = _c.value * 2 * math.pi;
            return Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (var i = 0; i < letters.length; i++)
                  Builder(builder: (_) {
                    final phase = t - i * 0.7;
                    final dy = math.sin(phase) * widget.fontSize * 0.09;
                    final shine = (math.sin(phase) + 1) / 2; // 0..1
                    final color = Color.lerp(accent, glow, shine * 0.6)!;
                    return Transform.translate(
                      offset: Offset(0, -dy),
                      child: Transform.rotate(
                        angle: math.cos(phase) * 0.04,
                        child: Text(
                          letters[i],
                          style: style.copyWith(
                            color: color,
                            shadows: [
                              // Sombra desplazada tipo cartel retro.
                              Shadow(
                                color: accent.withValues(alpha: 0.28),
                                offset: const Offset(2.5, 2.5),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  }),
              ],
            );
          },
        ),
      ),
    );
  }
}
