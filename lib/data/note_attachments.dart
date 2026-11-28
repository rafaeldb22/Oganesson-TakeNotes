import 'dart:convert';

import '../models/note.dart';
import 'markdown.dart';
import 'note_factory.dart';
import 'note_files.dart';
import 'note_images.dart';
import 'notes_repository.dart';

enum MediaKind { image, audio, file }

/// Una imagen, nota de voz o archivo dentro del Delta de una nota.
class MediaItem {
  const MediaItem(this.kind, this.path, this.name, this.embed, this.inGraph,
      {this.linked = false});
  final MediaKind kind;

  /// Conectado a la nota sin estar dentro de su texto.
  final bool linked;

  /// Ruta en Storage: identifica el archivo aunque esté en varias notas.
  final String path;
  final String name;

  /// Valor de `insert` en el Delta.
  final Map<String, dynamic> embed;

  /// Conectado a mano en la red de notas: se ve como una bola propia.
  final bool inGraph;

  NoteFile? get file =>
      kind == MediaKind.image ? null : NoteFile.parse(_fileData(embed));
  String? get imageSrc => embed['image'] as String?;
}

String? _fileData(Map embed) {
  final custom = embed['custom'];
  if (custom is! String || !custom.contains(NoteFiles.embedType)) return null;
  try {
    final m = jsonDecode(custom);
    return m is Map ? m[NoteFiles.embedType] as String? : null;
  } catch (_) {
    return null;
  }
}

bool _srcInGraph(String src) {
  final q = src.indexOf('?');
  return q != -1 && Uri.splitQueryString(src.substring(q + 1))['net'] == '1';
}

String _srcWithGraph(String src, bool on) {
  final q = src.indexOf('?');
  final base = q == -1 ? src : src.substring(0, q);
  final params = q == -1
      ? <String, String>{}
      : Map.of(Uri.splitQueryString(src.substring(q + 1)));
  params.remove('net');
  if (on) params['net'] = '1';
  if (params.isEmpty) return base;
  return '$base?${params.entries.map((e) => '${e.key}=${e.value}').join('&')}';
}

/// El mismo embed, marcado o no como conectado en la red.
Map<String, dynamic> embedWithGraph(Map<String, dynamic> embed, bool on) {
  final src = embed['image'];
  if (src is String) return {'image': _srcWithGraph(src, on)};
  final data = _fileData(embed);
  if (data == null) return embed;
  final m = Map<String, dynamic>.from(jsonDecode(data) as Map);
  if (on) {
    m['net'] = true;
  } else {
    m.remove('net');
  }
  return {
    'custom': jsonEncode({NoteFiles.embedType: jsonEncode(m)})
  };
}

/// Embed de un adjunto recién subido.
Map<String, dynamic> fileEmbed(NoteFile f) => {
      'custom': jsonEncode({NoteFiles.embedType: f.toJsonString()})
    };

MediaItem? _itemOf(Object? op) {
  if (op is! Map || op['insert'] is! Map) return null;
  final embed = Map<String, dynamic>.from(op['insert'] as Map);
  final src = embed['image'];
  if (src is String) {
    if (!NoteImages.isOurs(src)) return null;
    return MediaItem(MediaKind.image, NoteImages.pathOf(src), 'Imagen', embed,
        _srcInGraph(src));
  }
  final data = _fileData(embed);
  final f = data == null ? null : NoteFile.parse(data);
  if (f == null) return null;
  return MediaItem(f.isAudio ? MediaKind.audio : MediaKind.file, f.path, f.name,
      embed, (jsonDecode(data!) as Map)['net'] == true);
}

List<Object?> _ops(String content, String? rich) {
  if (rich != null) {
    try {
      final d = jsonDecode(rich);
      if (d is List && d.isNotEmpty) return List<Object?>.of(d);
    } catch (_) {}
  }
  // Nota de texto plano: su primera línea se conserva como título.
  return List<Object?>.of(jsonDecode(richFor(content)) as List);
}

(String, String) _result(List<Object?> ops) {
  final plain = StringBuffer();
  for (final o in ops) {
    final v = o is Map ? o['insert'] : null;
    plain.write(v is String ? v : '￼');
  }
  final text = plain.toString();
  return (
    text.endsWith('\n') ? text.substring(0, text.length - 1) : text,
    jsonEncode(ops),
  );
}

/// Imágenes, notas de voz y archivos de una nota, en orden.
List<MediaItem> mediaIn(String? rich) {
  if (rich == null ||
      (!rich.contains(NoteImages.scheme) && !rich.contains(NoteFiles.scheme))) {
    return const [];
  }
  try {
    return [
      for (final op in jsonDecode(rich) as List)
        if (_itemOf(op) case final item?) item,
    ];
  } catch (_) {
    return const [];
  }
}

/// Añade embeds al final, cada uno en su línea, sin tocar el formato de la
/// última línea (un título sigue siendo título).
(String content, String rich) withEmbeds(
    String content, String? rich, List<Map<String, dynamic>> embeds) {
  final ops = _ops(content, rich);
  for (final e in embeds) {
    ops
      ..add({'insert': e})
      ..add({'insert': '\n'});
  }
  return _result(ops);
}

/// Añade texto al final, sin heredar el formato de la última línea. El
/// Markdown (listas, títulos, negrita…) se convierte en formato.
(String content, String rich) withText(
    String content, String? rich, String text) {
  final ops = _ops(content, rich)..addAll(markdownOps(text.trimRight()));
  return _result(ops);
}

