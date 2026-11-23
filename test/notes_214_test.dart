import 'dart:convert';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notas/data/note_attachments.dart';
import 'package:notas/data/note_board.dart';
import 'package:notas/data/note_factory.dart';
import 'package:notas/data/note_files.dart';
import 'package:notas/data/notes_repository.dart';
import 'package:notas/ui/i18n.dart';
import 'package:notas/ui/note_editor.dart';
import 'package:notas/ui/theme.dart';
import 'package:notas/ui/whiteboard.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

Future<void> _settle(WidgetTester t, [int n = 8]) async {
  for (var i = 0; i < n; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
}

BoardStroke _line(double x) =>
    BoardStroke(0, 2, [Offset(x, 0), Offset(x + 10, 0)], [1, 1]);

void main() {
  test('completar gana aunque otro dispositivo tenga el reloj adelantado', () {
    SharedPreferences.setMockInitialValues({});
    final r = NotesRepository(
        SupabaseClient('http://127.0.0.1:9', 'k',
            authOptions: const AuthClientOptions(autoRefreshToken: false)),
        'demo')
      ..loaded = true;
    final now = DateTime.now();
    final n = r.createNote(
        dueAt: now.add(const Duration(days: 2)).toUtc(), remindAt: now.toUtc());
    r.updateContent(n.id, 'Tarea');
    final ahead = DateTime.now().toUtc().add(const Duration(hours: 1));
    n.updatedAt = ahead;
    r.toggleDone(n.id);
    expect(n.done, isTrue);
    expect(n.updatedAt.isAfter(ahead), isTrue);
    r.dispose();
  });

  testWidgets('quitar un archivo lo borra y no toca el título', (t) async {
    appLanguage.code = 'es';
    SharedPreferences.setMockInitialValues({});
    t.view.physicalSize = const Size(1200, 800);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final r = NotesRepository(
        SupabaseClient('http://127.0.0.1:9', 'k',
            authOptions: const AuthClientOptions(autoRefreshToken: false)),
        'demo')
      ..loaded = true;
    final n = r.createNote();
    const f = NoteFile(
        src: 'ogf://demo/a', name: 'a.pdf', size: 10, mime: 'application/pdf');
    final (c, rich) =
        withEmbeds('Titulo\nTexto', richFor('Titulo\nTexto'), [fileEmbed(f)]);
    r.updateContent(n.id, c, rich: rich);
    await t.pumpWidget(MaterialApp(
      theme: buildTheme(themeById(''), Brightness.dark),
      home: NoteEditor(
          repo: r,
          noteId: n.id,
          showBack: false,
          onClose: () {},
          onDelete: (_) {}),
    ));
    await _settle(t);
    await t.tap(find.byTooltip('Opciones'));
    await _settle(t);
    await t.tap(find.text('Quitar'));
    await _settle(t);
    final after = r.byId(n.id)!;
    expect(mediaIn(after.rich), isEmpty);
    expect(after.content, startsWith('Titulo\nTexto'));
    await t.pumpWidget(const SizedBox());
    r.dispose();
    await t.pump(const Duration(minutes: 5));
  });

  group('pasar la pizarra a texto', () {
    test('solo vuelve a leer lo nuevo', () {
      final c =
          BoardController(BoardData(strokes: [_line(0)]), onChanged: () {});
      final first = c.unreadData();
      expect(first.strokes.length, 1);
      c.markRead(first, 'hola');
      expect(c.unreadData().strokes, isEmpty);

      c.addStroke(_line(50));
      expect(c.unreadData().strokes.single.points.first.dx, 50);
    });

    test('mover o cortar un trazo leído no lo hace nuevo', () {
      final s = _line(0)..read = true;
      expect(s.moved(const Offset(5, 5)).read, isTrue);
      expect(s.transformed(BoardAffine.rotation(Offset.zero, 1)).read, isTrue);
      final long = BoardStroke(0, 2, [
        for (var x = 0.0; x <= 20; x++) Offset(x, 0),
      ], [
        for (var x = 0.0; x <= 20; x++) 1,
      ])
        ..read = true;
      final cut =
          eraseStrokes([long], const Offset(10, 0), const Offset(10, 0), 1)!;
      expect(cut.every((x) => x.read), isTrue);
    });

    test('lo leído sobrevive al guardar', () {
      final d = BoardData(strokes: [_line(0)..read = true], readText: 'hola');
      final back = BoardData.decode(jsonDecode(jsonEncode(d.encode())))!;
      expect(back.strokes.single.read, isTrue);
      expect(back.readText, 'hola');
    });
  });
}
