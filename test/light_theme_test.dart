import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notas/ui/theme.dart';

void main() {
  test('modo claro suavizado: sin blanco puro y tarjeta no más oscura', () {
    for (final t in appThemes) {
      final c = t.lightSoft;
      final bg = HSLColor.fromColor(c.background).lightness;
      final card = HSLColor.fromColor(c.card).lightness;
      // Apagado: ni el fondo ni las tarjetas brillan (el estilo de la 1.x,
      // un poco más claro, sigue sin blanco puro).
      final legacy = t.soft == SoftStyle.legacy;
      expect(card, lessThanOrEqualTo(legacy ? 0.96 : 0.91), reason: t.id);
      expect(bg, lessThanOrEqualTo(legacy ? 0.93 : 0.87), reason: t.id);
      expect(card, greaterThan(bg - 0.02), reason: t.id);
      // El texto (casi negro) sigue leyéndose bien sobre las tarjetas.
      expect(card, greaterThan(0.75), reason: t.id);
    }
  });

  test('Clásico: gris blanco neutro, sin tinte azulado', () {
    final c = themeById('clasico').lightSoft;
    for (final color in [c.background, c.card, c.hover, c.searchFill]) {
      final h = HSLColor.fromColor(color);
      expect(h.saturation, 0);
      expect(color.b, closeTo(color.r, 0.002)); // nada de azul de más
    }
    expect(themeById('clasico').soft, SoftStyle.neutral);
  });

  test('Café: como antes de la 2.0', () {
    final t = themeById('cafe');
    expect(t.soft, SoftStyle.legacy);
    final bg = HSLColor.fromColor(t.lightSoft.background).lightness;
    final orig = HSLColor.fromColor(t.light.background).lightness;
    expect(bg, closeTo(orig - 0.055, 0.005));
  });

  test('modo claro estándar: más suave (menos saturado) que el original', () {
    for (final t in appThemes.where((t) => t.soft == SoftStyle.standard)) {
      final c = t.lightSoft;
      for (final (o, n) in [
        (t.light.background, c.background),
        (t.light.card, c.card),
        (t.light.selected, c.selected),
      ]) {
        expect(HSLColor.fromColor(n).saturation,
            lessThanOrEqualTo(HSLColor.fromColor(o).saturation + 1e-6),
            reason: t.id);
      }
    }
  });

  test('Clásico oscuro: barra de título casi negra, sin amarillo', () {
    final c = themeById('clasico').dark;
    final h = HSLColor.fromColor(c.titleBarColor);
    expect(h.lightness, lessThan(0.1));
    expect(h.saturation, lessThan(0.15));
    // Los demás temas siguen con su barra teñida por el acento.
    final o = themeById('oceano').dark;
    expect(o.titleBarColor, isNot(o.card));
  });

  test('ids de tema únicos', () {
    final ids = appThemes.map((t) => t.id).toList();
    expect(ids.toSet().length, ids.length);
  });
}
