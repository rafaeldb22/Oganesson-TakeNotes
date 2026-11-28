import 'dart:async';
import 'dart:io' show File, Platform;
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config.dart';
import '../data/ai_assistant.dart';
import '../data/desktop_integration.dart';
import '../data/note_factory.dart';
import '../data/note_filters.dart';
import '../data/note_images.dart';
import '../data/notes_repository.dart';
import '../data/reminders.dart';
import '../data/vault.dart';
import '../data/widget_bridge.dart';
import '../models/note.dart';
import 'anim.dart';
import '../data/updater.dart';
import 'account_dialogs.dart';
import 'ai_tools_ui.dart';
import 'archived_sheet.dart';
import 'assistant_panel.dart';
import 'calendar_view.dart';
import 'command_palette.dart';
import 'completed_sheet.dart';
import 'friends_sheet.dart';
import 'context_menu.dart';
import 'folders.dart';
import '../data/smart_groups.dart';
import 'focus_tools.dart';
import 'folder_group.dart';
import 'drop_zone.dart';
import 'format.dart';
import 'graph_view.dart';
import 'i18n.dart';
import 'language_picker.dart';
import 'link_picker.dart';
import 'note_color_sheet.dart';
import 'note_editor.dart';
import 'note_image.dart' show NoteThumb;
import 'note_tools.dart';
import 'quick_capture.dart';
import 'schedule_sheet.dart';
import 'share_sheet.dart';
import 'sort_menu.dart';
import 'split.dart';
import 'new_note_icon.dart';
import 'reminder_settings.dart';
import 'shortcuts_sheet.dart';
import 'toast.dart';
import 'smooth_scroll.dart';
import 'text_menu.dart';
import 'theme.dart';
import 'title_bar.dart' show isDesktopWindows;
import 'theme_picker.dart';
import 'trash_sheet.dart';
import 'update_dialog.dart';
import 'vault_dialogs.dart';
import 'vault_screen.dart';
import 'urgency.dart';
import 'wave_title.dart';

/// Pantalla principal. Un único estado ("qué nota está abierta") que se
/// pinta de dos formas según el ancho disponible:
///  - ancho ≥ 760: lista + nota lado a lado (PC)
///  - estrecho: lista o nota a pantalla completa (móvil / ventana pequeña)
/// Al redimensionar la ventana se pasa de una a otra sin perder la nota abierta.
class NotesHome extends StatefulWidget {
  const NotesHome({super.key, required this.repo});
  final NotesRepository repo;

  @override
  State<NotesHome> createState() => _NotesHomeState();
}

class _NotesHomeState extends State<NotesHome> {
  final _search = TextEditingController();
  final _searchFocus = FocusNode();
  String _query = '';
  NoteFilters _filters = const NoteFilters();
  String? _openId;
  final Set<String> _removing = {}; // filas que se están plegando
  bool _openAutofocus = false;

  /// La nota abierta se acaba de eliminar: el editor sale con la animación
  /// de descarte y lo que hay debajo (lista o calendario) se queda quieto.
  bool _discarding = false;

  /// Hasta cuándo las filas entran con su animación escalonada. Solo al
  /// mostrar la lista (inicio o cambio de vista): al borrar, archivar o
  /// volver de una nota la lista ya estaba ahí y no se vuelve a animar.
  bool? _entering; // null: la lista aún no se ha mostrado
  Timer? _entranceTimer;
  bool get _entranceOpen {
    if (_entering == null) {
      _entering = true;
      _entranceTimer?.cancel();
      _entranceTimer =
          Timer(const Duration(milliseconds: 900), () => _entering = false);
    }
    return _entering!;
  }

  /// Qué filas hacen su animación de entrada (se decide una vez por nota):
  /// todas al mostrar la lista y, después, solo las que aparecen nuevas
  /// (una nota recién creada, una que vuelve con Deshacer…). Las que ya
  /// estaban no se vuelven a animar nunca.
  final Map<String, bool> _rowIntro = {};

  /// Notas que había en la lista en la última construcción.
  final Set<String> _knownIds = {};
  Set<String> _prevKnownIds = {};

  /// El título hace su fundido solo al abrir la app.
  bool _titleIntro = true;
  Timer? _titleTimer;

  StreamSubscription<Uri?>? _widgetSub;
  StreamSubscription<void>? _newNoteSub;
  StreamSubscription<void>? _captureSub;
  StreamSubscription<List<SharedMediaFile>>? _shareSub;

  /// 'todas' | 'calendario' | id de carpeta
  String _filter = 'todas';

  /// Orden de la lista: 'modificada' (por defecto), 'creada' o 'nombre'.
  String _sort = 'modificada';
  static const _kSort = 'orden_notas';

  // Cachés para que al redimensionar la ventana no se reconstruya todo.
  Widget? _listCache;
  Object? _listKey;
  Widget? _editorCache;
  Object? _editorKey;

  /// Desplazamiento suave de la lista con la rueda del ratón.
  final _listScroll = SmoothScrollController();

  /// Carpetas desplegadas en la lista (como las carpetas de Zen).
  final Set<String> _openFolders = {};
  static const _kOpenFolders = 'carpetas_abiertas';

  void _toggleFolder(String id) {
    setState(() => _openFolders.contains(id)
        ? _openFolders.remove(id)
        : _openFolders.add(id));
    SharedPreferences.getInstance()
        .then((p) => p.setStringList(_kOpenFolders, _openFolders.toList()))
        .catchError((_) => false);
  }

  NotesRepository get repo => widget.repo;

  // En PC la ventana mínima es de 760 px, así que siempre se usa la vista de
  // dos paneles y no hay saltos de diseño al redimensionar.
  static const _wideBreakpoint = 700.0;

  @override
  void initState() {
    super.initState();
    GestureBinding.instance.pointerRouter.addGlobalRoute(_sideButtons);
    HardwareKeyboard.instance.addHandler(_onKey);
    SmartGroups.instance.addListener(_onGroups);
    _widgetSub = WidgetBridge.clicks.listen(_onWidgetUri);
    // Al pulsar un aviso: abrir la nota o marcarla como hecha.
    Reminders.instance.attach(
      onOpen: (id) => _whenLoaded(() {
        if (mounted && repo.byId(id)?.deleted == false) _open(id);
      }),
      onDone: (id) => _whenLoaded(() {
        final n = repo.byId(id);
        if (mounted && n != null && !n.deleted && !n.done) {
          repo.toggleDone(id);
        }
      }),
    );
    // Windows: Ctrl+Alt+N (desde cualquier sitio) o la bandeja.
    _newNoteSub = DesktopIntegration.instance.newNoteRequests.listen((_) {
      if (mounted) _newNote();
    });
    DesktopIntegration.instance.askOnFirstClose = _askOnFirstClose;
    _captureSub =
        DesktopIntegration.instance.captureRequests.listen((_) => _capture());
    // Android: lo que se comparte desde otras apps se convierte en una nota.
    if (!kIsWeb && Platform.isAndroid) {
      final share = ReceiveSharingIntent.instance;
      _shareSub = share.getMediaStream().listen(_onShared, onError: (_) {});
      share.getInitialMedia().then(_onShared).catchError((_) {});
    }
    vault.addListener(_onVault);
    repo.onLocalEdit = vault.touch;
    WidgetBridge.initialUri().then(_onWidgetUri);
    _titleTimer = Timer(const Duration(milliseconds: 900), () {
      _titleIntro = false;
    });
    SharedPreferences.getInstance().then((p) {
      final v = p.getString(_kSort);
      final open = p.getStringList(_kOpenFolders);
      if (!mounted) return;
      setState(() {
        if (v != null) _sort = v;
        if (open != null) _openFolders.addAll(open);
      });
    }).catchError((_) {});
    if (!AppConfig.demo) {
      WidgetsBinding.instance
          .addPostFrameCallback((_) => checkForUpdatesOnStart(context));
    }
  }

  @override
  void dispose() {
    GestureBinding.instance.pointerRouter.removeGlobalRoute(_sideButtons);
    HardwareKeyboard.instance.removeHandler(_onKey);
    SmartGroups.instance.removeListener(_onGroups);
    Reminders.instance.detach();
    _widgetSub?.cancel();
    _newNoteSub?.cancel();
    _captureSub?.cancel();
    _shareSub?.cancel();
    _entranceTimer?.cancel();
    _titleTimer?.cancel();
    vault.removeListener(_onVault);
    repo.onLocalEdit = null;
    _search.dispose();
    _searchFocus.dispose();
    _listScroll.dispose();
    super.dispose();
  }

  late final VaultLock vault = VaultLock.forUser(repo.userId);

  /// Conversación con el asistente de IA (se mantiene mientras la app está
  /// abierta).
  late final AiSession _ai = AiSession(repo);

  void _openAssistant() => openAssistant(context, _ai, onOpenNote: _open);

  // ------------------------------------------------- selección múltiple

  /// Notas marcadas (Ctrl+clic, o ⋯/clic derecho → Seleccionar).
  final Set<String> _picked = {};
  bool get _selecting => _picked.isNotEmpty;

  void _togglePick(String id) {
    // Las notas de otra cuenta no se mueven ni se borran en bloque.
    final n = repo.byId(id);
    if (n == null || repo.isForeign(n)) return;
    setState(() => _picked.contains(id) ? _picked.remove(id) : _picked.add(id));
  }

  void _clearPicked() => setState(_picked.clear);

  void _bulkPin() {
    final notes = [for (final id in _picked) repo.byId(id)!];
    // Si alguna está sin fijar, se fijan todas; si no, se desfijan.
    final pin = notes.any((n) => !n.pinned);
    for (final n in notes) {
      if (n.pinned != pin) repo.togglePin(n.id);
    }
    _clearPicked();
  }

  Future<void> _bulkMove() async {
    final r = await pickFolder(context, repo, null);
    if (r == null || !mounted) return;
    for (final id in _picked) {
      repo.moveToFolder(id, r.isEmpty ? null : r);
    }
    _clearPicked();
  }

