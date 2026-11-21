import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/note.dart';
import 'widget_bridge.dart';

enum SyncStatus { syncing, synced, pending, offline }

/// Guarda las notas en local (funciona sin internet) y las sincroniza
/// con Supabase: sube los cambios pendientes y recibe los de otros
/// dispositivos en tiempo real. Si hay conflicto gana la edición más reciente.
class NotesRepository extends ChangeNotifier {
  NotesRepository(this._client, this.userId);

  final SupabaseClient _client;
  final String userId;

  final Map<String, Note> _notes = {};
  final Set<String> _dirty = {}; // cambios aún no subidos
  final Set<String> _fresh = {}; // creadas y todavía sin escribir nada

  SyncStatus status = SyncStatus.syncing;
  bool loaded = false;

  RealtimeChannel? _channel;
  Timer? _periodic;
  Timer? _pushDebounce;
  Timer? _saveDebounce;
  SharedPreferences? _prefs;
  bool _syncing = false;
  bool _syncAgain = false;
  bool _disposed = false;

  String get _cacheKey => 'notas_cache_$userId';
  String get _dirtyKey => 'notas_dirty_$userId';

  List<Note> get notes {
    final list = _notes.values.where((n) => !n.deleted).toList()
      ..sort((a, b) {
        if (a.pinned != b.pinned) return a.pinned ? -1 : 1;
        return b.updatedAt.compareTo(a.updatedAt);
      });
    return list;
  }

  Note? byId(String id) => _notes[id];

  // ---------------------------------------------------------------- ciclo

  Future<void> start() async {
    _prefs = await SharedPreferences.getInstance();
    if (_disposed) return;
    _loadLocal();
    loaded = true;
    _notify();
    _subscribe();
    unawaited(sync());
    _periodic = Timer.periodic(const Duration(seconds: 45), (_) => sync());
  }

  @override
  void dispose() {
    _disposed = true;
    _periodic?.cancel();
    _pushDebounce?.cancel();
    _saveDebounce?.cancel();
    _persist();
    final ch = _channel;
    if (ch != null) {
      unawaited(_client.removeChannel(ch));
    }
    super.dispose();
  }

  // ------------------------------------------------------------- cambios

  Note createNote() {
    final now = DateTime.now().toUtc();
    final n = Note(id: newNoteId(), content: '', createdAt: now, updatedAt: now);
    _notes[n.id] = n;
    _fresh.add(n.id);
    _notify();
    return n;
  }

  void updateContent(String id, String content) {
    final n = _notes[id];
    if (_disposed || n == null || n.content == content) return;
    n.content = content;
    n.updatedAt = DateTime.now().toUtc();
    _touch(id);
  }

  void togglePin(String id) {
    final n = _notes[id];
    if (_disposed || n == null) return;
    n.pinned = !n.pinned;
    n.updatedAt = DateTime.now().toUtc();
    _touch(id);
  }

  void delete(String id) {
    final n = _notes[id];
    if (_disposed || n == null) return;
    if (_fresh.contains(id)) {
      _fresh.remove(id);
      _notes.remove(id);
      _notify();
      return;
    }
    n.deleted = true;
    n.updatedAt = DateTime.now().toUtc();
    _touch(id);
  }

  /// Al salir del editor: una nota que se ha quedado vacía se elimina.
  void finishEditing(String id) {
    final n = _notes[id];
    if (_disposed || n == null || n.deleted) return;
    if (n.isEmpty) delete(id);
  }

  void _touch(String id) {
    _fresh.remove(id);
    _dirty.add(id);
    if (status != SyncStatus.offline) status = SyncStatus.pending;
    _schedulePersist();
    _pushDebounce?.cancel();
    _pushDebounce = Timer(const Duration(milliseconds: 900), _pushNow);
    _notify();
  }

  // -------------------------------------------------------- sincronizar

