import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/note.dart';

/// Una versión anterior de una nota.
class NoteVersion {
  NoteVersion(this.at, this.content, this.rich);
  final DateTime at;
  final String content;
  final String? rich;

  Map<String, dynamic> toJson() =>
      {'at': at.toUtc().toIso8601String(), 'c': content, 'r': rich};

  static NoteVersion? fromJson(Object? v) {
    if (v is! Map || v['c'] is! String) return null;
    final at = DateTime.tryParse('${v['at']}');
    return at == null
        ? null
        : NoteVersion(at.toUtc(), v['c'] as String, v['r'] as String?);
  }
}

/// Historial local: guarda cómo estaba una nota antes de cambiarla, como
/// mucho una versión cada [gap] y [maxPerNote] por nota. Las notas del Vault
/// nunca pasan por aquí.
class NoteHistory {
  NoteHistory({SharedPreferences? prefs, this.scope = ''}) : _prefs = prefs;

  /// Cuenta dueña del historial: cada una tiene el suyo.
  final String scope;

  static const maxPerNote = 20;
  static const maxNotes = 200;
  static const gap = Duration(minutes: 5);
  String get _key => 'note_history_v1_$scope';

  SharedPreferences? _prefs;
  final Map<String, List<NoteVersion>> _data = {};
  bool _loaded = false;

  /// Carga lo guardado; lo registrado antes de cargar se conserva.
  Future<void> load([SharedPreferences? prefs]) async {
    if (_loaded) return;
    _loaded = true;
    final p = _prefs = prefs ?? _prefs ?? await SharedPreferences.getInstance();
    try {
      final raw = p.getString(_key);
      if (raw == null) return;
      (jsonDecode(raw) as Map).forEach((id, list) {
        final saved = (list as List)
            .map(NoteVersion.fromJson)
            .whereType<NoteVersion>()
            .toList();
        _data[id as String] = [...saved, ...?_data[id]];
      });
    } catch (_) {
      // Un historial dañado no debe impedir usar la app.
    }
  }

  List<NoteVersion> versionsOf(String id) =>
      List.unmodifiable((_data[id] ?? const <NoteVersion>[]).reversed);

  /// Guarda el estado actual de [n], que está a punto de cambiar.
  void record(Note n, {DateTime? now}) {
    if (n.vault || n.content.trim().isEmpty) return;
    final at = (now ?? DateTime.now()).toUtc();
    final list = _data.putIfAbsent(n.id, () => []);
    if (list.isNotEmpty) {
      final last = list.last;
      if (last.content == n.content) return;
      if (at.difference(last.at) < gap) return;
    }
    list.add(NoteVersion(at, n.content, n.rich));
    if (list.length > maxPerNote) list.removeAt(0);
    if (_data.length > maxNotes) _dropOldest();
    _save();
  }

  void forget(String id) {
    if (_data.remove(id) != null) _save();
  }

  void _dropOldest() {
    final ids = _data.keys.toList()
      ..sort((a, b) => _data[a]!.last.at.compareTo(_data[b]!.last.at));
    for (final id in ids.take(_data.length - maxNotes)) {
      _data.remove(id);
    }
  }

  void _save() {
    final p = _prefs;
    if (p == null) return;
    p.setString(
        _key,
        jsonEncode({
          for (final e in _data.entries)
            e.key: [for (final v in e.value) v.toJson()]
        }));
  }
}
