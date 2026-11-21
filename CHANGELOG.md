# Changelog

All notable changes to Oganesson TakeNotes (formerly *Notas* / *BabuNotes*).

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
