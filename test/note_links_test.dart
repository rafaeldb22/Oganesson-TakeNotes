import 'package:flutter_test/flutter_test.dart';
import 'package:notas/data/note_links.dart';
import 'package:notas/models/note.dart';

Note n(String id, String content, {List<String>? links, int age = 0}) {
  final t = DateTime(2026, 1, 1).add(Duration(minutes: -age));
  return Note(
      id: id, content: content, createdAt: t, updatedAt: t, links: links);
}

void main() {
  test('enlaces manuales y de texto', () {
    final g = NoteGraph.build([
      n('a', 'Proyecto\nVer [[ideas]]', links: ['c', 'falta']),
      n('b', 'Ideas\nnada'),
      n('c', 'Compras\nlista'),
      n('vacia', '   '),
    ]);
    expect(g.outgoing['a'], {'b', 'c'}); // 'falta' no existe: se ignora
    expect(g.incoming['c'], {'a'});
    expect(g.degree('b'), 1);
    expect(g.nodes.map((e) => e.id), isNot(contains('vacia')));
  });

  test('título repetido: gana la nota más reciente', () {
    final g = NoteGraph.build([
      n('a', 'Diario\n[[Tema]]'),
      n('old', 'Tema\nvieja', age: 10),
      n('new', 'Tema\nnueva'),
    ]);
    expect(g.outgoing['a'], {'new'});
  });
}
