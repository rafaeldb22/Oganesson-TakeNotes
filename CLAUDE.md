# Oganesson TakeNotes

iPhone-style notes app for **Android (APK + home-screen widgets)** and **Windows**, built
with **Flutter** and synced in real time with **Supabase**. The owner (Rafa) speaks
Spanish: reply to him in Spanish. The app UI is **Spanish + English**: write UI text in
Spanish wrapped in `tr('…')` / `trf('… {0}', [x])` / `trn(n, one, many)` (`lib/ui/i18n.dart`)
and add the English to `lib/ui/i18n_en.dart`. Repository documentation, workflows and commit
messages are in English.

## First-time setup on a new PC

`scripts/setup_dev_windows.ps1` installs Git, Visual Studio 2022 (C++ desktop workload),
Flutter stable and Claude Code with winget / official installers, clones the repo into
`%USERPROFILE%\develop\Oganesson-TakeNotes` and runs `prepare_windows.ps1`.

## Run locally (Windows)

Requirements: Flutter stable (3.50+), Git and Visual Studio **2022** with the
"Desktop development with C++" workload (VS 2026 / MSVC 14.52 cannot build the Windows
notifications plugin because of `/await`), plus Windows **Developer Mode** on (Flutter needs
symlinks for plugins: `start ms-settings:developers`; the setup script enables it).

```powershell
./scripts/prepare_windows.ps1     # generates windows/, sets the Oganesson name and icon
flutter run -d windows             # or: flutter build windows --release
```

Android (device or emulator connected). Gradle needs **JDK 21** (with JDK 17 the release
lint of `image_picker_android` crashes on `List.removeLast()`); CI uses Java 21:

```bash
bash scripts/prepare_android.sh    # generates android/, copies widgets/manifest, desugaring, icons
flutter run -d <device-id>
```

`android/` and `windows/` are **not** in git: the scripts generate them with `flutter create`.
`test/` is in git (`flutter test`, also run by CI before building). Custom Android files live in `platform/android/` and are copied on top
(Kotlin widgets, layouts, manifest with notification permissions).

Demo mode without an account (sample notes): `--dart-define=DEMO=true`.

Notification test: `--dart-define=TEST_TOAST=true` schedules a test notification one
minute after startup (log line `TEST_TOAST programado para …`); close the app to check
that it still arrives. On Windows, check toasts are enabled first:
`ToastNotificationManager.CreateToastNotifier('Rafa.Oganesson').Setting` must be `Enabled`.

## Structure

- `lib/main.dart` — startup, Windows window (window_manager 0.5.x, hidden system title
  bar, minimum size, repaint after resizing), animated theme.
- `lib/config.dart` — Supabase URL and *publishable* key (public by design; security is RLS).
- `lib/models/note.dart` — `Note` (plain text + `rich` Quill Delta, folder, colour,
  `remindAt`/`dueAt`/`done` for deadlines) and `Folder`.
- `lib/data/notes_repository.dart` — local cache (SharedPreferences), change queue,
  upsert to Supabase, realtime for `notes` and `folders`, last edit wins, 3-day trash.
- `lib/data/reminders.dart` — notifications at 7/3/1 days before the deadline.
- `lib/data/widget_bridge.dart` — data for the Android widgets (home_widget). Renders the
  image widgets (calendar, tasks, next task, pinned notes: `lib/ui/calendar_widget_image.dart`,
  `lib/ui/widget_images.dart`) only for widgets that are installed. Kotlin side:
  `platform/android/.../ImagenWidget.kt` (base + TareasWidget/ProximaWidget/FijadasWidget,
  image picked by widget size), `CalendarioWidget.kt`, `NotasWidget.kt`, `AccionesWidget.kt`
  (native quick actions). Widget deep links: `notas://nueva|calendario|red|buscar|nota/<id>`.
- `lib/data/note_links.dart` — `NoteGraph` (links, backlinks). Links are `Note.links` (ids,
  set from right-click → *Enlazar* / *Crear subnota*, column `notes.links`); legacy
  `[[Title]]` text links are still read.
