import '../models/note.dart';
import 'notes_repository.dart';

/// Enlaces entre notas al estilo Obsidian: `[[Título de otra nota]]` dentro
/// del texto (también `[[Título|texto visible]]`). Se resuelven por el
/// título de la nota (su primera línea), sin distinguir mayúsculas.
/// No hace falta guardar nada aparte: los enlaces viven en el propio texto,
/// así que se sincronizan con la nota.
final linkPattern = RegExp(r'\[\[([^\[\]\n]+?)\]\]');

/// Título que se escribe dentro de `[[…]]` para enlazar a [note].
String linkTargetOf(Note note) =>
    note.title.replaceAll('[', '').replaceAll(']', '').trim();

String _key(String s) => s.trim().toLowerCase();

/// Grafo de enlaces calculado a partir de las notas.
class NoteGraph {
  NoteGraph._(this.nodes, this.outgoing, this.incoming, this.unresolved);

  /// Notas no vacías que forman el grafo.
  final List<Note> nodes;

  /// id → ids de las notas a las que enlaza.
  final Map<String, Set<String>> outgoing;

  /// id → ids de las notas que la enlazan (backlinks).
  final Map<String, Set<String>> incoming;

  /// id → títulos enlazados que no existen todavía.
  final Map<String, Set<String>> unresolved;

  int get edgeCount =>
      outgoing.values.fold(0, (sum, targets) => sum + targets.length);

  final _neighbors = <String, Set<String>>{};

  /// Notas enlazadas en cualquier sentido (se consulta en cada fotograma
  /// de la vista de red, por eso se guarda).
  Set<String> neighbors(String id) =>
      _neighbors.putIfAbsent(id, () => {...?outgoing[id], ...?incoming[id]});

  int degree(String id) => neighbors(id).length;

  static NoteGraph build(List<Note> notes) {
    final nodes = notes.where((n) => !n.isEmpty && !n.deleted).toList();
    // Si dos notas tienen el mismo título gana la editada más recientemente.
    final byTitle = <String, Note>{};
    for (final n in nodes) {
      final k = _key(linkTargetOf(n));
      final prev = byTitle[k];
      if (prev == null || n.updatedAt.isAfter(prev.updatedAt)) byTitle[k] = n;
    }
    final outgoing = <String, Set<String>>{};
    final incoming = <String, Set<String>>{};
    final unresolved = <String, Set<String>>{};
    final ids = {for (final n in nodes) n.id};
    // Enlaces hechos a mano (clic derecho → Enlazar / Crear subnota).
    for (final n in nodes) {
      for (final t in n.links) {
        if (t == n.id || !ids.contains(t)) continue;
        (outgoing[n.id] ??= <String>{}).add(t);
        (incoming[t] ??= <String>{}).add(n.id);
      }
    }
    for (final n in nodes) {
      for (final m in linkPattern.allMatches(n.content)) {
        final target = m.group(1)!.split('|').first.trim();
        if (target.isEmpty) continue;
        final dest = byTitle[_key(target)];
        if (dest == null) {
          (unresolved[n.id] ??= <String>{}).add(target);
        } else if (dest.id != n.id) {
          (outgoing[n.id] ??= <String>{}).add(dest.id);
          (incoming[dest.id] ??= <String>{}).add(n.id);
        }
      }
    }
    return NoteGraph._(nodes, outgoing, incoming, unresolved);
  }

  static NoteGraph? _cache;
  static int _cacheVersion = -1;
  static NotesRepository? _cacheRepo;

  /// Grafo del repositorio, recalculado solo cuando cambian las notas.
  static NoteGraph of(NotesRepository repo) {
    if (_cache == null ||
        _cacheVersion != repo.version ||
        !identical(_cacheRepo, repo)) {
      _cache = build(repo.notes);
      _cacheVersion = repo.version;
      _cacheRepo = repo;
    }
    return _cache!;
  }
}
