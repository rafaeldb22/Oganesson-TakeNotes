import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import 'note_images.dart';

/// Transformación afín: `x' = a·x + c·y + e`, `y' = b·x + d·y + f`.
class BoardAffine {
  const BoardAffine(this.a, this.b, this.c, this.d, this.e, this.f);
  final double a, b, c, d, e, f;

  static const identity = BoardAffine(1, 0, 0, 1, 0, 0);

  factory BoardAffine.translation(Offset o) =>
      BoardAffine(1, 0, 0, 1, o.dx, o.dy);

  factory BoardAffine.rotation(Offset center, double angle) {
    final co = math.cos(angle), si = math.sin(angle);
    return BoardAffine.translation(center) *
        BoardAffine(co, si, -si, co, 0, 0) *
        BoardAffine.translation(-center);
  }

  /// Escala a lo largo de los ejes de una caja girada [angle], desde [anchor].
  factory BoardAffine.scaleAlong(
      Offset anchor, double angle, double sx, double sy) {
    final co = math.cos(angle), si = math.sin(angle);
    return BoardAffine.translation(anchor) *
        BoardAffine(co, si, -si, co, 0, 0) *
        BoardAffine(sx, 0, 0, sy, 0, 0) *
        BoardAffine(co, -si, si, co, 0, 0) *
        BoardAffine.translation(-anchor);
  }

  /// Aplica primero [o] y después esta.
  BoardAffine operator *(BoardAffine o) => BoardAffine(
        a * o.a + c * o.b,
        b * o.a + d * o.b,
        a * o.c + c * o.d,
        b * o.c + d * o.d,
        a * o.e + c * o.f + e,
        b * o.e + d * o.f + f,
      );

  Offset apply(Offset p) =>
      Offset(a * p.dx + c * p.dy + e, b * p.dx + d * p.dy + f);

  /// Escala media, para que el grosor del trazo crezca con el dibujo.
  double get meanScale => math.sqrt((a * d - b * c).abs());

  bool get isIdentity =>
      a == 1 && b == 0 && c == 0 && d == 1 && e == 0 && f == 0;

  Float64List get matrix4 =>
      Float64List.fromList([a, b, 0, 0, c, d, 0, 0, 0, 0, 1, 0, e, f, 0, 1]);

  List<double> toList() => [a, b, c, d, e, f];
}

/// Caja de la selección, que puede estar girada.
class BoardBox {
  const BoardBox(this.center, this.size, this.angle);
  final Offset center;
  final Size size;
  final double angle;

  factory BoardBox.around(Rect r) => BoardBox(r.center, r.size, 0);

  static const rotateHandle = 8;

  Offset toWorld(Offset local) {
    final co = math.cos(angle), si = math.sin(angle);
    return center +
        Offset(co * local.dx - si * local.dy, si * local.dx + co * local.dy);
  }

  Offset toLocal(Offset world) {
    final v = world - center;
    final co = math.cos(angle), si = math.sin(angle);
    return Offset(co * v.dx + si * v.dy, -si * v.dx + co * v.dy);
  }

  bool contains(Offset world, [double pad = 0]) {
    final l = toLocal(world);
    return l.dx.abs() <= size.width / 2 + pad &&
        l.dy.abs() <= size.height / 2 + pad;
  }

  /// Tiradores en sentido horario desde la esquina superior izquierda:
  /// los pares son esquinas y los impares, lados.
  Offset handleLocal(int i) {
    final w = size.width / 2, h = size.height / 2;
    return switch (i) {
      0 => Offset(-w, -h),
      1 => Offset(0, -h),
      2 => Offset(w, -h),
      3 => Offset(w, 0),
      4 => Offset(w, h),
      5 => Offset(0, h),
      6 => Offset(-w, h),
      _ => Offset(-w, 0),
    };
  }

  (BoardAffine, BoardBox) move(Offset by) => (
        BoardAffine.translation(by),
        BoardBox(center + by, size, angle),
      );

  (BoardAffine, BoardBox) rotate(Offset from, Offset to) {
    final a0 = math.atan2(from.dy - center.dy, from.dx - center.dx);
    final a1 = math.atan2(to.dy - center.dy, to.dx - center.dx);
    final delta = a1 - a0;
    return (
      BoardAffine.rotation(center, delta),
      BoardBox(center, size, angle + delta),
    );
  }