  Future<bool> _confirmBulk(String title, String text, String action) async =>
      await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(title),
          content: Text(text),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text(tr('Cancelar'))),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, true), child: Text(action)),
          ],
        ),
      ) ==
      true;

  Future<void> _bulkArchive() async {
    final ids = _picked.toList();
    if (!await _confirmBulk(trf('¿Archivar {0} notas?', [ids.length]),
            tr('La encontrarás en ⋯ → Archivadas.'), tr('Archivar')) ||
        !mounted) {
      return;
    }
    if (ids.contains(_openId)) _close();
    for (final id in ids) {
      repo.setArchived(id, true);
    }
    _clearPicked();
    showToast(context, trf('{0} notas archivadas', [ids.length]),
        icon: Icons.archive_outlined,
        actionLabel: tr('Deshacer'), onAction: () {
      for (final id in ids) {
        repo.setArchived(id, false);
      }
    });
  }

  Future<void> _bulkDelete() async {
    final ids = _picked.toList();
    if (!await _confirmBulk(trf('¿Eliminar {0} notas?', [ids.length]),
            tr('Irán a la papelera durante 3 días.'), tr('Eliminar')) ||
        !mounted) {
      return;
    }
    if (ids.contains(_openId)) _close();
    for (final id in ids) {
      repo.delete(id);
    }
    _clearPicked();
    showToast(context, trf('{0} notas en la papelera', [ids.length]),
        icon: Icons.delete_outline_rounded,
        actionLabel: tr('Deshacer'), onAction: () {
      for (final id in ids) {
        repo.restore(id);
      }
    });
  }

  /// Barra de acciones mientras hay notas seleccionadas.
  Widget _selectionBar(BuildContext context) => SizedBox(
        key: const ValueKey('barra-seleccion'),
        height: 58,
        child: Row(
          children: [
            const SizedBox(width: 8),
            _BarButton(
                tooltip: tr('Cancelar selección'),
                icon: Icons.close_rounded,
                onTap: _clearPicked),
            Expanded(
              child: Text(
                trn(_picked.length, '{0} seleccionada', '{0} seleccionadas'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
            _BarButton(
                tooltip: tr('Fijar arriba'),
                icon: Icons.push_pin_outlined,
                onTap: _bulkPin),
            _BarButton(
                tooltip: tr('Mover a carpeta'),
                icon: Icons.drive_file_move_outline,
                onTap: _bulkMove),
            _BarButton(
                tooltip: tr('Archivar'),
                icon: Icons.archive_outlined,
                onTap: _bulkArchive),
            _BarButton(
                tooltip: tr('Eliminar'),
                icon: Icons.delete_outline_rounded,
                onTap: _bulkDelete),
            const SizedBox(width: 8),
          ],
        ),
      );

  /// Ctrl+K: buscar notas y lanzar cualquier acción.
  void _openPalette() {
    void view(String f) {
      _close();
      _setFilter(f);
    }

    showCommandPalette(
      context,
      repo: repo,
      onOpenNote: _open,
      commands: [
        PaletteCommand(Icons.sticky_note_2_rounded, tr('Nueva nota'), _newNote,
            shortcut: 'Ctrl+N'),
        PaletteCommand(
            Icons.timer_outlined, tr('Pomodoro'), () => showPomodoro(context)),
        PaletteCommand(Icons.insights_rounded, tr('Productividad'),
            () => showProductivity(context, repo)),
        PaletteCommand(Icons.add_a_photo_outlined, tr('Tareas desde una foto'),
            () => tasksFromPhoto(context, repo, onOpen: _open)),
        PaletteCommand(Icons.dashboard_customize_outlined,
            tr('Nueva desde plantilla'), _fromTemplate),
        PaletteCommand(Icons.ios_share_rounded, tr('Exportar notas'),
            () => showExportAll(context, repo)),
        PaletteCommand(Icons.download_rounded, tr('Importar copia'),
            () => importBackupFile(context, repo)),
        PaletteCommand(Icons.event_available_rounded, tr('Importar calendario'),
            () => importCalendarFile(context, repo)),
        PaletteCommand(Icons.create_new_folder_outlined, tr('Nueva carpeta'),
            () async {
          final f = await editFolderDialog(context, repo);
          if (f != null && !_openFolders.contains(f.id)) _toggleFolder(f.id);
        }),
        PaletteCommand(
            Icons.auto_awesome_outlined, tr('Asistente IA'), _openAssistant,
            shortcut: 'Ctrl+J'),
        PaletteCommand(
            Icons.sticky_note_2_outlined, tr('Notas'), () => view('todas'),
            shortcut: 'Ctrl+1'),
        PaletteCommand(Icons.calendar_month_outlined, tr('Calendario'),
            () => view('calendario'),
            shortcut: 'Ctrl+2'),
        PaletteCommand(
            Icons.hub_outlined, tr('Red de notas'), () => view('red'),
            shortcut: 'Ctrl+3'),
        PaletteCommand(Icons.palette_outlined, tr('Tema y colores'),
            () => showThemePicker(context),
            shortcut: 'Ctrl+,'),
        PaletteCommand(Icons.translate_rounded, tr('Idioma'),
            () => showLanguagePicker(context)),
        PaletteCommand(Icons.archive_outlined, tr('Archivadas'),
            () => showArchived(context, repo)),
        PaletteCommand(Icons.task_alt_rounded, tr('Completadas'),
            () => showCompleted(context, repo)),
        PaletteCommand(Icons.delete_outline, tr('Papelera'),
            () => showTrash(context, repo)),
        PaletteCommand(Icons.shield_outlined, 'Vault', _openVault),
        PaletteCommand(Icons.sync, tr('Sincronizar ahora'), repo.sync),
        PaletteCommand(
            Icons.system_update_alt_rounded,
            tr('Buscar actualizaciones'),
            () => checkForUpdatesManually(context)),
      ],
    );
  }

  /// El menú ⋯ cambia según el Vault esté abierto o no.
  void _onVault() {
    if (mounted) setState(() {});
  }

  /// Menú → Vault: lo abre (o lo crea) y muestra su pantalla.
  Future<void> _openVault() async {
    if (await ensureVaultOpen(context, vault) && mounted) {
      await openVaultScreen(context, repo, vault);
    }
  }

  /// Ejecuta [f] cuando las notas estén cargadas (al abrir la app desde
  /// un widget aún pueden estar cargándose).
  void _whenLoaded(VoidCallback f) {
    if (repo.loaded) {
      WidgetsBinding.instance.addPostFrameCallback((_) => f());
      return;
    }
    late VoidCallback listener;
    listener = () {
      if (!repo.loaded) return;
      repo.removeListener(listener);
      WidgetsBinding.instance.addPostFrameCallback((_) => f());
    };
    repo.addListener(listener);
  }

  void _onWidgetUri(Uri? uri) {
    if (uri == null || !mounted) return;
    if (uri.host == 'calendario') {
      _setFilter('calendario');
      return;
    }
    if (uri.host == 'red') {
      _setFilter('red');
      return;
    }
    if (uri.host == 'buscar') {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _searchFocus.requestFocus();
      });
      return;
    }
    // notas://nota/<id>: abrir esa nota (widget "Próxima tarea").
    if (uri.host == 'nota' && uri.pathSegments.isNotEmpty) {
      final id = uri.pathSegments.first;
      _whenLoaded(() {
        if (mounted && repo.byId(id) != null) _open(id);
      });
      return;
    }
    if (uri.host == 'nueva') {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _newNote();
      });
    }
  }

  /// Nota rápida (Ctrl+Alt+N): al guardar o cancelar, la ventana vuelve a
  /// como estaba.
  Future<void> _capture() async {
    if (!mounted) return;
    final desktop = DesktopIntegration.instance;
    final nav = Navigator.of(context, rootNavigator: true);
    var closed = false;
    desktop.cancelCapture = () {
      if (!closed) nav.maybePop();
    };
    final note = await showQuickCapture(context, repo);
    closed = true;
    desktop.cancelCapture = null;
    await desktop.endCapture();
    if (note != null && mounted) {
      showToast(context, tr('Nota guardada'),
          icon: Icons.check_circle_outline_rounded,
          actionLabel: tr('Abrir'),
          onAction: () => _open(note.id));
    }
  }

  /// Texto, enlaces e imágenes compartidos desde otra app.
  Future<void> _onShared(List<SharedMediaFile> files) async {
    if (files.isEmpty) return;
    final texts = <String>[];
    final images = <String>[];
    for (final f in files) {
      switch (f.type) {
        case SharedMediaType.text || SharedMediaType.url:
          texts.add(f.path);
        case SharedMediaType.image:
          if (f.message?.trim().isNotEmpty == true) texts.add(f.message!);
          try {
            final src =
                await NoteImages.instance.add(await File(f.path).readAsBytes());
            if (src != null) images.add(src);
          } catch (e) {
            debugPrint('Compartir: no se pudo leer la imagen ($e)');
          }
        default:
          break;
      }
    }
    unawaited(ReceiveSharingIntent.instance.reset());
    _whenLoaded(() {
      if (!mounted) return;
      final n = createNoteFrom(repo, text: texts.join('\n'), images: images);
      if (n == null) return;
      _open(n.id);
      showToast(context, tr('Guardado en una nota nueva'),
          icon: Icons.check_circle_outline_rounded);
    });
  }

  /// Primera vez que se cierra la ventana en Windows: ¿segundo plano o salir?
  Future<bool?> _askOnFirstClose() => showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          icon: Icon(Icons.keyboard_command_key_rounded,
              color: Palette.accent(ctx)),
          title: Text(tr('¿Dejar Oganesson en segundo plano?')),
          content: Text(tr('Seguirá en la bandeja del sistema (junto al '
              'reloj) y podrás crear una nota desde cualquier sitio con '
              'Ctrl+Alt+N. Puedes cambiarlo en ⋯.')),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: Text(tr('Salir del todo'))),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text(tr('Segundo plano'))),
          ],
        ),
      );

  void _newNote({String? folderId}) {
    final n = repo.createNote(folderId: folderId);
    _open(n.id, autofocus: true);
  }

  Future<void> _fromTemplate() async {
    final n = await pickTemplate(context, repo);
    if (n != null && mounted) _open(n.id);
  }

  /// Nueva nota temporal que vence el día elegido en el calendario.
  void _newOnDay(DateTime day) {
    final n = repo.createNote(
      dueAt: Note.dayEnd(day).toUtc(),
      remindAt: Note.dayStart(day).toUtc(),
    );
    _open(n.id, autofocus: true);
  }

  // Historial de pestañas: botones laterales del ratón y Alt+←/→.
  final _visited = <(String, String?)>[('todas', null)];
  int _visitedAt = 0;
  bool _walking = false;

  void _remember() {
    if (_walking) return;
    final here = (_filter, _openId);
    if (_visited[_visitedAt] == here) return;
    _visited
      ..removeRange(_visitedAt + 1, _visited.length)
      ..add(here);
    if (_visited.length > 60) _visited.removeAt(0);
    _visitedAt = _visited.length - 1;
  }

  /// Botones laterales del ratón, en toda la app (también con un diálogo o
  /// el asistente encima: entonces "atrás" lo cierra).
  void _sideButtons(PointerEvent e) {
    if (e is! PointerDownEvent || e.kind != PointerDeviceKind.mouse) return;
    final back = e.buttons & kBackMouseButton != 0;
    if (!back && e.buttons & kForwardMouseButton == 0) return;
    if (!mounted) return;
    if (ModalRoute.of(context)?.isCurrent == false) {
      if (back) Navigator.of(context).maybePop();
      return;
    }
    _walk(back ? -1 : 1);
  }

  /// Atajos que deben funcionar también con el cursor dentro de la nota
  /// (el editor se quedaría con ellos): Ctrl+Tab, Ctrl+↑/↓, Ctrl+W, Ctrl+Q
  /// y Ctrl+F para buscar dentro de la nota abierta.
  bool _onKey(KeyEvent e) {
    if (e is! KeyDownEvent && e is! KeyRepeatEvent) return false;
    final k = HardwareKeyboard.instance;
    if (!k.isControlPressed || k.isAltPressed || k.isMetaPressed) return false;
    if (!mounted || ModalRoute.of(context)?.isCurrent == false) return false;
    final key = e.logicalKey;
    if (key == LogicalKeyboardKey.tab) {
      _stepNote(k.isShiftPressed ? -1 : 1, wrap: true);
      return true;
    }
    if (k.isShiftPressed ||
        e is KeyRepeatEvent &&
            key != LogicalKeyboardKey.arrowUp &&
            key != LogicalKeyboardKey.arrowDown) {
      return false;
    }
    if (key == LogicalKeyboardKey.arrowDown ||
        key == LogicalKeyboardKey.arrowUp) {
      _stepNote(key == LogicalKeyboardKey.arrowDown ? 1 : -1);
      return true;
    }
    if (key == LogicalKeyboardKey.keyW && _openId != null) {
      _close();
      return true;
    }
    if (key == LogicalKeyboardKey.keyQ) {
      _toggleSidebar();
      return true;
    }
    if (key == LogicalKeyboardKey.keyF && _openId != null) {
      noteFindRequests.add(null);
      return true;
    }
    return false;
  }

  void _onGroups() {
    if (mounted && _sort == 'tipo') setState(() {});
  }

  /// Notas ya enviadas a clasificar en esta sesión (no se repite si falla).
  final _groupTried = <String>{};

  /// Secciones del orden "Por tipo (IA)".
  Map<String, List<Note>> _groupsOf(List<Note> notes) {
    final g = SmartGroups.instance;
    final pending = [
      for (final n in notes)
        if (g.categoryOf(n) == null && _groupTried.add('${n.id}|${n.title}')) n
    ];
    if (pending.isNotEmpty && AiSettings.instance.configured) {
      Future.microtask(() => g.classify(pending));
    }
    final out = <String, List<Note>>{};
    for (final n in notes) {
      (out[g.categoryOf(n) ?? tr('Sin clasificar')] ??= []).add(n);
    }
    final keys = out.keys.toList()
      ..sort((a, b) => a == tr('Sin clasificar')
          ? 1
          : b == tr('Sin clasificar')
              ? -1
              : a.compareTo(b));
    return {for (final k in keys) k: out[k]!};
  }

  /// Notas en el orden en que se ven en la lista (lo rellena `_buildList`).
  List<String> _order = const [];

  void _stepNote(int d, {bool wrap = false}) {
    final ids = _order;
    if (ids.isEmpty) return;
    final i = _openId == null ? -1 : ids.indexOf(_openId!);
    var j = i == -1 ? (d > 0 ? 0 : ids.length - 1) : i + d;
    if (wrap) j %= ids.length;
    if (j < 0 || j >= ids.length || ids[j] == _openId) return;
    _open(ids[j]);
  }

  bool _listHidden = false;

  void _toggleSidebar() {
    if (MediaQuery.sizeOf(context).width < _wideBreakpoint) return;
    setState(() => _listHidden = !_listHidden);
  }

  Widget _sidebarButton({required bool open}) => IconButton(
        tooltip:
            open ? tr('Ocultar panel (Ctrl+Q)') : tr('Mostrar panel (Ctrl+Q)'),
        onPressed: _toggleSidebar,
        icon: AnimatedRotation(
          turns: open ? 0 : 0.5,
          duration: Anim.medium,
          curve: Anim.curve,
          child: const Icon(Icons.keyboard_double_arrow_left_rounded),
        ),
      );

  void _walk(int step) {
    for (var i = _visitedAt + step; i >= 0 && i < _visited.length; i += step) {
      final (filter, id) = _visited[i];
      // Una nota borrada desde entonces se salta.
      if (id != null && repo.byId(id)?.deleted != false) continue;
      _walking = true;
      _setFilter(filter);
      id == null ? _close() : _open(id);
      _walking = false;
      _visitedAt = i;
      return;
    }
  }

  void _goHome() {
    _close();
    _setFilter('todas');
  }

  void _setFilter(String f) {
    if (f == _filter) return;
    // Al ir al calendario o a la red se cierra la nota abierta para que se vea.
    if ((f == 'calendario' || f == 'red') && _openId != null) {
      final was = _walking;
      _walking = true;
      _close();
      _walking = was;
    }
    // En PC Todas / Red / Calendario comparten la misma lista (no se vuelve
    // a montar): sus filas no deben repetir la entrada.
    const shared = {'todas', 'red', 'calendario'};
    final sameList = MediaQuery.sizeOf(context).width >= _wideBreakpoint &&
        shared.contains(f) &&
        shared.contains(_filter);
    setState(() {
      _filter = f;
      if (!sameList) {
        _entering = null;
        _rowIntro.clear();
      }
    });
    _remember();
  }

  void _open(String id, {bool autofocus = false}) {
    final prev = _openId;
    setState(() {
      _openId = id;
      _openAutofocus = autofocus;
      _discarding = false;
    });
    _remember();
    // Una nota nueva que se dejó vacía se descarta al cambiar de nota.
    if (prev != null && prev != id) repo.finishEditing(prev);
  }

  void _close() {
    final prev = _openId;
    if (prev == null || !mounted) return;
    setState(() {
      _openId = null;
      _discarding = false;
    });
    _remember();
    repo.finishEditing(prev);
  }

  /// Pliega la fila con animación y después la borra.
  void _deleteAnimated(String id) {
    if (_removing.contains(id)) return;
    setState(() {
      if (_openId == id) {
        _openId = null;
        _discarding = true;
      }
      _removing.add(id);
    });
    Future.delayed(Anim.medium, () {
      if (!mounted) return;
      _removing.remove(id);
      _deleteNote(id);
    });
  }

  void _deleteNote(String id) {
    final n = repo.byId(id);
    final hadContent = n != null && !n.isEmpty;
    if (_openId == id) {
      setState(() {
        _openId = null;
        _discarding = true;
      });
    }
    repo.delete(id);
    if (!hadContent || !mounted) return;
    showToast(
      context,
      tr('Nota movida a la papelera'),
      icon: Icons.delete_outline_rounded,
      actionLabel: tr('Deshacer'),
      onAction: () => repo.restore(id),
    );
  }

  /// Acciones de una nota: menú contextual con clic derecho (en [at]) o
  /// panel inferior con pulsación larga.
  Future<void> _options(Note n, [Offset? at]) async {
    final foreign = repo.isForeign(n);
    final actions = foreign
        ? <(String, IconData, String, bool)>[
            ('share', Icons.group_outlined, tr('Nota compartida'), false),
          ]
        : <(String, IconData, String, bool)>[
            ('share', Icons.group_add_outlined, tr('Compartir'), false),
            ('-', Icons.remove, '', false),
            (
              'link',
              Icons.hub_outlined,
              tr('Enlazar notas o archivos…'),
              false
            ),
            (
              'sub',
              Icons.account_tree_outlined,
              tr('Crear subnota enlazada'),
              false
            ),
            ('-', Icons.remove, '', false),
            (
              'pin',
              n.pinned ? Icons.push_pin : Icons.push_pin_outlined,
              n.pinned ? tr('Desfijar') : tr('Fijar arriba'),
              false
            ),
            (
              'dates',
              n.isTemporal ? Icons.alarm_on : Icons.alarm_add_outlined,
              n.isTemporal ? tr('Cambiar fechas') : tr('Hacer temporal'),
              false
            ),
            if (n.isTemporal)
              (
                'untimed',
                Icons.event_busy_outlined,
                tr('Quitar fechas'),
                false
              ),
            // El color solo se ve en la línea de tiempo.
            if (n.isTemporal)
              ('color', Icons.palette_outlined, tr('Color'), false),
            (
              'folder',
              Icons.drive_file_move_outline,
              tr('Mover a carpeta'),
              false
            ),
            ('-', Icons.remove, '', false),
            ('select', Icons.check_circle_outline, tr('Seleccionar'), false),
            ('vault', Icons.shield_outlined, tr('Enviar al Vault'), false),
            ('-', Icons.remove, '', false),
            ('delete', Icons.delete_outline, tr('Eliminar'), true),
          ];

    String? choice;
    if (at != null) {
      choice = await showContextMenu(
        context,
        position: at,
        title: n.title,
        entries: [
          for (final (id, icon, label, danger) in actions)
            id == '-' ? null : MenuEntry(id, icon, label, danger: danger),
        ],
      );
    } else {
      // Con scroll: en un móvil pequeño las opciones no caben.
      choice = await showModalBottomSheet<String>(
        context: context,
        useSafeArea: true,
        showDragHandle: true,
        isScrollControlled: true,
        constraints:
            BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.85),
        builder: (ctx) => SafeArea(
          child: ListView(
            shrinkWrap: true,
            children: [
              for (final (id, icon, label, danger) in actions)
                if (id == '-')
                  const Divider(height: 8)
                else
                  ListTile(
                    leading: Icon(icon,
                        color: danger
                            ? Theme.of(context).colorScheme.error
                            : null),
                    title: Text(label,
                        style: TextStyle(
                            color: danger
                                ? Theme.of(context).colorScheme.error
                                : null)),
                    onTap: () => Navigator.pop(ctx, id),
                  ),
            ],
          ),
        ),
      );
    }
    if (!mounted || choice == null) return;
    switch (choice) {
      case 'share':
        await showShareSheet(context, repo, n.id);
      case 'link':
        await showLinkNotesPicker(context, repo, n.id);
      case 'sub':
        final sub = repo.createSubnote(n.id);
        _open(sub.id, autofocus: true);
      case 'select':
        _togglePick(n.id);
      case 'pin':
        repo.togglePin(n.id);
      case 'dates':
        showScheduleSheet(context, repo, n.id);
      case 'untimed':
        repo.setSchedule(n.id);
      case 'vault':
        if (await ensureVaultOpen(context, vault) && mounted) {
          if (_openId == n.id) _close();
          repo.setVault(n.id, true);
          showToast(context, tr('Nota enviada al Vault'),
              icon: Icons.shield_outlined);
        }
      case 'color':
        showNoteColorSheet(context, repo, n.id);
      case 'folder':
        final r = await pickFolder(context, repo, n.folderId);
        if (r != null) repo.moveToFolder(n.id, r.isEmpty ? null : r);
      case 'delete':
        if (await confirmDelete(context, n.title) && mounted) {
          _deleteAnimated(n.id);
        }
    }
  }

  Future<void> _signOut() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('¿Cerrar sesión?')),
        content: Text(
            tr('Las notas siguen guardadas en tu cuenta. Volverán al entrar.')),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(tr('Cancelar'))),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(tr('Cerrar sesión'))),
        ],
      ),
    );
    if (ok == true) {
      VaultLock.lockAll();
      await repo.sync();
      await Supabase.instance.client.auth.signOut();
    }
  }

  Widget _editor({required bool showBack}) {
    final key = (_openId, showBack, _openAutofocus);
    if (_editorCache != null && _editorKey == key) return _editorCache!;
    _editorKey = key;
    return _editorCache = RepaintBoundary(
      key: ValueKey('editor-$_openId'),
      child: NoteEditor(
        repo: repo,
        noteId: _openId!,
        showBack: showBack,
        autofocus: _openAutofocus,
        onClose: _close,
        onDelete: _deleteAnimated,
        onOpenNote: _open,
        onCommandPalette: _openPalette,
      ),
    );
  }

  /// Lista cacheada: solo se reconstruye si cambian los datos o filtros,
  /// no por cambiar el tamaño de la ventana.
  Widget _list(BuildContext context, bool wide) {
    final key = (
      repo.version,
      repo.status,
      _query,
      _filter,
      _sort,
      Object.hashAllUnordered(_openFolders),
      _openId,
      wide,
      _removing.length,
      Object.hashAllUnordered(_picked),
      _filters.signature,
      _sort == 'tipo'
          ? Object.hash(
              SmartGroups.instance.signature, SmartGroups.instance.busy)
          : 0,
      Theme.of(context)
    );
    if (_listCache != null && _listKey == key) return _listCache!;
    _listKey = key;
    return _listCache = RepaintBoundary(child: _buildList(context, wide));
  }

  Widget _calendar() => CalendarView(
        key: const ValueKey('calendario'),
        repo: repo,
        onOpenNote: _open,
        onNewOnDay: _newOnDay,
        onEditDates: (id) => showScheduleSheet(context, repo, id),
      );

  Widget _graph() => GraphView(
        key: const ValueKey('red'),
        repo: repo,
        onOpenNote: _open,
      );

  @override
  Widget build(BuildContext context) {
    return Listener(
      // Cualquier toque cuenta como actividad para el bloqueo del Vault.
      onPointerDown: (e) {
        vault.touch();
      },
      onPointerSignal: (_) => vault.touch(),
      child: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.keyN, control: true):
              _newNote,
          const SingleActivator(LogicalKeyboardKey.keyH, control: true):
              _goHome,
          const SingleActivator(LogicalKeyboardKey.arrowLeft, alt: true): () =>
              _walk(-1),
          const SingleActivator(LogicalKeyboardKey.arrowRight, alt: true): () =>
              _walk(1),
          const SingleActivator(LogicalKeyboardKey.slash, control: true): () =>
              showShortcuts(context),
          // En teclado español, la tecla de "/" sin Mayús es el 7.
          const SingleActivator(LogicalKeyboardKey.digit7,
              control: true, shift: true): () => showShortcuts(context),
          // Esc: primero quita la selección; si no hay, cierra la nota.
          const SingleActivator(LogicalKeyboardKey.escape): () =>
              _selecting ? _clearPicked() : _close(),
          // Ctrl+F: buscar. Ctrl+1/2/3: notas, calendario, red.
          const SingleActivator(LogicalKeyboardKey.keyF, control: true): () =>
              _searchFocus.requestFocus(),
          const SingleActivator(LogicalKeyboardKey.digit1, control: true): () {
            _close();
            _setFilter('todas');
          },
          const SingleActivator(LogicalKeyboardKey.digit2, control: true): () {
            _close();
            _setFilter('calendario');
          },
          const SingleActivator(LogicalKeyboardKey.digit3, control: true): () {
            _close();
            _setFilter('red');
          },
          // Ctrl+,: tema y colores.
          // Ctrl+K: paleta de comandos.
          const SingleActivator(LogicalKeyboardKey.keyK, control: true):
              _openPalette,
          // Ctrl+J: asistente de IA.
          const SingleActivator(LogicalKeyboardKey.keyJ, control: true):
              _openAssistant,
          const SingleActivator(LogicalKeyboardKey.comma, control: true): () =>
              showThemePicker(context),
        },
        child: Focus(
          autofocus: true,
          child: ListenableBuilder(
            listenable: repo,
            builder: (context, _) {
              // Si la nota abierta se borró desde otro dispositivo, se cierra.
              final open = _openId == null ? null : repo.byId(_openId!);
              final hasOpen = open != null && !open.deleted;

              return LayoutBuilder(builder: (context, c) {
                final wide = c.maxWidth >= _wideBreakpoint;

                if (wide) {
                  return Scaffold(
                    body: Stack(
                      children: [
                        Positioned.fill(
                            child: ResizableSplit(
                          storageKey: 'lista',
                          initialFraction: 0.32,
                          minLeft: 300,
                          maxLeft: 560,
                          minRight: 380,
                          collapsed: _listHidden,
                          rail: Column(children: [
                            const SizedBox(height: 6),
                            _sidebarButton(open: false),
                          ]),
                          left: _list(context, true),
                          right: AnimatedSwitcher(
                            duration: Anim.medium,
                            switchInCurve: Anim.curve,
                            switchOutCurve: Curves.easeIn,
                            // Al eliminar la nota abierta solo se anima su
                            // salida; el calendario aparece sin más.
                            transitionBuilder: (child, anim) => !_discarding
                                ? fadeThrough(child, anim)
                                : '${(child.key as ValueKey?)?.value}'
                                        .startsWith('editor-')
                                    ? discardTransition(child, anim)
                                    : stillTransition(child, anim, fade: true),
                            child: hasOpen
                                ? _editor(showBack: false)
                                // Sin nota abierta se ve el calendario (o la
                                // red, si está elegida).
                                : _filter == 'red'
                                    ? RepaintBoundary(
                                        key: const ValueKey('red-panel'),
                                        child: _graph())
                                    : RepaintBoundary(
                                        key: const ValueKey('cal'),
                                        child: _calendar()),
                          ),
                        )),
                      ],
                    ),
                  );
                }

                // Estrecho: la nota se desliza por encima de la lista.
                return PopScope(
                  canPop: !hasOpen,
                  onPopInvokedWithResult: (didPop, _) {
                    if (!didPop) _close();
                  },
                  // La lista está SIEMPRE montada debajo: al abrir, cerrar,
                  // crear o borrar una nota solo se mueve la nota; la lista
                  // (carpetas, buscador, barra…) no se vuelve a construir.
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      // Al abrir una nota la lista se aparta un poco y se
                      // atenúa (como en iPhone). Si la nota se elimina, la
                      // lista vuelve a su sitio sin animación.
                      AnimatedSlide(
                        offset: hasOpen ? const Offset(-0.25, 0) : Offset.zero,
                        duration: _discarding ? Duration.zero : Anim.slow,
                        curve: Curves.easeOutCubic,
                        child: AnimatedOpacity(
                          opacity: hasOpen ? 0.5 : 1,
                          duration: _discarding ? Duration.zero : Anim.slow,
                          child: IgnorePointer(
                            ignoring: hasOpen,
                            child: ExcludeFocus(
                              excluding: hasOpen,
                              child: KeyedSubtree(
                                key: const ValueKey('lista'),
                                child: _list(context, false),
                              ),
                            ),
                          ),
                        ),
                      ),
                      AnimatedSwitcher(
                        duration: Anim.slow,
                        // Sin nota, la capa vacía no lleva transición (si
                        // no, su fondo taparía los toques a la lista).
                        transitionBuilder: (child, anim) =>
                            child.key == const ValueKey('sin-nota')
                                ? child
                                : _discarding
                                    ? discardTransition(child, anim)
                                    : pushTransition(child, anim, isPage: true),
                        layoutBuilder: (current, previous) => Stack(
                          fit: StackFit.expand,
                          children: [
                            ...previous,
                            if (current != null) current,
                          ],
                        ),
                        child: hasOpen
                            ? _editor(showBack: true)
                            : const SizedBox.shrink(key: ValueKey('sin-nota')),
                      ),
                    ],
                  ),
                );
              });
            },
          ),
        ),
      ),
    );
  }

  Widget _buildList(BuildContext context, bool wide) {
    if (_picked.isNotEmpty) {
      final alive = {for (final n in repo.notes) n.id};
      _picked.removeWhere((id) => !alive.contains(id));
    }
    final q = _query.toLowerCase();
    final all = repo.notes
        .where((n) => !n.isEmpty || n.id == _openId)
        .where((n) => q.isEmpty || n.content.toLowerCase().contains(q))
        .where((n) => !_filters.isActive || _filters.matches(n))
        .toList();
    switch (_sort) {
      case 'creada':
        all.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      case 'nombre':
        all.sort(
            (a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
      case 'manual':
        all.sort(_byPosition);
      default: // ya viene ordenada por última modificación
    }
    // Notas nuevas desde la última vez (las únicas que se animan al entrar).
    final known = Set.of(_knownIds);
    _knownIds
      ..clear()
      ..addAll(all.map((n) => n.id));
    _rowIntro.removeWhere((id, _) => !_knownIds.contains(id));
    _prevKnownIds = known;
    final pinned = all.where((n) => n.pinned).toList();
    final others = all.where((n) => !n.pinned).toList();
    final shownFolders = {
      for (final f in repo.folders)
        if (q.isNotEmpty || _openFolders.contains(f.id)) f.id
    };
    final anyFolder = {for (final f in repo.folders) f.id};
    _order = [
      for (final n in pinned) n.id,
      for (final f in repo.folders)
        if (shownFolders.contains(f.id))
          for (final n in others)
            if (n.folderId == f.id) n.id,
      for (final n in others)
        if (n.folderId == null || !anyFolder.contains(n.folderId)) n.id,
    ];
    final noteOpen = _openId != null && repo.byId(_openId!) != null;

    Widget body;
    if (!repo.loaded) {
      body = const Center(child: CircularProgressIndicator());
    } else if (_filter == 'calendario' && !wide) {
      body = _calendar();
    } else if (_filter == 'red' && !wide) {
      body = _graph();
    } else if (all.isEmpty &&
        (q.isNotEmpty || _filters.isActive || repo.folders.isEmpty)) {
      body = _EmptyList(
          searching: q.isNotEmpty || _filters.isActive,
          timeView: _filter == 'calendario');
    } else {
      var index = 0;
      final folders = repo.folders;
      final folderIds = {for (final f in folders) f.id};
      final loose = others
          .where((n) => n.folderId == null || !folderIds.contains(n.folderId))
          .toList();
      body = RefreshIndicator(
        onRefresh: repo.sync,
        child: ListView(
          key: const PageStorageKey('lista-notas'),
          controller: _listScroll,
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
          children: [
            // Cabecera: solo el selector de orden.
            Padding(
              key: const ValueKey('cabecera-lista'),
              padding: const EdgeInsets.fromLTRB(6, 2, 0, 0),
              child: Row(
                children: [
                  if (wide) _sidebarButton(open: true),
                  const Spacer(),
                  _sortMenu(context),
                ],
              ),
            ),
            // Soltar arriba del todo: fijar (solo se ve la línea).
            DropZone(
              key: const ValueKey('soltar-arriba'),
              height: 10,
              onDrop: (id) => _dropInto(id, folderId: null, pin: true),
            ),
            if (pinned.isNotEmpty)
              ..._section(context, tr('Fijadas'), pinned, wide, () => index++,
                  onDrop: (id) => _dropInto(id, folderId: null, pin: true)),
            if (_sort == 'tipo') ...[
              if (!AiSettings.instance.configured)
                Padding(
                  key: const ValueKey('tipo-sin-ia'),
                  padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
                  child: Text(
                      tr('Pon tu clave en el Asistente IA para agrupar por tipo.'),
                      style: TextStyle(color: Palette.secondary(context))),
                ),
              if (SmartGroups.instance.busy)
                const Padding(
                  key: ValueKey('tipo-cargando'),
                  padding: EdgeInsets.symmetric(vertical: 6),
                  child: LinearProgressIndicator(minHeight: 2),
                ),
              for (final e in _groupsOf(others).entries)
                ..._section(context, e.key, e.value, wide, () => index++),
            ] else
              for (final f in folders)
                if (q.isEmpty || others.any((n) => n.folderId == f.id))
                  Builder(
                    key: ValueKey('carpeta-${f.id}'),
                    builder: (context) {
                      final inFolder =
                          others.where((n) => n.folderId == f.id).toList();
                      final expanded =
                          q.isNotEmpty || _openFolders.contains(f.id);
                      return FolderGroup(
                        folder: f,
                        expanded: expanded,
                        onToggle: () => _toggleFolder(f.id),
                        onNewNote: () {
                          if (!_openFolders.contains(f.id)) _toggleFolder(f.id);
                          _newNote(folderId: f.id);
                        },
                        onOptions: (at) => _folderOptions(f, at),
                        onDropNote: (id) => _dropInto(id, folderId: f.id),
                        child: inFolder.isEmpty
                            ? null
                            : _tilesCard(
                                context, inFolder, wide, () => index++),
                      );
                    },
                  ),
            if (loose.isNotEmpty && _sort != 'tipo')
              ..._section(
                  context,
                  folders.isEmpty && pinned.isEmpty ? null : tr('Sin carpeta'),
                  loose,
                  wide,
                  () => index++,
                  onDrop: (id) => _dropInto(id, folderId: null)),
            // Soltar abajo del todo: sin carpeta (solo se ve la línea).
            DropZone(
              key: const ValueKey('soltar-abajo'),
              height: 56,
              onDrop: (id) => _dropInto(id, folderId: null),
            ),
          ],
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        centerTitle: false,
        titleSpacing: 20,
        // Con el panel estrecho el título se encoge en vez de desbordarse.
        // Vuelve al inicio, sin cambiar de aspecto al pasar el ratón.
        title: GestureDetector(
          key: const ValueKey('logo-inicio'),
          behavior: HitTestBehavior.opaque,
          onTap: _goHome,
          child: const FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: WaveTitle(text: 'oganesson', fontSize: 30),
          ),
        ).animate(value: _titleIntro ? null : 1).fadeIn(duration: Anim.slow),
        actions: [
          _SyncIndicator(repo: repo),
          Builder(
            builder: (btnContext) => IconButton(
              key: const ValueKey('boton-ajustes'),
              icon: AnimatedRotation(
                turns: _settingsTurns,
                duration: Anim.slow,
                curve: Anim.curve,
                child: const Icon(Icons.settings_outlined),
              ),
              tooltip: tr('Ajustes'),
              onPressed: () => _openSettings(btnContext),
            ),
          ),
          Builder(
            builder: (btnContext) => IconButton(
              icon: const Icon(Icons.more_horiz),
              tooltip: tr('Más opciones'),
              onPressed: () => _openMainMenu(btnContext),
            ),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: TextField(
              contextMenuBuilder: textFieldMenu,
              controller: _search,
              focusNode: _searchFocus,
              onChanged: (v) => setState(() => _query = v),
              decoration: InputDecoration(
                hintText: tr('Buscar'),
                prefixIcon: const Icon(Icons.search),
                suffixIcon: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    AnimatedSwitcher(
                      duration: Anim.fast,
                      transitionBuilder: (c, a) =>
                          ScaleTransition(scale: a, child: c),
                      child: _query.isEmpty
                          ? const SizedBox(key: ValueKey('sin'))
                          : IconButton(
                              key: const ValueKey('con'),
                              icon: const Icon(Icons.close),
                              onPressed: () {
                                _search.clear();
                                setState(() => _query = '');
                              },
                            ),
                    ),
                    IconButton(
                      tooltip: tr('Filtros'),
                      onPressed: () async {
                        final f =
                            await showFiltersSheet(context, repo, _filters);
                        if (f != null && mounted) {
                          setState(() => _filters = f);
                        }
                      },
                      icon: Badge(
                        isLabelVisible: _filters.isActive,
                        label: Text('${_filters.count}'),
                        backgroundColor: Palette.accent(context),
                        child: Icon(Icons.tune_rounded,
                            color: _filters.isActive
                                ? Palette.accent(context)
                                : null),
                      ),
                    ),
                  ],
                ),
                isDense: true,
                filled: true,
                fillColor: Palette.searchFill(context),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          Expanded(
            child: AnimatedSwitcher(
              duration: Anim.medium,
              transitionBuilder: fadeThrough,
              child: KeyedSubtree(
                // En pantalla ancha, Todas / Red / Calendario muestran las
                // mismas notas: misma clave = sin animación de transición.
                key: ValueKey('${wide && const {
                          'todas',
                          'red',
                          'calendario'
                        }.contains(_filter) ? 'todas' : _filter}'
                    '-${all.isEmpty}-${q.isEmpty && !_filters.isActive}'),
                child: body,
              ),
            ),
          ),
        ],
      ),
      // Barra inferior: asistente (aparte, a la izquierda) · nº de notas ·
      // notas · red · calendario · nueva carpeta · nueva nota.
      bottomNavigationBar: SafeArea(
        child: AnimatedSwitcher(
          duration: Anim.medium,
          transitionBuilder: (c, a) => FadeTransition(
            opacity: a,
            child: SlideTransition(
              position: Tween(begin: const Offset(0, 0.3), end: Offset.zero)
                  .animate(CurvedAnimation(parent: a, curve: Anim.curve)),
              child: c,
            ),
          ),
          child: _selecting
              ? _selectionBar(context)
              : SizedBox(
                  key: const ValueKey('barra-normal'),
                  height: 58,
                  child: Row(
                    children: [
                      const SizedBox(width: 8),
                      _BarButton(
                        tooltip: isDesktopWindows
                            ? '${tr('Asistente IA')} (Ctrl+J)'
                            : tr('Asistente IA'),
                        icon: Icons.auto_awesome_outlined,
                        onTap: _openAssistant,
                      ),
                      // Separado del resto de botones.
                      Container(
                        width: 1,
                        height: 26,
                        margin: const EdgeInsets.symmetric(horizontal: 8),
                        color: Palette.separator(context),
                      ),
                      const Spacer(),
                      // En el móvil la lista, el calendario y la red ocupan la misma
                      // pantalla: botón para volver a las notas.
                      if (!wide) ...[
                        _BarButton(
                          tooltip: tr('Notas'),
                          icon: _listShown(noteOpen)
                              ? Icons.sticky_note_2
                              : Icons.sticky_note_2_outlined,
                          active: _listShown(noteOpen),
                          onTap: () {
                            if (noteOpen) _close();
                            if (_filter == 'red' || _filter == 'calendario') {
                              _setFilter('todas');
                            }
                          },
                        ),
                        const SizedBox(width: 4),
                      ],
                      for (final (view, tip, on, off) in [
                        (
                          'red',
                          tr('Red de notas'),
                          Icons.hub,
                          Icons.hub_outlined
                        ),
                        (
                          'calendario',
                          tr('Calendario'),
                          Icons.calendar_month,
                          Icons.calendar_month_outlined
                        ),
                      ]) ...[
                        _BarButton(
                          // En escritorio el atajo de teclado va en la ayuda.
                          tooltip: isDesktopWindows
                              ? '$tip (Ctrl+${view == 'red' ? 3 : 2})'
                              : tip,
                          // Solo se ve activo cuando la vista está a la vista: con
                          // una nota abierta encima no se queda "pulsado".
                          icon: _viewShown(view, wide, noteOpen) ? on : off,
                          active: _viewShown(view, wide, noteOpen),
                          onTap: () {
                            if (noteOpen &&
                                (_filter == view ||
                                    (wide &&
                                        view == 'calendario' &&
                                        _filter != 'red'))) {
                              _close(); // volver a la red / al calendario
                            } else if (wide) {
                              // En pantalla ancha el calendario es la vista por
                              // defecto: la red se activa y desactiva.
                              _setFilter(view == 'red' && _filter == 'red'
                                  ? 'todas'
                                  : view);
                            } else {
                              _setFilter(_filter == view ? 'todas' : view);
                            }
                          },
                        ),
                        const SizedBox(width: 4),
                      ],
                      _BarButton(
                        tooltip: tr('Nueva carpeta'),
                        icon: Icons.create_new_folder_outlined,
                        onTap: () async {
                          final f = await editFolderDialog(context, repo);
                          if (f != null && !_openFolders.contains(f.id)) {
                            _toggleFolder(f.id);
                          }
                        },
                      ),
                      const SizedBox(width: 4),
                      _BarButton(
                        tooltip: tr('Nueva nota (Ctrl+N)'),
                        glyph: NewNoteIcon(color: Palette.accent(context)),
                        onTap: _newNote,
                      ),
                      const SizedBox(width: 8),
                    ],
                  ),
                ),
        ),
      ),
    );
  }

  void _setSort(String v) {
    setState(() => _sort = v);
    SharedPreferences.getInstance()
        .then((p) => p.setString(_kSort, v))
        .catchError((_) => false);
  }

  Widget _sortMenu(BuildContext context) =>
      SortMenu(value: _sort, onChanged: _setSort);

  /// Menú ⋯: panel animado con la cuenta arriba y las opciones por
  /// secciones (sale del botón, alineado a su derecha).
  Future<void> _openMainMenu(BuildContext btnContext) async {
    final box = btnContext.findRenderObject() as RenderBox;
    final at = box.localToGlobal(box.size.bottomRight(Offset.zero));
    final email = Supabase.instance.client.auth.currentUser?.email;
    final v = await Updater.instance.currentVersion().catchError((_) => '');
    final desktop = DesktopIntegration.instance;
    if (!mounted) return;
    final choice = await showContextMenu(
      context,
      position: at + const Offset(0, 4),
      alignRight: true,
      width: 290,
      header: _MenuHeader(email: email, version: v),
      entries: [
        MenuEntry.section(tr('Notas')),
        MenuEntry('plantillas', Icons.dashboard_customize_outlined,
            tr('Nueva desde plantilla')),
        MenuEntry('archivadas', Icons.archive_outlined, tr('Archivadas')),
        MenuEntry('completadas', Icons.task_alt_rounded, tr('Completadas')),
        MenuEntry('papelera', Icons.delete_outline, tr('Papelera')),
        MenuEntry('asistente', Icons.auto_awesome_outlined, tr('Asistente IA'),
            subtitle: tr('Con tu clave de Gemini')),
        MenuEntry('pomodoro', Icons.timer_outlined, tr('Pomodoro'),
            subtitle: Pomodoro.instance.running
                ? tr('En marcha')
                : tr('Concéntrate 25 minutos')),
        MenuEntry('productividad', Icons.insights_rounded, tr('Productividad')),
        MenuEntry('foto-tareas', Icons.add_a_photo_outlined,
            tr('Tareas desde una foto')),
        MenuEntry('vault', Icons.shield_outlined, 'Vault',
            subtitle: vault.unlocked
                ? tr('Abierto')
                : tr('Notas protegidas con contraseña')),
        if (vault.unlocked)
          MenuEntry(
              'vault-lock', Icons.lock_outline_rounded, tr('Bloquear Vault')),
        null,
        MenuEntry('coffee', Icons.coffee_outlined, tr('Invítame a un café'),
            subtitle: tr('Apoya el proyecto (open source)')),
        MenuEntry('github', Icons.code_rounded, tr('Código en GitHub')),
        if (desktop.supported) ...[
          null,
          MenuEntry('teclas', Icons.keyboard_rounded, tr('Teclas rápidas'),
              hint: 'Ctrl+/'),
          MenuEntry('salir', Icons.power_settings_new_rounded,
              tr('Salir de Oganesson'),
              subtitle: tr('Cerrar la ventana solo la oculta')),
        ],
        null,
        MenuEntry('logout', Icons.logout, tr('Cerrar sesión'), danger: true),
      ],
    );
    if (!mounted || choice == null) return;
    await _runMenuChoice(choice);
  }

  double _settingsTurns = 0;

  /// Ajustes: apariencia, datos, cuenta y opciones de la app.
  Future<void> _openSettings(BuildContext btnContext) async {
    setState(() => _settingsTurns += 0.25);
    final box = btnContext.findRenderObject() as RenderBox;
    final at = box.localToGlobal(box.size.bottomRight(Offset.zero));
    final desktop = DesktopIntegration.instance;
    final withWindows = desktop.supported && await desktop.startsWithWindows();
    if (!mounted) return;
    final choice = await showContextMenu(
      context,
      position: at + const Offset(0, 4),
      alignRight: true,
      width: 290,
      title: tr('Ajustes'),
      entries: [
        MenuEntry.section(tr('Apariencia')),
        MenuEntry('tema', Icons.palette_outlined, tr('Tema y colores')),
        MenuEntry('idioma', Icons.translate_rounded, tr('Idioma'),
            hint: AppLanguage.supported[appLanguage.code]),
        MenuEntry.section(tr('Datos')),
        MenuEntry('exportar', Icons.ios_share_rounded, tr('Exportar notas'),
            subtitle: tr('Copia, Markdown, PDF o calendario')),
        MenuEntry('importar', Icons.download_rounded, tr('Importar copia')),
        MenuEntry('importar-ics', Icons.event_available_rounded,
            tr('Importar calendario'),
            subtitle: tr('Archivo .ics')),
        MenuEntry('sync', Icons.sync, tr('Sincronizar ahora')),
        MenuEntry.section(tr('Cuenta')),
        MenuEntry('amigos', Icons.group_outlined, tr('Tu @nombre y amigos')),
        MenuEntry('cuenta-pass', Icons.manage_accounts_outlined,
            tr('Cambiar contraseña de la cuenta')),
        if (vault.state == VaultState.locked || vault.unlocked)
          MenuEntry('vault-pass', Icons.password_rounded,
              tr('Cambiar contraseña del Vault')),
        MenuEntry.section(tr('Aplicación')),
        MenuEntry('avisos', Icons.notifications_active_outlined, tr('Avisos'),
            subtitle: tr('Cuándo recordarte tus tareas')),
        MenuEntry('update', Icons.system_update_alt_rounded,
            tr('Buscar actualizaciones')),
        if (desktop.supported)
          MenuEntry(
              'arranque',
              withWindows
                  ? Icons.check_box_rounded
                  : Icons.check_box_outline_blank_rounded,
              tr('Abrir al iniciar Windows'),
              subtitle: tr('En segundo plano · Ctrl+Alt+N crea una nota')),
        null,
        MenuEntry('borrar-todo', Icons.delete_sweep_outlined,
            tr('Borrar todas las notas'),
            danger: true),
      ],
    );
    if (!mounted || choice == null) return;
    await _runMenuChoice(choice, withWindows: withWindows);
  }

  /// Manda todo a la papelera tras confirmarlo. Se puede deshacer.
  Future<void> _confirmDeleteAll() async {
    final count = repo.allActive
        .where((n) => !n.vault && !n.isEmpty && !repo.isForeign(n))
        .length;
    if (count == 0) {
      showToast(context, tr('No hay notas que borrar'),
          icon: Icons.info_outline_rounded);
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.delete_sweep_outlined),
        title: Text(tr('¿Borrar todas las notas?')),
        content: Text(trf(
            '{0} notas y eventos irán a la papelera y se borrarán del todo en 3 días, también en tus otros dispositivos. El Vault y las notas que te han compartido no se tocan.',
            [count])),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(tr('Cancelar'))),
          FilledButton(
              style: FilledButton.styleFrom(
                  backgroundColor: Theme.of(ctx).colorScheme.error,
                  foregroundColor: Theme.of(ctx).colorScheme.onError),
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(tr('Borrar todo'))),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    _close();
    _clearPicked();
    final ids = repo.deleteAllNotes();
    showToast(context, trf('{0} notas en la papelera', [ids.length]),
        icon: Icons.delete_outline_rounded,
        actionLabel: tr('Deshacer'), onAction: () {
      for (final id in ids) {
        repo.restore(id);
      }
    });
  }

  Future<void> _runMenuChoice(String choice, {bool withWindows = false}) async {
    final desktop = DesktopIntegration.instance;
    switch (choice) {
      case 'avisos':
        await showReminderSettings(context);
      case 'teclas':
        await showShortcuts(context);
      case 'borrar-todo':
        await _confirmDeleteAll();
      case 'pomodoro':
        await showPomodoro(context);
      case 'productividad':
        await showProductivity(context, repo);
      case 'foto-tareas':
        await tasksFromPhoto(context, repo, onOpen: _open);
      case 'plantillas':
        await _fromTemplate();
      case 'exportar':
        await showExportAll(context, repo);
      case 'importar':
        await importBackupFile(context, repo);
      case 'importar-ics':
        await importCalendarFile(context, repo);
      case 'tema':
        showThemePicker(context);
      case 'idioma':
        showLanguagePicker(context);
      case 'asistente':
        _openAssistant();
      case 'vault':
        _openVault();
      case 'vault-lock':
        vault.lock();
      case 'vault-pass':
        changeVaultPassword(context, vault);
      case 'archivadas':
        showArchived(context, repo);
      case 'completadas':
        showCompleted(context, repo);
      case 'papelera':
        showTrash(context, repo);
      case 'sync':
        repo.sync();
      case 'update':
        checkForUpdatesManually(context);
      case 'amigos':
        await showFriendsSheet(context, repo);
      case 'cuenta-pass':
        changeAccountPassword(context);
      case 'coffee':
        openLink(context, AppConfig.coffeeUrl);
      case 'github':
        openLink(context, AppConfig.githubUrl);
      case 'arranque':
        await desktop.setStartsWithWindows(!withWindows);
        if (mounted) {
          showToast(
              context,
              !withWindows
                  ? tr('Oganesson se abrirá al iniciar Windows')
                  : tr('Oganesson ya no se abrirá al iniciar Windows'),
              icon: Icons.power_settings_new_rounded);
        }
      case 'salir':
        await desktop.quit();
      case 'logout':
        _signOut();
    }
  }

  /// ¿Se está viendo [view] (red o calendario)? En pantalla ancha el
  /// calendario se ve siempre que no haya nota abierta ni red elegida.
  /// ¿Se ve la lista de notas? (móvil: ni nota abierta, ni calendario, ni red).
  bool _listShown(bool noteOpen) =>
      !noteOpen && _filter != 'red' && _filter != 'calendario';

  bool _viewShown(String view, bool wide, bool noteOpen) {
    if (noteOpen) return false;
    if (wide && view == 'calendario') return _filter != 'red';
    return _filter == view;
  }

  /// Opciones de una carpeta (clic derecho o pulsación larga).
  Future<void> _folderOptions(Folder f, Offset? at) async {
    final entries = [
      MenuEntry('new', Icons.note_add_outlined, tr('Nueva nota aquí')),
      MenuEntry('edit', Icons.edit_outlined, tr('Editar carpeta')),
    ];
    String? choice;
    if (at != null) {
      choice = await showContextMenu(context,
          position: at, title: f.name, entries: entries);
    } else {
      choice = await showModalBottomSheet<String>(
        context: context,
        useSafeArea: true,
        showDragHandle: true,
        builder: (ctx) => SafeArea(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            for (final e in entries)
              ListTile(
                leading: Icon(e.icon),
                title: Text(e.label),
                onTap: () => Navigator.pop(ctx, e.value),
              ),
          ]),
        ),
      );
    }
    if (!mounted) return;
    if (choice == 'new') {
      if (!_openFolders.contains(f.id)) _toggleFolder(f.id);
      _newNote(folderId: f.id);
    } else if (choice == 'edit') {
      await editFolderDialog(context, repo, folder: f);
    }
  }

  /// Tarjeta con las filas de unas notas.
  Widget _tilesCard(BuildContext context, List<Note> notes, bool wide,
      int Function() nextIndex) {
    final tiles = <Widget>[];
    // Fuera de la ventana de entrada las filas aparecen ya colocadas
    // (value: 1), sin cambiar el árbol para no perder su estado.
    final entering = _entranceOpen;
    for (var i = 0; i < notes.length; i++) {
      final n = notes[i];
      final order = nextIndex();
      tiles.add(KeyedSubtree(
        key: ValueKey('fila-${n.id}'),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (i > 0)
              Divider(height: 1, indent: 16, color: Palette.separator(context)),
            _NoteTile(
              removing: _removing.contains(n.id),
              checked: _picked.contains(n.id),
              selecting: _selecting,
              shared: repo.isShared(n),
              foreign: repo.isForeign(n),
              note: n,
              selected: wide && n.id == _openId,
              onTap: () {
                // Ctrl+clic selecciona; con selección activa, cada toque
                // marca o desmarca.
                if (_selecting || HardwareKeyboard.instance.isControlPressed) {
                  _togglePick(n.id);
                } else {
                  _open(n.id);
                }
              },
              onOptions: (at) => _options(n, at),
              onDismissed: (d) => d == DismissDirection.startToEnd
                  ? _deleteNote(n.id)
                  : _archiveNote(n.id),
              onDropBefore: (dragged) => _dropBefore(dragged, n, notes),
              onDropAfter: (dragged) =>
                  _dropBefore(dragged, n, notes, after: true),
              onDragMove: _autoScroll,
              onDragState: (_) {},
            ),
          ],
        )
            .animate(
                delay: entering ? (min(order, 10) * 40).ms : Duration.zero,
                value: _rowIntro.putIfAbsent(
                        n.id, () => entering || !_prevKnownIds.contains(n.id))
                    ? null
                    : 1)
            .fadeIn(duration: Anim.medium)
            .slideY(begin: 0.25, curve: Anim.curve, duration: Anim.slow),
      ));
    }
    return AnimatedSize(
      duration: Anim.medium,
      curve: Anim.curve,
      alignment: Alignment.topCenter,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Material(
          color: Palette.card(context),
          child: Column(children: tiles),
        ),
      ),
    );
  }

  List<Widget> _section(BuildContext context, String? title, List<Note> notes,
      bool wide, int Function() nextIndex,
      {void Function(String id)? onDrop}) {
    final header = title == null
        ? const SizedBox(height: 8)
        : Padding(
            padding: const EdgeInsets.fromLTRB(6, 8, 4, 6),
            child: Text(title,
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.3,
                    color: Palette.secondary(context))),
          );
    return [
      KeyedSubtree(
        key: ValueKey('titulo-$title'),
        child:
            onDrop == null ? header : DropZone(onDrop: onDrop, child: header),
      ),
      if (notes.isNotEmpty)
        KeyedSubtree(
          key: ValueKey('seccion-$title'),
          child: _tilesCard(context, notes, wide, nextIndex),
        ),
    ];
  }

  // ------------------------------------------------------ arrastrar y soltar

  int _byPosition(Note a, Note b) {
    final pa = a.position, pb = b.position;
    if (pa != null && pb != null) return pa.compareTo(pb);
    if (pa != null) return -1;
    if (pb != null) return 1;
    return b.updatedAt.compareTo(a.updatedAt);
  }

  /// Pasa al orden personalizado conservando el orden que se ve ahora.
  void _ensureManualOrder() {
    if (_sort == 'manual') return;
    final list = repo.notes.toList();
    switch (_sort) {
      case 'creada':
        list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      case 'nombre':
        list.sort(
            (a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
      default:
        list.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    }
    repo.setPositions({
      for (var i = 0; i < list.length; i++) list[i].id: i * 1000.0,
    });
    _setSort('manual');
    showToast(context, tr('Orden personalizado'),
        icon: Icons.drag_indicator_rounded);
  }

  /// Soltar una nota encima de otra: se coloca justo antes, en su grupo
  /// (fijadas, su carpeta o sin carpeta).
  void _dropBefore(String draggedId, Note target, List<Note> group,
      {bool after = false}) {
    final dragged = repo.byId(draggedId);
    if (dragged == null || draggedId == target.id) return;
    _ensureManualOrder();
    // Notas sin posición (p. ej. tareas creadas desde el calendario o la IA
    // después de ordenar): se numeran como se ven antes de colocar nada, si
    // no la nota soltada acababa lejos de donde se dejó.
    if (group.any((n) => n.position == null)) {
      final seen = group.toList()..sort(_byPosition);
      repo.setPositions(
          {for (var i = 0; i < seen.length; i++) seen[i].id: i * 1000.0});
    }
    final g = group.where((n) => n.id != draggedId).toList()..sort(_byPosition);
    final i = g.indexWhere((n) => n.id == target.id);
    final cur = target.position ?? 0;
    final double pos;
    if (after) {
      final next = i + 1 < g.length ? g[i + 1].position : null;
      pos = next == null ? cur + 1000 : (cur + next) / 2;
    } else {
      final prev = i > 0 ? g[i - 1].position : null;
      pos = prev == null ? cur - 1000 : (prev + cur) / 2;
    }
    repo.moveNote(draggedId,
        folderId: target.pinned ? dragged.folderId : target.folderId,
        position: pos);
    if (dragged.pinned != target.pinned) repo.togglePin(draggedId);
  }

  /// Arrastrando cerca del borde de arriba o de abajo, la lista se
  /// desplaza sola (más rápido cuanto más cerca del borde).
  void _autoScroll(Offset global) {
    if (!_listScroll.hasClients) return;
    final pos = _listScroll.position;
    final box =
        pos.context.notificationContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return;
    final y = box.globalToLocal(global).dy;
    const edge = 60.0;
    double delta = 0;
    if (y < edge) {
      delta = -14 * (1 - (y / edge).clamp(0.0, 1.0));
    } else if (y > box.size.height - edge) {
      delta = 14 * (1 - ((box.size.height - y) / edge).clamp(0.0, 1.0));
    }
    if (delta == 0) return;
    pos.jumpTo(
        (pos.pixels + delta).clamp(pos.minScrollExtent, pos.maxScrollExtent));
  }

  /// Soltar una nota en una carpeta, en "Sin carpeta" o en "Fijadas".
  void _dropInto(String id, {required String? folderId, bool pin = false}) {
    final n = repo.byId(id);
    if (n == null) return;
    if (pin) {
      if (!n.pinned) repo.togglePin(id);
      return;
    }
    // Al final del grupo si hay orden personalizado.
    double? pos;
    if (_sort == 'manual') {
      final ps = repo.notes
          .where((x) => x.folderId == folderId && x.position != null)
          .map((x) => x.position!);
      pos = ps.isEmpty ? 0 : ps.reduce(max) + 1000;
    }
    repo.moveNote(id, folderId: folderId, position: pos);
    if (n.pinned) repo.togglePin(id);
    if (folderId != null && !_openFolders.contains(folderId)) {
      _toggleFolder(folderId);
    }
  }

  void _archiveNote(String id) {
    if (_openId == id) {
      setState(() {
        _openId = null;
        _discarding = true;
      });
    }
    repo.setArchived(id, true);
    showToast(
      context,
      tr('Nota archivada'),
      icon: Icons.archive_outlined,
      actionLabel: tr('Deshacer'),
      onAction: () => repo.setArchived(id, false),
    );
  }
}

class _NoteTile extends StatefulWidget {
  const _NoteTile({
    required this.removing,
    this.checked = false,
    this.selecting = false,
    this.shared = false,
    this.foreign = false,
    required this.note,
    required this.selected,
    required this.onTap,
    required this.onOptions,
    required this.onDismissed,
    required this.onDropBefore,
    required this.onDropAfter,
    required this.onDragState,
    required this.onDragMove,
  });

  final bool removing;

  /// Marcada en la selección múltiple / hay selección activa.
  final bool checked;
  final bool selecting;

  /// Compartida con alguien / de otra cuenta.
  final bool shared;
  final bool foreign;
  final Note note;
  final bool selected;
  final VoidCallback onTap;

  /// Opciones de la nota: con posición = clic derecho (menú contextual).
  final void Function(Offset? at) onOptions;

  /// Deslizar: hacia la derecha elimina, hacia la izquierda archiva.
  final void Function(DismissDirection direction) onDismissed;

  /// Se ha soltado otra nota en la mitad de arriba: colocarla antes.
  final void Function(String draggedId) onDropBefore;

  /// Se ha soltado otra nota en la mitad de abajo: colocarla después.
  final void Function(String draggedId) onDropAfter;

  /// El cursor se mueve arrastrando esta nota (para desplazar la lista).
  final void Function(Offset globalPosition) onDragMove;

  /// Empieza (true) o termina (false) el arrastre de esta nota.
  final void Function(bool dragging) onDragState;

  @override
  State<_NoteTile> createState() => _NoteTileState();
}

class _NoteTileState extends State<_NoteTile> {
  bool _hover = false;
  bool _dropHover = false; // otra nota arrastrada encima
  bool _dropAfter = false; // ...en la mitad de abajo

  /// Deslizamiento en curso (dirección y cuánto), para dibujar el fondo.
  DismissDirection? _swipeDir;
  double _swipeProgress = 0;

  /// Punto de la nota arrastrada que queda bajo el cursor.
  static const _anchor = Offset(26, 22);
  double _dragDistance = 0;

  @override
  Widget build(BuildContext context) {
    final n = widget.note;
    // Resaltado limpio: una pastilla redondeada con margen (no toda la fila).
    final bg = widget.selected || widget.checked
        ? Palette.selected(context)
        : (_hover ? Palette.hover(context) : Palette.card(context));

    final scheme = Theme.of(context).colorScheme;
    // Fondo al deslizar: tinte suave del color de la acción sobre la
    // tarjeta (en armonía con el tema), con el icono y el texto en ese color.
    Widget swipeBg(Color color, IconData icon, String label, bool left) {
      final content = [
        Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.18),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, size: 17, color: color),
        ),
        const SizedBox(width: 10),
        Text(label,
            style: TextStyle(
                color: color, fontWeight: FontWeight.w700, fontSize: 13.5)),
      ];
      return Container(
        margin: const EdgeInsets.symmetric(horizontal: 5, vertical: 3),
        decoration: BoxDecoration(
          color: Color.alphaBlend(
              color.withValues(alpha: 0.14), Palette.card(context)),
          borderRadius: BorderRadius.circular(10),
        ),
        alignment: left ? Alignment.centerLeft : Alignment.centerRight,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: left ? content : content.reversed.toList(),
        ),
      );
    }

    // El fondo de Dismissible se recorta en rectángulo: en su lugar se
    // dibuja detrás la pastilla redondeada completa según la dirección.
    final dismissible = Dismissible(
      key: ValueKey('desliza-${n.id}'),
      // Con selección activa no se desliza ni se arrastra.
      direction: widget.selecting || widget.foreign
          ? DismissDirection.none
          : DismissDirection.horizontal,
      background: const SizedBox.shrink(),
      onUpdate: (d) {
        final dir = d.progress > 0 ? d.direction : null;
        if (dir != _swipeDir || (d.progress - _swipeProgress).abs() > 0.01) {
          setState(() {
            _swipeDir = dir;
            _swipeProgress = d.progress;
          });
        }
      },
      // Doble comprobación en los dos casos.
      confirmDismiss: (d) => d == DismissDirection.startToEnd
          ? confirmDelete(context, n.title)
          : confirmArchive(context, n.title),
      onDismissed: widget.onDismissed,
      child: MouseRegion(
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: Bouncy(
          pressedScale: 0.975,
          child: AnimatedContainer(
            duration: Anim.medium,
            curve: Anim.curve,
            margin: const EdgeInsets.symmetric(horizontal: 5, vertical: 3),
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(10),
            ),
            child: InkWell(
              // El fondo ya cambia con _hover: sin capa gris del InkWell.
              hoverColor: Colors.transparent,
              borderRadius: BorderRadius.circular(10),
              onTap: widget.onTap,
              // En Android la pulsación larga arrastra la nota (si se suelta
              // sin moverla, abre las opciones).
              onLongPress: _touchDrag ? null : () => widget.onOptions(null),
              onSecondaryTapUp: (d) => widget.onOptions(d.globalPosition),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
                child: Row(
                  children: [
                    // Casilla de la selección múltiple.
                    AnimatedSize(
                      duration: Anim.medium,
                      curve: Anim.curve,
                      child: widget.selecting
                          ? Padding(
                              padding: const EdgeInsets.only(right: 10),
                              child: AnimatedSwitcher(
                                duration: Anim.fast,
                                transitionBuilder: (c, a) =>
                                    ScaleTransition(scale: a, child: c),
                                child: Icon(
                                  widget.checked
                                      ? Icons.check_circle_rounded
                                      : Icons.radio_button_unchecked_rounded,
                                  key: ValueKey(widget.checked),
                                  size: 22,
                                  color: widget.checked
                                      ? Palette.accent(context)
                                      : Palette.secondary(context),
                                ),
                              ),
                            )
                          : const SizedBox.shrink(),
                    ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            n.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 16, fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(height: 3),
                          Row(
                            children: [
                              Text(fechaCorta(n.updatedAt),
                                  style: const TextStyle(fontSize: 14)),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  n.preview,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                      fontSize: 14,
                                      color: Palette.secondary(context)),
                                ),
                              ),
                            ],
                          ),
                          if (n.isTemporal) ...[
                            const SizedBox(height: 7),
                            Row(
                              children: [
                                Icon(Icons.alarm,
                                    size: 13, color: urgencyColor(context, n)),
                                const SizedBox(width: 6),
                                Expanded(
                                    child: TimeBar(note: n, compact: true)),
                                const SizedBox(width: 8),
                                Text(tiempoNota(n),
                                    style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                        color: urgencyColor(context, n))),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                    // Miniatura de la primera imagen (como en Notas de iPhone).
                    if (NoteImages.firstPathIn(n.rich) case final path?)
                      NoteThumb(path: path),
                    if (widget.shared)
                      Padding(
                        padding: const EdgeInsets.only(left: 8),
                        child: Tooltip(
                          message: tr('Nota compartida'),
                          child: Icon(Icons.group_outlined,
                              size: 16, color: Palette.secondary(context)),
                        ),
                      ),
                    AnimatedSwitcher(
                      duration: Anim.medium,
                      transitionBuilder: (c, a) =>
                          ScaleTransition(scale: a, child: c),
                      child: n.pinned
                          ? Padding(
                              key: const ValueKey('pin'),
                              padding: const EdgeInsets.only(left: 8),
                              child: Icon(Icons.push_pin,
                                  size: 16, color: Palette.accent(context)),
                            )
                          : const SizedBox(key: ValueKey('nopin')),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );

    // Hacia la derecha: eliminar. Hacia la izquierda: archivar.
    final tile = Stack(
      children: [
        if (_swipeDir != null)
          Positioned.fill(
            child: Opacity(
              opacity: (_swipeProgress * 4).clamp(0.0, 1.0),
              child: _swipeDir == DismissDirection.startToEnd
                  ? swipeBg(scheme.error, Icons.delete_outline_rounded,
                      tr('Eliminar'), true)
                  : swipeBg(Palette.accent(context), Icons.archive_outlined,
                      tr('Archivar'), false),
            ),
          ),
        dismissible,
      ],
    );

    // Al borrar: la fila se desliza, se desvanece y se pliega.
    final animated = ClipRect(
      child: AnimatedAlign(
        duration: Anim.medium,
        curve: Curves.easeInOutCubic,
        alignment: Alignment.topCenter,
        heightFactor: widget.removing ? 0 : 1,
        child: AnimatedSlide(
          duration: Anim.medium,
          curve: Curves.easeInCubic,
          offset: widget.removing ? const Offset(-0.25, 0) : Offset.zero,
          child: AnimatedOpacity(
            duration: Anim.fast,
            opacity: widget.removing ? 0 : 1,
            child: tile,
          ),
        ),
      ),
    );

    // Soltar otra nota encima: línea de inserción arriba.
    // Soltar otra nota encima: en la mitad de arriba va antes, en la de
    // abajo después (la línea de inserción lo muestra).
    final target = DragTarget<String>(
      onWillAcceptWithDetails: (d) => d.data != n.id,
      onMove: (d) {
        if (d.data == n.id) return;
        final box = context.findRenderObject() as RenderBox?;
        if (box == null) return;
        final local = box.globalToLocal(d.offset + _anchor);
        final after = local.dy > box.size.height / 2;
        if (!_dropHover || after != _dropAfter) {
          setState(() {
            _dropHover = true;
            _dropAfter = after;
          });
        }
      },
      onLeave: (_) => setState(() => _dropHover = false),
      onAcceptWithDetails: (d) {
        final after = _dropAfter;
        setState(() => _dropHover = false);
        after ? widget.onDropAfter(d.data) : widget.onDropBefore(d.data);
      },
      builder: (context, _, __) => Stack(
        children: [
          animated,
          AnimatedPositioned(
            duration: Anim.fast,
            curve: Anim.curve,
            left: 14,
            right: 14,
            top: _dropAfter ? null : 0,
            bottom: _dropAfter ? 0 : null,
            child: AnimatedContainer(
              duration: Anim.fast,
              height: _dropHover ? 3 : 0,
              decoration: BoxDecoration(
                color: Palette.accent(context),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
        ],
      ),
    );

    // Arrastrar la nota: con el ratón en vertical (lo horizontal es deslizar)
    // y en el móvil con pulsación larga.
    return LayoutBuilder(builder: (context, c) {
      if (widget.selecting || widget.foreign) return animated;
      final feedback = Material(
        color: Colors.transparent,
        child: Container(
          width: c.maxWidth,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: Palette.card(context),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Palette.accent(context), width: 1.5),
            boxShadow: [
              BoxShadow(
                color: Theme.of(context).shadowColor.withValues(alpha: 0.3),
                blurRadius: 18,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Row(
            children: [
              Icon(Icons.drag_indicator_rounded,
                  size: 18, color: Palette.secondary(context)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(n.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w600)),
              ),
            ],
          ),
        ),
      );
      final dimmed = Opacity(opacity: 0.35, child: animated);
      void started() {
        _dragDistance = 0;
        widget.onDragState(true);
      }

      void ended() => widget.onDragState(false);
      if (_touchDrag) {
        return LongPressDraggable<String>(
          data: n.id,
          feedback: feedback,
          childWhenDragging: dimmed,
          hapticFeedbackOnStart: true,
          onDragStarted: started,
          dragAnchorStrategy: (_, __, ___) => _anchor,
          onDragUpdate: (d) {
            _dragDistance += d.delta.distance;
            widget.onDragMove(d.globalPosition);
          },
          onDragEnd: (d) {
            ended();
            // Soltada casi sin moverla: era una pulsación larga normal.
            if (!d.wasAccepted && _dragDistance < 14) widget.onOptions(null);
          },
          child: target,
        );
      }
      return Draggable<String>(
        data: n.id,
        affinity: Axis.vertical,
        feedback: feedback,
        childWhenDragging: dimmed,
        dragAnchorStrategy: (_, __, ___) => _anchor,
        onDragUpdate: (d) => widget.onDragMove(d.globalPosition),
        onDragStarted: started,
        onDragEnd: (_) => ended(),
        child: target,
      );
    });
  }

  /// En pantallas táctiles (Android) se arrastra con pulsación larga.
  bool get _touchDrag => !kIsWeb && Platform.isAndroid;
}

class _SyncIndicator extends StatelessWidget {
  const _SyncIndicator({required this.repo});
  final NotesRepository repo;

  @override
  Widget build(BuildContext context) {
    final (Widget icon, String tip) = switch (repo.status) {
      SyncStatus.syncing => (
          const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2)),
          tr('Sincronizando…')
        ),
      SyncStatus.synced => (
          const Icon(Icons.cloud_done_outlined),
          tr('Todo sincronizado')
        ),
      SyncStatus.pending => (
          const Icon(Icons.cloud_upload_outlined),
          tr('Subiendo cambios…')
        ),
      SyncStatus.offline => (
          const Icon(Icons.cloud_off_outlined),
          tr('Sin conexión: los cambios se subirán al volver internet')
        ),
    };
    return IconButton(
      tooltip: tip,
      onPressed: repo.sync,
      icon: AnimatedSwitcher(
        duration: Anim.medium,
        transitionBuilder: (c, a) => FadeTransition(
          opacity: a,
          child: ScaleTransition(
            scale: Tween(begin: 0.5, end: 1.0)
                .animate(CurvedAnimation(parent: a, curve: Curves.easeOutBack)),
            child: c,
          ),
        ),
        child: KeyedSubtree(key: ValueKey(repo.status), child: icon),
      ),
    );
  }
}

class _EmptyList extends StatelessWidget {
  const _EmptyList({required this.searching, this.timeView = false});
  final bool searching;
  final bool timeView;

  @override
  Widget build(BuildContext context) {
    final color = Palette.secondary(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
                  searching
                      ? Icons.search_off
                      : (timeView
                          ? Icons.alarm_outlined
                          : Icons.sticky_note_2_outlined),
                  size: 56,
                  color: color)
              .animate(onPlay: (c) => c.repeat(reverse: true))
              .moveY(
                  begin: 0,
                  end: -6,
                  duration: 1600.ms,
                  curve: Curves.easeInOut),
          const SizedBox(height: 12),
          Text(
              searching
                  ? tr('Sin resultados')
                  : (timeView
                      ? tr('No hay notas temporales')
                      : tr('Aún no hay notas aquí')),
              style: TextStyle(color: color, fontSize: 16)),
          if (timeView && !searching) ...[
            const SizedBox(height: 6),
            Text(tr('Crea una con el lápiz y ponle fecha límite'),
                style: TextStyle(color: color, fontSize: 13)),
          ],
        ],
      )
          .animate()
          .fadeIn(duration: Anim.medium)
          .scale(begin: const Offset(0.92, 0.92), curve: Anim.curve),
    );
  }
}

class _BarButton extends StatelessWidget {
  const _BarButton({
    required this.tooltip,
    this.icon,
    this.glyph,
    required this.onTap,
    this.active = false,
  });

  final String tooltip;
  final IconData? icon;

  /// Dibujo propio en lugar de [icon].
  final Widget? glyph;
  final VoidCallback onTap;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final accent = Palette.accent(context);
    return Tooltip(
      message: tooltip,
      waitDuration: const Duration(milliseconds: 400),
      child: Bouncy(
        pressedScale: 0.82,
        hoverScale: 1.08,
        child: GestureDetector(
          onTap: onTap,
          child: AnimatedContainer(
            duration: Anim.medium,
            curve: Anim.curve,
            width: 46,
            height: 42,
            decoration: BoxDecoration(
              color:
                  active ? accent.withValues(alpha: 0.16) : Colors.transparent,
              borderRadius: BorderRadius.circular(13),
            ),
            alignment: Alignment.center,
            child: glyph ?? Icon(icon, size: 24, color: accent),
          ),
        ),
      ),
    );
  }
}

/// Pregunta en el centro de la pantalla antes de archivar una nota.
Future<bool> confirmArchive(BuildContext context, String title) async =>
    await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: Icon(Icons.archive_outlined, color: Palette.accent(ctx)),
        title: Text(trf('¿Archivar «{0}»?', [title])),
        content: Text(tr('La encontrarás en ⋯ → Archivadas.')),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(tr('Cancelar'))),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(tr('Archivar'))),
        ],
      ),
    ) ==
    true;

