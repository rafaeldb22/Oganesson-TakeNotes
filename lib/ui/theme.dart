import 'package:flutter/material.dart';

class Palette {
  static const accentLight = Color(0xFFD99A00);
  static const accentDark = Color(0xFFFFD60A);

  static bool _dark(BuildContext c) =>
      Theme.of(c).brightness == Brightness.dark;

  static Color accent(BuildContext c) => _dark(c) ? accentDark : accentLight;
  static Color background(BuildContext c) =>
      _dark(c) ? Colors.black : const Color(0xFFF2F2F7);
  static Color card(BuildContext c) =>
      _dark(c) ? const Color(0xFF1C1C1E) : Colors.white;
  static Color secondary(BuildContext c) =>
      _dark(c) ? const Color(0xFF98989F) : const Color(0xFF6C6C70);
  static Color separator(BuildContext c) =>
      _dark(c) ? const Color(0xFF38383A) : const Color(0xFFD1D1D6);
  static Color selected(BuildContext c) =>
      _dark(c) ? const Color(0xFF4A4120) : const Color(0xFFFFF1C2);
  static Color searchFill(BuildContext c) =>
      _dark(c) ? const Color(0xFF1C1C1E) : const Color(0xFFE3E3E8);
}

ThemeData buildTheme(Brightness b) {
  final dark = b == Brightness.dark;
  final accent = dark ? Palette.accentDark : Palette.accentLight;
  final bg = dark ? Colors.black : const Color(0xFFF2F2F7);
  final fg = dark ? Colors.white : Colors.black;

  final scheme = ColorScheme.fromSeed(seedColor: accent, brightness: b).copyWith(
    primary: accent,
    onPrimary: dark ? Colors.black : Colors.white,
    surface: dark ? const Color(0xFF1C1C1E) : Colors.white,
  );

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: bg,
    appBarTheme: AppBarTheme(
      backgroundColor: bg,
      foregroundColor: fg,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      iconTheme: IconThemeData(color: accent),
      actionsIconTheme: IconThemeData(color: accent),
    ),
    textSelectionTheme: TextSelectionThemeData(
      cursorColor: accent,
      selectionHandleColor: accent,
      selectionColor: dark ? const Color(0x66FFD60A) : const Color(0x55D99A00),
    ),
  );
}