- `lib/data/vault.dart` — `VaultLock`: master password for the Vault (notes with `vault = true`).
  Stored only as a PBKDF2-SHA256 hash (SharedPreferences + Supabase table `vaults`), silent
  auto-lock after 5 min without activity. The Vault is only reachable from ⋯ (its own screen,
  `lib/ui/vault_screen.dart`); `NotesRepository.notes` never contains vault notes
  (`vaultNotes` does, when unlocked). Password change needs the current one
  (`lib/ui/vault_dialogs.dart`) **or the account password** (`VaultLock.verifyAccountPassword`,
  re-signs in with `signInWithPassword`; also used by "forgot password" on the locked Vault).
  Email-code reset exists but is gated by `AppConfig.emailCodes`. Vault notes are not end-to-end
  encrypted (same RLS as other notes).
- Archive & manual order: `Note.archived` / `Note.position` (migration 006; uploads skip them
  while the columns are missing, `serverHasArchive`). Swipe left → archive, right → delete.
  Drag & drop in the list: `Draggable` (vertical, desktop) / `LongPressDraggable` (Android),
  drop targets on tiles, folder headers (`FolderGroup.onDropNote`) and `DropZone` headers.
  Reordering switches the sort to `'manual'`. Archived list: `lib/ui/archived_sheet.dart`.
- Images in notes: `lib/data/note_images.dart` (`NoteImages`: Quill image embeds with source
  `sb://<user>/<id>?w=&h=`, private Storage bucket `note-images` from migration 007, disk cache,
  persistent upload queue, background compression `compressImage`, cleanup on hard delete) and
  `lib/ui/note_image.dart` (`NoteImageEmbedBuilder`/`NoteImageView`, full-screen viewer,
  `pasteImagesFromClipboard` — wired as `QuillClipboardConfig.onClipboardPaste` on the
  controller —, `pickAndInsertImages` (image_picker), `ImageDropZone` (desktop_drop), copy with
  pasteboard, save with quill_native_bridge). Images are U+FFFC in `Note.content`; `Note.title`
  and `preview` ignore it.
- Screen transitions (`lib/ui/anim.dart`) all share one widget structure (`_layered`) so the
  transition can change mid-way without rebuilding the outgoing screen. Deleting/archiving the
  open note sets `_discarding` in `notes_home.dart` (editor uses `discardTransition`, the list
  `stillTransition`); list rows only play their entrance animation during `_entranceOpen`
  (first 900 ms after the list is shown / the view changes).
- Smooth wheel scrolling: use `SmoothScrollController` (`lib/ui/smooth_scroll.dart`) for new
  scroll views on desktop.
- Completed tasks: `Note.doneAt` (column `notes.done_at`); done > 3 days → hidden from lists and
  shown in ⋯ → Completadas (`lib/ui/completed_sheet.dart`); > 30 days → trash.
- `lib/data/updater.dart` — checks GitHub Releases (`AppConfig.githubRepo`) and installs the
  update (Windows: silent Inno Setup install that reopens the app; Android: APK + system
  installer). Needs the repository to be public.
- `lib/ui/` — `notes_home.dart` (list/editor, filters, cached panels), `note_editor.dart`
  + `editor_toolbar.dart` (flutter_quill with a custom toolbar), `calendar_view.dart`
  (current month ±3), `schedule_sheet.dart` (mini calendar + time wheel), `urgency.dart`
  (fuse bar), `split.dart` (resizable divider), `theme.dart` (10 light/dark themes),
  `wave_title.dart` (retro Shrikhand title), `title_bar.dart` (custom Windows title bar),
  `note_color_sheet.dart`, `trash_sheet.dart`, `calendar_widget_image.dart` (Android
  calendar widget in 2x2/4x2/4x4, rendered as images with home_widget), `graph_view.dart`
  (force-directed note network), `link_picker.dart` (`[[` note picker), `update_dialog.dart`
  (update prompt, `openLink`), `sort_menu.dart` (animated sort menu), `account_dialogs.dart`
  (change account password), `language_picker.dart`, `i18n.dart` + `i18n_en.dart`,
  `folder_group.dart` (collapsible Zen-style folders inside the list), `context_menu.dart`
  (`showContextMenu` for right-click menus), `toast.dart` (`showToast`, animated pop-up
  notifications; use it instead of SnackBar).