/// Pregunta en el centro de la pantalla antes de eliminar una nota.
Future<bool> confirmDelete(BuildContext context, String title) async =>
    await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: Icon(Icons.delete_outline_rounded,
            color: Theme.of(ctx).colorScheme.error),
        title: Text(trf('¿Eliminar «{0}»?', [title])),
        content: Text(tr('Irá a la papelera durante 3 días.')),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(tr('Cancelar'))),
          FilledButton(
              style: FilledButton.styleFrom(
                  backgroundColor: Theme.of(ctx).colorScheme.error,
                  foregroundColor: Theme.of(ctx).colorScheme.onError),
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(tr('Eliminar'))),
        ],
      ),
    ) ==
    true;

/// Cabecera del menú ⋯: icono de la cuenta, correo y versión de la app.
class _MenuHeader extends StatelessWidget {
  const _MenuHeader({required this.email, required this.version});
  final String? email;
  final String version;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final initial =
        (email == null || email!.isEmpty) ? 'O' : email![0].toUpperCase();
    return Container(
      margin: const EdgeInsets.fromLTRB(2, 2, 2, 6),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            p.accent.withValues(alpha: 0.22),
            p.accent.withValues(alpha: 0.06),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 18,
            backgroundColor: p.accent,
            child: Text(initial,
                style:
                    TextStyle(color: p.onAccent, fontWeight: FontWeight.w800)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(email ?? 'Oganesson',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 13.5, fontWeight: FontWeight.w700)),
                if (version.isNotEmpty)
                  Text('Oganesson $version',
                      style: TextStyle(fontSize: 11.5, color: p.secondary)),
              ],
            ),
          ),
          // Cerrar sesión siempre a la vista, junto a la cuenta.
          IconButton(
            tooltip: tr('Cerrar sesión'),
            visualDensity: VisualDensity.compact,
            icon: Icon(Icons.logout_rounded,
                size: 19, color: Theme.of(context).colorScheme.error),
            onPressed: () => Navigator.of(context).pop('logout'),
          ),
        ],
      ),
    );
  }
}
