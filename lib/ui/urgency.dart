import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/note.dart';
import 'anim.dart';
import 'format.dart';
import 'theme.dart';

/// Rango del calendario: este mes, los 3 anteriores y los 3 siguientes.
/// Se calcula siempre con la fecha de hoy, así que se actualiza solo.
({DateTime first, DateTime last}) calendarRange([DateTime? now]) {
  final n = now ?? DateTime.now();
  return (
    first: DateTime(n.year, n.month - 3, 1),
    last: DateTime(n.year, n.month + 4, 0, 23, 59),
  );
}

/// Colores de la "mecha": menta → oro → naranja → rojo brasa.
const fuseStops = <Color>[
  Color(0xFF2DD4A7),
  Color(0xFFFFC53D),
  Color(0xFFFF8A3D),
  Color(0xFFEF4444),
];

/// En modo claro la mecha se oscurece un poco para que destaque sobre el
/// fondo claro (en oscuro se deja igual).
List<Color> fuseForTheme(BuildContext context, List<Color> colors) {
  if (Theme.of(context).brightness == Brightness.dark) return colors;
  return [
    for (final c in colors)
      HSLColor.fromColor(c)
          .withLightness(
              (HSLColor.fromColor(c).lightness - 0.1).clamp(0.0, 1.0))
          .withSaturation(
              (HSLColor.fromColor(c).saturation + 0.08).clamp(0.0, 1.0))
          .toColor(),
  ];
}

/// Colores que se pueden elegir para una nota (y su mecha).
/// Ordenados por tono. Los valores ya usados no se cambian (las notas
/// guardan el ARGB), solo se añaden nuevos.
const noteColors = <(String, int)>[
  ('Rojo', 0xFFE5484D),
  ('Coral', 0xFFFF6B6B),
  ('Melocotón', 0xFFFFA48A),
  ('Naranja', 0xFFFF9F43),
  ('Ámbar', 0xFFF7C948),
  ('Arena', 0xFFD9B98C),
  ('Lima', 0xFF8BD450),
  ('Oliva', 0xFF8A9A3B),
  ('Bosque', 0xFF2F9E5B),
  ('Menta', 0xFF2DD4A7),
  ('Turquesa', 0xFF22B8CF),
  ('Cielo', 0xFF4DABF7),
  ('Azul', 0xFF3B6FE0),
  ('Índigo', 0xFF6C7CFF),
  ('Lavanda', 0xFF9F8CFF),
  ('Uva', 0xFFB197FC),
  ('Morado', 0xFF8E4EC6),
  ('Fucsia', 0xFFE64980),
  ('Rosa', 0xFFF783AC),
  ('Café', 0xFF9C6B4E),
  ('Pizarra', 0xFF6B7A90),
];

/// Degradado de la mecha para un color: de un tono claro y suave al color
/// intenso y, al final, más oscuro (se "quema").
List<Color> fusePalette(int? color) {
  if (color == null) return fuseStops;
  final c = Color(color);
  final hsl = HSLColor.fromColor(c);
  return [
    hsl.withLightness((hsl.lightness + 0.28).clamp(0.0, 0.92)).toColor(),
    c,
    hsl
        .withLightness((hsl.lightness - 0.18).clamp(0.08, 1.0))
        .withSaturation((hsl.saturation + 0.1).clamp(0.0, 1.0))
        .toColor(),
  ];
}

/// Color de una paleta de mecha en el punto t (0 = recién encendida).
Color paletteAt(List<Color> stops, double t) {
  final x = t.clamp(0.0, 1.0) * (stops.length - 1);
  final i = x.floor().clamp(0, stops.length - 2);
  return Color.lerp(stops[i], stops[i + 1], x - i)!;
}

/// Color de la mecha por defecto en el punto t.
Color fuseColor(double t) => paletteAt(fuseStops, t);

/// Color representativo de una nota temporal según su tiempo consumido.
Color urgencyColor(BuildContext context, Note n) {
  if (n.done) return Palette.secondary(context);
  final stops = fusePalette(n.color);
  if (n.isOverdue()) return stops.last;
  return paletteAt(stops, n.progress());
}

/// Barra de tiempo con forma de mecha: el tramo consumido brilla con un
/// degradado que va de menta a rojo, y en la punta hay una chispa que late.
class TimeBar extends StatelessWidget {
  const TimeBar({super.key, required this.note, this.compact = false});
  final Note note;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final color = urgencyColor(context, note);
    final p = note.done ? 1.0 : note.progress();
    final burning = !note.done && !note.isOverdue();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        FuseBar(
          progress: p,
          height: compact ? 4 : 6,
          spark: burning,
          dimmed: note.done,
          colors: fusePalette(note.color),
        ),
        if (!compact) ...[
          const SizedBox(height: 6),
          Row(
            children: [
              Icon(
                note.done
                    ? Icons.check_circle
                    : (note.isOverdue()
                        ? Icons.local_fire_department
                        : Icons.timer_outlined),
                size: 14,
                color: color,
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  tiempoRestante(note.dueAt!, done: note.done),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 12, color: color, fontWeight: FontWeight.w600),
                ),
              ),
              Text(fechaMedia(note.dueAt!),
                  style: TextStyle(
                      fontSize: 12, color: Palette.secondary(context))),
            ],
          ),
        ],
      ],
    );
  }
}

