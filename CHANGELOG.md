# Changelog

All notable changes to Oganesson TakeNotes (formerly *Notas* / *BabuNotes*).

## [2.16.0] — 2026-11-23

### Changed
- **Calendar lines**: long tasks have a solid first and last day, longer dashes in between, and
  lines now stack from the bottom of each day.
- The pen and highlighter icons no longer have a border.

### Fixed
- Marking a task as done, or any other edit, is no longer lost when another device's clock is ahead.

## [2.15.0] — 2026-11-23

### Added
- **The AI can analyze the files in a note**: PDFs (including scanned ones), Word, Excel,
  PowerPoint, text files, audio and images, whether they are inside the note or connected to it.
- **Analyze files** in the note's AI panel, and the assistant can open files when you ask about them.

### Changed
- *Summarize* and *Turn into tasks* now also use the note's files.

### Fixed
- Notes that only contain files can now use the AI panel.
- *Replace* is no longer offered on whiteboard notes, where it would have removed the whiteboard.

## [2.14.0] — 2026-11-23

### Added
- **Whiteboard to text** now explains what you wrote and only reads what is new.
- The links of a note also appear below its whiteboard.

### Changed
- **New sign-in screen** with a moving background, animated logo and smoother forms.
- **New AI panel** inside notes, with animated action cards.
- Multi-day calendar lines are now dashed.
- The pen and highlighter icons have a contrasting border.

### Fixed
- **Removing a PDF, audio or file no longer deletes the first letter of the note**, and now removes
  the attachment.
- Voice messages can be played again after they finish.
- The mouse wheel scrolls the whiteboard toolbar with every tool.
- Completing a repeating task or someone else's task now tells you what happened.

## [2.13.0] — 2026-11-23

### Added
- **PDF reader** inside the app, with page navigation and zoom.
- **Connected files**: attach images, voice messages and files to a note without putting them in
  its text. They appear at the bottom with its links and as circles in the network. Available from
  the link button in the editor, right-clicking a note and the network.
- **File index for the AI**: every file has a short code, so the assistant can find it and put it
  in any note.
- **The AI reads whiteboards**: handwriting and drawings, plus a button to turn them into text.
- **Whiteboard**: highlighter, quick colors and sizes, insert image and fit to screen. The selector
  can now resize, stretch and rotate.
- Right-click a calendar day to create a note on it.

### Changed
- **Calendar**: solid lines with no gradients, up to 7 per day, and each line keeps its row.
- Multi-day tasks are split into one segment per day, and single-day tasks are a plain line.
- Smoother pen strokes.
- Shorter labels in the note network.
- Creating a note from the calendar no longer opens the date menu.

### Fixed
- Left-clicking anything in the note network opens it directly.

## [2.12.0] — 2026-11-23

### Added
- **Whiteboard mode**: turn any note into a dotted whiteboard from the top bar. Draw with a mouse,
  touch screen or graphics tablet, with pen colors, size and pressure, an eraser with size and
  pressure, and a lasso that closes on release and selects everything inside. Right-click or
  long-press for paste, copy, cut, duplicate, insert image and more.
- **@usernames and friends**: every account has an @username, you can add friends and share with
  them in one tap, and sign in with your @username and password.
- **Files in the note network**: right-click a note to connect images, voice messages or files.
  They appear as larger bordered circles and open with a click.
- **The AI can reuse attachments**: it can copy images, voice notes and files from one note to
  another.

### Changed
- Completed tasks move to *Completed* after 10 minutes.
- On Android, the keyboard only opens when you tap somewhere to type.
- Shared notes show @usernames instead of email addresses.

### Fixed
- The AI now formats the first line of a note as its title, not the last one.
- Calendar tasks no longer hide behind **+N** when their day has free space.

## [2.11.0] — 2026-11-23

### Added
- **Resize images**: make any image in a note smaller, from 20 % to 100 %, with a live preview. The
  original image is kept and the size syncs across devices.
- **The AI can see images**: the assistant reads the images in your notes, and *Summarize* and
  *Turn into tasks* use them too. Vault notes and notes shared with you are never sent.