  /// Las esquinas mantienen la proporción; los lados cambian solo el ancho o
  /// solo el alto. El tirador opuesto se queda quieto.
  (BoardAffine, BoardBox) resize(int handle, Offset pointer) {
    const minScale = 0.05;
    final h = handleLocal(handle), a = handleLocal((handle + 4) % 8);
    final p = toLocal(pointer);
    final v = h - a, w = p - a;
    var sx = 1.0, sy = 1.0;
    if (handle.isEven) {
      final len = v.distanceSquared;
      final r = len == 0 ? 1.0 : (w.dx * v.dx + w.dy * v.dy) / len;
      sx = sy = math.max(r, minScale);
    } else if (v.dx != 0) {
      sx = math.max(w.dx / v.dx, minScale);
    } else if (v.dy != 0) {
      sy = math.max(w.dy / v.dy, minScale);
    }
    final t = BoardAffine.scaleAlong(toWorld(a), angle, sx, sy);
    return (
      t,
      BoardBox(t.apply(center), Size(size.width * sx, size.height * sy), angle),
    );
  }
}

/// Un trazo de la pizarra. [factors] es el grosor relativo en cada punto
/// (ya aplicada la presión), así se ve igual en cualquier dispositivo.
class BoardStroke {
  BoardStroke(this.color, this.width, this.points, this.factors);

  /// ARGB. 0 = tinta automática (negra en claro, blanca en oscuro).
  final int color;
  final double width;
  final List<Offset> points;
  final List<double> factors;

  /// Ya lo ha leído la IA: moverlo o borrar un trozo no lo hace nuevo.
  bool read = false;

  BoardStroke moved(Offset by) =>
      BoardStroke(color, width, [for (final p in points) p + by], factors)
        ..read = read;

  BoardStroke transformed(BoardAffine t) => BoardStroke(
      color, width * t.meanScale, [for (final p in points) t.apply(p)], factors)
    ..read = read;

  Rect get bounds {
    var r = Rect.fromCircle(center: points.first, radius: width / 2);
    for (final p in points) {
      r = r.expandToInclude(Rect.fromCircle(center: p, radius: width / 2));
    }
    return r;
  }

  Map<String, dynamic> toJson() => {
        'c': color,
        'w': width,
        'p': [
          for (var i = 0; i < points.length; i++) ...[
            (points[i].dx * 10).round() / 10,
            (points[i].dy * 10).round() / 10,
            (factors[i] * 100).round() / 100,
          ],
        ],
        if (read) 'x': 1,
      };

  static BoardStroke? fromJson(Object? j) {
    if (j is! Map || j['p'] is! List) return null;
    final raw = j['p'] as List;
    final pts = <Offset>[];
    final f = <double>[];
    for (var i = 0; i + 2 < raw.length; i += 3) {
      final x = raw[i], y = raw[i + 1], k = raw[i + 2];
      if (x is! num || y is! num || k is! num) return null;
      pts.add(Offset(x.toDouble(), y.toDouble()));
      f.add(k.toDouble());
    }
    if (pts.isEmpty) return null;
    return BoardStroke((j['c'] as num?)?.toInt() ?? 0,
        (j['w'] as num?)?.toDouble() ?? 3, pts, f)
      ..read = j['x'] == 1;
  }
}

/// Una imagen pegada en la pizarra (`src` es una fuente `sb://`).
class BoardImage {
  BoardImage(this.src, this.rect, [this.transform = BoardAffine.identity]);
  final String src;
  final Rect rect;

  /// Giro y escala aplicados a [rect].
  final BoardAffine transform;

  /// Ya la ha leído la IA.
  bool read = false;

  Offset get center => transform.apply(rect.center);

  Rect get bounds {
    final pts = [rect.topLeft, rect.topRight, rect.bottomRight, rect.bottomLeft]
        .map(transform.apply)
        .toList();
    final xs = pts.map((p) => p.dx), ys = pts.map((p) => p.dy);
    return Rect.fromLTRB(xs.reduce(math.min), ys.reduce(math.min),
        xs.reduce(math.max), ys.reduce(math.max));
  }

