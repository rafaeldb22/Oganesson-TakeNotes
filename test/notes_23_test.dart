import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:notas/data/note_export.dart';
import 'package:notas/data/note_factory.dart';
import 'package:notas/data/note_filters.dart';
import 'package:notas/data/note_history.dart';
import 'package:notas/data/notes_repository.dart';
import 'package:notas/data/recurrence.dart';
import 'package:notas/models/note.dart';
import 'package:notas/ui/i18n.dart';
import 'package:notas/ui/urgency.dart';
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

    test('completar avanza la fecha y desmarca las casillas', () {
      final repo = _repo();
      final n = repo.notes.firstWhere((x) => !x.isEmpty);
      final due = DateTime.now().add(const Duration(hours: 2));
      repo.setSchedule(n.id,
          remindAt: due.subtract(const Duration(hours: 1)), dueAt: due);
      repo.setRepeat(n.id, 'daily');
      final (c, r) = withChecklist(n.content, n.rich, [('paso', true)]);
      repo.updateContent(n.id, c, rich: r);
      repo.toggleDone(n.id);
      expect(n.done, isFalse);
      expect(n.dueAt!.isAfter(due.toUtc()), isTrue);
      expect(n.rich, isNot(contains('"checked"')));
      expect(n.rich, contains('"unchecked"'));
      repo.dispose();
    });
  });

  group('notas de un solo día', () {
    final due = DateTime(2030, 5, 10, 17, 30);

    test('sin barra hasta ese día y con barra desde las 00:00', () {
      final n = _note('p', 'Peluquería')
        ..dueAt = due.toUtc()
        ..remindAt = Note.dayStart(due).toUtc();
      expect(n.isSingleDay, isTrue);
      expect(n.showsBar(DateTime(2030, 5, 9, 23, 59)), isFalse);
      expect(n.showsBar(DateTime(2030, 5, 10)), isTrue);
    });

    test('un periodo normal sigue mostrando la barra', () {
      final n = _note('p', 'Proyecto')
        ..dueAt = due.toUtc()
        ..remindAt = DateTime(2030, 5, 1, 9).toUtc();
      expect(n.isSingleDay, isFalse);
      expect(n.showsBar(DateTime(2030, 4, 1)), isTrue);
    });

    test('al repetirse sigue siendo de un solo día', () {
      final repo = _repo();
      final n = repo.notes.firstWhere((x) => !x.isEmpty);
      final next = DateTime.now().add(const Duration(hours: 2));
      repo.setSchedule(n.id, remindAt: Note.dayStart(next), dueAt: next);
      repo.setRepeat(n.id, 'daily');
      repo.toggleDone(n.id);
      expect(n.dueAt!.isAfter(next.toUtc()), isTrue);
      expect(n.isSingleDay, isTrue);
      repo.dispose();
    });
  });

  test('las primeras líneas usan los 6 colores del tema, sin repetir', () {
    final repo = _repo();
    for (final n in repo.notes.toList()) {
      if (n.isTemporal) repo.setSchedule(n.id);
    }
    final due = DateTime.now().toUtc().add(const Duration(days: 1));
    final colors = {
      for (var i = 0; i < 6; i++) repo.createNote(dueAt: due).color
    };
    expect(colors, {for (final (_, c) in themeNoteColors) c});
    repo.dispose();
  });

  test('las líneas nuevas no repiten color, salvo elección manual', () {
    final repo = _repo();
    final due = DateTime.now().toUtc().add(const Duration(days: 1));
    final used = repo.notes
        .where((n) => n.isTemporal && !n.done)
        .map((n) => n.color)
        .whereType<int>()
        .toSet();
    final free = themeNoteColors.length - used.length;
    final fresh = [for (var i = 0; i < free; i++) repo.createNote(dueAt: due)];
    final colors = fresh.map((n) => n.color!).toSet();
    expect(colors.length, free);
    expect(colors.intersection(used), isEmpty);

    // Con la paleta llena se repite, pero nunca queda sin color.
    expect(repo.createNote(dueAt: due).color, isNotNull);

    repo.setColor(fresh[1].id, fresh[0].color);
    expect(fresh[1].color, fresh[0].color);

    repo.setColor(fresh[2].id, null);
    repo.setSchedule(fresh[2].id, dueAt: due.add(const Duration(days: 1)));
    expect(fresh[2].color, isNull);
    repo.dispose();
  });

  test('las subtareas antiguas pasan a casillas sin perderse', () async {
    final old = _note('vieja', 'Compra')
      ..subtasks = [
        Subtask(id: '1', text: 'Pan', done: true),
        Subtask(id: '2', text: 'Leche'),
      ];
    SharedPreferences.setMockInitialValues({
      'notas_cache_demo': jsonEncode([old.toRow()]),
    });
    final repo = NotesRepository(
        SupabaseClient('http://127.0.0.1:9', 'clave-de-prueba',
            authOptions: const AuthClientOptions(autoRefreshToken: false)),
        'demo');
    await repo.start();
    final n = repo.byId('vieja')!;
    expect(n.subtasks, isEmpty);
    expect(n.content, contains('Pan'));
    expect(n.content, contains('Leche'));
    expect(n.rich, contains('"checked"'));
    expect(n.rich, contains('"unchecked"'));
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
        ]);
      final md = noteToMarkdown(n);
      expect(md, contains('# Título'));
      expect(md, contains('- **negrita**'));
      expect(md, contains('- [x] hecha'));
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
