import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../config.dart';
import '../data/accounts.dart';
import '../data/notes_repository.dart';
import 'anim.dart';
import 'i18n.dart';
import 'text_menu.dart';
import 'theme.dart';
import 'toast.dart';

/// Tu @nombre y tu lista de amigos.
Future<void> showFriendsSheet(BuildContext context, NotesRepository repo) {
  return showModalBottomSheet<void>(
    context: context,
    useSafeArea: true,
    isScrollControlled: true,
    constraints: BoxConstraints(
        maxWidth: 520, maxHeight: MediaQuery.sizeOf(context).height * 0.85),
    builder: (_) => _FriendsSheet(repo: repo),
  );
}

class _FriendsSheet extends StatefulWidget {
  const _FriendsSheet({required this.repo});
  final NotesRepository repo;

  @override
  State<_FriendsSheet> createState() => _FriendsSheetState();
}

class _FriendsSheetState extends State<_FriendsSheet> {
  late final Accounts _api = Accounts(widget.repo.client);
  final _name = TextEditingController();
  final _search = TextEditingController();
  Timer? _debounce;
  String? _username;
  List<Person> _friends = const [];
  List<Person> _results = const [];
  bool _loading = !AppConfig.demo;
  bool _busy = false;
  String? _error =
      AppConfig.demo ? tr('Los amigos necesitan una cuenta.') : null;

  @override
  void initState() {
    super.initState();
    if (!AppConfig.demo) _load();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _name.dispose();
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final me = await _api.myUsername();
      final friends = await _api.friends();
      if (!mounted) return;
      setState(() {
        _username = me;
        _name.text = me ?? '';
        _friends = friends;
        _loading = false;
      });
    } on AccountException catch (e) {
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
    } on AccountException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _saveName() {
    final v = cleanUsername(_name.text);
    if (v == _username) return;
    if (!validUsername(v)) {
      setState(
          () => _error = tr('Usa de 3 a 20 letras, números o guiones bajos.'));
      return;
    }
    _run(() async {
      final saved = await _api.setUsername(v);
      if (!mounted) return;
      setState(() => _username = saved);
      showToast(context, trf('Ahora eres @{0}', [saved]),
          icon: Icons.check_circle_outline_rounded);
    });
  }

  void _onSearch(String q) {
    _debounce?.cancel();
    if (cleanUsername(q).length < 2) {
      setState(() => _results = const []);
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 280), () async {
      try {
        final found = await _api.search(q);
        if (mounted && _search.text == q) {
          setState(() {
            _results = found;
            _error = null;
          });
        }
      } on AccountException catch (e) {
        if (mounted) setState(() => _error = e.message);
      }
    });
  }

  void _add(Person x) => _run(() async {
        await _api.addFriend(x.id);
        final friends = await _api.friends();
        if (!mounted) return;
        setState(() {
          _friends = friends;
          _results = [
            for (final r in _results)
              r.id == x.id ? Person(r.id, r.username, isFriend: true) : r,
          ];
        });
      });

  void _remove(Person x) => _run(() async {
        await _api.removeFriend(x.id);
        final friends = await _api.friends();
        if (!mounted) return;
        setState(() {
          _friends = friends;
          _results = [
            for (final r in _results)
              r.id == x.id ? Person(r.id, r.username) : r,
          ];
        });
      });

  Widget _person(Person x, {required bool inResults}) {
    final p = Palette.of(context);
    return ListTile(
      key: ValueKey('${inResults ? 'r' : 'f'}-${x.id}'),
      dense: true,
      contentPadding: EdgeInsets.zero,
      leading: PersonAvatar(name: x.username),
      title: Text(x.handle, maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: inResults && x.isFriend
          ? Icon(Icons.check_rounded, color: p.accent, size: 20)
          : IconButton(
              tooltip: inResults ? tr('Añadir') : tr('Quitar'),
              icon: Icon(
                  inResults
                      ? Icons.person_add_alt_rounded
                      : Icons.close_rounded,
                  size: 19),
              onPressed: _busy ? null : () => inResults ? _add(x) : _remove(x),
            ),
    );
  }

  InputDecoration _deco(String hint, IconData icon) => InputDecoration(
        hintText: hint,
        prefixIcon: Icon(icon, size: 19),
        isDense: true,
        filled: true,
        fillColor: Palette.of(context).background,
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none),
      );

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(
          20, 0, 20, 16 + MediaQuery.viewInsetsOf(context).bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(tr('Tu @nombre y amigos'),
              style:
                  const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          Text(tr('Entra con tu @nombre y comparte sin enseñar tu correo.'),
              style: TextStyle(color: p.secondary, fontSize: 13)),
          const SizedBox(height: 14),
          if (_loading)
            const Padding(
              padding: EdgeInsets.all(22),
              child: Center(
                  child: SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2.5))),
            )
          else if (!AppConfig.demo) ...[
            Row(
              children: [
                Expanded(
                  child: TextField(
                    key: const ValueKey('mi-nombre'),
                    contextMenuBuilder: textFieldMenu,
                    controller: _name,
                    autocorrect: false,
                    maxLength: 21,
                    onSubmitted: (_) => _saveName(),
                    decoration:
                        _deco(tr('Tu @nombre'), Icons.alternate_email_rounded)
                            .copyWith(counterText: ''),
                  ),
                ),
                const SizedBox(width: 10),
                Bouncy(
                  child: FilledButton(
                    onPressed: _busy ? null : _saveName,
                    child: Text(tr('Guardar')),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              key: const ValueKey('buscar-amigos'),
              contextMenuBuilder: textFieldMenu,
              controller: _search,
              autocorrect: false,
              onChanged: _onSearch,
              decoration: _deco(tr('Buscar por @nombre'), Icons.search_rounded),
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
          const SizedBox(height: 8),
          if (!_loading)
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final (i, x) in _results.indexed)
                    _person(x, inResults: true)
                        .animate(delay: (24 * i).ms)
                        .fadeIn(duration: Anim.medium)
                        .slideY(begin: 0.12, curve: Anim.curve),
                  if (_results.isNotEmpty) const Divider(height: 16),
                  if (_friends.isEmpty && _results.isEmpty && !AppConfig.demo)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 18),
                      child: Text(tr('Todavía no tienes amigos añadidos.'),
                          textAlign: TextAlign.center,
                          style: TextStyle(color: p.secondary)),
                    ),
                  for (final x in _friends) _person(x, inResults: false),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// Inicial del @nombre en un círculo.
class PersonAvatar extends StatelessWidget {
  const PersonAvatar({super.key, required this.name});
  final String name;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final clean = name.startsWith('@') ? name.substring(1) : name;
    return CircleAvatar(
      radius: 16,
      backgroundColor: p.accent.withValues(alpha: 0.15),
      child: Text(clean.isEmpty ? '?' : clean[0].toUpperCase(),
          style: TextStyle(color: p.accent, fontWeight: FontWeight.w800)),
    );
  }
}
