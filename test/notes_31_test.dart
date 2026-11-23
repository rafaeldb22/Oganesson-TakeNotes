import 'dart:math';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:notas/data/ai_assistant.dart';
import 'package:notas/data/note_board.dart';
import 'package:notas/data/notes_repository.dart';
import 'package:notas/models/note.dart';
import 'package:notas/ui/i18n.dart';
import 'package:notas/ui/whiteboard.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

NotesRepository _repo() => NotesRepository(
    SupabaseClient('http://127.0.0.1:9', 'k',
        authOptions: const AuthClientOptions(autoRefreshToken: false)),
    'demo')
  ..loaded = true;

List<Offset> _zigzag({int passes = 8, double w = 80}) => [
      for (var i = 0; i <= passes * 10; i++)
        Offset((i % 20 < 10 ? i % 20 : 20 - i % 20) * w / 10, i * 0.2),
    ];

void main() {
  group('garabato', () {
    test('reconoce el ida y vuelta, no una línea ni una curva', () {
      expect(isScribble(_zigzag()), isTrue);
      expect(isScribble([for (var x = 0.0; x < 200; x += 2) Offset(x, 0)]),
          isFalse);
      expect(
          isScribble([
            for (var t = 0.0; t < 6; t += 0.05) Offset(t * 30, sin(t * 2) * 12),
          ]),
          isFalse);
    });

    test('borra lo que recorre y se puede deshacer', () {
      final ink = BoardStroke(0, 2, [
        for (var x = 0.0; x <= 80; x += 2) Offset(x, 8)
      ], [
        for (var x = 0.0; x <= 80; x += 2) 1,
      ]);
      final far =
          BoardStroke(0, 2, const [Offset(0, 300), Offset(9, 300)], [1, 1]);
      final c =
          BoardController(BoardData(strokes: [ink, far]), onChanged: () {});
      expect(c.eraseScribble(_zigzag(), 8), isTrue);
      expect(c.strokes.single, same(far));
      c.undo();
      expect(c.strokes.length, 2);
      expect(c.eraseScribble(const [Offset(900, 900), Offset(950, 900)], 8),
          isFalse);
    });
  });

  test('una fecha de todo el día no depende de la hora de inicio', () {
    final due = Note.dayEnd(DateTime(2026, 12, 5));
    final n = Note(
        id: 'n',
        content: 'x',
        createdAt: DateTime.utc(2026),
        updatedAt: DateTime.utc(2026),
        remindAt: DateTime(2026, 12, 1, 17, 42).toUtc(),
        dueAt: due.toUtc());
    expect(n.isAllDay, isTrue);
    n.dueAt = DateTime(2026, 12, 5, 20).toUtc();
    expect(n.isAllDay, isFalse);
  });

  test('la IA pide cada cambio por separado', () async {
    appLanguage.code = 'es';
    SharedPreferences.setMockInitialValues({});
    final r = _repo();
    final a = r.createNote(), b = r.createNote(), c = r.createNote();
    r.updateContent(a.id, 'A');
    r.updateContent(b.id, 'B');
    r.updateContent(c.id, 'C');
    final asked = <String>[];
    final tools = AiTools(r, confirm: (q) async {
      asked.add(q);
      return !q.contains('«C»');
    });
    await tools.run('link_notes', {
      'id': a.id,
      'targets': [b.id, c.id]
    });
    expect(asked.length, 2);
    expect(a.links, contains(b.id));
    expect(a.links, isNot(contains(c.id)));

    asked.clear();
    final out = await tools.run('set_pinned', {'id': b.id, 'pinned': true});
    expect(asked.length, 1);
    expect(out['ok'], isTrue);
    r.dispose();
  });

  test('sin hora, la IA deja la tarea hasta el final del día', () async {
    SharedPreferences.setMockInitialValues({});
    final r = _repo();
    final tools = AiTools(r, confirm: (_) async => true);
    final out =
        await tools.run('create_note', {'title': 'Tarea', 'due': '2030-03-04'});
    expect(r.byId('${out['id']}')!.isAllDay, isTrue);
    r.dispose();
  });
}