### Changed
- **Single-day notes** have one solid color, a smaller line, and take priority in the calendar.
- Thinner calendar lines.
- New animations for calendar lines, calendar import results, all-day dates, image resizing and the
  Settings button.

## [2.10.0] — 2026-11-23

### Added
- **Settings button** next to ⋯, with appearance, data, account and app options.
- **Delete all notes** in Settings. Notes go to the trash, and you can undo it. The Vault and notes
  shared with you are not affected.

### Changed
- **Imported calendar events** now appear only in the calendar, not in the note list or the network.
- **New dates are all-day by default**. Turn off *All day* to set an exact time. All-day reminders
  arrive at 9:00.

### Fixed
- Password recovery now shows why an email could not be sent.

## [2.9.0] — 2026-11-23

### Added
- **Calendar files**: import an `.ics` file from ⋯ → *Import calendar*, or export your pending dated
  notes from *Export notes*. Only current and future events are imported, and importing the same
  file again creates no duplicates.
- **Password recovery**: *Forgot your password?* on the sign-in screen sends a code by email.

### Changed
- **Sharing**: notes are shared with an existing account, and access follows that account.
- Creating an account no longer needs a confirmation email.

### Setup
- Run `supabase/migrations/011_share_by_account.sql` **before** turning off *Confirm email*, and add
  `{{ .Token }}` to the *Reset Password* email template.

## [2.8.0] — 2026-11-23

### Added
- **Single-day notes**: turn on *Only that day* in Dates to pick just a day and time. The bar stays
  hidden until 00:00 that day, the calendar shows only that day, and there is one reminder an hour
  before instead of the 7, 3 and 1-day ones.

### Changed
- **Timeline colors**: a new timeline gets the least used color. Colors you pick are always kept.

### Security
- **Shared files**: a file path written in a note no longer gives access to that file. Only the
  account that owns a file can share it, and removing it from the note removes the access.

### Setup
- Run the updated `supabase/migrations/010_note_sharing.sql` and keep *Confirm email* enabled.

## [2.7.0] — 2026-11-23

### Added
- **Shared notes**: share a note with another account from the editor toolbar, as *can edit* or
  *view only*. Changes arrive live, and you can remove people or leave a note at any time. Only
  the text is shared: folder, pin, dates and trash stay with the owner. If two people write at
  the same moment, the most recent save wins.

### Changed
- The note color now only affects timelines. Notes no longer show a color strip.
- Removed the "2 notes" and "1 link" counters, and "No additional text" under empty notes.
- The ⋯ menu scrolls slower and smoother, with softer opening, hover and press animations.

### Fixed
- **Updates**: reaching GitHub's API limit no longer shows a false connection error.
- Removed the stray `[[` from the "Link note" tooltip.

### Setup
- Run `supabase/migrations/010_note_sharing.sql` to enable shared notes, and keep *Confirm email*
  enabled in Supabase. Shared notes are never sent to the AI assistant.

## [2.6.0] — 2026-11-23

### Changed
- **New editor toolbar**: voice notes, attachments, drawing and AI actions now live next to the
  formatting tools. Smoother hover, press and active animations, an animated color palette, smooth
  wheel scrolling and a highlighted AI button.

### Removed
- **Subtasks**. Existing subtasks are converted into checkboxes inside their note, so nothing is
  lost. AI "turn into tasks", templates and tasks from a photo now create checkboxes too.

## [2.5.0] — 2026-11-22

### Added
- **Ask all your notes**: the assistant searches and reads your notes, answers from them and links
  the notes it used under the answer.
- **AI actions on a note**: summarize, fix writing, translate or turn into checkboxes. You review
  the result first, and replacing a note can be undone.
- **Daily summary** of overdue, today's and upcoming tasks, on demand.
- **Tasks from a photo**: pick an image, review what the AI found and create a note with checkboxes.

### Fixed
- **Privacy**: while the Vault was open, the assistant's task list could include completed Vault
  tasks. Vault notes are now excluded there too.

## [2.4.0] — 2026-11-22