  BoardImage transformed(BoardAffine t) =>
      BoardImage(src, rect, t * transform)..read = read;

  BoardImage moved(Offset by) => transformed(BoardAffine.translation(by));

  Map<String, dynamic> toJson() => {
        'g': src,
        'r': [rect.left, rect.top, rect.width, rect.height],
        if (!transform.isIdentity) 'm': transform.toList(),
        if (read) 'x': 1,
      };

  static BoardImage? fromJson(Object? j) {
    if (j is! Map || j['g'] is! String || j['r'] is! List) return null;
    final r = j['r'] as List;
    if (r.length != 4 || r.any((x) => x is! num)) return null;
    final m = j['m'];
    final t = m is List && m.length == 6 && m.every((x) => x is num)
        ? BoardAffine(
            (m[0] as num).toDouble(),
            (m[1] as num).toDouble(),
            (m[2] as num).toDouble(),
            (m[3] as num).toDouble(),
            (m[4] as num).toDouble(),
            (m[5] as num).toDouble())
        : BoardAffine.identity;
    return BoardImage(
        j['g'] as String,
        Rect.fromLTWH((r[0] as num).toDouble(), (r[1] as num).toDouble(),
            (r[2] as num).toDouble(), (r[3] as num).toDouble()),
        t)
      ..read = j['x'] == 1;
  }
}

Offset _catmull(Offset p0, Offset p1, Offset p2, Offset p3, double t) {
  final t2 = t * t, t3 = t2 * t;
  return ((p1 * 2) +
          (p2 - p0) * t +
          (p0 * 2 - p1 * 5 + p2 * 4 - p3) * t2 +
          (p1 * 3 - p0 - p2 * 3 + p3) * t3) *
      0.5;
}

/// Pinta un trazo con una curva que pasa por todos sus puntos. Con presión,
/// el grosor cambia poco a poco a lo largo de la curva.
void paintBoardStroke(Canvas canvas, BoardStroke s, Color ink) {
  final paint = Paint()
    ..color = s.color == 0 ? ink : Color(s.color)
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round
    ..style = PaintingStyle.stroke
    ..isAntiAlias = true;
  final p = s.points;
  if (p.length == 1) {
    canvas.drawCircle(p.first, s.width * s.factors.first / 2,
        paint..style = PaintingStyle.fill);
    return;
  }
  Offset at(int i) => p[i.clamp(0, p.length - 1)];
  final first = s.factors.first;
  if (s.factors.every((f) => (f - first).abs() < 0.02)) {
    final path = Path()..moveTo(p.first.dx, p.first.dy);
    for (var i = 0; i < p.length - 1; i++) {
      final c1 = at(i) + (at(i + 1) - at(i - 1)) / 6;
      final c2 = at(i + 1) - (at(i + 2) - at(i)) / 6;
      final e = at(i + 1);
      path.cubicTo(c1.dx, c1.dy, c2.dx, c2.dy, e.dx, e.dy);
    }
    canvas.drawPath(path, paint..strokeWidth = s.width * first);
    return;
  }
  // Con presión: el contorno del trazo (un borde a cada lado, con el grosor
  // de cada punto) relleno de una pieza, como la tinta de verdad. Sin juntas
  // ni escalones entre tramos.
  final c = <Offset>[at(0)], r = <double>[s.width * s.factors.first / 2];
  for (var i = 0; i < p.length - 1; i++) {
    final steps = ((at(i + 1) - at(i)).distance / 1.5).ceil().clamp(1, 14);
    for (var k = 1; k <= steps; k++) {
      final t = k / steps;
      c.add(_catmull(at(i - 1), at(i), at(i + 1), at(i + 2), t));
      final f = s.factors[i] + (s.factors[i + 1] - s.factors[i]) * t;
      r.add(math.max(0.25, s.width * f / 2));
    }
  }
  // Grosor suavizado (sin saltos entre puntos) y afinado al empezar y al
  // acabar, como la punta de una pluma.
  for (var pass = 0; pass < 2; pass++) {
    for (var i = 1; i < r.length - 1; i++) {
      r[i] = (r[i - 1] + r[i] * 2 + r[i + 1]) / 4;
    }
  }
  var total = 0.0;
  final along = <double>[0];
  for (var i = 1; i < c.length; i++) {
    total += (c[i] - c[i - 1]).distance;
    along.add(total);
  }
  final taper = math.min(total * 0.18, s.width * 3);
  if (taper > 0) {
    for (var i = 0; i < r.length; i++) {
      final edge = math.min(along[i], total - along[i]) / taper;
      if (edge < 1) r[i] *= 0.45 + 0.55 * math.sin(edge * math.pi / 2);
    }
  }
  final left = <Offset>[], right = <Offset>[];
  for (var i = 0; i < c.length; i++) {
    final d = c[math.min(i + 1, c.length - 1)] - c[math.max(i - 1, 0)];
    final len = d.distance;
    final n = len == 0 ? Offset.zero : Offset(-d.dy / len, d.dx / len) * r[i];
    left.add(c[i] + n);
    right.add(c[i] - n);
  }
  final path = Path()..moveTo(left.first.dx, left.first.dy);
  void smooth(List<Offset> pts) {
    for (var i = 1; i < pts.length - 1; i++) {
      final m = (pts[i] + pts[i + 1]) / 2;
      path.quadraticBezierTo(pts[i].dx, pts[i].dy, m.dx, m.dy);
    }
    path.lineTo(pts.last.dx, pts.last.dy);
  }

  smooth(left);
  path.lineTo(right.last.dx, right.last.dy);
  smooth(right.reversed.toList());
  path.close();
  paint.style = PaintingStyle.fill;
  canvas.drawPath(path, paint);
  // Puntas redondas aparte: un arco dentro del contorno podía girar al revés
  // y dejar un círculo "borrado" al principio y al final de la línea.
  canvas.drawCircle(c.first, r.first, paint);
  canvas.drawCircle(c.last, r.last, paint);
}

