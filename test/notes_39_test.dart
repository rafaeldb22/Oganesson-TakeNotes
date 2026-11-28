import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:notas/data/note_board.dart';

BoardStroke _line(double from, double to, {double y = 50, double step = 20}) {
  final pts = [for (var x = from; x <= to; x += step) Offset(x, y)];
  return BoardStroke(0, 3, pts, [for (final _ in pts) 1.0]);
}

void main() {
  test('erasing cuts where the eraser passes and leaves no loose dots', () {
    // Puntos separados 20: antes la goma solo quitaba puntos enteros.
    final out = eraseStrokes(
        [_line(0, 200)], const Offset(100, 0), const Offset(100, 100), 6)!;
    expect(out, hasLength(2));
    expect(out.every((s) => s.points.length >= 2), isTrue);
    // Rozando el final: no queda un punto suelto.
    final end = eraseStrokes([_line(0, 40, step: 4)], const Offset(38, 0),
        const Offset(38, 100), 6)!;
    expect(end.single.points.last.dx, lessThan(36));
    // Un trazo lejos de la goma ni se toca.
    final far = _line(0, 100, y: 500);
    expect(eraseStrokes([far], const Offset(0, 0), const Offset(10, 0), 5),
        isNull);
  });

  test('the sheet is square and grows to fit the drawing', () {
    final small = BoardData.paperFor([_line(200, 500, y: 300)], const [], 1200);
    expect(small, const Rect.fromLTWH(0, 0, 1200, 1200));
    // Dibujar pegado al borde de arriba a la izquierda también la agranda.
    final edge = BoardData.paperFor([_line(10, 300, y: 10)], const [], 1200);
    expect(edge.topLeft, const Offset(-200, -200));
    expect(edge.width, edge.height);
    final big = BoardData.paperFor([_line(0, 1500)], const [], 1200);
    expect(big.width, big.height);
    expect(big.right, greaterThanOrEqualTo(1500 + 100));
    final d = BoardData.decode(BoardData(side: 2000).encode())!;
    expect(d.side, 2000);
  });

  test('smoothing keeps the ends and sharp corners like GoodNotes', () {
    // Una "v": la punta no se redondea; los extremos no se mueven.
    final pts = [
      for (var x = 0.0; x <= 50; x += 2) Offset(x, x),
      for (var x = 52.0; x <= 100; x += 2) Offset(x, 100 - x),
    ];
    final (sp, sf) = smoothStroke(pts, [for (final _ in pts) 1.0]);
    expect(sp.first, pts.first);
    expect(sp.last, pts.last);
    expect(sp.length, sf.length);
    final tip = sp.reduce((a, b) => a.dy > b.dy ? a : b);
    expect(tip.dy, greaterThan(44));
  });
}
