import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../data/notes_repository.dart';
import '../data/widget_bridge.dart';
import '../models/note.dart';
import 'anim.dart';
import 'calendar_view.dart';
import 'folders.dart';
import 'format.dart';
import 'note_color_sheet.dart';
import 'note_editor.dart';
import 'schedule_sheet.dart';
import 'split.dart';
import 'theme.dart';
import 'theme_picker.dart';
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
  bool _openAutofocus = false;
  StreamSubscription<Uri?>? _widgetSub;

  /// 'todas' | 'temporales' | 'calendario' | id de carpeta
  String _filter = 'todas';

  // Cachés para que al redimensionar la ventana no se reconstruya todo.
  Widget? _listCache;
  Object? _listKey;
  Widget? _editorCache;
  Object? _editorKey;

  bool get _isFolderFilter =>
      !const {'todas', 'temporales', 'calendario'}.contains(_filter);

  NotesRepository get repo => widget.repo;

  // En PC la ventana mínima es de 760 px, así que siempre se usa la vista de
  // dos paneles y no hay saltos de diseño al redimensionar.
  static const _wideBreakpoint = 700.0;

  @override
  void initState() {
    super.initState();
    _widgetSub = WidgetBridge.clicks.listen(_onWidgetUri);
    WidgetBridge.initialUri().then(_onWidgetUri);
  }

  @override
  void dispose() {
    _widgetSub?.cancel();
    _search.dispose();
    super.dispose();
  }

  void _onWidgetUri(Uri? uri) {
    if (uri == null || !mounted) return;
    if (uri.host == 'nueva') {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _newNote();
      });
    }
  }

  void _newNote() {
    final n = repo.createNote(folderId: _isFolderFilter ? _filter : null);
    _open(n.id, autofocus: true);
    if (_filter == 'temporales' || _filter == 'calendario') {
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
    // Al ir al calendario se cierra la nota abierta para que se vea.
    if (f == 'calendario' && _openId != null) _close();
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
    messenger.showSnackBar(SnackBar(
      content: const Text('Nota eliminada'),
      behavior: SnackBarBehavior.floating,
      width: 340,
      duration: const Duration(seconds: 4),
      action: SnackBarAction(
        label: 'Deshacer',
        onPressed: () => repo.restore(id),
      ),
    ));
  }

  Future<void> _options(Note n) async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(n.pinned ? Icons.push_pin : Icons.push_pin_outlined),
              title: Text(n.pinned ? 'Desfijar' : 'Fijar arriba'),
              onTap: () {
                Navigator.pop(ctx);
                repo.togglePin(n.id);
              },
            ),
            ListTile(
              leading: Icon(n.isTemporal ? Icons.alarm_on : Icons.alarm_add_outlined),
              title: Text(n.isTemporal ? 'Cambiar fechas' : 'Hacer temporal'),
              onTap: () {
                Navigator.pop(ctx);
                showScheduleSheet(context, repo, n.id);
              },
            ),
            ListTile(
              leading: const Icon(Icons.palette_outlined),
              title: const Text('Color'),
              onTap: () {
                Navigator.pop(ctx);
                showNoteColorSheet(context, repo, n.id);
              },
            ),
            ListTile(
              leading: const Icon(Icons.drive_file_move_outline),
              title: const Text('Mover a carpeta'),
              onTap: () {
                Navigator.pop(ctx);
                pickFolder(context, repo, n.folderId).then((r) {
                  if (r != null) repo.moveToFolder(n.id, r.isEmpty ? null : r);
                });
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline, color: Colors.red),
              title:
                  const Text('Eliminar', style: TextStyle(color: Colors.red)),
              onTap: () {
                Navigator.pop(ctx);
                _deleteAnimated(n.id);
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _signOut() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('¿Cerrar sesión?'),
        content: const Text(
            'Las notas siguen guardadas en tu cuenta. Volverán al entrar.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Cerrar sesión')),
        ],
      ),
    );
    if (ok == true) {
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
      ),
    );
  }

  /// Lista cacheada: solo se reconstruye si cambian los datos o filtros,
  /// no por cambiar el tamaño de la ventana.
  Widget _list(BuildContext context, bool wide) {
    final key = (repo.version, repo.status, _query, _filter, _openId, wide,
        _removing.length, Theme.of(context));
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

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyN, control: true): _newNote,
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
                          : (_filter == 'calendario'
                              ? RepaintBoundary(
                                  key: const ValueKey('cal'),
                                  child: _calendar())
                              : _EmptyPane(
                                  key: const ValueKey('vacio'),
                                  onNew: _newNote)),
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
    );
  }

  Widget _buildList(BuildContext context, bool wide) {
    final q = _query.toLowerCase();
    final timeView = _filter == 'temporales' || _filter == 'calendario';
    final all = repo.notes
        .where((n) => !n.isEmpty || n.id == _openId)
        .where((n) => q.isEmpty || n.content.toLowerCase().contains(q))
        .where((n) => !_isFolderFilter || n.folderId == _filter)
        .where((n) => !timeView || n.isTemporal)
        .toList();
    final pinned = all.where((n) => n.pinned).toList();
    final others = all.where((n) => !n.pinned).toList();
    final total = repo.notes.where((n) => !n.isEmpty).length;

    Widget body;
    if (!repo.loaded) {
      body = const Center(child: CircularProgressIndicator());
    } else if (_filter == 'calendario' && !wide) {
      body = _calendar();
    } else if (all.isEmpty) {
      body = _EmptyList(searching: q.isNotEmpty, timeView: timeView);
    } else if (timeView) {
      body = _timeList(context, all);
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
              ..._section(context, 'Fijadas', pinned, wide, () => index++),
            if (others.isNotEmpty)
              ..._section(context, pinned.isEmpty ? 'Notas' : 'Otras notas',
                  others, wide, () => index++),
          ],
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        centerTitle: false,
        titleSpacing: 20,
        title: const WaveTitle(text: 'babunotes', fontSize: 30)
            .animate()
            .fadeIn(duration: Anim.slow),
        actions: [
          _SyncIndicator(repo: repo),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_horiz),
            onSelected: (v) {
              if (v == 'tema') showThemePicker(context);
              if (v == 'sync') repo.sync();
              if (v == 'logout') _signOut();
            },
            itemBuilder: (_) => const [
              PopupMenuItem(
                  value: 'tema',
                  child: ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.palette_outlined),
                      title: Text('Tema y colores'))),
              PopupMenuItem(
                  value: 'sync',
                  child: ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.sync),
                      title: Text('Sincronizar ahora'))),
              PopupMenuItem(
                  value: 'logout',
                  child: ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.logout),
                      title: Text('Cerrar sesión'))),
            ],
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
                hintText: 'Buscar',
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
                key: ValueKey('$_filter-${all.isEmpty}-${q.isEmpty}'),
                child: body,
              ),
            ),
          ),
        ],
      ),
      // En el calendario del móvil la barra inferior se oculta: el propio
      // calendario ya tiene su botón de nueva tarea y así nada se monta.
      bottomNavigationBar: (_filter == 'calendario' && !wide)
          ? null
          : SafeArea(
        child: SizedBox(
          height: 56,
          child: Stack(
            alignment: Alignment.center,
            children: [
              AnimatedSwitcher(
                duration: Anim.medium,
                transitionBuilder: (c, a) => FadeTransition(
                  opacity: a,
                  child: SlideTransition(
                    position: Tween(
                            begin: const Offset(0, 0.6), end: Offset.zero)
                        .animate(a),
                    child: c,
                  ),
                ),
                child: Text(
                  total == 1 ? '1 nota' : '$total notas',
                  key: ValueKey(total),
                  style: TextStyle(
                      fontSize: 12, color: Palette.secondary(context)),
                ),
              ),
              Positioned(
                right: 8,
                child: Bouncy(
                  pressedScale: 0.8,
                  hoverScale: 1.12,
                  child: IconButton(
                    tooltip: 'Nueva nota (Ctrl+N)',
                    iconSize: 30,
                    color: Palette.accent(context),
                    icon: const Icon(Icons.edit_note),
                    onPressed: _newNote,
                  ),
                )
                    .animate()
                    .scale(
                        begin: const Offset(0.4, 0.4),
                        duration: Anim.slow,
                        curve: Curves.easeOutBack)
                    .fadeIn(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _timeList(BuildContext context, List<Note> notes) {
    final sorted = [...notes]..sort((a, b) => a.dueAt!.compareTo(b.dueAt!));
    final groups = <String, List<Note>>{};
    for (final n in sorted) {
      groups.putIfAbsent(grupoTemporal(n.dueAt!, done: n.done), () => []).add(n);
    }
    var i = 0;
    return ListView(
      key: PageStorageKey('lista-tiempo-$_filter'),
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
      children: [
        for (final g in ordenGrupos)
          if (groups[g] != null) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 14, 4, 8),
              child: Row(
                children: [
                  Text(g,
                      style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: g == 'Vencidas'
                              ? const Color(0xFFE5484D)
                              : null)),
                  const SizedBox(width: 8),
                  Text('${groups[g]!.length}',
                      style: TextStyle(color: Palette.secondary(context))),
                ],
              ),
            ),
            for (final n in groups[g]!)
              Padding(
                key: ValueKey('t-${n.id}'),
                padding: const EdgeInsets.only(bottom: 10),
                child: TempCard(
                  note: n,
                  onOpen: () => _open(n.id),
                  onEditDates: () => showScheduleSheet(context, repo, n.id),
                  onToggleDone: () => repo.toggleDone(n.id),
                )
                    .animate(delay: (min(i++, 10) * 40).ms)
                    .fadeIn(duration: Anim.medium)
                    .slideY(begin: 0.2, curve: Anim.curve),
              ),
          ],
      ],
    );
  }

  List<Widget> _section(BuildContext context, String title, List<Note> notes,
      bool wide, int Function() nextIndex) {
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
              onOptions: () => _options(n),
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
        child: Text(title,
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
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
  final VoidCallback onOptions;
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
              onTap: widget.onTap,
              onLongPress: widget.onOptions,
              onSecondaryTap: widget.onOptions,
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
                                    size: 13,
                                    color: urgencyColor(context, n)),
                                const SizedBox(width: 6),
                                Expanded(child: TimeBar(note: n, compact: true)),
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
          'Todo sincronizado'
        ),
      SyncStatus.pending => (
          const Icon(Icons.cloud_upload_outlined),
          'Subiendo cambios…'
        ),
      SyncStatus.offline => (
          const Icon(Icons.cloud_off_outlined),
          'Sin conexión: los cambios se subirán al volver internet'
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
                  size: 56, color: color)
              .animate(onPlay: (c) => c.repeat(reverse: true))
              .moveY(begin: 0, end: -6, duration: 1600.ms, curve: Curves.easeInOut),
          const SizedBox(height: 12),
          Text(
              searching
                  ? 'Sin resultados'
                  : (timeView
                      ? 'No hay notas temporales'
                      : 'Aún no hay notas aquí'),
              style: TextStyle(color: color, fontSize: 16)),
          if (timeView && !searching) ...[
            const SizedBox(height: 6),
            Text('Crea una con el lápiz y ponle fecha límite',
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
              .moveY(begin: 0, end: -8, duration: 1800.ms, curve: Curves.easeInOut),
          const SizedBox(height: 14),
          Text('Elige una nota o crea una nueva',
              style: TextStyle(color: Palette.secondary(context))),
          const SizedBox(height: 14),
          Bouncy(
            hoverScale: 1.05,
            child: FilledButton.icon(
              onPressed: onNew,
              icon: const Icon(Icons.add),
              label: const Text('Nueva nota  (Ctrl+N)'),
            ),
          ),
        ],
      ).animate().fadeIn(duration: Anim.slow).slideY(begin: 0.05),
    );
  }
}