/// La pizarra como PNG sobre blanco, para que la lea la IA. null si está vacía.
Future<Uint8List?> renderBoardPng(
    BoardData d, Future<Uint8List?> Function(String path) load,
    {int maxSide = 1600}) async {
  Rect? box;
  for (final s in d.strokes) {
    box = box?.expandToInclude(s.bounds) ?? s.bounds;
  }
  for (final i in d.images) {
    box = box?.expandToInclude(i.bounds) ?? i.bounds;
  }
  if (box == null) return null;
  final area = box.inflate(24);
  final k = math.min(2.5, maxSide / math.max(area.width, area.height));
  final w = math.max(1, (area.width * k).ceil());
  final h = math.max(1, (area.height * k).ceil());
  final rec = PictureRecorder();
  final canvas = Canvas(rec);
  canvas.drawRect(Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()),
      Paint()..color = const Color(0xFFFFFFFF));
  canvas.scale(k);
  canvas.translate(-area.left, -area.top);
  final decoded = <Image>[];
  for (final i in d.images) {
    try {
      final bytes = await load(NoteImages.pathOf(i.src));
      if (bytes == null) continue;
      final codec = await instantiateImageCodec(bytes);
      final image = (await codec.getNextFrame()).image;
      codec.dispose();
      decoded.add(image);
      canvas.save();
      canvas.transform(i.transform.matrix4);
      canvas.drawImageRect(
          image,
          Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
          i.rect,
          Paint()..filterQuality = FilterQuality.medium);
      canvas.restore();
    } catch (_) {
      // Una imagen que no carga no impide leer el resto.
    }
  }
  for (final s in d.strokes) {
    paintBoardStroke(canvas, s, const Color(0xFF111111));
  }
  final picture = rec.endRecording();
  final out = await picture.toImage(w, h);
  final data = await out.toByteData(format: ImageByteFormat.png);
  picture.dispose();
  out.dispose();
  for (final i in decoded) {
    i.dispose();
  }
  return data?.buffer.asUint8List();
}

/// La pizarra de una nota. Vive dentro del Delta como un embed propio: así se
/// sincroniza, se comparte y conserva sus imágenes como el resto de la nota.
class BoardData {
  BoardData(
      {this.active = true,
      List<BoardStroke>? strokes,
      List<BoardImage>? images,
      this.readText = '',
      this.side = defaultSide,
      this.id = '',
      this.name = ''})
      : strokes = strokes ?? [],
        images = images ?? [];

