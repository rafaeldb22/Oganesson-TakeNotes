import 'package:flutter_test/flutter_test.dart';
import 'package:notas/data/notes_repository.dart';
import 'package:notas/models/note.dart';
import 'package:notas/ui/focus_tools.dart';
import 'package:notas/ui/format.dart';
import 'package:notas/ui/i18n.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

NotesRepository _repo() => NotesRepository(
    SupabaseClient('http://127.0.0.1:9', 'k',
        authOptions: const AuthClientOptions(autoRefreshToken: false)),
    'demo')
  ..loaded = true;

void main() {
  setUp(() {
    appLanguage.code = 'es';
    SharedPreferences.setMockInitialValues({});
  });

  test('a one-day note runs until midnight and says "Hoy"', () {
    final now = DateTime.now();
    final day = DateTime(now.year, now.month, now.day);
    final n = Note(
        id: 'n',
        content: 'x',
        createdAt: DateTime.utc(2026),
        updatedAt: DateTime.utc(2026),
        remindAt: day.toUtc(),
        dueAt: Note.dayEnd(day).toUtc());
    expect(n.isSingleDay, isTrue);
    expect(n.barEnd, DateTime(day.year, day.month, day.day + 1).toUtc());
    expect(n.isToday(), isTrue);
    expect(tiempoNota(n), startsWith('Hoy · quedan'));
  });

  test('temporal notes are calendar-only unless marked to complete', () {
    final r = _repo();
    final n = r.createNote(
        dueAt: DateTime.now().subtract(const Duration(days: 1)).toUtc());
    r.updateContent(n.id, 'Evento');
    expect(n.checkable, isFalse);
    expect(n.isOverdue(), isFalse);
    expect(tiempoNota(n), startsWith('terminó hace'));
    r.setCheckable(n.id, true);
    expect(n.checkable, isTrue);
    expect(n.isOverdue(), isTrue);
    r.dispose();
  });

  test('a task in a coloured folder takes the folder colour', () {
    final r = _repo();
    final f = r.createFolder('Clase', color: 0xFF3366FF);
    final n = r.createNote(folderId: f.id);
    r.updateContent(n.id, 'Entrega');
    r.setSchedule(n.id, dueAt: DateTime.now().add(const Duration(days: 2)));
    expect(n.color, 0xFF3366FF);
    r.dispose();
  });

  test('productivity counts created notes and done tasks per day', () async {
    final r = _repo();
    final a = r.createNote(dueAt: DateTime.now().toUtc());
    r.updateContent(a.id, 'Tarea');
    r.setCheckable(a.id, true);
    r.toggleDone(a.id);
    final b = r.createNote();
    r.updateContent(b.id, 'Nota');
    final s = await ProductivityStats.of(r);
    expect(s.days, hasLength(7));
    expect(s.created.last, 2);
    expect(s.done.last, 1);
    r.dispose();
  });
}
