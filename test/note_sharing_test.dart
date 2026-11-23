import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notas/data/ai_actions.dart';
import 'package:notas/data/ai_assistant.dart';
import 'package:notas/data/note_sharing.dart';
import 'package:notas/data/notes_repository.dart';
import 'package:notas/models/note.dart';
import 'package:notas/ui/i18n.dart';
import 'package:notas/ui/notes_home.dart';
import 'package:notas/ui/theme.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

NotesRepository _repo() => NotesRepository(
    SupabaseClient('http://127.0.0.1:9', 'clave-de-prueba',
        authOptions: const AuthClientOptions(autoRefreshToken: false)),
    'demo')
  ..loaded = true
  ..seedDemo();

/// Pone en la caché una nota de otra cuenta y arranca el repositorio.
Future<NotesRepository> _withForeign(String role) async {
  final t = DateTime.now().toUtc();
  final n = Note(
      id: 'ajena',
      content: 'Nota ajena\ntexto',
      createdAt: t,
      updatedAt: t,
      ownerId: 'otra-cuenta',
      dueAt: t.add(const Duration(days: 1)));
  SharedPreferences.setMockInitialValues({
    'notas_cache_demo': jsonEncode([n.toRow()]),
    'notas_compartidas_demo': jsonEncode({
      'in': {
        'ajena': {'role': role, 'owner': 'dueno@x.com'}
      },
      'out': [],
    }),
  });
  final repo = NotesRepository(
      SupabaseClient('http://127.0.0.1:9', 'clave-de-prueba',
          authOptions: const AuthClientOptions(autoRefreshToken: false)),
      'demo');
  await repo.start();
  return repo;
}

void main() {
  setUp(() {
    appLanguage.code = 'es';
    SharedPreferences.setMockInitialValues({});
  });

  test('sin texto debajo no se muestra nada', () {
    final t = DateTime.utc(2026);
    expect(
        Note(id: 'a', content: 'Solo', createdAt: t, updatedAt: t).preview, '');
  });

  test('una nota ajena solo cambia su texto, y con permiso', () async {
    final repo = await _withForeign('edit');
    final n = repo.byId('ajena')!;
    expect(repo.isForeign(n), isTrue);
    repo.togglePin(n.id);
    repo.moveToFolder(n.id, 'x');
    repo.setVault(n.id, true);
    repo.delete(n.id);
    expect(n.pinned, isFalse);
    expect(n.folderId, isNull);
    expect(n.vault, isFalse);
    expect(n.deleted, isFalse);
    repo.updateContent(n.id, 'Editada');
    expect(n.content, 'Editada');
    repo.dispose();
  });

  test('solo lectura no cambia nada', () async {
    final repo = await _withForeign('read');
    final n = repo.byId('ajena')!;
    expect(repo.canEdit(n), isFalse);
    repo.updateContent(n.id, 'No');
    expect(n.content, startsWith('Nota ajena'));
    repo.dispose();
  });

  test('las notas ajenas nunca llegan a la IA', () async {
    final repo = await _withForeign('edit');
    final tools = AiTools(repo, confirm: (_) async => true);
    expect(jsonEncode(await tools.run('list_notes', {})),
        isNot(contains('Nota ajena')));
    expect(jsonEncode(await tools.run('list_tasks', {'status': 'all'})),
        isNot(contains('Nota ajena')));
    expect(jsonEncode(await tools.run('read_note', {'id': 'ajena'})),
        contains('error'));
    expect(dailyBriefData(repo), isNot(contains('Nota ajena')));
    repo.dispose();
  });

  test('errores del servidor con mensajes claros', () {
    expect(
        shareError(const PostgrestException(message: 'x', code: 'PGRST202'))
            .message,
        contains('010'));
    expect(shareError(const PostgrestException(message: 'self')).message,
        contains('propia'));
    expect(shareError(StateError('x')).message, contains('conexión'));
  });

  testWidgets('la lista no tiene franja, contador ni "[["', (tester) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final repo = _repo();
    final n = repo.notes.firstWhere((x) => x.title == 'Pelis pendientes');
    repo.setColor(n.id, 0xFFE5484D);
    await tester.pumpWidget(MaterialApp(
      theme: buildTheme(themeById(''), Brightness.dark),
      home: NotesHome(repo: repo),
    ));
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.textContaining(RegExp(r'^\d+ notas?$')), findsNothing);
    expect(find.text('Sin texto adicional'), findsNothing);
    await tester.tap(find.text(n.title).first);
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.byType(QuillEditor), findsOneWidget);
    expect(find.byTooltip('Enlazar nota'), findsOneWidget);
    expect(find.byTooltip('Compartir'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    repo.dispose();
    await tester.pump(const Duration(minutes: 5));
  });

  testWidgets('nota de solo lectura: sin formato y con aviso', (tester) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final repo = await tester.runAsync(() => _withForeign('read'));
    await tester.pumpWidget(MaterialApp(
      theme: buildTheme(themeById(''), Brightness.dark),
      home: NotesHome(repo: repo!),
    ));
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.tap(find.text('Nota ajena').first);
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.textContaining('dueno@x.com'), findsOneWidget);
    expect(find.byTooltip('Negrita'), findsNothing);
    expect(find.byTooltip('Acciones con IA'), findsNothing);
    expect(find.byTooltip('Eliminar nota'), findsNothing);
    expect(find.byTooltip('Compartir'), findsOneWidget);
    expect(
        tester
            .widget<QuillEditor>(find.byType(QuillEditor))
            .controller
            .readOnly,
        isTrue);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    repo.dispose();
    await tester.pump(const Duration(minutes: 5));
  });
}
