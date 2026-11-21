import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Colores propios de la app. Es una ThemeExtension, así que al cambiar de
/// tema Flutter interpola (lerp) cada color y el cambio se ve animado.
@immutable
class NotasColors extends ThemeExtension<NotasColors> {
  const NotasColors({
    required this.accent,
    required this.onAccent,
    required this.background,
    required this.card,
    required this.secondary,
    required this.separator,
    required this.selected,
    required this.searchFill,
    required this.hover,
  });

  final Color accent;
  final Color onAccent;
  final Color background;
  final Color card;
  final Color secondary;
  final Color separator;
  final Color selected;
  final Color searchFill;
  final Color hover;

  @override
  NotasColors copyWith({
    Color? accent,
    Color? onAccent,
    Color? background,
    Color? card,
    Color? secondary,
    Color? separator,
    Color? selected,
    Color? searchFill,
    Color? hover,
  }) =>
      NotasColors(
        accent: accent ?? this.accent,
        onAccent: onAccent ?? this.onAccent,
        background: background ?? this.background,
        card: card ?? this.card,
        secondary: secondary ?? this.secondary,
        separator: separator ?? this.separator,
        selected: selected ?? this.selected,
        searchFill: searchFill ?? this.searchFill,
        hover: hover ?? this.hover,
      );

  @override
  NotasColors lerp(ThemeExtension<NotasColors>? other, double t) {
    if (other is! NotasColors) return this;
    Color l(Color a, Color b) => Color.lerp(a, b, t)!;
    return NotasColors(
      accent: l(accent, other.accent),
      onAccent: l(onAccent, other.onAccent),
      background: l(background, other.background),
      card: l(card, other.card),
      secondary: l(secondary, other.secondary),
      separator: l(separator, other.separator),
      selected: l(selected, other.selected),
      searchFill: l(searchFill, other.searchFill),
      hover: l(hover, other.hover),
    );
  }
}

/// Un tema = nombre + emoji + versión clara y oscura.
class AppTheme {
  const AppTheme({
    required this.id,
    required this.name,
    required this.description,
    required this.light,
    required this.dark,
  });

  final String id;
  final String name;
  final String description;
  final NotasColors light;
  final NotasColors dark;
}

const appThemes = <AppTheme>[
  AppTheme(
    id: 'clasico',
    name: 'Clásico',
    description: 'Amarillo de toda la vida',
    light: NotasColors(
      accent: Color(0xFFD99A00),
      onAccent: Colors.white,
      background: Color(0xFFF2F2F7),
      card: Colors.white,
      secondary: Color(0xFF6C6C70),
      separator: Color(0xFFD1D1D6),
      selected: Color(0xFFFFF1C2),
      searchFill: Color(0xFFE3E3E8),
      hover: Color(0xFFF7F7FA),
    ),
    dark: NotasColors(
      accent: Color(0xFFFFD60A),
      onAccent: Colors.black,
      background: Colors.black,
      card: Color(0xFF1C1C1E),
      secondary: Color(0xFF98989F),
      separator: Color(0xFF38383A),
      selected: Color(0xFF4A4120),
      searchFill: Color(0xFF1C1C1E),
      hover: Color(0xFF2C2C2E),
    ),
  ),
  AppTheme(
    id: 'oceano',
    name: 'Océano',
    description: 'Turquesa y azul marino',
    light: NotasColors(
      accent: Color(0xFF1F7A7A),
      onAccent: Colors.white,
      background: Color(0xFFEAF4F4),
      card: Color(0xFFFBFEFD),
      secondary: Color(0xFF5B7078),
      separator: Color(0xFFC7DCDD),
      selected: Color(0xFFCDEBEC),
      searchFill: Color(0xFFDCEBEC),
      hover: Color(0xFFF1F8F8),
    ),
    dark: NotasColors(
      accent: Color(0xFF5CC8C8),
      onAccent: Color(0xFF0B1A1F),
      background: Color(0xFF0F1722),
      card: Color(0xFF1A2332),
      secondary: Color(0xFF8FA6B2),
      separator: Color(0xFF2B3A4E),
      selected: Color(0xFF1E4A52),
      searchFill: Color(0xFF1A2332),
      hover: Color(0xFF223047),
    ),
  ),
  AppTheme(
    id: 'atardecer',
    name: 'Atardecer',
    description: 'Naranja cálido y arena',
    light: NotasColors(
      accent: Color(0xFFD9553A),
      onAccent: Colors.white,
      background: Color(0xFFFBF3EC),
      card: Color(0xFFFFFCF9),
      secondary: Color(0xFF7A675C),
      separator: Color(0xFFEAD7C8),
      selected: Color(0xFFFBDCCB),
      searchFill: Color(0xFFF2E5DA),
      hover: Color(0xFFFBF1E9),
    ),
    dark: NotasColors(
      accent: Color(0xFFF4A261),
      onAccent: Color(0xFF2A1408),
      background: Color(0xFF16100D),
      card: Color(0xFF241A15),
      secondary: Color(0xFFB09A8C),
      separator: Color(0xFF3D2E26),
      selected: Color(0xFF5A3424),
      searchFill: Color(0xFF241A15),
      hover: Color(0xFF30231C),
    ),
  ),
  AppTheme(
    id: 'bosque',
    name: 'Bosque',
    description: 'Verde salvia y marfil',
    light: NotasColors(
      accent: Color(0xFF3F7A3B),
      onAccent: Colors.white,
      background: Color(0xFFF1F3EC),
      card: Color(0xFFFCFCF8),
      secondary: Color(0xFF6B7263),
      separator: Color(0xFFD5DACB),
      selected: Color(0xFFDDE9D2),
      searchFill: Color(0xFFE4E8DC),
      hover: Color(0xFFF4F6EF),
    ),
    dark: NotasColors(
      accent: Color(0xFF9CCB8C),
      onAccent: Color(0xFF102010),
      background: Color(0xFF0E130D),
      card: Color(0xFF1A2218),
      secondary: Color(0xFF98A28E),
      separator: Color(0xFF2E3A2B),
      selected: Color(0xFF2D4A2B),
      searchFill: Color(0xFF1A2218),
      hover: Color(0xFF232D20),
    ),
  ),
  AppTheme(
    id: 'galaxia',
    name: 'Galaxia',
    description: 'Lavanda y morado profundo',
    light: NotasColors(
      accent: Color(0xFF6A4FB3),
      onAccent: Colors.white,
      background: Color(0xFFF3F1FA),
      card: Color(0xFFFDFCFF),
      secondary: Color(0xFF6E6880),
      separator: Color(0xFFDAD5EA),
      selected: Color(0xFFE5DDFA),
      searchFill: Color(0xFFE7E3F3),
      hover: Color(0xFFF6F4FC),
    ),
    dark: NotasColors(
      accent: Color(0xFFB9A4E8),
      onAccent: Color(0xFF1A1030),
      background: Color(0xFF120C1C),
      card: Color(0xFF221932),
      secondary: Color(0xFFA59CB8),
      separator: Color(0xFF3A2F4F),
      selected: Color(0xFF3F3070),
      searchFill: Color(0xFF221932),
      hover: Color(0xFF2C2240),
    ),
  ),
];