### Added
- **Voice notes** recorded inside a note, with playback.
- **Transcription** of voice notes with your own Gemini or ChatGPT key.
- **PDF and file attachments** up to 25 MB.
- **Drawing**: a canvas with colors, thickness, eraser, undo and redo, also on top of an image.
- **OCR**: extract the text of a photo or screenshot with your own AI key, review it and add it
  to the note.

### Privacy
- Transcription and OCR only run when you ask for them, and are not offered in Vault notes.

### Setup
- Run `supabase/migrations/009_note_files.sql` so attachments sync between devices. Without it
  they keep working on the device where they were added.

## [2.3.0] — 2026-11-22

### Added
- **Repeating tasks**: daily, weekdays, weekly, monthly or yearly. Completing one moves it to its
  next date and resets its steps.
- **Subtasks** with a progress bar.
- **Templates**: meeting, shopping, journal, project and trip, plus your own.
- **Search filters**: date, folder, color, images and tasks.
- **Version history** per note, stored on the device. Vault notes are never included.
- **Export and import**: Markdown and PDF, plus a full backup that can be imported again without
  overwriting newer notes. Backups never contain the Vault.

### Setup
- Run `supabase/migrations/008_tasks.sql` so repeats and subtasks sync between devices. Without
  it they keep working, but stay on the device where they were created.

## [2.2.0] — 2026-11-22

### Added
- **Command palette (Ctrl+K)**: search notes and run any action from the keyboard, also while
  writing in a note. Ignores accents and puts title matches first.
- **Quick note (Ctrl+Alt+N)**: a small floating window to jot something down; when you finish,
  the app goes back to how it was (hidden stays hidden).
- **Share to Oganesson on Android**: text, links and images from any app become a new note.
- **Live AI answers**: text appears as it is written with Gemini, ChatGPT and Claude.
- **Multi-select**: Ctrl+click, or *Select* in a note's menu, then pin, move, archive or delete
  several notes at once, with Undo.

### Fixed
- AI assistant: pressing *Stop* while it was running a tool left the conversation in a state
  that could make the next question fail. *Stop* now also prevents any further changes, and what
  was already changed keeps its Undo.

## [2.1.1] — 2026-11-22

### Changed
- The highlight of the selected note is softer, especially in light themes (a gentle tint
  instead of a block of colour).

## [2.1.0] — 2026-11-22

### Added
- AI assistant: **Stop** button while it answers, **Retry** on errors, **copy** an answer, and the
  conversation is **kept when you close the app** (old changes keep *Open*, not *Undo*).
- New AI tools: **set a note's colour** and **link notes** (they show up in the note network);
  note search now returns a snippet around the match.
- Answers render numbered lists, `code` and headings.

### Changed
- **Prompt caching**: the assistant's instructions no longer contain the date and time (which
  changed on every request and made every question be processed from scratch); the date, time
  and folders now travel with each question. Claude requests also use automatic caching and low
  effort (the recommended setting for chat): faster and cheaper answers.
- Tool descriptions now say *when* to use each tool, which helps every model pick the right one,
  and the instructions were tightened (ask when ambiguous, natural dates, never show ids).
- Temporary errors (rate limit per minute, overloaded service) are retried automatically.
- **Classic light theme**: almost white again (no bluish tint), just slightly dimmed so it does
  not glare.

## [2.0.1] — 2026-11-22

### Changed
- **Classic light theme**: neutral grey-white with no bluish tint, still as dark as in 2.0.
- **Coffee light theme**: back to how it looked before 2.0.
- **Other light themes**: less saturated (softer colours), same darkness as 2.0.
- **Classic dark theme**: the Windows title bar is near-black instead of yellow-tinted.

## [2.0.0] — 2026-11-22

### Added
- **AI assistant: ChatGPT and Claude too.** Besides the free Gemini key, each user can paste an
  OpenAI (ChatGPT) or Anthropic (Claude) API key; one key per provider, stored encrypted on the
  device. Same tools and safety for all three (Vault notes never visible, confirmation to archive
  or delete, Undo on every change). Claude uses Claude Opus 5.5 by default (Sonnet 5.5 and
  Haiku 5.5 to choose), with the server-side fallback on refusals; clear messages for no balance,
  invalid key, rate limits or overload on each provider.
