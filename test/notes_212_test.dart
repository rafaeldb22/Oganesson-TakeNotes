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
      final w = layoutWeek(monday, notes);
      expect(w[DateTime(2026, 11, 24)]!.extra, 1);
      final wed = w[DateTime(2026, 11, 25)]!;
      expect(wed.extra, 0);
      expect(wed.notes.map((n) => n?.id), contains('d'));
    });

    test('solo hay +N cuando hay más tareas que filas', () {
      final notes = [
        for (final id in ['a', 'b', 'c', 'd']) _task(id, day(2, 9), day(2, 18)),
      ];
      final slots = layoutWeek(monday, notes)[DateTime(2026, 11, 25)]!;
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
