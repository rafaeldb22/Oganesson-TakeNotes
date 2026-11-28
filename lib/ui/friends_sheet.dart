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

  Widget _label(String text) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 10, 4, 6),
        child: Text(text.toUpperCase(),
            style: TextStyle(
                fontSize: 11.5,
                letterSpacing: 0.8,
                fontWeight: FontWeight.w800,
                color: Palette.of(context).secondary)),
      );

  Widget _person(Person x, {required bool inResults}) {
    final p = Palette.of(context);
    return Padding(
      key: ValueKey('${inResults ? 'r' : 'f'}-${x.id}'),
      padding: const EdgeInsets.only(bottom: 6),
      child: Material(
        color: p.background,
        borderRadius: BorderRadius.circular(14),
        child: ListTile(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          contentPadding: const EdgeInsets.only(left: 10, right: 4),
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
                  onPressed:
                      _busy ? null : () => inResults ? _add(x) : _remove(x),
                ),
        ),
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
          // Tarjeta de perfil.
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: [
                p.accent.withValues(alpha: 0.22),
                p.accent.withValues(alpha: 0.06),
              ], begin: Alignment.topLeft, end: Alignment.bottomRight),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(children: [
              PersonAvatar(name: _username ?? '?', radius: 26),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                        _username == null
                            ? tr('Tu @nombre y amigos')
                            : '@$_username',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 20, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 2),
                    Text(
                        tr('Entra con tu @nombre y comparte sin enseñar tu correo.'),
                        style: TextStyle(color: p.secondary, fontSize: 12.5)),
                  ],
                ),
              ),
              if (!_loading && !AppConfig.demo)
                Column(children: [
                  Text('${_friends.length}',
                      style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          color: p.accent)),
                  Text(tr('amigos'),
                      style: TextStyle(fontSize: 11.5, color: p.secondary)),
                ]),
            ]),
          )
              .animate()
              .fadeIn(duration: Anim.medium)
              .slideY(begin: 0.15, curve: Anim.curve),
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
                  if (_results.isNotEmpty) _label(tr('Resultados')),
                  for (final (i, x) in _results.indexed)
                    _person(x, inResults: true)
                        .animate(delay: (24 * i).ms)
                        .fadeIn(duration: Anim.medium)
                        .slideY(begin: 0.12, curve: Anim.curve),
                  if (_friends.isNotEmpty) _label(tr('Tus amigos')),
                  if (_friends.isEmpty && _results.isEmpty && !AppConfig.demo)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 18),
                      child: Text(tr('Todavía no tienes amigos añadidos.'),
                          textAlign: TextAlign.center,
                          style: TextStyle(color: p.secondary)),
                    ),
                  for (final (i, x) in _friends.indexed)
                    _person(x, inResults: false)
                        .animate(delay: (30 * i + 80).ms)
                        .fadeIn(duration: Anim.medium)
                        .slideX(begin: 0.08, curve: Anim.curve),
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
  const PersonAvatar({super.key, required this.name, this.radius = 16});
  final String name;
  final double radius;

  static const _tones = [
    Color(0xFF3E7BFA),
    Color(0xFF30A46C),
    Color(0xFFF76B15),
    Color(0xFF8E4EC6),
    Color(0xFFE5484D),
    Color(0xFF12A594),
    Color(0xFFD99A00),
  ];

  @override
  Widget build(BuildContext context) {
    final clean = name.startsWith('@') ? name.substring(1) : name;
    // Cada persona con su color (siempre el mismo para el mismo nombre).
    final c = _tones[clean.codeUnits.fold(0, (a, b) => a + b) % _tones.length];
    return Container(
      width: radius * 2,
      height: radius * 2,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
            colors: [c, Color.lerp(c, Colors.white, 0.35)!],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight),
      ),
      child: Text(clean.isEmpty ? '?' : clean[0].toUpperCase(),
          style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w800,
              fontSize: radius * 0.9)),
    );
  }
}
