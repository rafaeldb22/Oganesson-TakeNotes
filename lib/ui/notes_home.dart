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
import 'format.dart';
import 'note_editor.dart';
import 'theme.dart';

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
  bool _openAutofocus = false;
  StreamSubscription<Uri?>? _widgetSub;

  NotesRepository get repo => widget.repo;

  static const _wideBreakpoint = 760.0;

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
    final n = repo.createNote();
    _open(n.id, autofocus: true);
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
              leading: const Icon(Icons.delete_outline, color: Colors.red),
              title:
                  const Text('Eliminar', style: TextStyle(color: Colors.red)),
              onTap: () {
                Navigator.pop(ctx);
                _deleteNote(n.id);
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
    return NoteEditor(
      key: ValueKey('editor-$_openId'),
      repo: repo,
      noteId: _openId!,
      showBack: showBack,
      autofocus: _openAutofocus,
      onClose: _close,
      onDelete: _deleteNote,
    );
  }

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
                final listWidth = (c.maxWidth * 0.34).clamp(300.0, 400.0);
                return Scaffold(
                  body: Row(
                    children: [
                      SizedBox(width: listWidth, child: _buildList(context, true)),
                      VerticalDivider(
                          width: 1, color: Palette.separator(context)),
                      Expanded(
                        child: AnimatedSwitcher(
                          duration: Anim.medium,
                          switchInCurve: Anim.curve,
                          switchOutCurve: Curves.easeIn,
                          transitionBuilder: fadeThrough,
                          child: hasOpen
                              ? _editor(showBack: false)
                              : _EmptyPane(
                                  key: const ValueKey('vacio'),
                                  onNew: _newNote),
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
                          child: _buildList(context, false),
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
    final all = repo.notes
        .where((n) => !n.isEmpty || n.id == _openId)
        .where((n) => q.isEmpty || n.content.toLowerCase().contains(q))
        .toList();
    final pinned = all.where((n) => n.pinned).toList();
    final others = all.where((n) => !n.pinned).toList();
    final total = repo.notes.where((n) => !n.isEmpty).length;

    Widget body;
    if (!repo.loaded) {
      body = const Center(child: CircularProgressIndicator());
    } else if (all.isEmpty) {
      body = _EmptyList(searching: q.isNotEmpty);
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
        title: const Text('Notas',
                style: TextStyle(fontSize: 30, fontWeight: FontWeight.w800))
            .animate()
            .fadeIn(duration: Anim.slow)
            .slideX(begin: -0.1, curve: Anim.curve),
        actions: [
          _SyncIndicator(repo: repo),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_horiz),
            onSelected: (v) {
              if (v == 'sync') repo.sync();
              if (v == 'logout') _signOut();
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'sync', child: Text('Sincronizar ahora')),
              PopupMenuItem(value: 'logout', child: Text('Cerrar sesión')),
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
          Expanded(
            child: AnimatedSwitcher(
              duration: Anim.medium,
              child: KeyedSubtree(
                key: ValueKey(all.isEmpty ? 'vacia-$q' : 'llena'),
                child: body,
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
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
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
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
    required this.note,
    required this.selected,
    required this.onTap,
    required this.onOptions,
    required this.onDismissed,
  });

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
    final dark = Theme.of(context).brightness == Brightness.dark;
    final hoverColor = dark ? const Color(0xFF2C2C2E) : const Color(0xFFF2F2F7);
    final bg = widget.selected
        ? Palette.selected(context)
        : (_hover ? hoverColor : Palette.card(context));

    return Dismissible(
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
  const _EmptyList({required this.searching});
  final bool searching;

  @override
  Widget build(BuildContext context) {
    final color = Palette.secondary(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(searching ? Icons.search_off : Icons.sticky_note_2_outlined,
                  size: 56, color: color)
              .animate(onPlay: (c) => c.repeat(reverse: true))
              .moveY(begin: 0, end: -6, duration: 1600.ms, curve: Curves.easeInOut),
          const SizedBox(height: 12),
          Text(searching ? 'Sin resultados' : 'Aún no tienes notas',
              style: TextStyle(color: color, fontSize: 16)),
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