- `supabase/migrations/` — schema, RLS, realtime, colour column, delete policy, `vaults`
  table (005), archive/order (006), `note-images` Storage bucket + policies (007). Migrations are
  run by hand in the Supabase SQL Editor.
- `installer/oganesson.iss` — Inno Setup script for `Oganesson-Setup.exe`.
- `lib/ui/logo.dart` — logo stroke/colours (`logoGlyphPath`, centred and scaled to `logoFill`)
  and the `StartupSplash` animation (wraps the whole app in `main.dart`). On Windows the window
  is shown from Dart, transparent, and made opaque after a few frames (no white flash);
  `prepare_windows.ps1` removes the runner's own `Show()` for this.
- Bottom sheets: pass `useSafeArea: true` and cap the height (≤ 90 %) so they never reach the
  phone's status bar.
- `tool/generate_icon_test.dart` — draws the logo with Flutter and writes `assets/icon/*.png`
  and `docs/icon.png` (`flutter test tool/generate_icon_test.dart`).
- `tool/record_gifs_test.dart` — renders the README media from the real widgets in demo data
  (`docs/banner.png`, `docs/screenshot-*.png`, `docs/startup.gif`, `docs/mobile.gif`,
  `docs/themes.gif`) with real Roboto/Material Icons fonts. Re-run it after visible UI changes.
- `.github/workflows/build.yml` — builds APK + Windows installer/zip and publishes a
  release (tag `v<pubspec version>`, notes taken from `CHANGELOG.md`).
- `.github/workflows/window-test.yml` — opens the app on Windows (demo mode), resizes
  it and stores screenshots in the `screenshots` branch.

## Conventions

- Bump `version:` in `pubspec.yaml` and add a section to `CHANGELOG.md` for each release.
- Windows minimum window width is 760 px: always the two-panel layout (breakpoint 700).
- Package versions are pinned in `pubspec.yaml` (window_manager <0.6 because 0.6 changed
  its API; flutter_local_notifications 19.x).
- Animations use `flutter_animate` and the helpers in `lib/ui/anim.dart`.
- Colours always through `Palette.*` (ThemeExtension `NotasColors`), never hard-coded. Light
  mode uses `AppTheme.lightSoft` (toned-down `light`), not `light` directly.
- Account password reset with an email code needs custom SMTP in Supabase (default templates
  only contain a link); not implemented. The Vault reset uses the same mechanism.
- Before calling something done: `flutter analyze` and, if possible, run it.

## Open items / known gaps

- Not yet verified on a real phone: Android calendar widget (2x2/4x2/4x4 sizes and the
  solid background), in-app APK update, trash purge, 7/3/1-day reminders, notification
  permissions on Android 13+.
- Migrations 005 (Vault, links, done_at) and 006 (archived, position) were applied to the
  production Supabase project on 2026-11-21 (via the Management API). New migrations still
  have to be run by hand (SQL Editor) or with a personal access token.
- Migration 007 (images bucket) is **pending** as of 2026-11-22: until it runs, images stay on
  the device that added them ("Waiting to upload") and other devices show "Image not available".
- Images: not yet verified on a real phone (Android paste via pasteboard, camera, saving to the
  gallery on Android < 10).
- Vault password reset by email code needs the Supabase *Magic Link* email template to include
  `{{ .Token }}`; on the free plan editing templates requires custom SMTP (Brevo, Resend…).
- In-app updates need the repository to be public (the GitHub API returns 404 while it is
  private, and the app then simply reports no update).
- Windows: some GPUs showed black/unpainted areas after resizing; a forced full repaint
  runs after resize/maximise (`forceFullRepaint` in `lib/main.dart`). Confirmed fine on
  the owner's PC (2026-11-21: 760 px, 1500x900, maximised and restored, no artefacts).
- Windows notifications: still unknown whether scheduled toasts fire while the app is
  closed (unpackaged app). The 2026-11-21 test could not tell: notifications were turned
  off system-wide on the owner's PC (`ToastEnabled = 0`). Repeat with `TEST_TOAST`.
- Password reset by email code: needs custom SMTP in Supabase (see above).
- Code comments are still in Spanish.
- The repository is private (the owner plans to make it public): until then the README
  download links only work when signed in and in-app update checks find nothing.
