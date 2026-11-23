import 'note_export.dart';
import 'note_factory.dart';
import 'note_files.dart';
import 'note_history.dart';
import 'recurrence.dart';
import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/note.dart';
import '../ui/urgency.dart' show noteColors;
import 'note_ics.dart';
import 'note_images.dart';
import 'note_sharing.dart';
import 'widget_bridge.dart';

enum SyncStatus { syncing, synced, pending, offline }

/// Guarda notas y carpetas en local (funciona sin internet) y las sincroniza
/// con Supabase: sube los cambios pendientes y recibe los de otros
/// dispositivos en tiempo real. Si hay conflicto gana la edición más reciente.
class NotesRepository extends ChangeNotifier {
  NotesRepository(this._client, this.userId);

  final SupabaseClient _client;
  final String userId;

  SupabaseClient get client => _client;

  // ---------------------------------------------------- notas compartidas

  /// Notas de otras cuentas a las que tengo acceso.
  final Map<String, IncomingShare> _incoming = {};

  /// Notas mías compartidas con alguien.
  final Set<String> _sharedOut = {};

  RealtimeChannel? _sharesChannel;

  String get _sharesKey => 'notas_compartidas_$userId';

  /// ¿Es una nota de otra cuenta?
  bool isForeign(Note n) => n.ownerId != null && n.ownerId != userId;

  /// ¿Participa en una compartición, en cualquier sentido?
  bool isShared(Note n) => isForeign(n) || _sharedOut.contains(n.id);

  bool canEdit(Note n) => !isForeign(n) || (_incoming[n.id]?.canEdit ?? false);

  IncomingShare? incomingShare(String id) => _incoming[id];

  /// Quita de este dispositivo una nota ajena (sin tocar la original).
  void dropForeign(String id) {
    final n = _notes[id];
    if (n == null || !isForeign(n)) return;
    _notes.remove(id);
    _dirty.remove(id);
    _incoming.remove(id);
    history.forget(id);
    _changed();
  }

  /// Lee quién comparte qué. Sin la migración 010 no hace nada.
  Future<void> _syncShares() async {
    try {
      final inc = await _client.rpc('my_shared_notes');
      final out = await _client
          .from('note_shares')
          .select('note_id')
          .eq('created_by', userId);
      _incoming
        ..clear()
        ..addAll({
          for (final r in inc as List)
            '${r['note_id']}':
                IncomingShare('${r['role']}', '${r['owner_email']}')
        });
      _sharedOut
        ..clear()
        ..addAll([for (final r in out) '${r['note_id']}']);
      _prefs?.setString(
          _sharesKey,
          jsonEncode({
            'in': {for (final e in _incoming.entries) e.key: e.value.toJson()},
            'out': _sharedOut.toList(),
          }));
    } catch (e) {
      debugPrint('Compartidas: $e');
    }
  }

  void _loadShares() {
    try {
      final raw = _prefs?.getString(_sharesKey);
      if (raw == null) return;
      final j = jsonDecode(raw) as Map<String, dynamic>;
      (j['in'] as Map).forEach((id, v) {
        _incoming['$id'] = IncomingShare('${v['role']}', '${v['owner']}');
      });
      _sharedOut.addAll((j['out'] as List).whereType<String>());
    } catch (_) {}
  }

  /// Sube el texto de notas ajenas. Si ya no tengo permiso, la versión local
  /// se descarta y la siguiente sincronización trae la buena.
  Future<void> _pushForeign(List<Note> list) async {
    for (final n in list) {
      final sent = n.updatedAt;
      final res = await _client
          .from('notes')
          .update({
            'content': n.content,
            'rich': n.rich,
            'updated_at': sent.toUtc().toIso8601String(),
          })
          .eq('id', n.id)
          .select('id');
      if (res.isEmpty) {
        _notes.remove(n.id);
        _dirty.remove(n.id);
        _notify();
      } else if (_notes[n.id]?.updatedAt == sent) {
        _dirty.remove(n.id);
      }
    }
  }

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

  /// ¿Está abierto el Vault? Mientras no, sus notas no aparecen en ninguna
  /// lista (notas, búsqueda, red, calendario, papelera).
  bool Function() vaultUnlocked = () => false;

