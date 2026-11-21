import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/note.dart';
import 'widget_bridge.dart';

enum SyncStatus { syncing, synced, pending, offline }

/// Guarda notas y carpetas en local (funciona sin internet) y las sincroniza
/// con Supabase: sube los cambios pendientes y recibe los de otros
/// dispositivos en tiempo real. Si hay conflicto gana la edición más reciente.
class NotesRepository extends ChangeNotifier {
  NotesRepository(this._client, this.userId);

  final SupabaseClient _client;
  final String userId;

  final Map<String, Note> _notes = {};
  final Set<String> _dirty = {}; // notas con cambios aún no subidos
  final Set<String> _fresh = {}; // notas creadas y todavía vacías

  final Set<String> _purge = {}; // borrados definitivos pendientes de subir

  /// Días que una nota pasa en la papelera antes de borrarse del todo.
  static const trashDays = 3;

  final Map<String, Folder> _folders = {};
  final Set<String> _dirtyFolders = {};

  SyncStatus status = SyncStatus.syncing;
  bool loaded = false;

  /// Sube cada vez que cambia algo: sirve para no recalcular listas.
  int version = 0;

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
  String get _foldersKey => 'carpetas_cache_$userId';
  String get _dirtyFoldersKey => 'carpetas_dirty_$userId';
  String get _purgeKey => 'notas_purga_$userId';

  // ------------------------------------------------------------ lecturas

  List<Note>? _sortedCache;
  int _sortedVersion = -1;

  List<Note> get notes {
    if (_sortedCache != null && _sortedVersion == version) return _sortedCache!;
    final list = _notes.values.where((n) => !n.deleted).toList()
      ..sort((a, b) {
        if (a.pinned != b.pinned) return a.pinned ? -1 : 1;
        return b.updatedAt.compareTo(a.updatedAt);
      });
    _sortedCache = list;
    _sortedVersion = version;
    return list;
  }

  /// Notas temporales ordenadas por fecha límite.
  List<Note> get temporales => notes
      .where((n) => n.isTemporal && !n.isEmpty)
      .toList()
    ..sort((a, b) => a.dueAt!.compareTo(b.dueAt!));

  List<Folder> get folders => _folders.values
      .where((f) => !f.deleted)
      .toList()
    ..sort((a, b) => a.createdAt.compareTo(b.createdAt));

  /// Notas en la papelera (borradas hace menos de 3 días), más recientes antes.
  List<Note> get trash {
    final limit =
        DateTime.now().toUtc().subtract(const Duration(days: trashDays));
    return _notes.values
        .where((n) =>
            n.deleted && !n.isEmpty && !_purge.contains(n.id) &&
            n.updatedAt.isAfter(limit))
        .toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
  }

  /// Cuándo se borrará del todo una nota de la papelera.
  DateTime purgeDate(Note n) =>
      n.updatedAt.add(const Duration(days: trashDays));

  /// Borra para siempre (de este dispositivo y de la nube).
  void deleteForever(String id) {
    if (_disposed || !_notes.containsKey(id)) return;
    _notes.remove(id);
    _dirty.remove(id);
    _purge.add(id);
    _changed();
  }

  void emptyTrash() {
    for (final n in trash) {
      _notes.remove(n.id);
      _dirty.remove(n.id);
      _purge.add(n.id);
    }
    _changed();
  }

  /// Pasa a borrado definitivo lo que lleva más de 3 días en la papelera.
  void _autoPurge() {
    final limit =
        DateTime.now().toUtc().subtract(const Duration(days: trashDays));
    final old = _notes.values
        .where((n) => n.deleted && !n.updatedAt.isAfter(limit))
        .map((n) => n.id)
        .toList();
    for (final id in old) {
      _notes.remove(id);
      _dirty.remove(id);
      _purge.add(id);
    }
  }

  Note? byId(String id) => _notes[id];
  Folder? folderById(String? id) => id == null ? null : _folders[id];

  int countIn(String folderId) =>
      notes.where((n) => n.folderId == folderId && !n.isEmpty).length;

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

  // ------------------------------------------------------- cambios notas

