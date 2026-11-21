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

  /// Repositorio público (enlace del menú y comprobación de actualizaciones).
  static const githubRepo = 'rafaeldb22/Oganesson-TakeNotes';
  static const githubUrl = 'https://github.com/$githubRepo';
  static const coffeeUrl = 'https://buymeacoffee.com/rafaeldb';

  /// true cuando Supabase tiene SMTP propio y la plantilla "Magic Link"
  /// incluye `{{ .Token }}`: activa "¿Has olvidado la contraseña?" del Vault
  /// (código de 6 dígitos por correo). Con el SMTP por defecto el correo
  /// solo trae un enlace, así que va desactivado.
  static const emailCodes = bool.fromEnvironment('EMAIL_CODES');

  static bool get isConfigured =>
      supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty;
}