  /// false si la tabla `notes` de Supabase aún no tiene la columna `vault`
  /// (migración 005 sin ejecutar). Entonces las notas del Vault no se suben,
  /// para que no aparezcan como notas normales en otros dispositivos.
  bool serverHasVault = true;

  /// Llamar cuando se bloquea o desbloquea el Vault.
  void vaultChanged() => _notify();

  /// Notas de las listas normales: nunca las del Vault (tienen su propia
  /// pantalla, desde ⋯) ni las completadas hace más de 3 días.
  bool _visible(Note n) => !n.vault && !n.archived && !isArchived(n);

  /// false si Supabase aún no tiene las columnas de la migración 006
  /// (`archived`, `position`): se suben las notas sin esos campos.
  bool serverHasArchive = true;

  /// false si Supabase aún no tiene la migración 008 (`repeat`, `subtasks`):
  /// esos datos se quedan en este dispositivo y no se pierden.
  bool serverHasTasks = true;

  /// Versiones anteriores de las notas (solo en este dispositivo).
  late final NoteHistory history = NoteHistory(scope: userId);

  /// Notas archivadas (deslizar a la izquierda), más recientes primero.
  List<Note> get archivedNotes => _notes.values
      .where((n) => n.archived && !n.deleted && !n.vault && !n.isEmpty)
      .toList()
    ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

  void setArchived(String id, bool archived) =>
      _edit(id, (n) => n.archived = archived);

  /// Coloca varias notas a la vez (orden personalizado al arrastrar).
  void setPositions(Map<String, double> positions) {
    if (_disposed || positions.isEmpty) return;
    final now = DateTime.now().toUtc();
    for (final e in positions.entries) {
      final n = _notes[e.key];
      if (n == null || isForeign(n) || n.position == e.value) continue;
      n.position = e.value;
      n.updatedAt = now;
      _dirty.add(n.id);
    }
    _changed();
  }

  /// Mueve una nota a otra carpeta (o a ninguna) y, si se indica, a otra
  /// posición del orden personalizado.
  void moveNote(String id, {required String? folderId, double? position}) =>
      _edit(id, (n) {
        n.folderId = folderId;
        if (position != null) n.position = position;
      });

  /// Notas del Vault (solo con el Vault abierto), más recientes primero.
  List<Note> get vaultNotes {
    if (!vaultUnlocked()) return const [];
    return _notes.values.where((n) => n.vault && !n.deleted).toList()
      ..sort((a, b) {
        if (a.pinned != b.pinned) return a.pinned ? -1 : 1;
        return b.updatedAt.compareTo(a.updatedAt);
      });
  }

  /// Días que una nota completada sigue en las listas antes de pasar a
  /// "Completadas", y días que se guarda allí antes de ir a la papelera.
  static const completedAfterDays = 3;
  static const completedKeepDays = 30;

  DateTime _doneSince(Note n) => n.doneAt ?? n.updatedAt;

  /// Completada hace más de 3 días: ya no sale en las listas.
  bool isArchived(Note n) =>
      n.done &&
      DateTime.now().toUtc().difference(_doneSince(n)).inDays >=
          completedAfterDays;

  /// Notas en "Completadas", las más recientes primero.
  List<Note> get completed => _notes.values
      .where((n) =>
          !n.deleted &&
          !n.isEmpty &&
          isArchived(n) &&
          (!n.vault || vaultUnlocked()))
      .toList()
    ..sort((a, b) => _doneSince(b).compareTo(_doneSince(a)));

  /// Cuándo se irá a la papelera una nota completada.
  DateTime completedUntil(Note n) =>
      _doneSince(n).add(const Duration(days: completedKeepDays));

