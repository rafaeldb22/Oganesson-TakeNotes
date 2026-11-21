# Oganesson TakeNotes

iPhone-style notes app for **Android (APK + home-screen widgets)** and **Windows**, built
with **Flutter** and synced in real time with **Supabase**. The owner (Rafa) speaks
Spanish: reply to him in Spanish and keep the app's UI text in Spanish. Repository
documentation, workflows and commit messages are in English.

## First-time setup on a new PC

`scripts/setup_dev_windows.ps1` installs Git, Visual Studio 2022 (C++ desktop workload),
Flutter stable and Claude Code with winget / official installers, clones the repo into
`%USERPROFILE%\develop\Oganesson-TakeNotes` and runs `prepare_windows.ps1`.

## Run locally (Windows)

Requirements: Flutter stable (3.50+), Git and Visual Studio **2022** with the
"Desktop development with C++" workload (VS 2026 / MSVC 14.52 cannot build the Windows
notifications plugin because of `/await`).

```powershell
./scripts/prepare_windows.ps1     # generates windows/, sets the Oganesson name and icon
flutter run -d windows             # or: flutter build windows --release
```

Android (device or emulator connected):

```bash
bash scripts/prepare_android.sh    # generates android/, copies widgets/manifest, desugaring, icons
flutter run -d <device-id>
```

`android/`, `windows/` and `test/` are **not** in git: the scripts generate them with
`flutter create`. Custom Android files live in `platform/android/` and are copied on top
(Kotlin widgets, layouts, manifest with notification permissions).

Demo mode without an account (sample notes): `--dart-define=DEMO=true`.

## Structure

- `lib/main.dart` — startup, Windows window (window_manager 0.5.x, hidden system title
  bar, minimum size, repaint after resizing), animated theme.
- `lib/config.dart` — Supabase URL and *publishable* key (public by design; security is RLS).
- `lib/models/note.dart` — `Note` (plain text + `rich` Quill Delta, folder, colour,
  `remindAt`/`dueAt`/`done` for deadlines) and `Folder`.
- `lib/data/notes_repository.dart` — local cache (SharedPreferences), change queue,
  upsert to Supabase, realtime for `notes` and `folders`, last edit wins, 3-day trash.
- `lib/data/reminders.dart` — notifications at 7/3/1 days before the deadline.
- `lib/data/widget_bridge.dart` — data for the Android widgets (home_widget).
- `lib/ui/` — `notes_home.dart` (list/editor, filters, cached panels), `note_editor.dart`
  + `editor_toolbar.dart` (flutter_quill with a custom toolbar), `calendar_view.dart`
  (current month ±3), `schedule_sheet.dart` (mini calendar + time wheel), `urgency.dart`
  (fuse bar), `split.dart` (resizable divider), `theme.dart` (10 light/dark themes),
  `wave_title.dart` (retro Shrikhand title), `title_bar.dart` (custom Windows title bar),
  `note_color_sheet.dart`, `trash_sheet.dart`, `calendar_widget_image.dart` (Android 4x2
  calendar widget, rendered as an image with home_widget).
- `supabase/migrations/` — schema, RLS, realtime, colour column, delete policy.
- `installer/oganesson.iss` — Inno Setup script for `Oganesson-Setup.exe`.
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
- Colours always through `Palette.*` (ThemeExtension `NotasColors`), never hard-coded.
- Password reset with an email code needs custom SMTP in Supabase (default templates
  only contain a link); not implemented.
- Before calling something done: `flutter analyze` and, if possible, run it.

## Open items / known gaps

- Not yet verified on a real phone: Android calendar widget (4x2), trash purge,
  7/3/1-day reminders, notification permissions on Android 13+.
- Windows: some GPUs showed black/unpainted areas after resizing; a forced full repaint
  runs after resize/maximise (`forceFullRepaint` in `lib/main.dart`). Needs confirmation
  on the owner's PC.
- Windows notifications: unknown whether scheduled toasts fire while the app is closed
  (unpackaged app).
- Password reset by email code: needs custom SMTP in Supabase (see above).
- Code comments are still in Spanish (UI text must stay Spanish).
- The repository is private: the README download links only work when signed in.
