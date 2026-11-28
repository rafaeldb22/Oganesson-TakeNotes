/// Markdown sencillo (el que escriben Gemini y los demás modelos) a Delta de
/// Quill: `#`/`##`/`###`, `- `/`* `, `1. `, `- [ ]`/`- [x]`, `> `, `**negrita**`,
/// `*cursiva*`, `~~tachado~~` y `` `código` ``.
library;

final _check = RegExp(r'^\s*(?:[-*+]\s+)?\[( |x|X)\]\s+');
final _bullet = RegExp(r'^\s*[-*+•]\s+');
final _ordered = RegExp(r'^\s*\d+[.)]\s+');
final _header = RegExp(r'^(#{1,3})\s+');
final _quote = RegExp(r'^>\s?');
final _inline = RegExp(
    r'\*\*(.+?)\*\*|__(.+?)__|~~(.+?)~~|`([^`]+)`|(?<![\w*])\*(?!\s)(.+?)(?<!\s)\*(?![\w*])');

/// Ops de Quill para [text], una línea por párrafo (sin título).
List<Map<String, dynamic>> markdownOps(String text) {
  final ops = <Map<String, dynamic>>[];
  for (var line in text.replaceAll('\r\n', '\n').split('\n')) {
    Map<String, dynamic>? block;
    if (_check.firstMatch(line) case final m?) {
      block = {'list': m[1] == ' ' ? 'unchecked' : 'checked'};
      line = line.substring(m.end);
    } else if (_header.firstMatch(line) case final m?) {
      block = {'header': m[1]!.length};
      line = line.substring(m.end);
    } else if (_ordered.firstMatch(line) case final m?) {
      block = {'list': 'ordered'};
      line = line.substring(m.end);
    } else if (_bullet.firstMatch(line) case final m?) {
      block = {'list': 'bullet'};
      line = line.substring(m.end);
    } else if (_quote.firstMatch(line) case final m?) {
      block = {'blockquote': true};
      line = line.substring(m.end);
    }
    ops.addAll(inlineOps(line));
    ops.add({'insert': '\n', if (block != null) 'attributes': block});
  }
  return ops;
}

/// Negrita, cursiva, tachado y código dentro de una línea.
List<Map<String, dynamic>> inlineOps(String line) {
  final ops = <Map<String, dynamic>>[];
  var at = 0;
  for (final m in _inline.allMatches(line)) {
    if (m.start > at) ops.add({'insert': line.substring(at, m.start)});
    final (text, attr) = m[1] != null
        ? (m[1]!, 'bold')
        : m[2] != null
            ? (m[2]!, 'bold')
            : m[3] != null
                ? (m[3]!, 'strike')
                : m[4] != null
                    ? (m[4]!, 'code')
                    : (m[5]!, 'italic');
    ops.add({
      'insert': text,
      'attributes': {attr: true}
    });
    at = m.end;
  }
  if (at < line.length) ops.add({'insert': line.substring(at)});
  return ops;
}

/// Quita las marcas de Markdown de una línea suelta (p. ej. un título).
String stripMarkdown(String line) {
  return inlineOps(line.replaceFirst(_header, '').trim())
      .map((o) => o['insert'])
      .join();
}