  Note createNote({String? folderId, DateTime? dueAt, DateTime? remindAt}) {
    final now = DateTime.now().toUtc();
    final n = Note(
      id: newNoteId(),
      content: '',
      createdAt: now,
      updatedAt: now,
      folderId: folderId,
      dueAt: dueAt,
      remindAt: remindAt,
    );
    _notes[n.id] = n;
    _fresh.add(n.id);
    _notify();
    return n;
  }

  void updateContent(String id, String content, {String? rich}) {
    final n = _notes[id];
    if (_disposed || n == null) return;
    if (n.content == content && n.rich == rich) return;
    n.content = content;
    n.rich = rich;
    n.updatedAt = DateTime.now().toUtc();
    _touch(id);
  }

  void togglePin(String id) => _edit(id, (n) => n.pinned = !n.pinned);

  void toggleDone(String id) => _edit(id, (n) => n.done = !n.done);

  void setColor(String id, int? color) => _edit(id, (n) => n.color = color);

  void moveToFolder(String id, String? folderId) =>
      _edit(id, (n) => n.folderId = folderId);

  void setSchedule(String id, {DateTime? remindAt, DateTime? dueAt}) =>
      _edit(id, (n) {
        n.remindAt = remindAt?.toUtc();
        n.dueAt = dueAt?.toUtc();
        if (dueAt == null) n.done = false;
      });

