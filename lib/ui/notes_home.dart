import 'dart:async';
import 'dart:math';

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
import 'account_dialogs.dart';
import 'calendar_view.dart';
import 'completed_sheet.dart';
import 'folders.dart';
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
  String _query = '';
  String? _openId;
  final Set<String> _removing = {}; // filas que se están plegando
  ScaffoldFeatureController<SnackBar, SnackBarClosedReason>? _lastBar;
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

  bool get _isFolderFilter =>
      !const {'todas', 'calendario', 'red'}.contains(_filter);

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
      if (v != null && mounted) setState(() => _sort = v);
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

  void _onWidgetUri(Uri? uri) {
    if (uri == null || !mounted) return;
    if (uri.host == 'calendario') {
      _setFilter('calendario');
      return;
    }
    if (uri.host == 'nueva') {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _newNote();
      });
    }
  }

  void _newNote() {
    final n = repo.createNote(folderId: _isFolderFilter ? _filter : null);
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
      folderId: _isFolderFilter ? _filter : null,
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
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    final bar = messenger.showSnackBar(SnackBar(
      content: Text(tr('Nota movida a la papelera')),
      behavior: SnackBarBehavior.floating,
      width: 340,
      duration: const Duration(seconds: 3),
      action: SnackBarAction(
        label: tr('Deshacer'),
        onPressed: () => repo.restore(id),
      ),
    ));
    // Las versiones nuevas de Flutter dejan fijos los avisos con botón;
    // lo cerramos nosotros a los 3 segundos.
    _lastBar = bar;
    bar.closed.then((_) {
      if (identical(_lastBar, bar)) _lastBar = null;
    });
    Timer(const Duration(seconds: 3), () {
      if (identical(_lastBar, bar)) bar.close();
    });
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
      final overlay =
          Overlay.of(context).context.findRenderObject() as RenderBox;
      choice = await showMenu<String>(
        context: context,
        position: RelativeRect.fromRect(
            at & const Size(1, 1), Offset.zero & overlay.size),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        items: [
          for (final (id, icon, label, danger) in actions)
            if (id == '-')
              const PopupMenuDivider()
            else
              PopupMenuItem(
                value: id,
                height: 40,
                child: Row(
                  children: [
                    Icon(icon,
                        size: 19,
                        color: danger
                            ? Theme.of(context).colorScheme.error
                            : Palette.secondary(context)),
                    const SizedBox(width: 12),
                    Text(label,
                        style: TextStyle(
                            color: danger
                                ? Theme.of(context).colorScheme.error
                                : null)),
                  ],
                ),
              ),
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
                    body: ResizableSplit(
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
                            : switch (_filter) {
                                'calendario' => RepaintBoundary(
                                    key: const ValueKey('cal'),
                                    child: _calendar()),
                                'red' => RepaintBoundary(
                                    key: const ValueKey('red-panel'),
                                    child: _graph()),
                                _ => _EmptyPane(
                                    key: const ValueKey('vacio'),
                                    onNew: _newNote),
                              },
                      ),
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
        .where((n) => !_isFolderFilter || n.folderId == _filter)
        .toList();
    switch (_sort) {
      case 'creada':
        all.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      case 'nombre':
        all.sort(
            (a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
      default: // ya viene ordenada por última modificación
    }
    final pinned = all.where((n) => n.pinned).toList();
    final others = all.where((n) => !n.pinned).toList();
    final total = repo.notes.where((n) => !n.isEmpty).length;
    final pendientes = repo.temporales.where((n) => !n.done).length;
    final enlaces = _filter == 'red' ? NoteGraph.of(repo).edgeCount : 0;
    final noteOpen = _openId != null && repo.byId(_openId!) != null;

    Widget body;
    if (!repo.loaded) {
      body = const Center(child: CircularProgressIndicator());
    } else if (_filter == 'calendario' && !wide) {
      body = _calendar();
    } else if (_filter == 'red' && !wide) {
      body = _graph();
    } else if (all.isEmpty) {
      body = _EmptyList(
          searching: q.isNotEmpty, timeView: _filter == 'calendario');
    } else {
      var index = 0;
      body = RefreshIndicator(
        onRefresh: repo.sync,
        child: ListView(
          key: const PageStorageKey('lista-notas'),
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
          children: [
            if (pinned.isNotEmpty)
              ..._section(context, 'Fijadas', pinned, wide, () => index++,
                  trailing: _sortMenu(context)),
            if (others.isNotEmpty)
              ..._section(
                  context,
                  pinned.isEmpty ? tr('Notas') : tr('Otras notas'),
                  others,
                  wide,
                  () => index++,
                  trailing: pinned.isEmpty ? _sortMenu(context) : null),
          ],
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        centerTitle: false,
        titleSpacing: 20,
        title: const WaveTitle(text: 'oganesson', fontSize: 30)
            .animate()
            .fadeIn(duration: Anim.slow),
        actions: [
          _SyncIndicator(repo: repo),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_horiz),
            tooltip: tr('Más opciones'),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            onSelected: (v) {
              switch (v) {
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
            },
            itemBuilder: (_) {
              PopupMenuItem<String> item(
                      String value, IconData icon, String title,
                      {String? subtitle, String? trailing}) =>
                  PopupMenuItem(
                    value: value,
                    child: ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(icon),
                      title: Text(title),
                      subtitle: subtitle == null ? null : Text(subtitle),
                      trailing: trailing == null
                          ? null
                          : Text(trailing,
                              style:
                                  TextStyle(color: Palette.secondary(context))),
                    ),
                  );
              final done = repo.completed.length;
              return [
                item('tema', Icons.palette_outlined, tr('Tema y colores')),
                item('idioma', Icons.translate_rounded, tr('Idioma'),
                    trailing: AppLanguage.supported[appLanguage.code]),
                const PopupMenuDivider(),
                item('vault', Icons.shield_outlined, 'Vault',
                    subtitle: tr('Notas protegidas con contraseña')),
                if (vault.unlocked)
                  item('vault-lock', Icons.lock_outline_rounded,
                      tr('Bloquear Vault')),
                if (vault.state == VaultState.locked || vault.unlocked)
                  item('vault-pass', Icons.password_rounded,
                      tr('Cambiar contraseña del Vault')),
                item('completadas', Icons.task_alt_rounded, tr('Completadas'),
                    trailing: done == 0 ? null : '$done'),
                item('papelera', Icons.delete_outline, tr('Papelera'),
                    trailing:
                        repo.trash.isEmpty ? null : '${repo.trash.length}'),
                const PopupMenuDivider(),
                item('sync', Icons.sync, tr('Sincronizar ahora')),
                item('update', Icons.system_update_alt_rounded,
                    tr('Buscar actualizaciones')),
                item('cuenta-pass', Icons.manage_accounts_outlined,
                    tr('Cambiar contraseña de la cuenta')),
                const PopupMenuDivider(),
                item('coffee', Icons.coffee_outlined, tr('Invítame a un café'),
                    subtitle: tr('Apoya el proyecto (open source)')),
                item('github', Icons.code_rounded, tr('Código en GitHub')),
                const PopupMenuDivider(),
                item('logout', Icons.logout, tr('Cerrar sesión')),
              ];
            },
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: TextField(
              controller: _search,
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
          FilterChips(
            repo: repo,
            selected: _filter,
            onSelect: _setFilter,
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
                  if (f != null) _setFilter(f.id);
                },
              ),
              Expanded(
                child: Center(
                  child: AnimatedSwitcher(
                    duration: Anim.medium,
                    transitionBuilder: (c, a) => FadeTransition(
                      opacity: a,
                      child: SlideTransition(
                        position:
                            Tween(begin: const Offset(0, 0.6), end: Offset.zero)
                                .animate(a),
                        child: c,
                      ),
                    ),
                    child: Text(
                      switch (_filter) {
                        'calendario' => trn(pendientes, '{0} tarea pendiente',
                            '{0} tareas pendientes'),
                        'red' => trn(enlaces, '{0} enlace', '{0} enlaces'),
                        _ => trn(total, '{0} nota', '{0} notas'),
                      },
                      key: ValueKey('$_filter-$total-$pendientes-$enlaces'),
                      style: TextStyle(
                          fontSize: 12, color: Palette.secondary(context)),
                    ),
                  ),
                ),
              ),
              for (final (view, tip, on, off) in [
                ('red', tr('Red de notas'), Icons.hub, Icons.hub_outlined),
                (
                  'calendario',
                  'Calendario',
                  Icons.calendar_month,
                  Icons.calendar_month_outlined
                ),
              ]) ...[
                _BarButton(
                  tooltip: tip,
                  // Solo se ve activo cuando la vista está a la vista: con
                  // una nota abierta encima no se queda "pulsado".
                  icon: _filter == view && !noteOpen ? on : off,
                  active: _filter == view && !noteOpen,
                  onTap: () {
                    if (_filter == view && noteOpen) {
                      _close(); // volver a la red / al calendario
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

  List<Widget> _section(BuildContext context, String title, List<Note> notes,
      bool wide, int Function() nextIndex,
      {Widget? trailing}) {
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
              onDismissed: () => _deleteNote(n.id),
            ),
          ],
        )
            .animate(delay: (min(order, 10) * 40).ms)
            .fadeIn(duration: Anim.medium)
            .slideY(begin: 0.25, curve: Anim.curve, duration: Anim.slow),
      ));
    }
    return [
      Padding(
        key: ValueKey('titulo-$title'),
        padding: const EdgeInsets.fromLTRB(4, 14, 4, 8),
        child: Row(
          children: [
            Expanded(
              child: Text(title,
                  style: const TextStyle(
                      fontSize: 17, fontWeight: FontWeight.w700)),
            ),
            if (trailing != null) trailing,
          ],
        ),
      ),
      AnimatedSize(
        key: ValueKey('seccion-$title'),
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
      ),
    ];
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
  });

  final bool removing;
  final Note note;
  final bool selected;
  final VoidCallback onTap;

  /// Opciones de la nota: con posición = clic derecho (menú contextual).
  final void Function(Offset? at) onOptions;
  final VoidCallback onDismissed;

  @override
  State<_NoteTile> createState() => _NoteTileState();
}

class _NoteTileState extends State<_NoteTile> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final n = widget.note;
    final bg = widget.selected
        ? Palette.selected(context)
        : (_hover ? Palette.hover(context) : Palette.card(context));

    final tile = Dismissible(
      key: ValueKey('desliza-${n.id}'),
      direction: DismissDirection.endToStart,
      background: Container(
        color: Colors.red,
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        child: const Icon(Icons.delete, color: Colors.white),
      ),
      // Doble comprobación: pregunta antes de eliminar al deslizar.
      confirmDismiss: (_) => confirmDelete(context, n.title),
      onDismissed: (_) => widget.onDismissed(),
      child: MouseRegion(
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: Bouncy(
          pressedScale: 0.975,
          child: AnimatedContainer(
            duration: Anim.fast,
            curve: Curves.easeOut,
            color: bg,
            child: InkWell(
              // El fondo ya cambia con _hover: sin capa gris del InkWell.
              hoverColor: Colors.transparent,
              onTap: widget.onTap,
              onLongPress: () => widget.onOptions(null),
              onSecondaryTapUp: (d) => widget.onOptions(d.globalPosition),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
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

    // Al borrar: la fila se desliza, se desvanece y se pliega.
    return ClipRect(
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
  }
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

class _EmptyPane extends StatelessWidget {
  const _EmptyPane({super.key, required this.onNew});
  final VoidCallback onNew;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Palette.card(context),
      alignment: Alignment.center,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.sticky_note_2_outlined,
                  size: 72, color: Palette.secondary(context))
              .animate(onPlay: (c) => c.repeat(reverse: true))
              .moveY(
                  begin: 0,
                  end: -8,
                  duration: 1800.ms,
                  curve: Curves.easeInOut),
          const SizedBox(height: 14),
          Text(tr('Elige una nota o crea una nueva'),
              style: TextStyle(color: Palette.secondary(context))),
          const SizedBox(height: 14),
          Bouncy(
            hoverScale: 1.05,
            child: FilledButton.icon(
              onPressed: onNew,
              icon: const Icon(Icons.add),
              label: Text(tr('Nueva nota  (Ctrl+N)')),
            ),
          ),
        ],
      ).animate().fadeIn(duration: Anim.slow).slideY(begin: 0.05),
    );
  }
}

/// Botón de la barra inferior, con estado activo (tinte del acento).
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
