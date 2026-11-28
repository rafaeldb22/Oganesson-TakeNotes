import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../data/notes_repository.dart';
import '../data/recurrence.dart';
import '../models/note.dart';
import 'anim.dart';
import 'format.dart';
import 'i18n.dart';
import 'theme.dart';
import 'toast.dart';

/// Botón de completar: avisa cuando el cambio no se vería en la tarea (una
/// nota de otra cuenta, o una repetida que salta a su siguiente fecha).
void completeTask(BuildContext context, NotesRepository repo, String id) {
  final n = repo.byId(id);
  if (n == null) return;
  if (repo.isForeign(n)) {
    showToast(context, tr('Solo quien creó la nota puede completarla'),
        icon: Icons.info_outline_rounded);
    return;
  }
  final repeats = !n.done && RepeatRule.parse(n.repeat) != null;
  repo.toggleDone(id);
  if (repeats) {
    showToast(context, trf('Hecha. Vuelve {0}', [fechaDia(n.dueAt!)]),
        icon: Icons.event_repeat_rounded);
  }
}

/// Rango del calendario: los 3 meses anteriores y hasta 3 años vista (en
/// diciembre de 2026, hasta diciembre de 2029). Se calcula con la fecha de
/// hoy, así que se actualiza solo.
const calendarMonthsBefore = 3, calendarMonthsAfter = 36;

