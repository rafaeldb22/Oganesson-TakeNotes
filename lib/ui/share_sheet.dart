import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../config.dart';
import '../data/note_sharing.dart';
import '../data/notes_repository.dart';
import 'anim.dart';
import 'i18n.dart';
import 'theme.dart';
import 'toast.dart';

/// Compartir una nota con otras cuentas, o ver quién la comparte contigo.
Future<void> showShareSheet(
    BuildContext context, NotesRepository repo, String noteId) {
  return showModalBottomSheet<void>(
    context: context,
    useSafeArea: true,
    isScrollControlled: true,
    constraints: BoxConstraints(
        maxWidth: 520, maxHeight: MediaQuery.sizeOf(context).height * 0.85),
    builder: (_) => _ShareSheet(repo: repo, noteId: noteId),
  );
}

class _ShareSheet extends StatefulWidget {
  const _ShareSheet({required this.repo, required this.noteId});
  final NotesRepository repo;
  final String noteId;

  @override
  State<_ShareSheet> createState() => _ShareSheetState();
}

class _ShareSheetState extends State<_ShareSheet> {
  final _email = TextEditingController();
  late final NoteSharing _api = NoteSharing(widget.repo.client);
  List<SharePerson> _people = const [];
  String _role = 'edit';
  bool _loading = !AppConfig.demo;
  bool _busy = false;
  String? _error =
      AppConfig.demo ? tr('Las notas compartidas necesitan una cuenta.') : null;

  bool get _foreign {
    final n = widget.repo.byId(widget.noteId);
    return n != null && widget.repo.isForeign(n);
  }

  @override
  void initState() {
    super.initState();
    if (!AppConfig.demo) _load();
  }

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final p = await _api.people(widget.noteId);
      if (mounted) {
        setState(() {
          _people = p;
          _loading = false;
          _error = null;
        });
      }
    } on ShareException catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = e.message;
        });
      }
    }
  }

  Future<void> _run(Future<void> Function() job) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await job();
      await _load();
      await widget.repo.sync();
    } on ShareException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _invite() {
    final email = _email.text.trim();
    if (email.isEmpty) return;
    _run(() async {
      await _api.share(widget.noteId, email, _role);
      _email.clear();
      if (mounted) {
        showToast(context, trf('Compartida con {0}', [email.toLowerCase()]),
            icon: Icons.group_add_outlined);
      }
    });
  }

  Future<void> _leave() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('¿Dejar de ver esta nota?')),
        content:
            Text(tr('Desaparecerá de tu cuenta. Quien la creó la conserva.')),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(tr('Cancelar'))),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(tr('Salir'))),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _busy = true);
    try {
      await _api.leave(widget.noteId);
      widget.repo.dropForeign(widget.noteId);
      if (mounted) Navigator.pop(context);
    } on ShareException catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = e.message;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final foreign = _foreign;
    final canInvite = !foreign && !AppConfig.demo;
    return Padding(
      padding: EdgeInsets.fromLTRB(
          20, 0, 20, 16 + MediaQuery.viewInsetsOf(context).bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(foreign ? tr('Nota compartida') : tr('Compartir nota'),
              style:
                  const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          Text(
              foreign
                  ? tr('Otra persona te ha dado acceso a esta nota.')
                  : tr('La verá al entrar con ese correo en Oganesson.'),
              style: TextStyle(color: p.secondary, fontSize: 13)),
          const SizedBox(height: 14),
          if (canInvite) ...[
            TextField(
              key: const ValueKey('correo-compartir'),
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              autocorrect: false,
              onSubmitted: (_) => _invite(),
              decoration: InputDecoration(
                hintText: tr('Correo de la otra cuenta'),
                prefixIcon: const Icon(Icons.alternate_email_rounded, size: 19),
                isDense: true,
                filled: true,
                fillColor: p.background,
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none),
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: SegmentedButton<String>(
                    showSelectedIcon: false,
                    segments: [
                      ButtonSegment(
                          value: 'edit',
                          icon: const Icon(Icons.edit_outlined, size: 16),
                          label: Text(tr('Puede editar'))),
                      ButtonSegment(
                          value: 'read',
                          icon: const Icon(Icons.visibility_outlined, size: 16),
                          label: Text(tr('Solo ver'))),
                    ],
                    selected: {_role},
                    onSelectionChanged: (s) => setState(() => _role = s.first),
                  ),
                ),
                const SizedBox(width: 10),
                Bouncy(
                  child: FilledButton(
                    onPressed: _busy ? null : _invite,
                    child: Text(tr('Compartir')),
                  ),
                ),
              ],
            ),
          ],
          AnimatedSize(
            duration: Anim.medium,
            curve: Anim.curve,
            alignment: Alignment.topCenter,
            child: _error == null
                ? const SizedBox(width: double.infinity)
                : Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: Text(_error!,
                        style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                            fontSize: 13)),
                  ),
          ),
          const SizedBox(height: 10),
          if (_loading)
            const Padding(
              padding: EdgeInsets.all(18),
              child: Center(
                  child: SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2.5))),
            )
          else
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final (i, person) in _people.indexed)
                    ListTile(
                      key: ValueKey(person.email),
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: CircleAvatar(
                        radius: 16,
                        backgroundColor: p.accent.withValues(alpha: 0.15),
                        child: Text(person.email[0].toUpperCase(),
                            style: TextStyle(
                                color: p.accent, fontWeight: FontWeight.w800)),
                      ),
                      title: Text(person.email,
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                      subtitle: Text(switch (person.role) {
                        'owner' => tr('Propietario'),
                        'read' => tr('Solo ver'),
                        _ => tr('Puede editar'),
                      }),
                      trailing: !foreign && !person.isOwner
                          ? IconButton(
                              tooltip: tr('Quitar'),
                              icon: const Icon(Icons.close_rounded, size: 18),
                              onPressed: _busy
                                  ? null
                                  : () => _run(() => _api.unshare(
                                      widget.noteId, person.email)),
                            )
                          : null,
                    )
                        .animate(delay: (30 * i.clamp(0, 8)).ms)
                        .fadeIn(duration: Anim.medium)
                        .slideY(begin: 0.12, curve: Anim.curve),
                ],
              ),
            ),
          if (foreign) ...[
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _busy ? null : _leave,
              icon: const Icon(Icons.logout_rounded, size: 18),
              label: Text(tr('Dejar de ver esta nota')),
            ),
          ],
        ],
      ),
    );
  }
}