- **Windows: background app with a global shortcut.** Oganesson starts with Windows hidden in the
  system tray (with Open / New note / Quit), closing the window keeps it running (the first time
  it asks), and **Ctrl+Alt+N** anywhere in Windows shows it and opens a new note. Only one copy
  runs: opening it again brings back the running one. *Open when Windows starts* and *Quit
  Oganesson* are in ⋯.

### Changed
- Bottom bar: the AI assistant sits on its own at the far left; *New folder* moved next to
  *New note*.
- Light themes are darker and less glaring.
- README media re-recorded with the new bar and themes.

## [1.8.1] — 2026-11-22

### Fixed
- **AI assistant: misleading "daily limit reached" message right after adding a key.** Google
  answers with the same 429 error when a model has no free quota for the key's project
  ("limit: 0"), when the per-minute limit is hit, or when the daily one is. The app now tells
  them apart, says how many seconds to wait when Google says so, and shows Google's exact reason.
- A key from a Google project with **prepaid billing and no credits left** (HTTP 402) is now
  explained as such (with billing on, the free plan does not apply) instead of looking like a
  rate limit, and the app no longer tries every model in vain.
- *Test and save* now makes a real minimal request (looking up the model did not check quota)
  and, if the chosen model has no free quota, tries the other Gemini models and keeps the first
  one that works.

## [1.8.0] — 2026-11-22

### Added
- **AI assistant with your own Gemini key** (✨ button in the bottom bar, ⋯ → *AI assistant*,
  **Ctrl+J**). Each user pastes their own free Gemini API key from Google AI Studio; it is stored
  encrypted on the device only (flutter_secure_storage) and never uploaded.
  - It uses Gemini function calling to work with your notes: list and read notes and tasks, list
    folders, create notes (title, text, folder, deadline), append text, set or clear dates, mark
    tasks done, pin and move notes. Archive and delete ask for confirmation.
  - **Vault notes are never visible to it** (not listed, not readable, not editable).
  - Every change it makes shows up as a card with *Open* and *Undo*.
  - Guided setup with key test, model choice (Gemini Flash-Lite / Gemini Flash / custom), a
    privacy note, and clear messages for an invalid key, no connection or the free-plan limit.

## [1.7.4] — 2026-11-22

### Changed
- **Note network entrance: the bounce is back, but gentle**. Notes start gathered towards the
  centre of their final places and spread out with a soft spring (about half a second), with
  lower force and top speed than before 1.7.3. The camera is framed on the final layout from the
  start, so there is no jerky zoom.

### Fixed
- **New notes start with the title style again**: any update from the notes repository (for
  example a sync status change) before typing the first letter was treated as a remote change and
  replaced the empty note, dropping the big title format of the first line.

## [1.7.3] — 2026-11-22

### Changed
- **Smooth note network entrance**: the layout is computed before the network is shown, so it no
  longer "explodes" and reshuffles when you open it. Notes now appear in place from the centre
  outwards (growing and fading in), followed by their links and names, and the camera eases
  into position instead of jumping.

## [1.7.2] — 2026-11-22

### Changed
- **Bigger Android app icon**: the logo stroke is now as large as the launcher mask allows (it
  is fitted to the visible circle, so no tip is cut on round or squircle icons) and noticeably
  bolder.
- **Folder hover**: a soft tint of the folder's own colour instead of the heavy grey, fading in
  (220 ms) and out (420 ms) smoothly; the "+" button slides and fades in.

## [1.7.1] — 2026-11-22

### Added
- Image viewer shortcuts on Windows: **Ctrl+C** copies the image and **Ctrl+S** saves it (shown in
  the button tooltips).

### Fixed
- The blinking text cursor is no longer drawn right next to an image (it took the image's height
  and looked huge); it only shows next to text.

### Changed
- Supabase is initialised with the new `publishableKey` parameter (`anonKey` is deprecated);
  `supabase_flutter` ≥ 2.18.
- Code clean-up: no more analyzer warnings besides the SDK-wide `material.dart` notice.

## [1.7.0] — 2026-11-22

