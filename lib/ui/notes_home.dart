import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../data/notes_repository.dart';
import '../data/widget_bridge.dart';
import '../models/note.dart';
import 'format.dart';
import 'note_editor.dart';
import 'theme.dart';

class NotesHome extends StatefulWidget {
  const NotesHome({super.key, required this.repo});
  final NotesRepository repo;

  @override
  State<NotesHome> createState() => _NotesHomeState();
}

class _NotesHomeState extends State<NotesHome> {
  final _search = TextEditingController();
  String _query = '';
  String? _selectedId; // nota abierta en el panel derecho (pantallas anchas)
  bool _selectedAutofocus = false;
  StreamSubscription<Uri?>? _widgetSub;

  NotesRepository get repo => widget.repo;

  static const _wideBreakpoint = 760.0;
  bool _isWide(BuildContext c) => MediaQuery.sizeOf(c).width >= _wideBreakpoint;

  @override
  void initState() {
    super.initState();
    // Toques en el widget de Android.
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
        if (!mounted) return;
        Navigator.of(context).popUntil((r) => r.isFirst);
        _newNote();
      });
    }
  }

  void _newNote() {
    final n = repo.createNote();
    _open(n.id, autofocus: true);
  }

  void _open(String id, {bool autofocus = false}) {
    if (_isWide(context)) {
      setState(() {
        _selectedId = id;
        _selectedAutofocus = autofocus;
      });
    } else {
      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) =>
            NoteEditor(repo: repo, noteId: id, autofocus: autofocus),
      ));
    }
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
              title: const Text('Eliminar',
                  style: TextStyle(color: Colors.red)),
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

  void _deleteNote(String id) {
    if (_selectedId == id) setState(() => _selectedId = null);
    repo.delete(id);
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

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyN, control: true): _newNote,
      },
      child: Focus(
        autofocus: true,
        child: ListenableBuilder(
          listenable: repo,
          builder: (context, _) {
            final wide = _isWide(context);
            final list = _buildList(context, wide);
            if (!wide) return list;

            final sel = _selectedId == null ? null : repo.byId(_selectedId!);
            final showEditor = sel != null && !sel.deleted;
            return Scaffold(
              body: Row(
                children: [
                  SizedBox(width: 360, child: list),
                  VerticalDivider(width: 1, color: Palette.separator(context)),
                  Expanded(
                    child: showEditor
                        ? NoteEditor(
                            key: ValueKey(_selectedId),
                            repo: repo,
                            noteId: _selectedId!,
                            embedded: true,
                            autofocus: _selectedAutofocus,
                            onClosed: () => setState(() => _selectedId = null),
                          )
                        : _EmptyPane(onNew: _newNote),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildList(BuildContext context, bool wide) {
    final q = _query.toLowerCase();
    final all = repo.notes
        .where((n) => !n.isEmpty || n.id == _selectedId)
        .where((n) => q.isEmpty || n.content.toLowerCase().contains(q))
        .toList();
    final pinned = all.where((n) => n.pinned).toList();
    final others = all.where((n) => !n.pinned).toList();
    final total = repo.notes.where((n) => !n.isEmpty).length;

    Widget body;
    if (!repo.loaded) {
      body = const Center(child: CircularProgressIndicator());
    } else if (all.isEmpty) {
      body = Center(
        child: Text(
          q.isEmpty ? 'Aún no tienes notas' : 'Sin resultados',
          style: TextStyle(color: Palette.secondary(context), fontSize: 16),
        ),
      );
    } else {
      body = RefreshIndicator(
        onRefresh: repo.sync,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
          children: [
            if (pinned.isNotEmpty) ..._section(context, 'Fijadas', pinned),
            if (others.isNotEmpty)
              ..._section(
                  context, pinned.isEmpty ? 'Notas' : 'Otras notas', others),
          ],
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        centerTitle: false,
        titleSpacing: 20,
        title: const Text('Notas',
            style: TextStyle(fontSize: 30, fontWeight: FontWeight.w800)),
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
                suffixIcon: _query.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () {
                          _search.clear();
                          setState(() => _query = '');
                        },
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
          Expanded(child: body),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: SizedBox(
          height: 54,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Text(total == 1 ? '1 nota' : '$total notas',
                  style: TextStyle(
                      fontSize: 12, color: Palette.secondary(context))),
              Positioned(
                right: 8,
                child: IconButton(
                  tooltip: 'Nueva nota (Ctrl+N)',
                  iconSize: 30,
                  color: Palette.accent(context),
                  icon: const Icon(Icons.edit_note),
                  onPressed: _newNote,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _section(BuildContext context, String title, List<Note> notes) {
    final tiles = <Widget>[];
    for (var i = 0; i < notes.length; i++) {
      if (i > 0) {
        tiles.add(Divider(
            height: 1, indent: 16, color: Palette.separator(context)));
      }
      tiles.add(_tile(context, notes[i]));
    }
    return [
      Padding(
        padding: const EdgeInsets.fromLTRB(4, 14, 4, 8),
        child: Text(title,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
      ),
      ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Material(
          color: Palette.card(context),
          child: Column(children: tiles),
        ),
      ),
    ];
  }

  Widget _tile(BuildContext context, Note n) {
    final selected = n.id == _selectedId && _isWide(context);
    return Dismissible(
      key: ValueKey('nota-${n.id}'),
      direction: DismissDirection.endToStart,
      background: Container(
        color: Colors.red,
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        child: const Icon(Icons.delete, color: Colors.white),
      ),
      onDismissed: (_) => _deleteNote(n.id),
      child: Material(
        color: selected ? Palette.selected(context) : Colors.transparent,
        child: InkWell(
          onTap: () => _open(n.id),
          onLongPress: () => _options(n),
          onSecondaryTap: () => _options(n),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
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
                            fontSize: 14, color: Palette.secondary(context)),
                      ),
                    ),
                  ],
                ),
              ],
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
    return IconButton(tooltip: tip, icon: icon, onPressed: repo.sync);
  }
}

class _EmptyPane extends StatelessWidget {
  const _EmptyPane({required this.onNew});
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
              size: 64, color: Palette.secondary(context)),
          const SizedBox(height: 12),
          Text('Elige una nota o crea una nueva',
              style: TextStyle(color: Palette.secondary(context))),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: onNew,
            icon: const Icon(Icons.add),
            label: const Text('Nueva nota  (Ctrl+N)'),
          ),
        ],
      ),
    );
  }
}