  void _edit(String id, void Function(Note n) change) {
    final n = _notes[id];
    if (_disposed || n == null) return;
    change(n);
    n.updatedAt = DateTime.now().toUtc();
    // Una nota "fresca" con fecha o carpeta ya cuenta como nota real
    // solo cuando tenga texto; si sigue vacía se descartará al cerrar.
    if (_fresh.contains(id) && n.isEmpty) {
      _notify();
      return;
    }
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

  /// Deshace un borrado (botón "Deshacer").
  void restore(String id) {
    final n = _notes[id];
    if (_disposed || n == null || !n.deleted) return;
    n.deleted = false;
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
    _changed();
  }

  // ----------------------------------------------------- cambios carpetas

  Folder createFolder(String name, {int? color}) {
    final now = DateTime.now().toUtc();
    final f = Folder(
        id: newNoteId(),
        name: name.trim(),
        color: color,
        createdAt: now,
        updatedAt: now);
    _folders[f.id] = f;
    _dirtyFolders.add(f.id);
    _changed();
    return f;
  }

  void renameFolder(String id, String name, {int? color}) {
    final f = _folders[id];
    if (_disposed || f == null) return;
    f.name = name.trim();
    if (color != null) f.color = color;
    f.updatedAt = DateTime.now().toUtc();
    _dirtyFolders.add(id);
    _changed();
  }

  /// Borra la carpeta; sus notas pasan a "Todas" (no se borran).
  void deleteFolder(String id) {
    final f = _folders[id];
    if (_disposed || f == null) return;
    f.deleted = true;
    f.updatedAt = DateTime.now().toUtc();
    _dirtyFolders.add(id);
    for (final n in _notes.values.where((n) => n.folderId == id).toList()) {
      n.folderId = null;
      n.updatedAt = DateTime.now().toUtc();
      _dirty.add(n.id);
    }
    _changed();
  }

  void _changed() {
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
      var changed = false;
      final rows = await _client.from('notes').select();
      for (final r in rows) {
        if (_mergeNote(Note.fromRow(r))) changed = true;
      }
      try {
        final frows = await _client.from('folders').select();
        for (final r in frows) {
          if (_mergeFolder(Folder.fromRow(r))) changed = true;
        }
      } catch (e) {
        debugPrint('Carpetas: $e');
      }
      _persist();
      if (changed) _notify();
      _setStatus(_isClean ? SyncStatus.synced : SyncStatus.pending);
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

  bool get _isClean =>
      _dirty.isEmpty && _dirtyFolders.isEmpty && _purge.isEmpty;

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
      _setStatus(_isClean ? SyncStatus.synced : SyncStatus.pending);
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
    _autoPurge();
    // Borrados definitivos.
    if (_purge.isNotEmpty) {
      final ids = _purge.toList();
      await _client.from('notes').delete().inFilter('id', ids);
      _purge.removeAll(ids);
    }

    // Primero carpetas (las notas pueden apuntar a ellas).
    if (_dirtyFolders.isNotEmpty) {
      final sent = <String, DateTime>{};
      final rows = <Map<String, dynamic>>[];
      for (final id in _dirtyFolders.toList()) {
        final f = _folders[id];
        if (f == null) {
          _dirtyFolders.remove(id);
          continue;
        }
        sent[id] = f.updatedAt;
        rows.add(f.toRow(userId: userId));
      }
      if (rows.isNotEmpty) {
        await _client.from('folders').upsert(rows);
        sent.forEach((id, ts) {
          if (_folders[id]?.updatedAt == ts) _dirtyFolders.remove(id);
        });
      }
    }

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
  bool _mergeNote(Note remote) {
    if (_purge.contains(remote.id)) return false;
    final local = _notes[remote.id];
    if (local != null && !remote.updatedAt.isAfter(local.updatedAt)) {
      return false;
    }
    _notes[remote.id] = remote;
    _dirty.remove(remote.id);
    _fresh.remove(remote.id);
    return true;
  }

  bool _mergeFolder(Folder remote) {
    final local = _folders[remote.id];
    if (local != null && !remote.updatedAt.isAfter(local.updatedAt)) {
      return false;
    }
    _folders[remote.id] = remote;
    _dirtyFolders.remove(remote.id);
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
              if (_mergeNote(Note.fromRow(rec))) {
                _schedulePersist();
                _notify();
              }
            } catch (e) {
              debugPrint('Realtime notas: $e');
            }
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'folders',
          callback: (payload) {
            final rec = payload.newRecord;
            if (_disposed || rec.isEmpty) return;
            try {
              if (_mergeFolder(Folder.fromRow(rec))) {
                _schedulePersist();
                _notify();
              }
            } catch (e) {
              debugPrint('Realtime carpetas: $e');
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
      debugPrint('Caché de notas dañada, se ignora: $e');
    }
    try {
      final raw = prefs.getString(_foldersKey);
      if (raw != null) {
        for (final m in jsonDecode(raw) as List) {
          final f = Folder.fromRow(Map<String, dynamic>.from(m as Map));
          _folders[f.id] = f;
        }
      }
      _dirtyFolders.addAll(prefs.getStringList(_dirtyFoldersKey) ?? const []);
      _purge.addAll(prefs.getStringList(_purgeKey) ?? const []);
      _dirtyFolders.removeWhere((id) => !_folders.containsKey(id));
    } catch (e) {
      debugPrint('Caché de carpetas dañada, se ignora: $e');
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
    prefs.setString(
        _foldersKey, jsonEncode(_folders.values.map((f) => f.toRow()).toList()));
    prefs.setStringList(_dirtyFoldersKey, _dirtyFolders.toList());
    prefs.setStringList(_purgeKey, _purge.toList());
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
    version++;
    notifyListeners();
    WidgetBridge.schedule(notes);
  }

  // --------------------------------------------------------------- demo

  /// Notas de ejemplo (solo modo DEMO de las pruebas automáticas).
  void seedDemo() {
    if (_disposed || notes.isNotEmpty) return;
    final now = DateTime.now().toUtc();
    final clase = createFolder('Clase', color: 0xFF5C8DF6);
    createFolder('Personal', color: 0xFFE76F51);
    const textos = [
      'Lista de la compra\nLeche, pan, huevos y café',
      'Ideas para el proyecto\nApp de notas sincronizada con widget',
      'Examen de historia\nRepasar temas 4, 5 y 6',
      'Pelis pendientes\nDune 2, Oppenheimer, Interstellar',
      'Entregar trabajo de física\nPráctica del péndulo',
    ];
    for (var i = 0; i < textos.length; i++) {
      final n = createNote();
      n.content = textos[i];
      n.pinned = i == 0;
      n.updatedAt = now.subtract(Duration(hours: i * 20));
      if (i == 2) {
        n.folderId = clase.id;
        n.remindAt = now.subtract(const Duration(days: 4));
        n.dueAt = now.add(const Duration(days: 3));
      }
      if (i == 4) {
        n.color = 0xFFB197FC;
        n.folderId = clase.id;
        n.remindAt = now.subtract(const Duration(days: 10));
        n.dueAt = now.add(const Duration(hours: 20));
      }
      _fresh.remove(n.id);
    }
    _notify();
  }
}