### Added
- **Crop images**: full-screen crop editor (free, 1:1, 4:3, 16:9, 3:4), rotate 90°, undo/redo.
  From the image's hover toolbar, its menu (right click / long press) or the full-screen viewer.
- **Move images around the text**: drag an image by its handle (Windows) or long-press and drag
  it (Android); an accent line shows where it will land. *Move up* / *Move down* in its menu.
- **Thumbnails in the list**: notes with images show the first one next to their title.
- New GitHub page: banner with the real app on a PC window and a phone, new animations
  (images, notes) and a "How it works" table.

### Changed
- The full-screen image viewer always shows its buttons (close, crop, copy, save, remove).

### Fixed
- **Notes list animation, for real this time**: on the phone the list was rebuilt every time a
  note was closed, created or deleted, so the whole screen (title, search, folders, rows) played
  its entrance again. The list now stays mounted under the note, and only the note that comes
  in (new, restored with Undo) or goes out animates.
- A pasted image in the middle of a sentence was mixed into that line of text: images now always
  get their own line.
- Crop editor: changing the aspect ratio while the image was still loading crashed.

## [1.6.0] — 2026-11-22

### Added
- **Images in notes.** Paste a screenshot or a copied image with **Ctrl+V**, drop image files
  onto the note (Windows), or use the new image button in the format bar (Android: gallery or
  camera; Windows: pick several files). Images appear instantly with a soft fade, show
  *Uploading…* / *Waiting to upload* while syncing, and on hover offer view, copy, save and
  remove. Tap one to open it full screen: it flies out of the note, zooms with pinch, wheel or
  double tap, and closes by dragging it down or with Esc. Right click / long press for the same
  actions.
  - Photos are compressed in the background (longest side ≤ 2048 px, JPEG); small screenshots
    stay PNG so text stays sharp. GIFs are kept as they are.
  - Stored in a private Supabase Storage bucket, one folder per user (migration
    `007_note_images.sql`), and cached on the device. Without connection (or before the
    migration runs) images stay on the device and upload later.
  - Images of notes deleted for good are removed from the cloud too.
- **Vault password with your account password.** When changing the Vault password you can type
  your account password instead of the current Vault one, and *Forgot your password?* on the
  locked Vault now resets it with the account password (no email code needed).

### Changed
- Deleting or archiving the open note no longer replays the "back to the list" animation: the
  note leaves with its own discard animation (shrinks and fades) and the list, which was already
  there, stays still. The list's entrance animation only plays when the view is first shown.
- Notes that only contain an image are titled *Image*; images don't count for titles or
  previews.
- Android builds now use JDK 21 (CI included).

## [1.5.2] — 2026-11-21

### Added
- **New GitHub page**: banner with the gold logo, buttons in the logo colours, fresh screenshots
  and animated previews (phone tour, startup animation, themes). They are recorded from the real
  app with `flutter test tool/record_gifs_test.dart`.

### Changed
- Note network labels and the note editor use the theme font explicitly (same look as the rest
  of the app).

## [1.5.1] — 2026-11-21

### Added
- **Mobile: Notes button** in the bottom bar, next to Network and Calendar, to go back to the note
  list (on the phone the three views share the screen).

### Changed
- Bigger, centred logo in the startup animation and in the app icon.
- Windows: the startup animation is now seen from the start. The window appears only once it has
  something painted (no white flash) and the animation waits until it is visible; it also covers
  the title bar.

### Fixed
- Mobile: bottom sheets (themes, schedule, trash, archived, completed…) stop below the status bar
  and at most at 90 % of the screen, so they can always be dragged down.
- Untranslated sync tooltips ("Sincronizando…", "Subiendo cambios…").
- `scripts/prepare_windows.ps1` no longer deletes the `test/` folder.

## [1.5.0] — 2026-11-21

### Added
- **Startup animation**: when the app opens, the gold logo line draws itself on the navy
  background like a pen (with a spark at the tip), the name appears and everything fades into
  the app (under 2 seconds; on Windows the title bar stays usable).

### Changed
- The logo's stroke and colours live in `lib/ui/logo.dart`, shared by the startup animation and
  the icon generator.

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