  /// Las completadas hace más de 30 días van a la papelera.
  void _expireCompleted() {
    final limit = DateTime.now()
        .toUtc()
        .subtract(const Duration(days: completedKeepDays));
    for (final n in _notes.values) {
      if (n.done &&
          !n.deleted &&
          !isForeign(n) &&
          _doneSince(n).isBefore(limit)) {
        n.deleted = true;
        n.updatedAt = DateTime.now().toUtc();
        _dirty.add(n.id);
      }
    }
  }

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
    final list = _notes.values.where((n) => !n.deleted && _visible(n)).toList()
      ..sort((a, b) {
        if (a.pinned != b.pinned) return a.pinned ? -1 : 1;
        return b.updatedAt.compareTo(a.updatedAt);
      });
    _sortedCache = list;
    _sortedVersion = version;
    return list;
  }

  /// Notas temporales ordenadas por fecha límite.
  List<Note> get temporales =>
      notes.where((n) => n.isTemporal && !n.isEmpty).toList()
        ..sort((a, b) => a.dueAt!.compareTo(b.dueAt!));

  List<Folder> get folders => _folders.values.where((f) => !f.deleted).toList()
    ..sort((a, b) => a.createdAt.compareTo(b.createdAt));

  /// Notas en la papelera (borradas hace menos de 3 días), más recientes antes.
  List<Note> get trash {
    final limit =
        DateTime.now().toUtc().subtract(const Duration(days: trashDays));
    return _notes.values
        .where((n) =>
            n.deleted &&
            !n.isEmpty &&
            !_purge.contains(n.id) &&
            (!n.vault || vaultUnlocked()) &&
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
    final n = _notes.remove(id)!;
    _dirty.remove(id);
    _purge.add(id);
    history.forget(id);
    _releaseImages([n]);
    _releaseFiles([n]);
    _changed();
  }

  void emptyTrash() {
    final gone = trash;
    for (final n in gone) {
      _notes.remove(n.id);
      _dirty.remove(n.id);
      _purge.add(n.id);
      history.forget(n.id);
    }
    _releaseImages(gone);
    _releaseFiles(gone);
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
    final gone = <Note>[];
    for (final id in old) {
      gone.add(_notes.remove(id)!);
      _dirty.remove(id);
      _purge.add(id);
      history.forget(id);
    }
    _releaseImages(gone);
    _releaseFiles(gone);
  }

  /// Borra de la nube las imágenes de notas eliminadas para siempre, salvo
  /// las que siga usando otra nota (una imagen copiada de una nota a otra).
  void _releaseImages(List<Note> gone) {
    final paths = {for (final n in gone) ...NoteImages.pathsIn(n.rich)};
    if (paths.isEmpty) return;
    for (final n in _notes.values) {
      paths.removeAll(NoteImages.pathsIn(n.rich));
    }
    NoteImages.instance.remove(paths);
  }

  /// Igual con los adjuntos.
  void _releaseFiles(List<Note> gone) {
    final paths = {for (final n in gone) ...NoteFiles.pathsIn(n.rich)};
    if (paths.isEmpty) return;
    for (final n in _notes.values) {
      paths.removeAll(NoteFiles.pathsIn(n.rich));
    }
    NoteFiles.instance.remove(paths);
  }

  Note? byId(String id) => _notes[id];
  Folder? folderById(String? id) => id == null ? null : _folders[id];

  int countIn(String folderId) => notes
      .where((n) => n.folderId == folderId && !n.isEmpty && !n.vault)
      .length;

  /// Se llama en cada cambio hecho en este dispositivo (cuenta como
  /// actividad para el bloqueo automático del Vault).
  VoidCallback? onLocalEdit;

  // ---------------------------------------------------------------- ciclo

  Future<void> start() async {
    _prefs = await SharedPreferences.getInstance();
    if (_disposed) return;
    await history.load(_prefs);
    if (_disposed) return;
    _loadLocal();
    _notes.values.toList().forEach(_absorbSubtasks);
    _loadShares();
    loaded = true;
    _notify();
    _subscribe();
    unawaited(sync());
    _periodic = Timer.periodic(const Duration(seconds: 45), (_) => sync());
  }

  @override
  void dispose() {
    _disposed = true;
    final shares = _sharesChannel;
    if (shares != null) unawaited(_client.removeChannel(shares));
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
      color: dueAt == null ? null : _nextTimelineColor(),
    );
    _notes[n.id] = n;
    _fresh.add(n.id);
    _notify();
    return n;
  }

  /// Color para una línea temporal nueva: el menos usado por las activas.
  int _nextTimelineColor() {
    final used = <int, int>{};
    for (final n in _notes.values) {
      if (n.isTemporal && !n.done && !n.deleted && !n.archived && !n.vault) {
        final c = n.color;
        if (c != null) used[c] = (used[c] ?? 0) + 1;
      }
    }
    var best = noteColors.first.$2;
    for (var i = 0; i < noteColors.length; i++) {
      // La paleta va por tono: saltar 8 evita que las seguidas se parezcan.
      final c = noteColors[i * 8 % noteColors.length].$2;
      if ((used[c] ?? 0) < (used[best] ?? 0)) best = c;
    }
    return best;
  }

  void updateContent(String id, String content, {String? rich}) {
    final n = _notes[id];
    if (_disposed || n == null || !canEdit(n)) return;
    if (n.content == content && n.rich == rich) return;
    if (!n.vault) history.record(n);
    n.content = content;
    n.rich = rich;
    n.updatedAt = DateTime.now().toUtc();
    _touch(id);
  }

  void togglePin(String id) => _edit(id, (n) => n.pinned = !n.pinned);

  /// Completar una tarea repetitiva la pasa a la siguiente fecha.
  void toggleDone(String id) => _edit(id, (n) {
        final rule = RepeatRule.parse(n.repeat);
        if (!n.done && rule != null && n.dueAt != null) {
          final due = n.dueAt!;
          final next = rule.next(due.toLocal(), after: DateTime.now());
          final shift = next.toUtc().difference(due);
          final singleDay = n.isSingleDay;
          n.dueAt = next.toUtc();
          // Con cambio de hora, sumar el desfase movería las 00:00.
          n.remindAt = singleDay
              ? Note.dayStart(next).toUtc()
              : n.remindAt?.add(shift);
          n.rich = uncheckAll(n.rich);
          return;
        }
        n.done = !n.done;
        n.doneAt = n.done ? DateTime.now().toUtc() : null;
      });

  void setRepeat(String id, String? rule) => _edit(id, (n) => n.repeat = rule);

  /// Añade casillas al final de la nota.
  void addChecklist(String id, List<String> items) {
    final n = _notes[id];
    if (n == null || items.isEmpty) return;
    final (content, rich) =
        withChecklist(n.content, n.rich, [for (final t in items) (t, false)]);
    updateContent(id, content, rich: rich);
  }

  /// Pasa las subtareas de la 2.3 a casillas dentro de la nota: no se pierde
  /// nada y deja de haber dos sistemas de tareas.
  void _absorbSubtasks(Note n) {
    if (n.subtasks.isEmpty) return;
    final (content, rich) = withChecklist(
        n.content, n.rich, [for (final t in n.subtasks) (t.text, t.done)]);
    n
      ..content = content
      ..rich = rich
      ..subtasks = []
      ..updatedAt = DateTime.now().toUtc();
    _dirty.add(n.id);
  }

  /// Vuelve a una versión guardada; la actual queda también en el historial.
  void restoreVersion(String id, NoteVersion v) {
    final n = _notes[id];
    if (n != null && !n.vault) history.record(n, force: true);
    updateContent(id, v.content, rich: v.rich);
  }

  /// Mezcla una copia: añade lo que falta y actualiza lo que sea más nuevo.
  /// Nunca borra nada ni importa notas del Vault.
  ({int notes, int folders}) importBackup(Backup b) {
    var notes = 0, folders = 0;
    for (final f in b.folders) {
      final local = _folders[f.id];
      if (local != null && !f.updatedAt.isAfter(local.updatedAt)) continue;
      _folders[f.id] = f;
      _dirtyFolders.add(f.id);
      folders++;
    }
    for (final n in b.notes) {
      if (n.vault) continue;
      final local = _notes[n.id];
      if (local != null &&
          (local.vault ||
              isForeign(local) ||
              !n.updatedAt.isAfter(local.updatedAt))) {
        continue;
      }
      n.ownerId = userId;
      _notes[n.id] = n;
      _dirty.add(n.id);
      notes++;
    }
    if (notes + folders > 0) {
      _notify();
      _schedulePersist();
      unawaited(sync());
    }
    return (notes: notes, folders: folders);
  }

  /// Añade los eventos de un calendario. Los que ya están, aunque se hayan
  /// editado o estén en la papelera, no se tocan.
  ({int added, int existing}) importEvents(List<IcsEvent> events) {
    var added = 0, existing = 0;
    final now = DateTime.now().toUtc();
    for (final e in events) {
      final id = icsNoteId(userId, e.uid);
      if (_notes.containsKey(id)) {
        existing++;
        continue;
      }
      _notes[id] = Note(
        id: id,
        content: e.content,
        createdAt: now,
        updatedAt: now,
        remindAt: e.remindAt,
        dueAt: e.dueAt,
        repeat: e.repeat,
        color: _nextTimelineColor(),
        ownerId: userId,
      );
      _dirty.add(id);
      added++;
    }
    if (added > 0) {
      _notify();
      _schedulePersist();
      unawaited(sync());
    }
    return (added: added, existing: existing);
  }

  /// Enlaza dos notas (enlace manual, se ve en la red y en el panel).
  void addLinks(String id, Iterable<String> targets) => _edit(id, (n) {
        for (final t in targets) {
          if (t != id && !n.links.contains(t)) n.links.add(t);
        }
      });

  void removeLink(String id, String target) => _edit(id, (n) {
        n.links.remove(target);
        // El enlace puede estar guardado en la otra nota.
        final other = _notes[target];
        if (other != null && other.links.remove(id)) {
          other.updatedAt = DateTime.now().toUtc();
          _dirty.add(other.id);
        }
      });

  /// Crea una subnota enlazada a [parentId] y la devuelve.
  Note createSubnote(String parentId) {
    final parent = _notes[parentId];
    final n = createNote(folderId: parent?.folderId);
    if (parent != null) {
      parent.links.add(n.id);
      parent.updatedAt = DateTime.now().toUtc();
      _dirty.add(parent.id);
      if (parent.vault) n.vault = true;
      _changed();
    }
    return n;
  }

  void setColor(String id, int? color) => _edit(id, (n) => n.color = color);

  /// Mete o saca una nota del Vault.
  void setVault(String id, bool vault) => _edit(id, (n) => n.vault = vault);

  /// Todas las notas activas, también las del Vault (para los avisos).
  List<Note> get allActive => _notes.values.where((n) => !n.deleted).toList();

  void moveToFolder(String id, String? folderId) =>
      _edit(id, (n) => n.folderId = folderId);

  void setSchedule(String id, {DateTime? remindAt, DateTime? dueAt}) =>
      _edit(id, (n) {
        // Solo al convertirse en línea: "Automático" elegido después se respeta.
        if (n.dueAt == null && dueAt != null && n.color == null) {
          n.color = _nextTimelineColor();
        }
        n.remindAt = remindAt?.toUtc();
        n.dueAt = dueAt?.toUtc();
        if (dueAt == null) n.done = false;
      });

  /// Devuelve una nota al estado de [s] (Deshacer lo que hizo el asistente).
  void restoreState(Note s) => _edit(s.id, (n) {
        n
          ..content = s.content
          ..rich = s.rich
          ..folderId = s.folderId
          ..remindAt = s.remindAt
          ..dueAt = s.dueAt
          ..done = s.done
          ..doneAt = s.doneAt
          ..color = s.color
          ..pinned = s.pinned
          ..deleted = s.deleted
          ..archived = s.archived
          ..repeat = s.repeat
          ..subtasks = [
            for (final t in s.subtasks)
              Subtask(id: t.id, text: t.text, done: t.done)
          ]
          ..links = List.of(s.links);
      });

  void _edit(String id, void Function(Note n) change) {
    final n = _notes[id];
    // Carpeta, fechas, fijar… de una nota ajena son de quien la creó.
    if (_disposed || n == null || isForeign(n)) return;
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
    if (_disposed || n == null || isForeign(n)) return;
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
    onLocalEdit?.call();
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
      if (rows.isNotEmpty) {
        final had = serverHasVault;
        serverHasVault = rows.first.containsKey('vault');
        serverHasArchive = rows.first.containsKey('archived');
        serverHasTasks = rows.first.containsKey('subtasks');
        if (had != serverHasVault) changed = true;
      }
      for (final r in rows) {
        if (_mergeNote(Note.fromRow(r))) changed = true;
      }
      // Notas ajenas a las que ya no tengo acceso.
      final alive = {for (final r in rows) r['id']};
      final revoked = _notes.values
          .where((n) => isForeign(n) && !alive.contains(n.id))
          .map((n) => n.id)
          .toList();
      for (final id in revoked) {
        _notes.remove(id);
        _dirty.remove(id);
        history.forget(id);
        changed = true;
      }
      final before = jsonEncode([_incoming.keys.toList(), _sharedOut.toList()]);
      await _syncShares();
      if (before !=
          jsonEncode([_incoming.keys.toList(), _sharedOut.toList()])) {
        changed = true;
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
    _expireCompleted();
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
    final foreign = <Note>[];
    final rows = <Map<String, dynamic>>[];
    for (final id in _dirty.toList()) {
      final n = _notes[id];
      if (n == null) {
        _dirty.remove(id);
        continue;
      }
      // Sin la columna `vault` en Supabase, las del Vault esperan en local.
      if (n.vault && !serverHasVault) continue;
      if (isForeign(n)) {
        foreign.add(n);
        continue;
      }
      sent[id] = n.updatedAt;
      rows.add(n.toRow(
          userId: userId,
          withVault: serverHasVault,
          withArchive: serverHasArchive,
          withTasks: serverHasTasks));
    }
    await _pushForeign(foreign);
    if (rows.isEmpty) return;
    try {
      await _client.from('notes').upsert(rows);
    } on PostgrestException catch (e) {
      // Columna `vault` inexistente: se sube el resto sin ella.
      if (serverHasVault &&
          (e.message.contains('vault') ||
              e.message.contains('links') ||
              e.message.contains('done_at'))) {
        serverHasVault = false;
        _notify();
        return _pushDirty();
      }
      // Igual con las columnas de la migración 006.
      if (serverHasArchive &&
          (e.message.contains('archived') || e.message.contains('position'))) {
        serverHasArchive = false;
        _notify();
        return _pushDirty();
      }
      // Igual con las columnas de la migración 008.
      if (serverHasTasks &&
          (e.message.contains('subtasks') || e.message.contains('repeat'))) {
        serverHasTasks = false;
        _notify();
        return _pushDirty();
      }
      rethrow;
    }
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
    // Sin la migración 008 el servidor no trae estos datos: no se pierden.
    if (!serverHasTasks && local != null) {
      remote
        ..repeat = local.repeat
        ..subtasks = local.subtasks;
    }
    if (!remote.vault) {
      if (local != null && local.content != remote.content) {
        history.record(local);
      }
    }
    _notes[remote.id] = remote;
    _dirty.remove(remote.id);
    _fresh.remove(remote.id);
    _absorbSubtasks(remote);
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
    // Canal aparte: sin la migración 010 esta tabla no existe, y en el mismo
    // canal dejaría sin tiempo real también a las notas.
    _sharesChannel = _client
        .channel('compartidas-$userId')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'note_shares',
          callback: (_) {
            if (!_disposed) unawaited(sync());
          },
        )
        .subscribe();
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
    prefs.setString(_foldersKey,
        jsonEncode(_folders.values.map((f) => f.toRow()).toList()));
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
    // Con enlaces [[…]] para que la vista de red tenga algo que mostrar.
    const textos = [
      'Lista de la compra\nLeche, pan, huevos y café',
      'Ideas para el proyecto\nApp de notas sincronizada con widget. '
          'Ver [[Examen de historia]] y [[Pelis pendientes]]',
      'Examen de historia\nRepasar temas 4, 5 y 6. '
          'Después: [[Entregar trabajo de física]]',
      'Pelis pendientes\nDune 2, Oppenheimer, Interstellar',
      'Entregar trabajo de física\nPráctica del péndulo. '
          'Apuntes en [[Ideas para el proyecto]]',
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
