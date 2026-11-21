# BabuNotes

App de notas estilo iPhone para **Android (APK + widget 2x2)** y **Windows**, hecha en
**Flutter** y sincronizada en tiempo real con **Supabase**. El usuario (Rafa) habla en
español: responde y escribe los textos de la interfaz en español.

## Ejecutar en local (Windows)

Requisitos: Flutter estable (3.50+), Git y Visual Studio **2022** con la carga
"Desarrollo para el escritorio con C++" (VS 2026 / MSVC 14.52 no compila el plugin
de notificaciones de Windows por `/await`).

```powershell
./scripts/preparar_windows.ps1     # genera windows/, nombre BabuNotes e icono
flutter run -d windows              # o: flutter build windows --release
```

Android (con un móvil conectado o un emulador):

```bash
bash scripts/preparar.sh android    # genera android/, copia widget/manifest, parchea desugaring, iconos
flutter run -d <id-del-movil>
```

`android/`, `windows/` y `test/` **no** están en git: se generan con `flutter create`
mediante los scripts. Los archivos propios de Android viven en `plataforma/android/`
y se copian encima (widget Kotlin, layout, manifest con permisos de notificaciones).

Modo demo sin cuenta (notas de ejemplo): `--dart-define=DEMO=true`.

## Estructura

- `lib/main.dart` — arranque, ventana de Windows (window_manager 0.5.x, tamaño mínimo,
  repintado tras redimensionar), tema animado.
- `lib/config.dart` — URL y clave *publishable* de Supabase (públicas por diseño; la
  seguridad es RLS).
- `lib/models/note.dart` — `Note` (texto plano + `rich` Delta Quill, carpeta,
  `remindAt`/`dueAt`/`done` para temporales) y `Folder`.
- `lib/data/notes_repository.dart` — caché local (SharedPreferences), cola de cambios,
  upsert a Supabase, realtime de `notes` y `folders`, gana la edición más reciente.
- `lib/data/reminders.dart` — avisos con flutter_local_notifications (Android y Windows).
- `lib/data/widget_bridge.dart` — datos del widget Android (home_widget).
- `lib/ui/` — pantallas: `notes_home.dart` (lista/editor, filtros, cachés para
  redimensionar sin tirones), `note_editor.dart` + `editor_toolbar.dart` (flutter_quill
  con barra propia), `calendar_view.dart` (mes actual ±3), `schedule_sheet.dart`
  (mini calendario + rueda de hora), `urgency.dart` (barra "mecha"), `split.dart`
  (separador ajustable), `theme.dart` (5 temas claro/oscuro), `wave_title.dart`
  (título retro Shrikhand con ola).
- `supabase/schema.sql` + `supabase/migracion_2.sql` — tablas, RLS y realtime.
- `.github/workflows/compilar.yml` — compila APK + Windows y publica un Release.
- `.github/workflows/probar-ventana.yml` — abre la app en Windows (modo demo),
  redimensiona y guarda capturas en la rama `capturas`.

## Convenciones

- Versiones de paquetes acotadas en `pubspec.yaml` (window_manager <0.6 porque 0.6
  cambió la API; flutter_local_notifications 19.x).
- Animaciones con `flutter_animate` y los helpers de `lib/ui/anim.dart` (`Anim.*`,
  `Bouncy`, `fadeThrough`, `pushTransition`).
- Colores siempre vía `Palette.*` (ThemeExtension `NotasColors`), nunca fijos.
- Antes de dar algo por terminado: `flutter analyze` y, si es posible, ejecutarlo.
