# BabuNotes — Android + Windows sincronizadas

App de notas estilo iPhone hecha con **Flutter**. Las notas se guardan en tu propia base de datos gratuita de **Supabase**: lo que escribes en el móvil aparece solo en el PC (y al revés) en uno o dos segundos. Funciona también sin internet: los cambios se suben al volver la conexión.

- **Android**: app + **widget 2x2** con la última nota y un botón «Nueva nota» que abre la app directamente con el teclado listo.
- **Windows**: vista de dos paneles (lista + nota), `Ctrl+N` para nota nueva.
- Fijar notas, buscar, deslizar para borrar, modo oscuro automático.

---

## 1. Crear la base de datos (Supabase) — 5 min

1. Entra en <https://supabase.com>, crea cuenta y pulsa **New project** (elige región Europa; la contraseña de la base de datos no la vas a necesitar).
2. Ve a **SQL Editor → New query**, pega todo el contenido de `supabase/schema.sql` y pulsa **Run**. Debe decir *Success*.
3. *(Recomendado)* **Authentication → Sign In / Providers → Email** y desactiva **Confirm email**. Así puedes crear la cuenta desde la app sin tener que confirmar el correo. Si lo dejas activado, también funciona: confirmas el email una vez y listo.
4. Copia dos datos de **Project Settings → API** (o **API Keys**, según la versión del panel):
   - **Project URL** (algo como `https://abcd1234.supabase.co`)
   - **anon / publishable key** (la clave pública; **nunca** la `service_role` / `secret`).

## 2. Subir el proyecto a GitHub — 5 min

1. Crea un repositorio **privado** nuevo en GitHub (por ejemplo `notas`).
2. Sube el contenido de esta carpeta (en la web: *uploading an existing file* y arrastra todo). Comprueba que se ha subido la carpeta `.github/workflows/compilar.yml`; si no aparece, créala a mano con **Add file → Create new file** y pega su contenido.
3. En el repo: **Settings → Secrets and variables → Actions → New repository secret** y crea:
   - `SUPABASE_URL` → la Project URL
   - `SUPABASE_ANON_KEY` → la clave anon/publishable

## 3. Compilar — automático (~10-15 min)

Ve a **Actions → Compilar Notas → Run workflow**. Se compila sola cada vez que subas cambios a `main`.
Si la primera ejecución falló porque aún no habías puesto los secrets, simplemente dale a **Re-run all jobs**.

Cuando termine, en **Releases** (columna derecha del repo) tendrás:

- **Notas.apk** → ábrelo desde el móvil e instálalo (Android te pedirá permitir instalar apps de esa fuente).
- **Notas-Windows.zip** → descomprímelo en una carpeta (por ejemplo `Documentos\Notas`) y abre `notas.exe`. Windows SmartScreen avisará porque la app no está firmada: **Más información → Ejecutar de todas formas**. Puedes anclarla a la barra de tareas.

## 4. Usarla

1. Abre la app en el móvil → **Crear cuenta** con tu correo y una contraseña.
2. En el PC → **Entrar** con la misma cuenta.
3. Widget: mantén pulsado el fondo de pantalla → **Widgets** → **Notas** → arrástralo (2x2).

## Cosas a saber

- **El widget no puede tener un cuadro de texto dentro**: Android no permite escribir directamente en widgets. Por eso el botón abre la app ya en una nota nueva con el teclado abierto.
- El widget se actualiza cuando la app ha estado abierta (aunque sea en segundo plano). Si escribes en el PC con el móvil apagado, el widget mostrará la nota nueva la próxima vez que abras la app.
- Si editas la *misma* nota en los dos dispositivos a la vez sin conexión, se queda la versión editada más tarde.
- **Supabase gratis pausa el proyecto tras ~1 semana sin uso**. Si pasa, entra en supabase.com y pulsa *Restore*; las notas no se pierden y además siguen en la caché de cada dispositivo.
- Las actualizaciones del APK se instalan encima sin desinstalar (la firma va incluida en `plataforma/android/debug.keystore`; por eso conviene que el repo sea privado).

## Estructura

```
lib/                         código de la app (Dart/Flutter)
  data/notes_repository.dart   caché local + sincronización + tiempo real
  data/widget_bridge.dart      datos que ve el widget de Android
  ui/                          pantallas (login, lista, editor)
plataforma/android/          widget 2x2 (Kotlin + XML) y AndroidManifest
supabase/schema.sql          tabla, seguridad y tiempo real
.github/workflows/           compilación automática (APK + Windows)
scripts/preparar.sh          genera android/ y windows/ con flutter create
```

### Compilar en tu propio PC (opcional)

Con Flutter instalado: `bash scripts/preparar.sh` y luego
`flutter run --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_ANON_KEY=...`


## Seguir con Claude Code en tu PC

1. Instala [Flutter](https://docs.flutter.dev/get-started/install/windows), Git y
   Visual Studio 2022 con "Desarrollo para el escritorio con C++".
2. Instala Claude Code y, en una terminal: `git clone https://github.com/rafaeldb22/BabuNotes`
   y luego `cd BabuNotes` y `claude`.
3. Pídele: *"prepara y ejecuta la app en Windows"*. Claude Code lee `CLAUDE.md`
   y sabe cómo compilarla (`./scripts/preparar_windows.ps1` y `flutter run -d windows`).
