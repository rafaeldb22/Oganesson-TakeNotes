import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../data/notes_repository.dart';
import '../data/vault.dart';
import '../models/note.dart';
import 'anim.dart';
import 'context_menu.dart';
import 'format.dart';
import 'i18n.dart';
import 'note_editor.dart';
import 'notes_home.dart' show confirmDelete;
import 'theme.dart';

/// Abre la pantalla del Vault (el Vault ya debe estar desbloqueado).
Future<void> openVaultScreen(
    BuildContext context, NotesRepository repo, VaultLock vault) {
  return Navigator.of(context).push(MaterialPageRoute(
    builder: (_) => VaultScreen(repo: repo, vault: vault),
  ));
}

/// Notas del Vault. Solo se llega desde ⋯ → Vault; al bloquearse (a mano o
/// tras 5 minutos sin uso) se cierra sola.
class VaultScreen extends StatefulWidget {
  const VaultScreen({super.key, required this.repo, required this.vault});
  final NotesRepository repo;
  final VaultLock vault;

  @override
  State<VaultScreen> createState() => _VaultScreenState();
}

class _VaultScreenState extends State<VaultScreen> {
  NotesRepository get repo => widget.repo;
  VaultLock get vault => widget.vault;

  @override
  void initState() {
    super.initState();
    vault.addListener(_onVault);
  }

  @override
  void dispose() {
    vault.removeListener(_onVault);
    super.dispose();
  }

  void _onVault() {
    if (!vault.unlocked && mounted) {
      // Bloqueado: fuera del Vault (y de cualquier nota suya abierta).
      final route = ModalRoute.of(context);
      Navigator.of(context).popUntil((r) => r.isFirst || r == route);
      if (Navigator.of(context).canPop()) Navigator.of(context).pop();
    }
  }

  Future<void> _openNote(String id, {bool autofocus = false}) async {
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (ctx) => Scaffold(
        body: NoteEditor(
          repo: repo,
          noteId: id,
          autofocus: autofocus,
          showBack: true,
          onClose: () => Navigator.of(ctx).maybePop(),
          onDelete: (nid) {
            repo.delete(nid);
            Navigator.of(ctx).maybePop();
          },
        ),
      ),
    ));
    repo.finishEditing(id);
  }

  void _newNote() {
    final n = repo.createNote();
    repo.setVault(n.id, true);
    _openNote(n.id, autofocus: true);
  }

  Future<void> _addExisting() async {
    final picked = await showDialog<Set<String>>(
      context: context,
      builder: (_) => _PickNotesDialog(repo: repo),
    );
    if (picked == null) return;
    for (final id in picked) {
      repo.setVault(id, true);
    }
  }

  Future<void> _options(Note n, [Offset? at]) async {
    final items = [
      ('out', Icons.lock_open_rounded, tr('Sacar del Vault'), false),
      ('delete', Icons.delete_outline, tr('Eliminar'), true),
    ];
    String? choice;
    if (at != null) {
      choice = await showContextMenu(
        context,
        position: at,
        title: n.title,
        entries: [
          for (final (id, icon, label, danger) in items)
            MenuEntry(id, icon, label, danger: danger),
        ],
      );
    } else {
      choice = await showModalBottomSheet<String>(
        context: context,
        useSafeArea: true,
        showDragHandle: true,
        builder: (ctx) => SafeArea(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            for (final (id, icon, label, _) in items)
              ListTile(
                leading: Icon(icon),
                title: Text(label),
                onTap: () => Navigator.pop(ctx, id),
              ),
          ]),
        ),
      );
    }
    if (!mounted) return;
    if (choice == 'out') {
      repo.setVault(n.id, false);
    } else if (choice == 'delete' && await confirmDelete(context, n.title)) {
      repo.delete(n.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Listener(
      onPointerDown: (_) => vault.touch(),
      child: Scaffold(
        appBar: AppBar(
          title: Row(children: [
            Icon(Icons.shield_outlined, color: p.accent, size: 22),
            const SizedBox(width: 10),
            const Text('Vault'),
          ]),
          actions: [
            IconButton(
              tooltip: tr('Añadir notas existentes'),
              icon: const Icon(Icons.playlist_add_rounded),
              onPressed: _addExisting,
            ),
            IconButton(
              tooltip: tr('Bloquear Vault'),
              icon: const Icon(Icons.lock_outline_rounded),
              onPressed: vault.lock,
            ),
            const SizedBox(width: 4),
          ],
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: _newNote,
          icon: const Icon(Icons.edit_note),
          label: Text(tr('Nueva nota')),
        ),
        body: ListenableBuilder(
          listenable: repo,
          builder: (context, _) {
            final notes = repo.vaultNotes.where((n) => !n.isEmpty).toList();
            if (notes.isEmpty) {
              return Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.shield_outlined, size: 56, color: p.secondary),
                    const SizedBox(height: 12),
                    Text(tr('El Vault está vacío'),
                        style: TextStyle(fontSize: 16, color: p.secondary)),
                    const SizedBox(height: 6),
                    Text(tr('Crea una nota o añade notas que ya tengas.'),
                        style: TextStyle(fontSize: 13, color: p.secondary)),
                  ],
                ),
              ).animate().fadeIn(duration: Anim.medium);
            }
            return ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
              itemCount: notes.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (_, i) {
                final n = notes[i];
                return Material(
                  color: p.card,
                  borderRadius: BorderRadius.circular(14),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(14),
                    onTap: () => _openNote(n.id),
                    onLongPress: () => _options(n),
                    onSecondaryTapUp: (d) => _options(n, d.globalPosition),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(n.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  fontSize: 15.5, fontWeight: FontWeight.w600)),
                          const SizedBox(height: 3),
                          Text(
                            '${fechaCorta(n.updatedAt)}  '
                            '${n.hasPreview ? n.preview : ''}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(color: p.secondary, fontSize: 13),
                          ),
                        ],
                      ),
                    ),
                  ),
                )
                    .animate(delay: (25 * i.clamp(0, 12)).ms)
                    .fadeIn(duration: Anim.medium)
                    .slideY(begin: 0.1, curve: Anim.curve);
              },
            );
          },
        ),
      ),
    );
  }
}

/// Elegir notas normales para moverlas al Vault.
class _PickNotesDialog extends StatefulWidget {
  const _PickNotesDialog({required this.repo});
  final NotesRepository repo;

  @override
  State<_PickNotesDialog> createState() => _PickNotesDialogState();
}

class _PickNotesDialogState extends State<_PickNotesDialog> {
  final _selected = <String>{};

  @override
  Widget build(BuildContext context) {
    final notes = widget.repo.notes.where((n) => !n.isEmpty).toList();
    return AlertDialog(
      title: Text(tr('Mover notas al Vault')),
      content: SizedBox(
        width: 420,
        height: 380,
        child: notes.isEmpty
            ? Center(child: Text(tr('No hay notas')))
            : ListView(
                children: [
                  for (final n in notes)
                    CheckboxListTile(
                      value: _selected.contains(n.id),
                      dense: true,
                      controlAffinity: ListTileControlAffinity.leading,
                      onChanged: (v) => setState(() => v == true
                          ? _selected.add(n.id)
                          : _selected.remove(n.id)),
                      title: Text(n.title,
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                    ),
                ],
              ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(tr('Cancelar'))),
        FilledButton(
          onPressed: _selected.isEmpty
              ? null
              : () => Navigator.pop(context, _selected),
          child: Text(tr('Mover al Vault')),
        ),
      ],
    );
  }
}
