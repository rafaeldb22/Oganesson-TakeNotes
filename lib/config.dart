/// Claves de Supabase. La "publishable key" es pública por diseño
/// (la seguridad la dan las políticas RLS de la tabla). Se pueden
/// sobrescribir al compilar con --dart-define si cambias de proyecto.
class AppConfig {
  static const supabaseUrl = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'https://otjmapexdxndreozjhfn.supabase.co',
  );
  static const supabaseAnonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue: 'sb_publishable_WpQZsE_uPBQibO3_09BNUA_8tEIYlnz',
  );

  /// Solo para pruebas automáticas: entra sin cuenta con notas de ejemplo.
  static const demo = bool.fromEnvironment('DEMO');

  static bool get isConfigured =>
      supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty;
}
