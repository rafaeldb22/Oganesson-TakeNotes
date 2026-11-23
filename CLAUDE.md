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
  and `preview` ignore it. `lib/ui/image_tools.dart`: `insertImageBlock` (always use it to insert
  an image: Quill only wraps *videos* in their own line), `moveImageTo/Up/Down`,
  `ImageMoveTarget` (drop target around the editor; uses `QuillEditorConfig.editorKey` to map the
  pointer to a document position) and `openImageCropper` (crop_your_image). List rows show
  `NoteThumb` for notes with images.
- Screen transitions (`lib/ui/anim.dart`) all share one widget structure (`_layered`) so the
  transition can change mid-way without rebuilding the outgoing screen. Deleting/archiving the
  open note sets `_discarding` in `notes_home.dart` (editor uses `discardTransition`).
  **Narrow layout: the list is always mounted** under the editor (Stack: list with a parallax
  `AnimatedSlide` + the editor in an `AnimatedSwitcher`); never swap the list out of the tree or
  the whole screen replays its entrance. Rows decide once (`_rowIntro`) whether they animate in:
  all of them during `_entranceOpen` (first 900 ms after the list is shown / the view changes),
  afterwards only ids that were not in the previous build (`_knownIds`). Regression tests:
  `test/discard_animation_test.dart` (checks that no `State` of the list is recreated).
