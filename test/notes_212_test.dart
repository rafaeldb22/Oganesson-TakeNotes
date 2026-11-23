import 'dart:convert';
import 'dart:ui';

import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notas/data/accounts.dart';
import 'package:notas/data/note_attachments.dart';
import 'package:notas/data/note_board.dart';
import 'package:notas/data/note_factory.dart';
import 'package:notas/models/note.dart';
import 'package:notas/ui/calendar_view.dart';

Note _task(String id, DateTime from, DateTime to) => Note(
      id: id,
      content: id,
      createdAt: from.toUtc(),
      updatedAt: from.toUtc(),
      remindAt: from.toUtc(),
      dueAt: to.toUtc(),
    );

BoardStroke _line(double x0, double x1) => BoardStroke(0, 2, [
      for (var x = x0; x <= x1; x += 1) Offset(x, 0),
    ], [
      for (var x = x0; x <= x1; x += 1) 1,
    ]);

void main() {
  group('2.13', () {
    test('siete líneas solapadas conservan su fila toda la semana', () {
      final monday = DateTime(2026, 11, 23);
      final notes = [
        for (var i = 0; i < 7; i++)
          _task('n$i', DateTime(2026, 11, 23 + (i % 2), 9),
              DateTime(2026, 11, 28, 18)),
      ];
      final rows = assignLanes(notes);
      expect(rows.values.toSet().length, 7);
      final week = layoutWeek(monday, notes, assigned: rows);
      final sat = week[DateTime(2026, 11, 28)]!;
      expect(sat.extra, 0);
      for (final n in notes) {
        expect(sat.notes[rows[n.id]!]?.id, n.id);
      }
    });

    test('dos tareas que no coinciden comparten fila', () {
      final rows = assignLanes([
        _task('a', DateTime(2026, 11, 23, 9), DateTime(2026, 11, 24, 9)),
        _task('b', DateTime(2026, 11, 26, 9), DateTime(2026, 11, 27, 9)),
      ]);
      expect(rows['a'], rows['b']);
    });

    test('un archivo conectado no entra en el texto de la nota', () {
      final n = Note(
          id: 'n',
          content: 'Nota',
          rich: richFor('Nota'),
          createdAt: DateTime.utc(2026),
          updatedAt: DateTime.utc(2026),
          links: [
            'otra-nota',
            'att:${jsonEncode({'image': 'sb://u/foto?w=1&h=1'})}',
          ]);
      expect(mediaIn(n.rich), isEmpty);
      final item = linkedMedia(n).single;
      expect(item.linked, isTrue);
      expect(item.path, 'u/foto');
      expect(allMediaOf(n).length, 1);
    });

    test('el código de un archivo es estable y corto', () {
      expect(mediaCode('u/a'), mediaCode('u/a'));
      expect(mediaCode('u/a'), isNot(mediaCode('u/b')));
      expect(mediaCode('u/a'), matches(RegExp(r'^F[0-9A-Z]{7}$')));
    });

    test('escalar desde una esquina deja quieta la opuesta', () {
      final box = BoardBox.around(const Rect.fromLTWH(0, 0, 100, 50));
      final (t, b) = box.resize(4, const Offset(200, 100));
      final anchor = t.apply(Offset.zero);
      expect(anchor.dx, closeTo(0, 1e-6));
      expect(anchor.dy, closeTo(0, 1e-6));
      expect(b.size.width, closeTo(200, 1e-6));
      expect(b.size.height, closeTo(100, 1e-6));
    });

    test('un lado cambia solo el ancho', () {
      final box = BoardBox.around(const Rect.fromLTWH(0, 0, 100, 50));
      final (_, b) = box.resize(3, const Offset(150, 25));
      expect(b.size.width, closeTo(150, 1e-6));
      expect(b.size.height, closeTo(50, 1e-6));
    });

    test('girar mantiene el centro y los trazos a la misma distancia', () {
      final box = BoardBox.around(const Rect.fromLTWH(-10, -10, 20, 20));
      final (t, b) = box.rotate(const Offset(10, 0), const Offset(0, 10));
      expect(b.angle, closeTo(1.5707963, 1e-6));
      final p = t.apply(const Offset(10, 0));
      expect(p.dx, closeTo(0, 1e-6));
      expect(p.dy, closeTo(10, 1e-6));
    });

    test('una imagen girada se guarda y se recupera', () {
      final t = BoardAffine.rotation(const Offset(5, 5), 0.5);
      final img = BoardImage('sb://u/a', const Rect.fromLTWH(0, 0, 10, 10), t);
      final back = BoardImage.fromJson(jsonDecode(jsonEncode(img.toJson())))!;
      expect(back.center.dx, closeTo(img.center.dx, 1e-6));
      expect(back.bounds.width, closeTo(img.bounds.width, 1e-6));
    });
  });

  group('calendario', () {
    final monday = DateTime(2026, 11, 23);
    DateTime day(int i, [int h = 12]) => DateTime(2026, 11, 23 + i, h);

    test('una tarea usa un hueco libre en vez de quedarse en +N', () {
      // Tres líneas ocupan el lunes y el martes; la cuarta empieza el martes
      // y llega al jueves, cuando ya hay sitio.
      final notes = [
        _task('a', day(0), day(1)),
        _task('b', day(0), day(1)),
        _task('c', day(0), day(1)),
        _task('d', day(1), day(3)),
      ];
      final w = layoutWeek(monday, notes, lanes: 3);
      expect(w[DateTime(2026, 11, 24)]!.extra, 1);
      final wed = w[DateTime(2026, 11, 25)]!;
      expect(wed.extra, 0);
      expect(wed.notes.map((n) => n?.id), contains('d'));
    });

    test('solo hay +N cuando hay más tareas que filas', () {
      final notes = [
        for (final id in ['a', 'b', 'c', 'd']) _task(id, day(2, 9), day(2, 18)),
      ];
      final slots =
          layoutWeek(monday, notes, lanes: 3)[DateTime(2026, 11, 25)]!;
      expect(slots.notes.whereType<Note>().length, 3);
      expect(slots.extra, 1);
    });
  });

  group('títulos de la IA', () {
    test('añadir texto no convierte la última línea en título', () {
      final rich = richFor('Compra\nleche');
      final (_, out) = withText('Compra\nleche', rich, 'pan');
      final doc = Document.fromJson(jsonDecode(out) as List);
      final lines = doc.root.children.toList();
      expect(lines.first.style.attributes.containsKey('header'), isTrue);
      expect(lines.last.toPlainText().trim(), 'pan');
      expect(lines.last.style.attributes.containsKey('header'), isFalse);
    });

    test('añadir a una nota con solo título lo mantiene como título', () {
      final (content, out) = withText('Ideas', richFor('Ideas'), 'una');
      expect(content, 'Ideas\nuna');
      final lines =
          Document.fromJson(jsonDecode(out) as List).root.children.toList();
      expect(lines.first.style.attributes.containsKey('header'), isTrue);
      expect(lines.last.style.attributes.containsKey('header'), isFalse);
    });
  });

  group('adjuntos', () {
    const src = 'sb://u1/img?w=10&h=20';

    test('una imagen copiada conserva su formato y la marca de la red', () {
      final (content, rich) = withEmbeds('Nota', richFor('Nota'), [
        embedWithGraph({'image': src}, true),
      ]);
      expect(content, 'Nota\n￼\n'.trimRight());
      final item = mediaIn(rich).single;
      expect(item.kind, MediaKind.image);
      expect(item.path, 'u1/img');
      expect(item.inGraph, isTrue);
      expect(embedWithGraph(item.embed, false)['image'], src);
      Document.fromJson(jsonDecode(rich) as List);
    });
  });

  group('pizarra', () {
    test('se guarda dentro del Delta y se recupera', () {
      final board = BoardData(strokes: [_line(0, 4)]);
      final (content, rich) =
          BoardData.store('Título', richFor('Título'), board);
      expect(content, startsWith('Título'));
      final back = BoardData.of(rich)!;
      expect(back.strokes.single.points.length, 5);
      final doc = Document.fromJson(jsonDecode(rich) as List);
      expect(doc.toPlainText(), contains('Título'));

      back.strokes = [];
      final (_, again) = BoardData.store(content, rich, back);
      expect(BoardData.of(again)!.strokes, isEmpty);
      expect(RegExp('oga-board').allMatches(again).length, 1);
    });

    test('la goma parte un trazo en dos', () {
      final out = eraseStrokes(
          [_line(0, 20)], const Offset(10, 0), const Offset(10, 0), 2)!;
      expect(out.length, 2);
      expect(out.first.points.last.dx, lessThan(10));
      expect(out.last.points.first.dx, greaterThan(10));
    });

    test('la goma no toca lo que está lejos', () {
      expect(
          eraseStrokes(
              [_line(0, 5)], const Offset(50, 50), const Offset(50, 50), 2),
          isNull);
    });

    test('el lazo selecciona solo lo que queda dentro', () {
      const loop = [
        Offset(-5, -5),
        Offset(12, -5),
        Offset(12, 5),
        Offset(-5, 5),
      ];
      final strokes = [_line(0, 10), _line(30, 40)];
      expect(strokesInLasso(strokes, loop), {0});
    });
  });

  group('@nombres', () {
    test('normaliza y valida', () {
      expect(cleanUsername(' @Rafa_1 '), 'rafa_1');
      expect(validUsername('@rafa'), isTrue);
      expect(validUsername('ab'), isFalse);
      expect(validUsername('con espacio'), isFalse);
    });

    test('distingue @nombre de correo al entrar', () {
      expect(isUsernameLogin('@rafa'), isTrue);
      expect(isUsernameLogin('rafa'), isTrue);
      expect(isUsernameLogin('rafa@correo.com'), isFalse);
    });
  });
}
