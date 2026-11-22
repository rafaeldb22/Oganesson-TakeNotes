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
    this.titleBar,
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

  /// Color de la barra de título de Windows. null = el de la tarjeta con un
  /// toque del acento.
  final Color? titleBar;

  bool get _isDark => card.computeLuminance() < 0.2;

  /// Barra de título: la propia del tema o la tarjeta teñida con el acento.
  Color get titleBarColor =>
      titleBar ??
      Color.alphaBlend(accent.withValues(alpha: _isDark ? 0.12 : 0.08), card);

  /// Versión más suave de una paleta clara: baja el brillo del fondo y de
  /// las tarjetas (que dejan de ser blanco puro) y oscurece un poco los
  /// textos secundarios y separadores para que se lean mejor.
  NotasColors softened([SoftStyle style = SoftStyle.standard]) {
    Color shift(Color c, double dl, {double maxL = 1, double ds = 0}) {
      final h = HSLColor.fromColor(c);
      return h
          .withLightness((h.lightness + dl).clamp(0.0, maxL))
          .withSaturation((h.saturation + ds).clamp(0.0, 1.0))
          .toColor();
    }

    // Gris neutro: sin ningún tinte (ni azulado ni cálido).
    Color grey(Color c, double dl, {double maxL = 1}) {
      final h = HSLColor.fromColor(c);
      return h
          .withLightness((h.lightness + dl).clamp(0.0, maxL))
          .withSaturation(0)
          .toColor();
    }

    switch (style) {
      case SoftStyle.legacy:
        // Como en la 1.x (más claro): el que gustaba en Café.
        return NotasColors(
          accent: shift(accent, -0.04, ds: 0.04),
          onAccent: onAccent,
          background: shift(background, -0.055, ds: 0.03),
          card: shift(card, -0.045, maxL: 0.955),
          secondary: shift(secondary, -0.08),
          separator: shift(separator, -0.07),
          selected: shift(selected, -0.05, ds: 0.05),
          searchFill: shift(searchFill, -0.06),
          hover: shift(hover, -0.07, maxL: 0.93),
        );
      case SoftStyle.neutral:
        // Casi blanco y neutro (sin el tono azulado del original), solo un
        // poco más oscuro para que no deslumbre.
        return NotasColors(
          accent: shift(accent, -0.04, ds: 0.04),
          onAccent: onAccent,
          background: grey(background, -0.035, maxL: 0.925),
          card: grey(card, -0.04, maxL: 0.955),
          secondary: grey(secondary, -0.08),
          separator: grey(separator, -0.06),
          selected: shift(selected, -0.05, ds: 0.05),
          searchFill: grey(searchFill, -0.045, maxL: 0.885),
          hover: grey(hover, -0.06, maxL: 0.935),
        );
      case SoftStyle.standard:
        break;
    }

    // Modo claro apagado: nada de blanco brillante (2.0: un poco más oscuro
    // que antes) y colores suaves: al oscurecer se baja la saturación en vez
    // de subirla, para que no se vean chillones.
    return NotasColors(
      accent: shift(accent, -0.06, ds: -0.08),
      onAccent: onAccent,
      background: shift(background, -0.10, maxL: 0.865, ds: -0.12),
      card: shift(card, -0.09, maxL: 0.905, ds: -0.12),
      secondary: shift(secondary, -0.10, ds: -0.08),
      separator: shift(separator, -0.11, ds: -0.10),
      selected: shift(selected, -0.09, ds: -0.10),
      searchFill: shift(searchFill, -0.11, maxL: 0.84, ds: -0.12),
      hover: shift(hover, -0.12, maxL: 0.875, ds: -0.12),
    );
  }

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
    Color? titleBar,
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
        titleBar: titleBar ?? this.titleBar,
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
      titleBar: titleBar == null && other.titleBar == null
          ? null
          : l(titleBarColor, other.titleBarColor),
    );
  }
}

/// Un tema = nombre + emoji + versión clara y oscura.
/// Cómo se apaga el modo claro de un tema.
enum SoftStyle {
  /// Más oscuro (2.0).
  standard,

  /// Como en la 1.x, más claro.
  legacy,

  /// Casi blanco y neutro (sin tinte de color), apenas más oscuro.
  neutral,
}

class AppTheme {
  const AppTheme({
    required this.id,
    required this.name,
    required this.description,
    required this.light,
    required this.dark,
    this.soft = SoftStyle.standard,
  });

  final String id;
  final String name;
  final String description;
  final NotasColors light;
  final NotasColors dark;
  final SoftStyle soft;

  static final _soft = <String, NotasColors>{};

  /// Modo claro suavizado (el que usa la app): sin blancos puros que
  /// deslumbren, con más contraste en textos secundarios y separadores.
  NotasColors get lightSoft =>
      _soft.putIfAbsent(id, () => light.softened(soft));
}