- AI assistant (bring your own key): `lib/data/ai_assistant.dart` — `AiProvider` (gemini /
  openai / claude: key URL, models, fallbacks), `AiSettings` (one key per provider in
  flutter_secure_storage, never in Supabase; models in SharedPreferences), `AiClient` with
  `GeminiClient` / `OpenAiClient` (Chat Completions) / `ClaudeClient` (Messages API, raw HTTP —
  Dart has no official SDK; `anthropic-version: 2026-10-21`, default `claude-opus-5-5`,
  `fallbacks: "default"` + beta header on Opus/Sonnet 5.5, assistant content replayed unchanged,
  all tool_results in one user message). Injectable `AiTransport(method, url, headers, body)` for
  tests; friendly per-provider errors (quota, no balance, 402 prepay, invalid key), `AiTools` (function declarations + execution on `NotesRepository`; Vault notes
  are invisible: `repo.notes` excludes them and `_note()` rejects them; destructive actions go
  through `confirm`; every change records an `AiAction` with undo via `repo.restoreState`) and
  `AiSession` (keeps the raw model `content` so Gemini's thought signatures are sent back).
  UI: `lib/ui/assistant_panel.dart` (`openAssistant`: right panel on wide, bottom sheet on phone).
  Free-tier limits are per Google project and only shown in AI Studio (reset at midnight PT).
  Imported `.ics` events are read-only for the AI: `list_calendar` and `read_note` only (`_note()`
  rejects them). Read-only tools run in parallel; each change asks through `confirm`, one by one.
  The system prompt must stay **static** (prompt caching): per-turn data (date, time, folders) goes
  in a `<contexto>` block appended to each user message (`AiSession._context`). Claude requests send
  top-level `cache_control` and `output_config.effort: low`. Retryable errors (`AiException.retryable`)
  are retried in `AiSession._complete`; the chat is persisted per user (`asistente_chat_<userId>`),
  trimming history only at plain user messages (`AiClient.isUserText`).
- Windows background mode: `lib/data/desktop_integration.dart` — single instance
  (windows_single_instance, `--new-note` / show on second launch), tray icon (tray_manager **0.5.x**,
  icon `assets/icon/tray.ico` generated by `tool/generate_icon_test.dart`), global **Ctrl+Alt+N**
  (hotkey_manager **0.2.x**). Do NOT upgrade tray_manager to 0.9 / hotkey_manager to 0.4: they
  pull `nativeapi`/`cnativeapi`, whose C++ build hook breaks `flutter test` on the Linux CI feeding `newNoteRequests`, close = hide (`setPreventClose`, first
  close asks), start with Windows via `reg add HKCU\…\Run` with `--background` (launch_at_startup
  conflicts with win32 6 used by package_info_plus). `main.dart` doesn't show the window and the
  splash is skipped when started with `--background`.
- Daily-use tools (2.2): `lib/ui/command_palette.dart` (Ctrl+K; inside Quill it needs
  `customShortcuts`, because Quill binds Ctrl+K to links), `lib/ui/quick_capture.dart` +
  `DesktopIntegration.beginCapture/endCapture`, `lib/data/note_factory.dart` (`createNoteFrom`),
  Android share via receive_sharing_intent (`_onShared`), multi-select `_picked` in
  `notes_home.dart`. AI streaming: each client rebuilds SSE events into the normal response shape
  (`_GeminiStream`, `_OpenAiStream`, `_ClaudeStream`); tests inject `AiStreamTransport`.
- Notes tools (2.3): `lib/data/recurrence.dart`, `note_history.dart` (local, per account, never
  Vault), `note_filters.dart`, `note_export.dart` (Markdown, PDF, `Backup`), UI in
  `lib/ui/note_tools.dart`. Migration 008 is optional at runtime (`serverHasTasks`). The note list
  is memoized: anything that changes it must be part of its hash in `notes_home.dart`.
- Media (2.4): `lib/data/note_files.dart` (bucket `note-files`, migration 009, Quill custom embed
  `oga-file`, sources `ogf://`), `lib/ui/note_media.dart` (cards, recorder, AI reading),
  `lib/ui/drawing_pad.dart`. `NoteMediaScope.allowAi` is false in Vault notes: anything that sends
  note content to an AI provider must check it.
- AI actions (2.5): `lib/data/ai_actions.dart` (one-shot calls without tools, `parseTasks`,
  `dailyBriefData`), UI in `lib/ui/ai_tools_ui.dart`. `repo.completed` can contain Vault notes while
  it is unlocked: filter `!n.vault` before giving anything to an AI.
- Subtasks were removed in 2.6: `Note.subtasks` only exists to read 2.3 data, and the repository
  converts it to Quill checkboxes (`_absorbSubtasks`). Editor tools live in `EditorToolbar`.
- Shared notes (2.7): migration 010 (`note_shares`, RPCs, RLS, a trigger that lets non-owners change
  only text), `lib/data/note_sharing.dart`, `lib/ui/share_sheet.dart`. `repo.isForeign(n)` = another
  account's note: never upsert it (`_pushForeign`), never send it to an AI.
- Calendar files: `lib/data/note_ics.dart` (`notesToIcs`, `parseIcs`, `icsNoteId`). Import keeps only
  current and future events, and ids are per account so re-importing never duplicates. Imported
  events have UUID v5 ids (`Note.isCalendarEvent`): `repo.notes` excludes them, `repo.calendarItems`
  includes them. All-day is stored as 00:00 to 23:59 local (`Note.isAllDay`).
- Image display size is `z=<percent>` in the `sb://` source (`NoteImages.scaleOf/withScale`). The AI
  sees images through the `read_note_images` tool, which reads each one with `aiReadMedia`.
- Smooth wheel scrolling: use `SmoothScrollController` (`lib/ui/smooth_scroll.dart`) for new
  scroll views on desktop.
- Completed tasks: `Note.doneAt` (column `notes.done_at`); done ≥ 10 minutes → hidden from lists and
  shown in ⋯ → Completadas (`lib/ui/completed_sheet.dart`); > 30 days → trash.
- Whiteboard (2.12): `lib/data/note_board.dart` (model, lasso, eraser) and `lib/ui/whiteboard.dart`.
  It is a Quill custom embed `oga-board` inside `Note.rich`, so sync, sharing and image cleanup work
  unchanged. While it is open, `_ctrl` is stale: save through `BoardData.store`, never `_onEdit`.
- Attachments as data: `lib/data/note_attachments.dart` (`mediaIn`, `withEmbeds`, `withText`). Append
  through these helpers: inserting before the last newline moves that line's header to the new text.
  Connected files (2.13) live in `Note.links` as `att:<embed JSON>` tokens next to note ids, never in
  the text; migration 013 makes sharing cover them. Older network files are embeds marked `net`.
  The AI reaches files by code (`mediaCode`, tools `find_files` / `attach_files`), with the latest
  25 listed in `<contexto>`. PDFs open in `lib/ui/pdf_viewer.dart` (pdfrx).
- Accounts (2.12): migration 012, `lib/data/accounts.dart`, `lib/ui/friends_sheet.dart`. Friends are
  one-way. `note_shares.email` now holds `u:<account id>`, and the `email` / `owner_email` columns
  of `note_people` / `my_shared_notes` carry the @username. `login_email` returns the address only
  for the right password and locks after 8 failures in 15 minutes.
- Quill passes custom embeds a detached node whose `documentOffset` is always 0: find them with
  `fileEmbedOffset`, and remove embeds with `removeEmbedLine`.
- Whiteboard to text only sends strokes with `read == false` and stores the result in
  `BoardData.readText`.
- The AI reads attachments through `readMediaItem` (`lib/data/note_file_reader.dart`): local text
  for PDF, Office and text files, the provider for audio, images and scanned PDFs. Results are cached
  in memory by path. Tool: `read_note_files`; panel action: `NoteAiAction.analyze`.
- Android keyboard: use `autoKeyboard` (`lib/ui/anim.dart`) instead of `autofocus: true` on text
  fields.
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
- Migrations 007 to 010 were applied to production on 2026-11-23, with custom SMTP (Brevo). Shared
  file access goes through `note_shared_files`, never a path alone.
- Migration 011 ties shares to an existing account id, so sign-up needs no confirmation email. Run
  it **before** turning off *Confirm email*. Password recovery needs `{{ .Token }}` in the Supabase
  *Reset Password* email template.
- Migrations 012 (@usernames, friends) and 013 (connected files in shared notes) must be run by hand
  in the SQL Editor, in that order. Until then the app keeps working with email sign-in and email
  sharing, and collaborators can't open connected files.
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
