# Changelog

All notable changes to Oganesson TakeNotes (formerly *Notas* / *BabuNotes*).

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