class FuseBar extends StatefulWidget {
  const FuseBar({
    super.key,
    required this.progress,
    this.height = 6,
    this.spark = true,
    this.dimmed = false,
    this.colors = fuseStops,
  });

  final double progress;
  final double height;
  final bool spark;
  final bool dimmed;
  final List<Color> colors;

  @override
  State<FuseBar> createState() => _FuseBarState();
}

class _FuseBarState extends State<FuseBar> with TickerProviderStateMixin {
  late final AnimationController _flicker = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  );
  late final AnimationController _grow = AnimationController(
    vsync: this,
    duration: Anim.slow,
  )..forward();

  @override
  void initState() {
    super.initState();
    if (widget.spark) _flicker.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(FuseBar old) {
    super.didUpdateWidget(old);
    if (widget.spark && !_flicker.isAnimating) {
      _flicker.repeat(reverse: true);
    } else if (!widget.spark && _flicker.isAnimating) {
      _flicker.stop();
    }
  }

  @override
  void dispose() {
    _flicker.dispose();
    _grow.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final light = Theme.of(context).brightness == Brightness.light;
    final track =
        Palette.secondary(context).withValues(alpha: light ? 0.26 : 0.16);
    final colors = fuseForTheme(context, widget.colors);
    // Espacio extra arriba y abajo para que la chispa no se corte.
    final pad = widget.spark ? widget.height * 0.9 : 0.0;
    return RepaintBoundary(
      child: SizedBox(
        height: widget.height + pad * 2,
        width: double.infinity,
        // El ancho va al pintor: al cambiar el tamaño de la ventana la mecha
        // se repinta en el mismo frame (antes esperaba al repintado tardío).
        child: LayoutBuilder(
            builder: (context, c) => CustomPaint(
                  painter: _FusePainter(
                    width: c.maxWidth,
                    progress: widget.progress,
                    barHeight: widget.height,
                    track: track,
                    flicker: _flicker,
                    grow: CurvedAnimation(parent: _grow, curve: Anim.curve),
                    spark: widget.spark,
                    dimmed: widget.dimmed,
                    colors: colors,
                  ),
                )),
      ),
    );
  }
}

class _FusePainter extends CustomPainter {
  _FusePainter({
    required this.width,
    required this.progress,
    required this.barHeight,
    required this.track,
    required this.flicker,
    required this.grow,
    required this.spark,
    required this.dimmed,
    required this.colors,
  }) : super(repaint: Listenable.merge([flicker, grow]));

  final List<Color> colors;

  final double progress;
  final double barHeight;
  final Color track;
  final Animation<double> flicker;
  final Animation<double> grow;
  final bool spark;
  final bool dimmed;
  final double width;

  @override
  void paint(Canvas canvas, Size size) {
    final y = size.height / 2;
    final r = Radius.circular(barHeight / 2);
    final full =
        RRect.fromLTRBR(0, y - barHeight / 2, size.width, y + barHeight / 2, r);

    // Cordón que queda por quemar.
    canvas.drawRRect(full, Paint()..color = track);

    final p = progress.clamp(0.0, 1.0) * grow.value;
    final x = size.width * p;
    if (x <= 0.5) return;

    // Tramo consumido con el degradado de la mecha a lo largo de toda la barra.
    final shader = LinearGradient(
      colors: dimmed
          ? colors.map((c) => c.withValues(alpha: 0.35)).toList()
          : colors,
    ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));
    canvas.save();
    canvas.clipRect(Rect.fromLTWH(0, 0, x, size.height));
    canvas.drawRRect(full, Paint()..shader = shader);
    canvas.restore();

    if (!spark) return;
    // Chispa: halo + núcleo que laten.
    final c = paletteAt(colors, p);
    final f = flicker.value;
    final glowR = barHeight * (1.25 + 0.45 * f);
    canvas.drawCircle(
      Offset(x, y),
      glowR,
      Paint()
        ..shader = RadialGradient(colors: [
          c.withValues(alpha: 0.75),
          c.withValues(alpha: 0.0),
        ]).createShader(Rect.fromCircle(center: Offset(x, y), radius: glowR)),
    );
    canvas.drawCircle(
      Offset(x, y),
      barHeight * (0.42 + 0.12 * math.sin(f * math.pi)),
      Paint()..color = Color.lerp(c, Colors.white, 0.65)!,
    );
  }

  @override
  bool shouldRepaint(_FusePainter old) =>
      old.width != width ||
      old.progress != progress ||
      old.track != track ||
      old.spark != spark ||
      old.dimmed != dimmed ||
      !identical(old.colors, colors) &&
          old.colors.toString() != colors.toString() ||
      old.barHeight != barHeight;
}