AppTheme themeById(String id) =>
    appThemes.firstWhere((t) => t.id == id, orElse: () => appThemes.first);

/// Tema elegido + modo (automático / claro / oscuro). Se guarda en el
/// dispositivo para que la próxima vez se abra igual.
class ThemeSettings extends ChangeNotifier {
  String themeId = appThemes.first.id;
  ThemeMode mode = ThemeMode.system;

  static const _kTheme = 'ajustes_tema';
  static const _kMode = 'ajustes_modo';

  AppTheme get theme => themeById(themeId);

  /// Aviso para repintar el widget de Android con el color nuevo.
  VoidCallback? onThemeChanged;

  Future<void> load() async {
    try {
      final p = await SharedPreferences.getInstance();
      themeId = themeById(p.getString(_kTheme) ?? themeId).id;
      mode = ThemeMode.values.firstWhere(
        (m) => m.name == p.getString(_kMode),
        orElse: () => ThemeMode.system,
      );
    } catch (_) {}
  }

  Future<void> setTheme(String id) async {
    if (id == themeId) return;
    themeId = id;
    notifyListeners();
    onThemeChanged?.call();
    try {
      (await SharedPreferences.getInstance()).setString(_kTheme, id);
    } catch (_) {}
  }

  Future<void> setMode(ThemeMode m) async {
    if (m == mode) return;
    mode = m;
    notifyListeners();
    try {
      (await SharedPreferences.getInstance()).setString(_kMode, m.name);
    } catch (_) {}
  }
}

/// Instancia global (la app es pequeña; así no hace falta un paquete extra).
final themeSettings = ThemeSettings();

/// Acceso corto a los colores del tema actual.
class Palette {
  static NotasColors of(BuildContext c) =>
      Theme.of(c).extension<NotasColors>() ?? appThemes.first.light;

  static Color accent(BuildContext c) => of(c).accent;
  static Color background(BuildContext c) => of(c).background;
  static Color card(BuildContext c) => of(c).card;
  static Color secondary(BuildContext c) => of(c).secondary;
  static Color separator(BuildContext c) => of(c).separator;
  static Color selected(BuildContext c) => of(c).selected;
  static Color searchFill(BuildContext c) => of(c).searchFill;
  static Color hover(BuildContext c) => of(c).hover;
}

ThemeData buildTheme(AppTheme t, Brightness b) {
  final dark = b == Brightness.dark;
  final c = dark ? t.dark : t.light;
  final fg = dark ? Colors.white : const Color(0xFF111111);

  final scheme = ColorScheme.fromSeed(seedColor: c.accent, brightness: b)
      .copyWith(
    primary: c.accent,
    onPrimary: c.onAccent,
    surface: c.card,
    secondary: c.accent,
  );

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: c.background,
    extensions: [c],
    splashFactory: InkRipple.splashFactory,
    appBarTheme: AppBarTheme(
      backgroundColor: c.background,
      foregroundColor: fg,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      iconTheme: IconThemeData(color: c.accent),
      actionsIconTheme: IconThemeData(color: c.accent),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      actionTextColor: c.accent,
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: c.card,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: c.card,
      surfaceTintColor: Colors.transparent,
      showDragHandle: true,
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: c.card,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    ),
    textSelectionTheme: TextSelectionThemeData(
      cursorColor: c.accent,
      selectionHandleColor: c.accent,
      selectionColor: c.accent.withValues(alpha: 0.35),
    ),
  );
}
