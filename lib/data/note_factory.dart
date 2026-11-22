import 'dart:convert';

import '../models/note.dart';
import 'notes_repository.dart';

/// Delta de Quill (en JSON) para un texto: la primera línea es el título y
/// las imágenes van debajo, cada una en su propia línea.
String richFor(String text, {List<String> images = const []}) {
  final clean = text.replaceAll('\r\n', '\n').trim();
  final ops = <Map<String, dynamic>>[];
  if (clean.isNotEmpty) {
    final cut = clean.indexOf('\n');
    final title = cut == -1 ? clean : clean.substring(0, cut).trimRight();
    final body = cut == -1 ? '' : clean.substring(cut + 1);
    ops
      ..add({'insert': title})
      ..add({
        'insert': '\n',
        'attributes': {'header': 1}
      });
    if (body.isNotEmpty) ops.add({'insert': '$body\n'});
  }
  for (final src in images) {
    ops
      ..add({
        'insert': {'image': src}
      })
      ..add({'insert': '\n'});
  }
  if (ops.isEmpty) ops.add({'insert': '\n'});
  return jsonEncode(ops);
}

/// Crea una nota con formato a partir de texto e imágenes ya guardadas
/// (captura rápida, compartir desde otra app). null si no hay nada.
Note? createNoteFrom(
  NotesRepository repo, {
  required String text,
  List<String> images = const [],
}) {
  final clean = text.replaceAll('\r\n', '\n').trim();
  if (clean.isEmpty && images.isEmpty) return null;
  final n = repo.createNote();
  final plain = [
    if (clean.isNotEmpty) clean,
    for (final _ in images) '￼',
  ].join('\n');
  repo.updateContent(n.id, plain, rich: richFor(clean, images: images));
  return repo.byId(n.id);
}

/// Añade casillas al final de una nota, conservando su formato.
(String content, String rich) withChecklist(
    String content, String? rich, List<(String, bool)> items) {
  var ops = <Object?>[];
  if (rich != null) {
    try {
      final d = jsonDecode(rich);
      if (d is List) ops = List<Object?>.of(d);
    } catch (_) {}
  }
  final base = content.trimRight();
  if (ops.isEmpty && base.isNotEmpty)
    ops = [
      {'insert': '$base\n'}
    ];
  final last = ops.isEmpty ? null : ops.last;
  if (last is Map && last['insert'] is String) {
    if (!(last['insert'] as String).endsWith('\n')) ops.add({'insert': '\n'});
  }
  for (final (text, done) in items) {
    ops
      ..add({'insert': text})
      ..add({
        'insert': '\n',
        'attributes': {'list': done ? 'checked' : 'unchecked'}
      });
  }
  final lines = [for (final (text, _) in items) text].join('\n');
  return (base.isEmpty ? '$lines\n' : '$base\n$lines\n', jsonEncode(ops));
}

/// Desmarca todas las casillas (al repetirse una tarea).
String? uncheckAll(String? rich) {
  if (rich == null || !rich.contains('"checked"')) return rich;
  try {
    final ops = jsonDecode(rich);
    if (ops is! List) return rich;
    for (final op in ops) {
      if (op is Map && op['attributes'] is Map) {
        final a = op['attributes'] as Map;
        if (a['list'] == 'checked') a['list'] = 'unchecked';
      }
    }
    return jsonEncode(ops);
  } catch (_) {
    return rich;
  }
}
