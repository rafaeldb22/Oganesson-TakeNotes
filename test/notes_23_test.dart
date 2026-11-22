import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:notas/data/note_export.dart';
import 'package:notas/data/note_filters.dart';
import 'package:notas/data/note_history.dart';
import 'package:notas/data/notes_repository.dart';
import 'package:notas/data/recurrence.dart';
import 'package:notas/models/note.dart';
import 'package:notas/ui/i18n.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

NotesRepository _repo() => NotesRepository(
    SupabaseClient('http://127.0.0.1:9', 'clave-de-prueba',
        authOptions: const AuthClientOptions(autoRefreshToken: false)),
    'demo')
  ..loaded = true
  ..seedDemo();

Note _note(String id, String text, {DateTime? at, bool vault = false}) {
  final t = at ?? DateTime.utc(2026, 1, 1);
  return Note(id: id, content: text, createdAt: t, updatedAt: t, vault: vault);
}

void main() {
  setUp(() {
    appLanguage.code = 'es';
    SharedPreferences.setMockInitialValues({});
  });

  group('repetición', () {
    test('mensual usa el último día sin perder el original', () {
      final d = DateTime(2026, 1, 31, 9);
      expect(RepeatRule.monthly.next(d), DateTime(2026, 2, 28, 9));
      expect(RepeatRule.monthly.next(d, after: DateTime(2026, 2, 28, 10)),
          DateTime(2026, 3, 31, 9));
    });

    test('laborables se salta el fin de semana', () {
      expect(RepeatRule.weekdays.next(DateTime(2026, 11, 20, 8)),
          DateTime(2026, 11, 23, 8));
    });

    test('una tarea muy vencida salta a la próxima fecha futura', () {
      final next = RepeatRule.daily
          .next(DateTime(2026, 1, 1, 8), after: DateTime(2026, 1, 10, 12));
      expect(next, DateTime(2026, 1, 11, 8));
    });

    test('anual del 29 de febrero', () {
      expect(
          RepeatRule.yearly.next(DateTime(2028, 2, 29)), DateTime(2029, 2, 28));
    });

    test('completar avanza la fecha y reinicia las subtareas', () {
      final repo = _repo();
      final n = repo.notes.firstWhere((x) => !x.isEmpty);
      final due = DateTime.now().add(const Duration(hours: 2));
      repo.setSchedule(n.id,
          remindAt: due.subtract(const Duration(hours: 1)), dueAt: due);
      repo.setRepeat(n.id, 'daily');
      repo.addSubtask(n.id, 'paso');
      repo.toggleSubtask(n.id, n.subtasks.first.id);
      repo.toggleDone(n.id);
      expect(n.done, isFalse);
      expect(n.dueAt!.isAfter(due.toUtc()), isTrue);
      expect(n.subtasks.first.done, isFalse);
      repo.dispose();
    });
  });

  test('subtareas: añadir, progreso, renombrar y quitar', () {
    final repo = _repo();
    final n = repo.notes.firstWhere((x) => !x.isEmpty);
    repo.addSubtask(n.id, ' uno ');
    repo.addSubtask(n.id, 'dos');
    repo.toggleSubtask(n.id, n.subtasks.first.id);
    expect(n.subtaskProgress, 0.5);
    repo.renameSubtask(n.id, n.subtasks.last.id, 'tres');
    expect(n.subtasks.map((t) => t.text), ['uno', 'tres']);
    repo.removeSubtask(n.id, n.subtasks.first.id);
    expect(n.subtasks.length, 1);
    final back = Note.fromRow(jsonDecode(jsonEncode(n.toRow())));
    expect(back.subtasks.single.text, 'tres');
    repo.dispose();
  });

  group('historial', () {
    test('agrupa cambios seguidos y limita las versiones', () {
      final h = NoteHistory();
      final n = _note('a', 'v0');
      final t = DateTime.utc(2026, 1, 1);
      h.record(n, now: t);
      n.content = 'v1';
      h.record(n, now: t.add(const Duration(minutes: 1)));
      expect(h.versionsOf('a').length, 1);
      for (var i = 2; i < 40; i++) {
        n.content = 'v$i';
        h.record(n, now: t.add(Duration(minutes: 10 * i)));
      }
      expect(h.versionsOf('a').length, NoteHistory.maxPerNote);
      expect(h.versionsOf('a').first.content, 'v39');
    });

    test('nunca guarda notas del Vault', () {
      final h = NoteHistory();
      h.record(_note('v', 'secreto', vault: true));
      expect(h.versionsOf('v'), isEmpty);
    });

    test('sobrevive a reiniciar la app', () async {
      final prefs = await SharedPreferences.getInstance();
      final h = NoteHistory();
      await h.load(prefs);
      h.record(_note('a', 'guardada'));
      final again = NoteHistory();
      await again.load(prefs);
      expect(again.versionsOf('a').single.content, 'guardada');
    });
  });

  group('exportar e importar', () {
    test('Markdown conserva el formato', () {
      final n = _note('m', 'Título\nuno')
        ..rich = jsonEncode([
          {'insert': 'Título'},
          {
            'insert': '\n',
            'attributes': {'header': 1}
          },
          {
            'insert': 'negrita',
            'attributes': {'bold': true}
          },
          {
            'insert': '\n',
            'attributes': {'list': 'bullet'}
          },
          {'insert': 'hecha'},
          {
            'insert': '\n',
            'attributes': {'list': 'checked'}
          },
        ])
        ..subtasks = [Subtask(id: 's', text: 'paso', done: true)];
      final md = noteToMarkdown(n);
      expect(md, contains('# Título'));
      expect(md, contains('- **negrita**'));
      expect(md, contains('- [x] hecha'));
      expect(md, contains('- [x] paso'));
    });

    test('la copia no incluye el Vault y se recupera entera', () {
      final b = Backup(
        [_note('a', 'visible'), _note('v', 'secreto', vault: true)],
        const [],
      );
      final text = b.encode();
      expect(text, isNot(contains('secreto')));
      final back = Backup.decode(text);
      expect(back.notes.single.content, 'visible');
    });

    test('rechaza archivos que no son una copia', () {
      expect(() => Backup.decode('hola'), throwsFormatException);
      expect(() => Backup.decode('{"a":1}'), throwsFormatException);
      expect(() => Backup.decode('{"format":"oganesson-backup","notes":[1]}'),
          throwsFormatException);
    });

    test('importar no pisa lo más nuevo ni toca el Vault', () {
      final repo = _repo();
      final local = repo.notes.firstWhere((x) => !x.isEmpty);
      final original = local.content;
      final old = _note(local.id, 'versión vieja');
      final nueva = _note('importada', 'nueva', at: DateTime.utc(2026, 6, 1));
      final oculta = _note('oculta', 'x', vault: true);
      final r = repo.importBackup(Backup([old, nueva, oculta], const []));
      expect(r.notes, 1);
      expect(repo.byId(local.id)!.content, original);
      expect(repo.byId('importada')!.content, 'nueva');
      expect(repo.byId('oculta'), isNull);
      repo.dispose();
    });

    test('genera un PDF válido con tildes', () async {
      final bytes = await notesToPdf([_note('p', 'Título\ncañón y acción')]);
      expect(String.fromCharCodes(bytes.take(4)), '%PDF');
    });

    test('nombre de archivo seguro', () {
      expect(safeFileName('a/b:c?', 'md'), 'abc.md');
      expect(safeFileName('  ', 'pdf'), 'nota.pdf');
    });
  });

  test('filtros combinados', () {
    final now = DateTime(2026, 6, 15, 12);
    final n = _note('f', 'x￼', at: DateTime(2026, 6, 15, 9).toUtc())
      ..color = 7
      ..folderId = 'c';
    expect(const NoteFilters(withImages: true).matches(n, now: now), isTrue);
    expect(const NoteFilters(withTasks: true).matches(n, now: now), isFalse);
    expect(const NoteFilters(color: 7, folderId: 'c').matches(n, now: now),
        isTrue);
    expect(const NoteFilters(folderId: '').matches(n, now: now), isFalse);
    expect(
        const NoteFilters(date: DateFilter.today).matches(n, now: now), isTrue);
    expect(
        const NoteFilters(date: DateFilter.today)
            .matches(n, now: DateTime(2026, 6, 16, 1)),
        isFalse);
    expect(const NoteFilters(date: DateFilter.week, color: 7).count, 2);
  });
}