({DateTime first, DateTime last}) calendarRange([DateTime? now]) {
  final n = now ?? DateTime.now();
  return (
    first: DateTime(n.year, n.month - calendarMonthsBefore, 1),
    last: DateTime(n.year, n.month + calendarMonthsAfter + 1, 0, 23, 59),
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
/// Los 6 colores que se pueden poner a una nota temporal: salen del tema
/// (el acento y tonos vecinos, más uno que contrasta), así combinan con él.
List<(String, int)> get themeNoteColors {
  final t = themeSettings.theme;
  if (_paletteFor != t.id) {
    _palette = noteColorsFor(t);
    _paletteFor = t.id;
  }
  return _palette;
}

String? _paletteFor;
List<(String, int)> _palette = const [];

List<(String, int)> noteColorsFor(AppTheme t) {
  final a = HSLColor.fromColor(t.light.accent);
  // Tema gris (Grafito): una gama propia de tonos sobrios.
  final grey = a.saturation < 0.15;
  final base = grey ? 210.0 : a.hue;
  const offsets = [0.0, 32.0, -32.0, 64.0, 180.0, 212.0];
  const light = [0.50, 0.56, 0.46, 0.58, 0.52, 0.47];
  final used = <String>{};
  return [
    for (var i = 0; i < 6; i++)
      () {
        var h = (base + offsets[i]) % 360;
        if (h < 0) h += 360;
        final c =
            HSLColor.fromAHSL(1, h, grey ? 0.30 + i * 0.06 : 0.68, light[i])
                .toColor();
        var name = colorName(h);
        // Dos tonos con el mismo nombre: claro / oscuro.
        if (!used.add(name))
          name = '$name ${light[i] < 0.5 ? 'oscuro' : 'claro'}';
        return (name, c.toARGB32());
      }(),
  ];
}

/// Color con que se ve una nota: el suyo ajustado a los 6 del tema puesto
/// (al cambiar de tema, las notas cambian con él).
Color themedNoteColor(int argb) => Color(nearestThemeColor(argb));

/// Nombre aproximado de un tono (para la lista de colores y la IA).
String colorName(double hue) {
  const names = [
    (15.0, 'Rojo'),
    (40.0, 'Naranja'),
    (62.0, 'Ámbar'),
    (85.0, 'Lima'),
    (150.0, 'Verde'),
    (185.0, 'Turquesa'),
    (205.0, 'Cielo'),
    (245.0, 'Azul'),
    (275.0, 'Índigo'),
    (305.0, 'Violeta'),
    (335.0, 'Magenta'),
    (360.0, 'Rosa'),
  ];
  for (final (limit, name) in names) {
    if (hue < limit) return name;
  }
  return 'Rojo';
}

/// El color del tema más parecido a [argb] (la IA puede pedir cualquiera).
int nearestThemeColor(int argb) {
  int d(int a, int b) {
    final dr = (a >> 16 & 255) - (b >> 16 & 255);
    final dg = (a >> 8 & 255) - (b >> 8 & 255);
    final db = (a & 255) - (b & 255);
    return dr * dr + dg * dg + db * db;
  }

  return themeNoteColors
      .map((c) => c.$2)
      .reduce((x, y) => d(x, argb) <= d(y, argb) ? x : y);
}

/// Todos los nombres de color que entiende la IA (se ajustan a los 6 del
/// tema al aplicarlos).
const noteColors = <(String, int)>[
  ('Granate', 0xFF9F1D35),
  ('Rojo', 0xFFE5484D),
  ('Cereza', 0xFFD6204E),
  ('Coral', 0xFFFF6B6B),
  ('Melocotón', 0xFFFFA48A),
  ('Mandarina', 0xFFF76707),
  ('Naranja', 0xFFFF9F43),
  ('Mostaza', 0xFFC99700),
  ('Ámbar', 0xFFF7C948),
  ('Arena', 0xFFD9B98C),
  ('Pistacho', 0xFFC0E218),
  ('Lima', 0xFF8BD450),
  ('Oliva', 0xFF8A9A3B),
  ('Esmeralda', 0xFF0CA678),
  ('Bosque', 0xFF2F9E5B),
  ('Menta', 0xFF2DD4A7),
  ('Verde azulado', 0xFF0B7285),
  ('Aguamarina', 0xFF66E0D5),
  ('Turquesa', 0xFF22B8CF),
  ('Cielo', 0xFF4DABF7),
  ('Azul', 0xFF3B6FE0),
  ('Zafiro', 0xFF1C3FAA),
  ('Índigo', 0xFF6C7CFF),
  ('Lavanda', 0xFF9F8CFF),
  ('Uva', 0xFFB197FC),
  ('Violeta', 0xFF7048E8),
  ('Morado', 0xFF8E4EC6),
  ('Magenta', 0xFFD633C9),
  ('Fucsia', 0xFFE64980),
  ('Frambuesa', 0xFFB5179E),
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

/// Paleta de una nota: las de un solo día tienen un color fijo, sin degradado.
List<Color> notePalette(Note n) {
  final own = n.color == null ? null : nearestThemeColor(n.color!);
  if (!n.isSingleDay) return fusePalette(own);
  final c = own == null ? fuseStops.first : Color(own);
  return [c, c];
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
  final stops = notePalette(n);
  final c = n.isOverdue() ? stops.last : paletteAt(stops, n.progress());
  return readableOn(c, light: Theme.of(context).brightness == Brightness.light);
}

/// Color de texto legible: sobre fondo claro se oscurece (luminosidad
/// máxima 0,40) conservando el tono; sobre oscuro se deja igual.
Color readableOn(Color c, {required bool light}) {
  if (!light) return c;
  final h = HSLColor.fromColor(c);
  if (h.lightness <= 0.40) return c;
  return h
      .withLightness(0.40)
      .withSaturation((h.saturation + 0.1).clamp(0.0, 1.0))
      .toColor();
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
        if (note.showsBar()) ...[
          FuseBar(
            progress: p,
            height: compact || note.isSingleDay ? 4 : 6,
            spark: burning,
            dimmed: note.done,
            colors: notePalette(note),
          ),
          if (!compact) const SizedBox(height: 6),
        ],
        if (!compact) ...[
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
              // En sitios estrechos la fecha baja a su propia línea: antes el
              // tiempo se cortaba ("20 …") o se pegaba a la fecha.
              Expanded(
                child: LayoutBuilder(builder: (context, c) {
                  final left = Text(tiempoNota(note),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 12,
                          color: color,
                          fontWeight: FontWeight.w600));
                  final date = Text(fechaNota(note),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 12, color: Palette.secondary(context)));
                  if (c.maxWidth < 230) {
                    return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [left, const SizedBox(height: 2), date]);
                  }
                  return Row(children: [
                    Expanded(child: left),
                    const SizedBox(width: 10),
                    date,
                  ]);
                }),
              ),
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