const appThemes = <AppTheme>[
  AppTheme(
    id: 'clasico',
    name: 'Clásico',
    description: 'Amarillo de toda la vida',
    // Gris blanco neutro (el fondo original tira a azulado).
    soft: SoftStyle.neutral,
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
      // Barra de título casi negra (sin el tinte amarillo del acento).
      titleBar: Color(0xFF141416),
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
  AppTheme(
    id: 'cereza',
    name: 'Cereza',
    description: 'Rosa intenso y nata',
    light: NotasColors(
      accent: Color(0xFFD6336C),
      onAccent: Colors.white,
      background: Color(0xFFFCF1F4),
      card: Color(0xFFFFFBFC),
      secondary: Color(0xFF7C6870),
      separator: Color(0xFFF0D5DE),
      selected: Color(0xFFFAD9E4),
      searchFill: Color(0xFFF4E4EA),
      hover: Color(0xFFFBF0F3),
    ),
    dark: NotasColors(
      accent: Color(0xFFFF8FB4),
      onAccent: Color(0xFF2A0A16),
      background: Color(0xFF170D11),
      card: Color(0xFF26161C),
      secondary: Color(0xFFB59AA4),
      separator: Color(0xFF402831),
      selected: Color(0xFF5A2338),
      searchFill: Color(0xFF26161C),
      hover: Color(0xFF321D25),
    ),
  ),
  AppTheme(
    id: 'medianoche',
    name: 'Medianoche',
    description: 'Azul eléctrico y noche',
    light: NotasColors(
      accent: Color(0xFF2F6FED),
      onAccent: Colors.white,
      background: Color(0xFFEFF3FB),
      card: Color(0xFFFCFDFF),
      secondary: Color(0xFF5E6B82),
      separator: Color(0xFFD3DCEC),
      selected: Color(0xFFD9E5FC),
      searchFill: Color(0xFFE2E9F5),
      hover: Color(0xFFF1F5FC),
    ),
    dark: NotasColors(
      accent: Color(0xFF7AA7FF),
      onAccent: Color(0xFF07152E),
      background: Color(0xFF0A0F1C),
      card: Color(0xFF141B2D),
      secondary: Color(0xFF8E9AB3),
      separator: Color(0xFF263049),
      selected: Color(0xFF1F3561),
      searchFill: Color(0xFF141B2D),
      hover: Color(0xFF1B2439),
    ),
  ),
  AppTheme(
    id: 'cafe',
    name: 'Café',
    description: 'Marrón tostado y crema',
    // Como estaba antes de la 2.0.
    soft: SoftStyle.legacy,
    light: NotasColors(
      accent: Color(0xFF9C6644),
      onAccent: Colors.white,
      background: Color(0xFFF6F0EA),
      card: Color(0xFFFFFCF8),
      secondary: Color(0xFF7A6A5E),
      separator: Color(0xFFE6D8CB),
      selected: Color(0xFFEFDDCC),
      searchFill: Color(0xFFEDE3D9),
      hover: Color(0xFFF8F2EC),
    ),
    dark: NotasColors(
      accent: Color(0xFFD4A373),
      onAccent: Color(0xFF24160B),
      background: Color(0xFF14100C),
      card: Color(0xFF221B15),
      secondary: Color(0xFFAD9C8D),
      separator: Color(0xFF3B3026),
      selected: Color(0xFF4A3524),
      searchFill: Color(0xFF221B15),
      hover: Color(0xFF2C231B),
    ),
  ),
  AppTheme(
    id: 'grafito',
    name: 'Grafito',
    description: 'Blanco y negro, sin distracciones',
    light: NotasColors(
      accent: Color(0xFF2B2B2E),
      onAccent: Colors.white,
      background: Color(0xFFF2F2F2),
      card: Colors.white,
      secondary: Color(0xFF6E6E73),
      separator: Color(0xFFD9D9DC),
      selected: Color(0xFFE4E4E7),
      searchFill: Color(0xFFE6E6E8),
      hover: Color(0xFFF6F6F7),
    ),
    dark: NotasColors(
      accent: Color(0xFFE8E8EA),
      onAccent: Color(0xFF111111),
      background: Color(0xFF0B0B0C),
      card: Color(0xFF18181A),
      secondary: Color(0xFF9A9AA0),
      separator: Color(0xFF2E2E31),
      selected: Color(0xFF34343A),
      searchFill: Color(0xFF18181A),
      hover: Color(0xFF222225),
    ),
  ),
  AppTheme(
    id: 'aurora',
    name: 'Aurora',
    description: 'Verde boreal y cian',
    light: NotasColors(
      accent: Color(0xFF0E9F8E),
      onAccent: Colors.white,
      background: Color(0xFFEDF7F5),
      card: Color(0xFFFBFEFD),
      secondary: Color(0xFF5B726E),
      separator: Color(0xFFCDE5E0),
      selected: Color(0xFFCDF0E9),
      searchFill: Color(0xFFDDEFEB),
      hover: Color(0xFFF0F8F6),
    ),
    dark: NotasColors(
      accent: Color(0xFF4FE3C1),
      onAccent: Color(0xFF02201A),
      background: Color(0xFF07130F),
      card: Color(0xFF10211C),
      secondary: Color(0xFF8BA9A1),
      separator: Color(0xFF1F3A33),
      selected: Color(0xFF14453A),
      searchFill: Color(0xFF10211C),
      hover: Color(0xFF172C26),
    ),
  ),
  AppTheme(
    id: 'sepia',
    name: 'Sepia',
    description: 'Papel cálido, cómodo para leer',
    light: NotasColors(
      accent: Color(0xFF9A5B2E),
      onAccent: Colors.white,
      background: Color(0xFFF1E7D6),
      card: Color(0xFFFAF3E6),
      secondary: Color(0xFF7A6A58),
      separator: Color(0xFFDCCDB5),
      selected: Color(0xFFEBD9B8),
      searchFill: Color(0xFFE8DCC6),
      hover: Color(0xFFF4EAD8),
    ),
    dark: NotasColors(
      accent: Color(0xFFE0A86E),
      onAccent: Color(0xFF241A10),
      background: Color(0xFF1B1611),
      card: Color(0xFF26201A),
      secondary: Color(0xFFA8998A),
      separator: Color(0xFF3B3229),
      selected: Color(0xFF4A3826),
      searchFill: Color(0xFF26201A),
      hover: Color(0xFF30281F),
    ),
  ),
  AppTheme(
    id: 'nordico',
    name: 'Nórdico',
    description: 'Gris azulado frío y sereno',
    light: NotasColors(
      accent: Color(0xFF4C6A92),
      onAccent: Colors.white,
      background: Color(0xFFE8ECF1),
      card: Color(0xFFF6F8FA),
      secondary: Color(0xFF5F6B7A),
      separator: Color(0xFFCCD4DE),
      selected: Color(0xFFD5E0EE),
      searchFill: Color(0xFFDDE3EA),
      hover: Color(0xFFEEF2F6),
    ),
    dark: NotasColors(
      accent: Color(0xFF88C0D0),
      onAccent: Color(0xFF14202A),
      background: Color(0xFF2E3440),
      card: Color(0xFF3B4252),
      secondary: Color(0xFFA3ABBA),
      separator: Color(0xFF4C566A),
      selected: Color(0xFF3E5A6B),
      searchFill: Color(0xFF3B4252),
      hover: Color(0xFF434C5E),
    ),
  ),
  AppTheme(
    id: 'neon',
    name: 'Neón',
    description: 'Magenta y cian sobre negro',
    light: NotasColors(
      accent: Color(0xFFC2185B),
      onAccent: Colors.white,
      background: Color(0xFFEFE9F2),
      card: Color(0xFFFAF6FC),
      secondary: Color(0xFF6A5F73),
      separator: Color(0xFFDACFE0),
      selected: Color(0xFFF5CFE1),
      searchFill: Color(0xFFE6DDEB),
      hover: Color(0xFFF5EEF8),
    ),
    dark: NotasColors(
      accent: Color(0xFFFF4FA3),
      onAccent: Color(0xFF1A0010),
      background: Color(0xFF0B0712),
      card: Color(0xFF16101F),
      secondary: Color(0xFF9D8FB0),
      separator: Color(0xFF2C2240),
      selected: Color(0xFF3D1636),
      searchFill: Color(0xFF16101F),
      hover: Color(0xFF211830),
    ),
  ),
  AppTheme(
    id: 'matcha',
    name: 'Matcha',
    description: 'Verde té suave y crema',
    light: NotasColors(
      accent: Color(0xFF5E8C3A),
      onAccent: Colors.white,
      background: Color(0xFFEAEEDD),
      card: Color(0xFFF7F8EF),
      secondary: Color(0xFF65705A),
      separator: Color(0xFFD3DAC2),
      selected: Color(0xFFDDE8C6),
      searchFill: Color(0xFFE1E6D2),
      hover: Color(0xFFF0F3E6),
    ),
    dark: NotasColors(
      accent: Color(0xFFA5D46E),
      onAccent: Color(0xFF13200A),
      background: Color(0xFF12170E),
      card: Color(0xFF1D2417),
      secondary: Color(0xFF9AA690),
      separator: Color(0xFF313B28),
      selected: Color(0xFF34482A),
      searchFill: Color(0xFF1D2417),
      hover: Color(0xFF262F1F),
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

  /// Fondo de la barra de título de Windows: la superficie de tarjeta con un
  /// toque del acento, para que se distinga del contenido de la app.
  static Color titleBar(BuildContext c) {
    return of(c).titleBarColor;
  }
}

ThemeData buildTheme(AppTheme t, Brightness b) {
  final dark = b == Brightness.dark;
  final c = dark ? t.dark : t.lightSoft;
  final fg = dark ? Colors.white : const Color(0xFF111111);

  final scheme =
      ColorScheme.fromSeed(seedColor: c.accent, brightness: b).copyWith(
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