  static const embedType = 'oga-board';

  /// Una nota puede tener varias pizarras: cada una con su id ('' en las
  /// guardadas antes de la 3.12) y un nombre opcional.
  final String id;
  String name;

  static String newId() {
    final r = math.Random();
    return List.generate(
        8, (_) => 'abcdefghijkmnpqrstuvwxyz23456789'[r.nextInt(32)]).join();
  }

  /// Lado mínimo de la hoja cuadrada (Normal / Grande / Enorme). Si el
  /// contenido no cabe, la hoja crece sola.
  static const defaultSide = 1200.0;
  static const sides = [1200.0, 2000.0, 3200.0];
  double side;

  /// La hoja: un cuadrado que empieza en (0, 0), de al menos [minSide], que
  /// crece de 200 en 200 para que todo quepa con margen.
  static Rect paperFor(
      List<BoardStroke> strokes, List<BoardImage> images, double minSide) {
    Rect? box;
    for (final s in strokes) {
      box = box?.expandToInclude(s.bounds) ?? s.bounds;
    }
    for (final i in images) {
      box = box?.expandToInclude(i.bounds) ?? i.bounds;
    }
    const margin = 120.0;
    // Hacia arriba o a la izquierda también crece, de 200 en 200.
    double edge(double v) => math.min(0.0, ((v - margin) / 200).floor() * 200);
    final left = edge(box?.left ?? 0);
    final top = edge(box?.top ?? 0);
    final need = box == null
        ? minSide
        : math.max(box.right + margin - left, box.bottom + margin - top);
    final side = math.max(minSide, (need / 200).ceil() * 200.0);
    return Rect.fromLTWH(left, top, side, side);
  }

  bool active;
  List<BoardStroke> strokes;
  List<BoardImage> images;

  /// Lo que la IA ya ha sacado de esta pizarra.
  String readText;

  String encode() => jsonEncode({
        'on': active,
        's': [for (final s in strokes) s.toJson()],
        'i': [for (final i in images) i.toJson()],
        if (readText.isNotEmpty) 'rt': readText,
        if (side != defaultSide) 'sz': side,
        if (id.isNotEmpty) 'id': id,
        if (name.isNotEmpty) 'nm': name,
      });

  static BoardData? decode(Object? data) {
    try {
      final j = jsonDecode('$data');
      if (j is! Map) return null;
      return BoardData(
        active: j['on'] != false,
        strokes: [
          for (final s in (j['s'] as List?) ?? const [])
            if (BoardStroke.fromJson(s) case final x?) x,
        ],
        images: [
          for (final i in (j['i'] as List?) ?? const [])
            if (BoardImage.fromJson(i) case final x?) x,
        ],
        readText: j['rt'] is String ? j['rt'] as String : '',
        side: (j['sz'] as num?)?.toDouble() ?? defaultSide,
        id: j['id'] is String ? j['id'] as String : '',
        name: j['nm'] is String ? j['nm'] as String : '',
      );
    } catch (_) {
      return null;
    }
  }

  static String? _dataIn(Object? op) {
    if (op is! Map || op['insert'] is! Map) return null;
    final custom = (op['insert'] as Map)['custom'];
    if (custom is! String || !custom.contains(embedType)) return null;
    try {
      final m = jsonDecode(custom);
      return m is Map ? m[embedType] as String? : null;
    } catch (_) {
      return null;
    }
  }

  /// La pizarra guardada en el Delta de una nota, si tiene.
  /// La pizarra [id] de la nota (sin id: la primera).
  static BoardData? of(String? rich, {String? id}) {
    for (final b in all(rich)) {
      if (id == null || b.id == id) return b;
    }
    return null;
  }

  /// Todas las pizarras de la nota, en orden.
  static List<BoardData> all(String? rich) {
    if (rich == null || !rich.contains(embedType)) return const [];
    try {
      return [
        for (final op in jsonDecode(rich) as List)
          if (_dataIn(op) case final d?)
            if (decode(d) case final b?) b,
      ];
    } catch (_) {
      return const [];
    }
  }