/// Añade [text] justo después de la línea [afterLine] (para seguir una lista
/// o un apartado). Si no la encuentra, va al final.
(String content, String rich) withTextAfter(
    String content, String? rich, String afterLine, String text) {
  final ops = _ops(content, rich);
  final target = afterLine.trim().toLowerCase();
  // Posición (en caracteres del Delta) del salto de línea de esa línea.
  var pos = 0;
  int? at;
  final line = StringBuffer();
  for (final o in ops) {
    final v = o is Map ? o['insert'] : null;
    final s = v is String ? v : '\uFFFC';
    for (var i = 0; i < s.length; i++) {
      if (s[i] == '\n') {
        if (at == null && line.toString().trim().toLowerCase() == target) {
          at = pos + i + 1;
        }
        line.clear();
      } else {
        line.write(s[i]);
      }
    }
    pos += s.length;
  }
  if (at == null) return withText(content, rich, text);
  // Parte las ops en [at] y mete las nuevas en medio.
  final before = <Object?>[], after = <Object?>[];
  var seen = 0;
  for (final o in ops) {
    final v = o is Map ? o['insert'] : null;
    final len = v is String ? v.length : 1;
    if (seen + len <= at) {
      before.add(o);
    } else if (seen >= at) {
      after.add(o);
    } else {
      final cut = at - seen;
      final m = o as Map;
      before.add({...m, 'insert': (v as String).substring(0, cut)});
      after.add({...m, 'insert': v.substring(cut)});
    }
    seen += len;
  }
  return _result([...before, ...markdownOps(text.trimRight()), ...after]);
}

/// Prefijo de los adjuntos guardados en `Note.links`, junto a los ids de nota.
const linkedMediaPrefix = 'att:';

String _linkToken(Map<String, dynamic> embed) =>
    '$linkedMediaPrefix${jsonEncode(embedWithGraph(embed, false))}';

MediaItem? _linkedItem(String token) {
  if (!token.startsWith(linkedMediaPrefix)) return null;
  try {
    final embed = jsonDecode(token.substring(linkedMediaPrefix.length));
    final item = _itemOf({'insert': embed});
    if (item == null) return null;
    return MediaItem(item.kind, item.path, item.name, item.embed, true,
        linked: true);
  } catch (_) {
    return null;
  }
}

/// Adjuntos conectados a la nota sin estar dentro de su texto.
List<MediaItem> linkedMedia(Note n) => [
      for (final t in n.links)
        if (_linkedItem(t) case final item?) item,
    ];

/// Todo lo que tiene una nota: dentro del texto y conectado.
List<MediaItem> allMediaOf(Note n) => [...mediaIn(n.rich), ...linkedMedia(n)];

/// Conecta un adjunto a una nota sin meterlo en su texto: sale abajo, con
/// los enlaces, y como una bola en la red.
void connectMedia(
    NotesRepository repo, String noteId, Map<String, dynamic> embed) {
  final n = repo.byId(noteId);
  final item = _itemOf({'insert': embed});
  if (n == null || item == null) return;
  if (linkedMedia(n).any((m) => m.path == item.path)) return;
  repo.addLinks(noteId, [_linkToken(embed)]);
}

/// Quita un adjunto conectado. Si no está en otra nota, el archivo sigue en
/// la nube hasta que se borre la nota.
void removeLinkedMedia(NotesRepository repo, String noteId, String path) {
  final n = repo.byId(noteId);
  if (n == null) return;
  for (final t in n.links.toList()) {
    if (_linkedItem(t)?.path == path) repo.removeLink(noteId, t);
  }
}

/// Código corto y estable de un archivo, para que la IA lo pida sin errores.
String mediaCode(String path) {
  var h = 0x811c9dc5;
  for (final c in path.codeUnits) {
    h = ((h ^ c) * 0x01000193) & 0xffffffff;
  }
  return 'F${h.toRadixString(36).toUpperCase().padLeft(7, '0')}';
}

/// Un archivo disponible y la nota en la que está.
class MediaEntry {
  const MediaEntry(this.code, this.note, this.item);
  final String code;
  final Note note;
  final MediaItem item;

  String get kindName => switch (item.kind) {
        MediaKind.image => 'image',
        MediaKind.audio => 'audio',
        MediaKind.file => item.file?.isPdf == true ? 'pdf' : 'file',
      };
}

/// Índice de todos los archivos de [notes], sin repetir.
List<MediaEntry> mediaCatalog(Iterable<Note> notes) {
  final seen = <String>{};
  return [
    for (final n in notes)
      for (final m in allMediaOf(n))
        if (seen.add(m.path)) MediaEntry(mediaCode(m.path), n, m),
  ];
}

/// Quita la bola de la red; el adjunto sigue dentro de la nota.
void disconnectMedia(NotesRepository repo, String noteId, String path) {
  final n = repo.byId(noteId);
  if (n == null) return;
  final ops = _ops(n.content, n.rich);
  for (var i = 0; i < ops.length; i++) {
    final item = _itemOf(ops[i]);
    if (item != null && item.path == path && item.inGraph) {
      ops[i] = {'insert': embedWithGraph(item.embed, false)};
    }
  }
  final (content, rich) = _result(ops);
  repo.updateContent(noteId, content, rich: rich);
}
