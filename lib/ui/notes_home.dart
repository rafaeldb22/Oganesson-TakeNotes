import 'dart:async';
import 'dart:io' show Platform;
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config.dart';
import '../data/note_links.dart';
import '../data/notes_repository.dart';
import '../data/vault.dart';
import '../data/widget_bridge.dart';
import '../models/note.dart';
import 'anim.dart';
import '../data/updater.dart';
import 'account_dialogs.dart';
import 'archived_sheet.dart';
import 'calendar_view.dart';
import 'completed_sheet.dart';
import 'context_menu.dart';
import 'folders.dart';
import 'folder_group.dart';
import 'drop_zone.dart';
import 'format.dart';
import 'graph_view.dart';
import 'i18n.dart';
import 'language_picker.dart';
import 'link_picker.dart';
import 'note_color_sheet.dart';
import 'note_editor.dart';
import 'schedule_sheet.dart';
import 'sort_menu.dart';
import 'split.dart';
import 'toast.dart';
import 'smooth_scroll.dart';
import 'text_menu.dart';
import 'theme.dart';
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
  String? _openId;
  final Set<String> _removing = {}; // filas que se están plegando
  bool _openAutofocus = false;
  StreamSubscription<Uri?>? _widgetSub;

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
    _widgetSub = WidgetBridge.clicks.listen(_onWidgetUri);
    vault.addListener(_onVault);
    repo.onLocalEdit = vault.touch;
    WidgetBridge.initialUri().then(_onWidgetUri);
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
    _widgetSub?.cancel();
    vault.removeListener(_onVault);
    repo.onLocalEdit = null;
    _search.dispose();
    _searchFocus.dispose();
    _listScroll.dispose();
    super.dispose();
  }

  late final VaultLock vault = VaultLock.forUser(repo.userId);

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

  void _newNote({String? folderId}) {
    final n = repo.createNote(folderId: folderId);
    _open(n.id, autofocus: true);
    if (_filter == 'calendario') {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) showScheduleSheet(context, repo, n.id);
      });
    }
  }

  /// Nueva nota temporal que vence el día elegido en el calendario.
  void _newOnDay(DateTime day) {
    final due = DateTime(day.year, day.month, day.day, 20);
    final n = repo.createNote(
      dueAt: due.toUtc(),
      remindAt: DateTime.now().toUtc().isBefore(due.toUtc())
          ? DateTime.now().toUtc()
          : due.toUtc(),
    );
    _open(n.id, autofocus: true);
  }

  void _setFilter(String f) {
    if (f == _filter) return;
    // Al ir al calendario o a la red se cierra la nota abierta para que se vea.
    if ((f == 'calendario' || f == 'red') && _openId != null) _close();
    setState(() => _filter = f);
  }

  void _open(String id, {bool autofocus = false}) {
    final prev = _openId;
    setState(() {
      _openId = id;
      _openAutofocus = autofocus;
    });
    // Una nota nueva que se dejó vacía se descarta al cambiar de nota.
    if (prev != null && prev != id) repo.finishEditing(prev);
  }

  void _close() {
    final prev = _openId;
    if (prev == null || !mounted) return;
    setState(() => _openId = null);
    repo.finishEditing(prev);
  }

  /// Pliega la fila con animación y después la borra.
  void _deleteAnimated(String id) {
    if (_removing.contains(id)) return;
    if (_openId == id) _openId = null;
    setState(() => _removing.add(id));
    Future.delayed(Anim.medium, () {
      if (!mounted) return;
      _removing.remove(id);
      _deleteNote(id);
    });
  }

  void _deleteNote(String id) {
    final n = repo.byId(id);
    final hadContent = n != null && !n.isEmpty;
    if (_openId == id) setState(() => _openId = null);
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
    final actions = <(String, IconData, String, bool)>[
      ('link', Icons.hub_outlined, tr('Enlazar con otras notas…'), false),
      ('sub', Icons.account_tree_outlined, tr('Crear subnota enlazada'), false),
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
      ('color', Icons.palette_outlined, tr('Color'), false),
      ('folder', Icons.drive_file_move_outline, tr('Mover a carpeta'), false),
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
      choice = await showModalBottomSheet<String>(
        context: context,
        showDragHandle: true,
        builder: (ctx) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
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
      case 'link':
        await showLinkNotesPicker(context, repo, n.id);
      case 'sub':
        final sub = repo.createSubnote(n.id);
        _open(sub.id, autofocus: true);
      case 'pin':
        repo.togglePin(n.id);
      case 'dates':
        showScheduleSheet(context, repo, n.id);
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
      onPointerDown: (_) => vault.touch(),
      onPointerSignal: (_) => vault.touch(),
      child: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.keyN, control: true):
              _newNote,
          const SingleActivator(LogicalKeyboardKey.escape): _close,
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
                          left: _list(context, true),
                          right: AnimatedSwitcher(
                            duration: Anim.medium,
                            switchInCurve: Anim.curve,
                            switchOutCurve: Curves.easeIn,
                            transitionBuilder: fadeThrough,
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
                        // Contador abajo a la derecha de la ventana.
                        Positioned(
                          right: 14,
                          bottom: 8,
                          child: IgnorePointer(
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: Palette.background(context)
                                    .withValues(alpha: 0.85),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: _statusText(context),
                            ),
                          ),
                        ),
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
                  child: AnimatedSwitcher(
                    duration: Anim.slow,
                    transitionBuilder: (child, anim) => pushTransition(
                      child,
                      anim,
                      isPage: child.key != const ValueKey('lista'),
                    ),
                    layoutBuilder: (current, previous) => Stack(
                      fit: StackFit.expand,
                      children: [...previous, if (current != null) current],
                    ),
                    child: hasOpen
                        ? _editor(showBack: true)
                        : KeyedSubtree(
                            key: const ValueKey('lista'),
                            child: _list(context, false),
                          ),
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
    final q = _query.toLowerCase();
    final all = repo.notes
        .where((n) => !n.isEmpty || n.id == _openId)
        .where((n) => q.isEmpty || n.content.toLowerCase().contains(q))
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
    final pinned = all.where((n) => n.pinned).toList();
    final others = all.where((n) => !n.pinned).toList();
    final noteOpen = _openId != null && repo.byId(_openId!) != null;

    Widget body;
    if (!repo.loaded) {
      body = const Center(child: CircularProgressIndicator());
    } else if (_filter == 'calendario' && !wide) {
      body = _calendar();
    } else if (_filter == 'red' && !wide) {
      body = _graph();
    } else if (all.isEmpty && (q.isNotEmpty || repo.folders.isEmpty)) {
      body = _EmptyList(
          searching: q.isNotEmpty, timeView: _filter == 'calendario');
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
                      count: inFolder.where((n) => !n.isEmpty).length,
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
                          : _tilesCard(context, inFolder, wide, () => index++),
                    );
                  },
                ),
            if (loose.isNotEmpty)
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
        title: const FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: WaveTitle(text: 'oganesson', fontSize: 30),
        ).animate().fadeIn(duration: Anim.slow),
        actions: [
          _SyncIndicator(repo: repo),
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
                suffixIcon: AnimatedSwitcher(
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
                    '-${all.isEmpty}-${q.isEmpty}'),
                child: body,
              ),
            ),
          ),
        ],
      ),
      // Barra inferior: nueva carpeta · nº de notas · calendario · nueva nota.
      bottomNavigationBar: SafeArea(
        child: SizedBox(
          height: 58,
          child: Row(
            children: [
              const SizedBox(width: 8),
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
              // Contador: en pantalla ancha va abajo a la derecha de la
              // ventana; en el móvil, aquí.
              Expanded(
                child: wide
                    ? const SizedBox()
                    : Center(child: _statusText(context)),
              ),
              for (final (view, tip, on, off) in [
                ('red', tr('Red de notas'), Icons.hub, Icons.hub_outlined),
                (
                  'calendario',
                  tr('Calendario'),
                  Icons.calendar_month,
                  Icons.calendar_month_outlined
                ),
              ]) ...[
                _BarButton(
                  tooltip: tip,
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
                      _setFilter(
                          view == 'red' && _filter == 'red' ? 'todas' : view);
                    } else {
                      _setFilter(_filter == view ? 'todas' : view);
                    }
                  },
                ),
                const SizedBox(width: 4),
              ],
              _BarButton(
                tooltip: tr('Nueva nota (Ctrl+N)'),
                icon: Icons.edit_note,
                big: true,
                onTap: _newNote,
              ),
              const SizedBox(width: 8),
            ],
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
    final done = repo.completed.length;
    final archived = repo.archivedNotes.length;
    final trash = repo.trash.length;
    final email = Supabase.instance.client.auth.currentUser?.email;
    final v = await Updater.instance.currentVersion().catchError((_) => '');
    if (!mounted) return;
    final choice = await showContextMenu(
      context,
      position: at + const Offset(0, 4),
      alignRight: true,
      width: 290,
      header: _MenuHeader(email: email, version: v),
      entries: [
        MenuEntry.section(tr('Notas')),
        MenuEntry('archivadas', Icons.archive_outlined, tr('Archivadas'),
            badge: archived == 0 ? null : '$archived'),
        MenuEntry('completadas', Icons.task_alt_rounded, tr('Completadas'),
            badge: done == 0 ? null : '$done'),
        MenuEntry('papelera', Icons.delete_outline, tr('Papelera'),
            badge: trash == 0 ? null : '$trash'),
        MenuEntry('vault', Icons.shield_outlined, 'Vault',
            subtitle: vault.unlocked
                ? tr('Abierto')
                : tr('Notas protegidas con contraseña')),
        if (vault.unlocked)
          MenuEntry(
              'vault-lock', Icons.lock_outline_rounded, tr('Bloquear Vault')),
        MenuEntry.section(tr('Apariencia')),
        MenuEntry('tema', Icons.palette_outlined, tr('Tema y colores')),
        MenuEntry('idioma', Icons.translate_rounded, tr('Idioma'),
            hint: AppLanguage.supported[appLanguage.code]),
        MenuEntry.section(tr('Cuenta')),
        MenuEntry('sync', Icons.sync, tr('Sincronizar ahora')),
        MenuEntry('update', Icons.system_update_alt_rounded,
            tr('Buscar actualizaciones')),
        MenuEntry('cuenta-pass', Icons.manage_accounts_outlined,
            tr('Cambiar contraseña de la cuenta')),
        if (vault.state == VaultState.locked || vault.unlocked)
          MenuEntry('vault-pass', Icons.password_rounded,
              tr('Cambiar contraseña del Vault')),
        null,
        MenuEntry('coffee', Icons.coffee_outlined, tr('Invítame a un café'),
            subtitle: tr('Apoya el proyecto (open source)')),
        MenuEntry('github', Icons.code_rounded, tr('Código en GitHub')),
        null,
        MenuEntry('logout', Icons.logout, tr('Cerrar sesión'), danger: true),
      ],
    );
    if (!mounted || choice == null) return;
    switch (choice) {
      case 'tema':
        showThemePicker(context);
      case 'idioma':
        showLanguagePicker(context);
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
      case 'cuenta-pass':
        changeAccountPassword(context);
      case 'coffee':
        openLink(context, AppConfig.coffeeUrl);
      case 'github':
        openLink(context, AppConfig.githubUrl);
      case 'logout':
        _signOut();
    }
  }

  /// ¿Se está viendo [view] (red o calendario)? En pantalla ancha el
  /// calendario se ve siempre que no haya nota abierta ni red elegida.
  bool _viewShown(String view, bool wide, bool noteOpen) {
    if (noteOpen) return false;
    if (wide && view == 'calendario') return _filter != 'red';
    return _filter == view;
  }

  /// Nº de notas, enlaces o tareas pendientes según la vista.
  Widget _statusText(BuildContext context) {
    final total = repo.notes.where((n) => !n.isEmpty).length;
    final pendientes = repo.temporales.where((n) => !n.done).length;
    final enlaces = _filter == 'red' ? NoteGraph.of(repo).edgeCount : 0;
    return AnimatedSwitcher(
      duration: Anim.medium,
      transitionBuilder: (c, a) => FadeTransition(
        opacity: a,
        child: SlideTransition(
          position:
              Tween(begin: const Offset(0, 0.6), end: Offset.zero).animate(a),
          child: c,
        ),
      ),
      child: Text(
        switch (_filter) {
          'calendario' =>
            trn(pendientes, '{0} tarea pendiente', '{0} tareas pendientes'),
          'red' => trn(enlaces, '{0} enlace', '{0} enlaces'),
          _ => trn(total, '{0} nota', '{0} notas'),
        },
        key: ValueKey('$_filter-$total-$pendientes-$enlaces'),
        style: TextStyle(fontSize: 12, color: Palette.secondary(context)),
      ),
    );
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
              note: n,
              selected: wide && n.id == _openId,
              onTap: () => _open(n.id),
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
            .animate(delay: (min(order, 10) * 40).ms)
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
    if (_openId == id) setState(() => _openId = null);
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
    final bg = widget.selected
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
      direction: DismissDirection.horizontal,
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
                    // Franja con el color elegido para la nota.
                    AnimatedContainer(
                      duration: Anim.medium,
                      width: n.color == null ? 0 : 4,
                      height: 38,
                      margin: EdgeInsets.only(right: n.color == null ? 0 : 12),
                      decoration: BoxDecoration(
                        gradient: n.color == null
                            ? null
                            : LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: fusePalette(n.color)),
                        borderRadius: BorderRadius.circular(2),
                      ),
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
                                Text(tiempoRestante(n.dueAt!, done: n.done),
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
          'Sincronizando…'
        ),
      SyncStatus.synced => (
          const Icon(Icons.cloud_done_outlined),
          tr('Todo sincronizado')
        ),
      SyncStatus.pending => (
          const Icon(Icons.cloud_upload_outlined),
          'Subiendo cambios…'
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
    required this.icon,
    required this.onTap,
    this.active = false,
    this.big = false,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback onTap;
  final bool active;
  final bool big;

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
            child: Icon(icon, size: big ? 30 : 24, color: accent),
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