  Future<void> sync() async {
    if (_disposed) return;
    if (_syncing) {
      _syncAgain = true;
      return;
    }
    _syncing = true;
    _setStatus(SyncStatus.syncing);
    try {
      await _pushDirty();
      final rows = await _client.from('notes').select();
      var changed = false;
      for (final r in rows) {
        if (_mergeRemote(Note.fromRow(r))) changed = true;
      }
      _persist();
      if (changed) _notify();
      _setStatus(_dirty.isEmpty ? SyncStatus.synced : SyncStatus.pending);
    } catch (e) {
      debugPrint('Error al sincronizar: $e');
      _setStatus(SyncStatus.offline);
    } finally {
      _syncing = false;
      if (_syncAgain && !_disposed) {
        _syncAgain = false;
        unawaited(sync());
      }
    }
  }

  Future<void> _pushNow() async {
    if (_disposed) return;
    if (_syncing) {
      _syncAgain = true;
      return;
    }
    _syncing = true;
    try {
      await _pushDirty();
      _persist();
      _setStatus(_dirty.isEmpty ? SyncStatus.synced : SyncStatus.pending);
    } catch (e) {
      debugPrint('Error al subir: $e');
      _setStatus(SyncStatus.offline);
    } finally {
      _syncing = false;
      if (_syncAgain && !_disposed) {
        _syncAgain = false;
        unawaited(sync());
      }
    }
  }

  Future<void> _pushDirty() async {
    if (_dirty.isEmpty) return;
    final sent = <String, DateTime>{};
    final rows = <Map<String, dynamic>>[];
    for (final id in _dirty.toList()) {
      final n = _notes[id];
      if (n == null) {
        _dirty.remove(id);
        continue;
      }
      sent[id] = n.updatedAt;
      rows.add(n.toRow(userId: userId));
    }
    if (rows.isEmpty) return;
    await _client.from('notes').upsert(rows);
    // Solo se marca como subido si no se ha vuelto a editar mientras tanto.
    sent.forEach((id, ts) {
      if (_notes[id]?.updatedAt == ts) _dirty.remove(id);
    });
  }

  /// Devuelve true si la versión remota sustituye a la local.
  bool _mergeRemote(Note remote) {
    final local = _notes[remote.id];
    if (local != null && !remote.updatedAt.isAfter(local.updatedAt)) {
      return false;
    }
    _notes[remote.id] = remote;
    _dirty.remove(remote.id);
    _fresh.remove(remote.id);
    return true;
  }

  void _subscribe() {
    _channel = _client
        .channel('notas-$userId')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'notes',
          callback: (payload) {
            final rec = payload.newRecord;
            if (_disposed || rec.isEmpty) return;
            try {
              if (_mergeRemote(Note.fromRow(rec))) {
                _schedulePersist();
                _notify();
              }
            } catch (e) {
              debugPrint('Realtime: $e');
            }
          },
        )
        .subscribe((state, _) {
      // Al (re)conectar, sincronizamos por si nos perdimos algo.
      if (state == RealtimeSubscribeStatus.subscribed) unawaited(sync());
    });
  }

  // ------------------------------------------------------------- local

  void _loadLocal() {
    final prefs = _prefs!;
    try {
      final raw = prefs.getString(_cacheKey);
      if (raw != null) {
        for (final m in jsonDecode(raw) as List) {
          final n = Note.fromRow(Map<String, dynamic>.from(m as Map));
          _notes[n.id] = n;
        }
      }
      _dirty.addAll(prefs.getStringList(_dirtyKey) ?? const []);
      _dirty.removeWhere((id) => !_notes.containsKey(id));
    } catch (e) {
      debugPrint('Caché local dañada, se ignora: $e');
    }
  }

  void _persist() {
    final prefs = _prefs;
    if (prefs == null) return;
    final list = _notes.values
        .where((n) => !_fresh.contains(n.id))
        .map((n) => n.toRow())
        .toList();
    prefs.setString(_cacheKey, jsonEncode(list));
    prefs.setStringList(_dirtyKey, _dirty.toList());
  }

  void _schedulePersist() {
    _saveDebounce?.cancel();
    _saveDebounce = Timer(const Duration(milliseconds: 400), _persist);
  }

  void _setStatus(SyncStatus s) {
    if (_disposed || status == s) return;
    status = s;
    notifyListeners();
  }

  void _notify() {
    if (_disposed) return;
    notifyListeners();
    WidgetBridge.schedule(notes);
  }
}
