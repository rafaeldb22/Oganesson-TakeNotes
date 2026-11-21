import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notas/ui/theme.dart';

void main() {
  test('modo claro suavizado: sin blanco puro y tarjeta no más oscura', () {
    for (final t in appThemes) {
      final c = t.lightSoft;
      final bg = HSLColor.fromColor(c.background).lightness;
      final card = HSLColor.fromColor(c.card).lightness;
      expect(card, lessThanOrEqualTo(0.96), reason: t.id);
      expect(bg, lessThan(0.93), reason: t.id);
      expect(card, greaterThan(bg - 0.02), reason: t.id);
    }
  });

  test('ids de tema únicos', () {
    final ids = appThemes.map((t) => t.id).toList();
    expect(ids.toSet().length, ids.length);
  });
}
