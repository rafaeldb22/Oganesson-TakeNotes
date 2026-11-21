# Changelog

All notable changes to Oganesson TakeNotes (formerly *Notas* / *BabuNotes*).

## [1.4.2] — 2026-11-21

### Added
- Windows keyboard shortcuts: **Ctrl+F** search, **Ctrl+1 / Ctrl+2 / Ctrl+3** notes, calendar and
  network, **Ctrl+,** theme and colours (plus the existing Ctrl+N and Esc). The bottom-bar
  tooltips show them.

## [1.4.1] — 2026-11-21

### Fixed
- Light mode: remaining-time texts in light colours (yellow, mint…) were hard to read; they are
  now darkened for light backgrounds while keeping their hue (notes list, calendar panel and the
  Android widgets).

## [1.4.0] — 2026-11-21

### Added
- **Four new Android widgets** (six in total):
  - **Tareas** (2×2 / 4×2 / 4×4): today's tasks first, then upcoming ones, with their fuse. Tap
    to open the calendar.
  - **Próxima tarea** (2×1 / 2×2): the most urgent task with a big countdown and its fuse. Tap to
    open that note.
  - **Notas fijadas** (4×2 / 4×4): your pinned notes (or the most recent ones). Tap to open the
    app.
  - **Accesos rápidos** (4×1): New note, Calendar, Network and Search buttons in the theme colour.
  Only the widgets you have on the home screen are drawn, and they refresh when you reopen the
  app.
- **Four new themes**: Sepia (warm paper, easy to read), Nórdico (cool blue-grey), Neón (magenta
  and cyan on black) and Matcha (soft green tea).
- **New logo**: a continuous gold line with two loops on a navy gradient, without the outer
  border (Windows, Android adaptive icon and README).
- Automated tests are now part of the repository and run before every release build.

### Changed
- **Light mode is easier on the eyes**: no pure-white surfaces (background and cards are toned
  down for every theme) and secondary text and separators have more contrast.
- Time fuses and calendar task lines are deeper in light mode so they stand out.

## [1.3.4] — 2026-11-21

