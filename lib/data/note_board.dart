import 'dart:convert';
import 'dart:ui';

/// Un trazo de la pizarra. [factors] es el grosor relativo en cada punto
/// (ya aplicada la presión), así se ve igual en cualquier dispositivo.
class BoardStroke {
  BoardStroke(this.color, this.width, this.points, this.factors);

  /// ARGB. 0 = tinta automática (negra en claro, blanca en oscuro).
  final int color;
  final double width;
  final List<Offset> points;
  final List<double> factors;

  BoardStroke moved(Offset by) =>
      BoardStroke(color, width, [for (final p in points) p + by], factors);

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
        (j['w'] as num?)?.toDouble() ?? 3, pts, f);
  }
}

/// Una imagen pegada en la pizarra (`src` es una fuente `sb://`).
class BoardImage {
  BoardImage(this.src, this.rect);
  final String src;
  final Rect rect;

  BoardImage moved(Offset by) => BoardImage(src, rect.shift(by));

  Map<String, dynamic> toJson() => {
        'g': src,
        'r': [rect.left, rect.top, rect.width, rect.height],
      };

  static BoardImage? fromJson(Object? j) {
    if (j is! Map || j['g'] is! String || j['r'] is! List) return null;
    final r = j['r'] as List;
    if (r.length != 4 || r.any((x) => x is! num)) return null;
    return BoardImage(
        j['g'] as String,
        Rect.fromLTWH((r[0] as num).toDouble(), (r[1] as num).toDouble(),
            (r[2] as num).toDouble(), (r[3] as num).toDouble()));
  }
}

/// La pizarra de una nota. Vive dentro del Delta como un embed propio: así se
/// sincroniza, se comparte y conserva sus imágenes como el resto de la nota.
class BoardData {
  BoardData(
      {this.active = true,
      List<BoardStroke>? strokes,
      List<BoardImage>? images})
      : strokes = strokes ?? [],
        images = images ?? [];

  static const embedType = 'oga-board';

  bool active;
  List<BoardStroke> strokes;
  List<BoardImage> images;

  String encode() => jsonEncode({
        'on': active,
        's': [for (final s in strokes) s.toJson()],
        'i': [for (final i in images) i.toJson()],
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
  static BoardData? of(String? rich) {
    if (rich == null || !rich.contains(embedType)) return null;
    try {
      for (final op in jsonDecode(rich) as List) {
        final d = _dataIn(op);
        if (d != null) return decode(d);
      }
    } catch (_) {}
    return null;
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
    final at = ops.indexWhere((o) => _dataIn(o) != null);
    if (at != -1) {
      ops[at] = embed;
    } else {
      ops
        ..add(embed)
        ..add({'insert': '\n'});
    }
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
List<BoardStroke>? eraseStrokes(
    List<BoardStroke> strokes, Offset from, Offset to, double radius) {
  var touched = false;
  final out = <BoardStroke>[];
  for (final s in strokes) {
    final reach = radius + s.width / 2;
    var pts = <Offset>[];
    var f = <double>[];
    var cut = false;
    void flush() {
      if (pts.isNotEmpty) out.add(BoardStroke(s.color, s.width, pts, f));
      pts = [];
      f = [];
    }

    for (var i = 0; i < s.points.length; i++) {
      if (_segDistance(s.points[i], from, to) <= reach) {
        cut = true;
        flush();
      } else {
        pts.add(s.points[i]);
        f.add(s.factors[i]);
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