  static bool _isBoard(Object? op, String id) {
    final d = _dataIn(op);
    return d != null && decode(d)?.id == id;
  }

  /// Guarda [board] en el Delta (sustituye la que hubiera o la añade al final)
  /// y devuelve el texto plano y el Delta nuevos.
  static (String content, String rich) store(
      String content, String? rich, BoardData board) {
    var ops = <Object?>[];
    if (rich != null) {
      try {
        ops = List<Object?>.of(jsonDecode(rich) as List);
      } catch (_) {}
    }
    if (ops.isEmpty) {
      final base = content.trimRight();
      ops = [
        {'insert': base.isEmpty ? '\n' : '$base\n'}
      ];
    }
    final embed = {
      'insert': {
        'custom': jsonEncode({embedType: board.encode()})
      }
    };
    final at = ops.indexWhere((o) => _isBoard(o, board.id));
    if (at != -1) {
      ops[at] = embed;
    } else {
      ops
        ..add(embed)
        ..add({'insert': '\n'});
    }
    return _result(ops);
  }

  /// Quita la pizarra del Delta, con su línea, sin tocar el resto de la nota.
  static (String content, String rich) remove(String content, String rich,
      {String? id}) {
    final ops = List<Object?>.of(jsonDecode(rich) as List);
    final at = ops
        .indexWhere((o) => id == null ? _dataIn(o) != null : _isBoard(o, id));
    if (at == -1) return (content, rich);
    ops.removeAt(at);
    final next = at < ops.length ? ops[at] : null;
    if (next is Map &&
        next['attributes'] == null &&
        next['insert'] is String &&
        (next['insert'] as String).startsWith('\n')) {
      final rest = (next['insert'] as String).substring(1);
      if (rest.isEmpty) {
        ops.removeAt(at);
      } else {
        ops[at] = {'insert': rest};
      }
    }
    final last = ops.isEmpty ? null : ops.last;
    if (last is! Map ||
        last['insert'] is! String ||
        !(last['insert'] as String).endsWith('\n')) {
      ops.add({'insert': '\n'});
    }
    return _result(ops);
  }

  static (String, String) _result(List<Object?> ops) {
    final plain = StringBuffer();
    for (final o in ops) {
      final v = o is Map ? o['insert'] : null;
      plain.write(v is String ? v : '￼');
    }
    final text = plain.toString();
    return (
      text.endsWith('\n') ? text.substring(0, text.length - 1) : text,
      jsonEncode(ops),
    );
  }
}

/// ¿Está [p] dentro del polígono? (regla par-impar)
bool insidePolygon(Offset p, List<Offset> poly) {
  var inside = false;
  for (var i = 0, j = poly.length - 1; i < poly.length; j = i++) {
    final a = poly[i], b = poly[j];
    if ((a.dy > p.dy) != (b.dy > p.dy) &&
        p.dx < (b.dx - a.dx) * (p.dy - a.dy) / (b.dy - a.dy) + a.dx) {
      inside = !inside;
    }
  }
  return inside;
}

/// Índices de los trazos con la mayoría de sus puntos dentro del lazo.
Set<int> strokesInLasso(List<BoardStroke> strokes, List<Offset> lasso) {
  if (lasso.length < 3) return {};
  return {
    for (var i = 0; i < strokes.length; i++)
      if (strokes[i].points.where((p) => insidePolygon(p, lasso)).length * 2 >=
          strokes[i].points.length)
        i,
  };
}

double _segDistance(Offset p, Offset a, Offset b) {
  final ab = b - a;
  final len = ab.distanceSquared;
  final t = len == 0
      ? 0.0
      : (((p - a).dx * ab.dx + (p - a).dy * ab.dy) / len).clamp(0.0, 1.0);
  return (a + ab * t - p).distance;
}