### Fixed
- Calendar task lines change colour smoothly again: each day is a gradient from the colour at
  its start to the colour at its end (using the task's real times), and the time that has
  already passed is drawn slightly darker (today splits at the current time).
- *Sign out* was unreachable: the ⋯ menu was taller than the window. The menu now fits the
  screen (scrolling inside if needed) and has a sign-out button next to the account at the top.

## [1.3.3] — 2026-11-21

### Fixed
- Swiping a note no longer shows a square block: the rounded background pill is drawn whole
  behind the row instead of using the (rectangular-clipped) swipe background.
- Drag & drop: no more boxes when dragging — drop zones only show the insertion line, like
  between notes, and the list no longer shifts when a drag starts. Drop on the top or bottom
  half of any note (also in other folders) to place it before or after it; drop at the very top
  of the list to pin, at the very bottom to leave it without folder.
- Calendar: day numbers were off-centre (the today circle went outside its cell); they are
  centred again.

### Changed
- Android calendar widget: the 4×2 size shows today's tasks on the left (then upcoming ones)
  and the month on the right; 4×4 shows today's tasks too.

## [1.3.2] — 2026-11-21

### Changed
- Rounded swipe backgrounds: archiving / deleting now shows a rounded pill sliding over a
  rounded tinted background (no square corners).
- Better drag & drop: drop a note on the top or bottom half of another note to place it before
  or after it (the insertion line shows where), including notes inside other folders or in
  *Sin carpeta*, so you no longer have to aim at the folder name. The list scrolls by itself
  when you drag near the top or bottom edge, and the dragged note follows the cursor.

### Fixed
- Windows: the time bar inside a note lagged behind when resizing the window; it now resizes
  in the same frame (and the window repaints every frame while resizing).

## [1.3.1] — 2026-11-21

### Fixed
- **Android in-app update** failed with *"Permission denied: MANAGE_EXTERNAL_STORAGE"*: the APK
  is now downloaded to the app's internal cache, which the installer can open without extra
  permissions. If installing still fails, the update dialog offers *Download in the browser*.
  (Phones on an older version must install this one manually once, from the Android download.)

### Changed
- New right-click menu for text (cut, copy, paste, select all) in the editor and every text
  field: icons, keyboard shortcuts, hover highlight and an animated entrance.
- Swipe backgrounds (delete / archive) use soft theme tints instead of bright red / accent.
- Cleaner hover: note rows highlight as a rounded inset pill with a smooth fade.
- Less space between the sort menu and *Fijadas*.
- Calendar: task bars are continuous across consecutive days.
- The colour sheet no longer shows the fuse preview.

## [1.3.0] — 2026-11-21

### Added
- **Archive**: swipe a note to the left to archive it (it asks first, like deleting, and can be
  undone). Archived notes are in the new *⋯ → Archivadas* section (unarchive or delete).
- **Drag & drop**: drag notes up or down (mouse drag on desktop, long press on Android) to move
  them into a folder, out of it (*Sin carpeta*), to *Fijadas*, or to another position. Folders
  light up and open when you hover a note over them. Reordering switches the list to the new
  *Personalizado* (custom) sort, which is synced.
- Supabase migration `006_archive_order.sql` (`notes.archived`, `notes.position`).

### Changed
- Swipe right deletes, swipe left archives.
- The **calendar** is now the default view in the right panel when no note is open.
- New **⋯ menu**: account header with the app version, sections (Notes, Appearance, Account),
  counters, subtitles and a staggered animated entrance.
- **Smooth mouse-wheel scrolling**: the notes list, the editor, the calendar and the date sheet
  glide instead of jumping.
- **Date picker**: new time wheel (hours and 5-minute steps) that turns smoothly with the mouse
  wheel; the remaining time and duration are now rounded correctly ("quedan 6 h 25 min",
  "dura 2 d", "vence ahora").
- The "Notas" title above the list was removed (only the sort menu remains).

## [1.2.1] — 2026-11-21

### Added
- **More note colours**: 21 instead of 9 (Red, Peach, Sand, Olive, Forest, Turquoise, Blue,
  Lavender, Purple, Fuchsia, Coffee and Slate added), each with its own time fuse. Existing
  colours keep their values.

## [1.2.0] — 2026-11-21

### Changed
- **Folders like Zen browser**: folders now live inside the notes list as collapsible groups
  (chevron, folder icon and colour, note count). Open one to see its notes indented under a
  guide line; hover for a quick *new note here* button, right-click for options. Open folders
  are remembered and searching opens the ones with matches. The folder chips row is gone.
- New **context menu** (right click on a note or folder): header with the name, grouped
  options with icons, soft hover highlight and a smooth scale/fade in and out from the cursor.
- **Pop-up notifications** (undo delete, updates, password changes…) now animate in and out.
- **Date picker**: days react on hover, months slide when changing, the range has rounded
  ends, and quick presets (Today, Tomorrow, In a week, In a month).
- **Network view**: hovering a note animates the highlight (the node grows with a halo, its
  links light up and the rest fades smoothly).
- The note / link / pending-task counter moved to the bottom-right corner of the window.

### Fixed
- Narrowing the left panel no longer overflows (the title scales down).
- Missing English translations ("Pinned", "All", "Calendar"…).

## [1.1.0] — 2026-11-21

### Added
- **Note network** (like Obsidian's graph view): right-click a note (long press on Android) →
  *Enlazar con otras notas…* to connect it with other notes, or *Crear subnota enlazada* to
  create a linked sub-note. The link button in the formatting bar opens the same picker. A new
  **Network** view in the bottom bar shows every note as a node and every link as a line: zoom,
  pan, drag nodes, hover to highlight a note and its neighbours, tap to open it. Each note lists
  its links and backlinks at the bottom.
- **In-app updates**: the app checks GitHub Releases on startup and offers the new version. On
  Windows it downloads the installer, updates silently and reopens; on Android it downloads the
  APK and opens the system installer. Also available from *⋯ → Buscar actualizaciones*.
- *⋯* menu: **Invítame a un café** (Buy Me a Coffee donations) and **Código en GitHub**.
- Android calendar widget in **three sizes**: 2×2 (month), 4×2 (month + tasks) and 4×4 (month +
  task list). It adapts when resized.
- **Vault** (only in *⋯ → Vault*): notes protected by a master password, in their own screen
  (new note, add existing notes, right-click → remove from the Vault). Vault notes never show
  in the normal lists, search, calendar, network or Android widgets (their reminders say
  *"Nota del Vault"*). It locks itself silently after 5 minutes without use. The password is
  stored only as a salted PBKDF2-SHA256 hash and synced through Supabase.
- **Change passwords** from *⋯* by typing the current one: the account password and the Vault
  password. (Vault reset by email code is built in but off until custom SMTP is configured:
  `--dart-define=EMAIL_CODES=true`.)
- **Completed** (*⋯ → Completadas*): tasks completed more than 3 days ago leave the notes list
  by themselves and are kept there for 30 days (restore or delete), then go to the trash.
- **English**: the app is now available in Spanish and English (*⋯ → Idioma*; defaults to the
  system language).
- Sort notes by **last modified**, **creation date** or **name** (remembered), from a new
  animated sort menu.

### Changed
- Swipe to delete now asks *"¿Eliminar «note title»?"* in the middle of the screen first.
- Task cards: cleaner hover effect (soft theme-coloured border, light shadow and tint instead of
  a flat grey overlay).
- Windows: redesigned title bar, now a separate strip tinted with the theme colour with a
  divider line, dimmed while the window is unfocused.
- Formatting bar: scrolls with the mouse wheel or by dragging, and fades at the edges when more
  buttons are hidden.

### Fixed
- Android calendar widget looked transparent: it now has a solid rounded background in the theme
  colour, and the task list only shows as many tasks as fit.
- Calendar: "bottom overflowed" stripes when the window (or phone screen) was small; day cells
  now have a safe minimum height and the month scrolls instead.
- Network and calendar buttons stayed highlighted after opening a note; tapping them with a note
  open now goes back to that view.
- Network view: dragged nodes could be drawn over the rest of the app; the header is now its
  own bar, the graph area is clipped below it, the *Sueltas* / *Centrar* buttons sit at the
  bottom left, and the graph is framed while it settles.
- Switching between *All*, *Network* and *Calendar* no longer replays the list animation when
  the list shows the same notes.

## [1.0.0] — 2026-11-21

### Changed
- Renamed the app to **Oganesson** (repository: *Oganesson TakeNotes*).
- New minimalist icon: a straight note with the element symbol **Og** and atomic number 118.
- Windows: the system title bar is replaced by a custom one (drag to move, double-click to maximise, own minimise / maximise / close buttons), like Chrome.
- New notes start with a big title line again; plain-text notes show their first line as a title.
- Removed the time-grouped "temporary" list: in calendar mode the left panel shows your regular notes.
- Documentation, workflows and scripts translated to English.

### Added
- Windows installer (**Oganesson-Setup.exe**, per-user, Start menu entry, uninstaller) alongside the portable zip.
- Direct download buttons in the README and release notes generated from this changelog.

## [0.7.0] — 2026-11-21

### Added
- **Trash**: deleted notes are kept for 3 days (restore, delete forever, empty trash) and then purged automatically.
- **Calendar widget** for Android (4×2): current month plus upcoming tasks sorted by deadline.
- 10 colour themes (Cereza, Medianoche, Café, Grafito and Aurora added), each with light and dark mode.

### Changed
- Top bar only shows *All* and your folders; **calendar** and **new folder** moved to the bottom bar next to *new note*.
- Reminders only fire when 7 days, 3 days and 1 day are left, titled *"Recordatorio: …"*.
- The undo bar after deleting closes by itself after 3 seconds.
- Back to the retro animated title; new cleaner icon.

## [0.6.0] — 2026-11-21

### Added
- Custom colour per note; it also tints the note's fuse bar and its calendar bars.

### Fixed
- Mobile editor: removed the overlapping back label and moved secondary actions into a "more" menu.
- Mobile calendar: everything in a single scroll so nothing overlaps.
- Windows: minimum width of 760 px so the layout never switches while resizing; lighter repaint after resizing.

## [0.5.0] — 2026-11-21

### Added
- **Fuse-style time bar**: gradient from mint to red with an animated spark at the tip.
- Resizable panels (list | editor and calendar | tasks) that remember their width.
- Date picker with a mini calendar (start → end range) and a 24 h time wheel.
- Custom editor toolbar: paragraph styles, bold / italic / underline / strikethrough, lists, checklists, quote, code and a curated colour palette.
- New app name and icon (*BabuNotes*).

### Changed
- Redesigned calendar: left-aligned month header, grid filling the available height, day panel with weekday and task count.
- Cleaner UI: chips without clipped shadows, better contrast on cards.

## [0.4.0] — 2026-11-21

### Added
- **Folders** synced across devices.
- **Rich text editor** based on flutter_quill.
- **Temporary notes** with a deadline and reminders (flutter_local_notifications, Android + Windows).
- **Calendar** covering the current month ± 3 months, with a bar for every task.
- Retro animated title.

### Changed
- Fewer rebuilds while resizing the window (cached panels, repaint boundaries).

## [0.3.0] — 2026-11-21

### Added
- 5 colour themes with light and dark mode and animated switching; the Android widget follows the theme.
- Undo after deleting a note, with a collapsing delete animation.
- Automated Windows window test that takes screenshots in CI.

### Fixed
- The "OK" button in the editor is vertically centred.

## [0.2.0] — 2026-11-21

### Added
- Animations: iOS-like note transitions, staggered list, bouncy buttons, hover effects.

### Fixed
- Windows: the open note is kept when the window crosses the narrow/wide breakpoint; minimum window size; window opens centred.

## [0.1.0] — 2026-11-21

### Added
- First version: Flutter app for Android and Windows.
- Real-time sync with Supabase, offline cache, sign up / sign in.
- iPhone-style notes list and editor (pinning, search, swipe to delete).
- Android 2×2 home-screen widget with the latest note and a *New note* button.
- GitHub Actions builds the APK and the Windows app and publishes a release.
