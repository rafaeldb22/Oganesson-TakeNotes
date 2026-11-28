import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:notas/data/markdown.dart';
import 'package:notas/data/note_attachments.dart';

void main() {
  test('markdown blocks and inline styles become Quill attributes', () {
    final ops = markdownOps('## Plan\n- pan\n1. uno\n- [ ] tarea\n- [x] hecha\n'
        '> cita\n**negrita** y *cursiva* con `code` y ~~no~~');
    Map? attrsOfLine(int n) =>
        ops.where((o) => o['insert'] == '\n').elementAt(n)['attributes']
            as Map?;
    expect(attrsOfLine(0), {'header': 2});
    expect(attrsOfLine(1), {'list': 'bullet'});
    expect(attrsOfLine(2), {'list': 'ordered'});
    expect(attrsOfLine(3), {'list': 'unchecked'});
    expect(attrsOfLine(4), {'list': 'checked'});
    expect(attrsOfLine(5), {'blockquote': true});
    expect(ops.firstWhere((o) => o['insert'] == 'negrita')['attributes'],
        {'bold': true});
    expect(ops.firstWhere((o) => o['insert'] == 'cursiva')['attributes'],
        {'italic': true});
    expect(ops.firstWhere((o) => o['insert'] == 'code')['attributes'],
        {'code': true});
    expect(ops.firstWhere((o) => o['insert'] == 'no')['attributes'],
        {'strike': true});
  });

  test('plain asterisks inside words are left alone', () {
    final ops = inlineOps('2*3*4 y a * b');
    expect(ops.map((o) => o['insert']).join(), '2*3*4 y a * b');
    expect(ops.every((o) => o['attributes'] == null), isTrue);
  });

  test('withText converts markdown and keeps plain content in sync', () {
    final (content, rich) = withText('Compra', null, '- **leche**\n- pan');
    expect(content, 'Compra\nleche\npan');
    final ops = jsonDecode(rich) as List;
    expect(ops.where((o) => (o['attributes'] as Map?)?['list'] == 'bullet'),
        hasLength(2));
    expect(stripMarkdown('## **Hola**'), 'Hola');
  });
}