/// Borra lo que toca la goma en el tramo [from]→[to]. Un trazo cortado por la
/// mitad se queda en dos. Devuelve null si no ha tocado nada.
/// ¿Es un garabato de ida y vuelta para tachar? Escribir normal no da tantos
/// cambios de sentido con tanto recorrido en tan poco sitio.
bool isScribble(List<Offset> points) {
  if (points.length < 12) return false;
  var length = 0.0;
  var box = Rect.fromPoints(points.first, points.first);
  for (var i = 1; i < points.length; i++) {
    length += (points[i] - points[i - 1]).distance;
    box = box.expandToInclude(Rect.fromPoints(points[i], points[i]));
  }
  final diagonal =
      box.size.longestSide == 0 ? 0.0 : Offset(box.width, box.height).distance;
  if (diagonal < 12 || length < diagonal * 4.5) return false;

  int reversals(double Function(Offset) axis, double extent) {
    final slack = math.max(4.0, extent * 0.3);
    var count = 0, direction = 0;
    var peak = axis(points.first);
    for (final p in points) {
      final v = axis(p);
      final moved = v - peak;
      if (direction == 0) {
        if (moved.abs() >= slack) {
          direction = moved.sign.toInt();
          peak = v;
        }
      } else if (moved * direction > 0) {
        peak = v;
      } else if (moved.abs() >= slack) {
        count++;
        direction = -direction;
        peak = v;
      }
    }
    return count;
  }

  return math.max(reversals((p) => p.dx, box.width),
          reversals((p) => p.dy, box.height)) >=
      4;
}

/// Radio de borrado de un garabato: cubre el hueco entre sus pasadas para
/// que no quede tinta entre una y otra.
double scribbleReach(List<Offset> points, double minimum) {
  var length = 0.0;
  var box = Rect.fromPoints(points.first, points.first);
  for (var i = 1; i < points.length; i++) {
    length += (points[i] - points[i - 1]).distance;
    box = box.expandToInclude(Rect.fromPoints(points[i], points[i]));
  }
  if (length == 0) return minimum;
  final spacing = box.width * box.height / length;
  return (spacing * 0.65).clamp(minimum, minimum * 3);
}

/// Puntos de un trazo cada [step] como mucho (para cortar justo donde pasa
/// la goma y no en el punto más cercano).
(List<Offset>, List<double>) _dense(BoardStroke s, double step) {
  final p = <Offset>[s.points.first], f = <double>[s.factors.first];
  for (var i = 1; i < s.points.length; i++) {
    final a = s.points[i - 1], b = s.points[i];
    final n = ((b - a).distance / step).ceil();
    for (var k = 1; k <= n; k++) {
      final t = k / n;
      p.add(Offset.lerp(a, b, t)!);
      f.add(s.factors[i - 1] + (s.factors[i] - s.factors[i - 1]) * t);
    }
  }
  return (p, f);
}

double _length(List<Offset> p) {
  var l = 0.0;
  for (var i = 1; i < p.length; i++) {
    l += (p[i] - p[i - 1]).distance;
  }
  return l;
}

List<BoardStroke>? eraseStrokes(
    List<BoardStroke> strokes, Offset from, Offset to, double radius) {
  var touched = false;
  final out = <BoardStroke>[];
  final zone = Rect.fromPoints(from, to).inflate(radius);
  for (final s in strokes) {
    final reach = radius + s.width / 2;
    // Lejos de la goma: ni se mira punto a punto.
    if (!s.bounds.overlaps(zone.inflate(s.width / 2))) {
      out.add(s);
      continue;
    }
    final (dp, df) = _dense(s, math.max(0.8, radius / 3));
    var pts = <Offset>[];
    var f = <double>[];
    var cut = false;
    // Los restos diminutos de un corte no se guardan: eran los puntos
    // sueltos que dejaba la goma (y el garabato).
    final minLength = math.max(2.0, s.width * 1.2);
    void flush() {
      if (pts.length >= 2 && _length(pts) >= minLength) {
        out.add(BoardStroke(s.color, s.width, pts, f)..read = s.read);
      }
      pts = [];
      f = [];
    }

    for (var i = 0; i < dp.length; i++) {
      if (_segDistance(dp[i], from, to) <= reach) {
        cut = true;
        flush();
      } else {
        pts.add(dp[i]);
        f.add(df[i]);
      }
    }
    if (!cut) {
      out.add(s);
      continue;
    }
    touched = true;
    flush();
  }
  return touched ? out : null;
}
