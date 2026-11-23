import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notas/data/note_board.dart';
import 'package:notas/data/notes_repository.dart';
import 'package:notas/ui/i18n.dart';
import 'package:notas/ui/note_editor.dart';
import 'package:notas/ui/theme.dart';
import 'package:notas/ui/whiteboard.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

Future<void> _settle(WidgetTester t, [int n = 6]) async {
  for (var i = 0; i < n; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _loadIcons() async {
  var d = File(Platform.resolvedExecutable).parent;
  while (
      !Directory('${d.path}/bin/cache/artifacts/material_fonts').existsSync()) {
    if (d.parent.path == d.path) return;
    d = d.parent;
  }
  final f = File(
      '${d.path}/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf');
  if (!f.existsSync()) return;
  final loader = FontLoader('MaterialIcons')
    ..addFont(Future.value(ByteData.sublistView(f.readAsBytesSync())));
  await loader.load();
}

Future<NotesRepository> _open(WidgetTester t, String id0) async {
  appLanguage.code = 'es';
  SharedPreferences.setMockInitialValues({});
  t.view.physicalSize = const Size(1200, 800);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  final repo = NotesRepository(
      SupabaseClient('http://127.0.0.1:9', 'clave-de-prueba',
          authOptions: const AuthClientOptions(autoRefreshToken: false)),
      'demo')
    ..loaded = true
    ..seedDemo();
  final id = repo.notes.first.id;
  await t.pumpWidget(MaterialApp(
    theme: buildTheme(themeById(''), Brightness.dark),
    home: NoteEditor(
        repo: repo,
        noteId: id,
        showBack: false,
        onClose: () {},
        onDelete: (_) {}),
  ));
  await _settle(t);
  return repo;
}

Future<void> _drag(WidgetTester t, List<Offset> path) async {
  final g = await t.startGesture(path.first, kind: PointerDeviceKind.mouse);
  await t.pump(const Duration(milliseconds: 16));
  for (final p in path.skip(1)) {
    await g.moveTo(p);
    await t.pump(const Duration(milliseconds: 16));
  }
  await g.up();
  await t.pump(const Duration(milliseconds: 16));
}

Future<void> _end(WidgetTester t, NotesRepository repo) async {
  await t.pumpWidget(const SizedBox());
  repo.dispose();
  await t.pump(const Duration(minutes: 5));
}

void main() {
  testWidgets('dibuja, selecciona con lazo, borra y vuelve al texto',
      (t) async {
    await t.runAsync(_loadIcons);
    final repo = await _open(t, '');
    final id = repo.notes.first.id;
    final title = repo.byId(id)!.title;

    await t.tap(find.byTooltip('Modo pizarra'));
    await _settle(t);
    expect(find.byType(Whiteboard), findsOneWidget);
    expect(find.byTooltip('Negrita'), findsNothing);
    expect(find.byTooltip('Compartir'), findsOneWidget);
    expect(find.byTooltip('Deshacer'), findsOneWidget);

    final box = t.getRect(find.byType(Whiteboard));
    Offset at(double x, double y) => box.topLeft + Offset(x, y);
    await _drag(t, [for (var x = 200.0; x <= 400; x += 20) at(x, 200)]);
    await _drag(t, [for (var x = 200.0; x <= 400; x += 20) at(x, 420)]);
    await t.pump(const Duration(milliseconds: 600));
    expect(BoardData.of(repo.byId(id)!.rich)!.strokes.length, 2);

    // Lazo alrededor del primer trazo: se cierra solo al soltar.
    await t.tap(find.byTooltip('Selector'));
    await _settle(t, 3);
    await _drag(t, [
      at(170, 160),
      at(430, 160),
      at(430, 260),
      at(170, 260),
    ]);
    final state = t.widget<Whiteboard>(find.byType(Whiteboard)).controller;
    expect(state.selectedStrokes.length, 1);

    // Clic derecho: menú con las acciones de la selección.
    final menu = await t.startGesture(at(300, 210),
        kind: PointerDeviceKind.mouse, buttons: kSecondaryMouseButton);
    await menu.up();
    await _settle(t);
    expect(find.text('Duplicar'), findsOneWidget);
    await t.tap(find.text('Eliminar'));
    await _settle(t);
    expect(state.strokes.length, 1);

    await t.tap(find.byTooltip('Deshacer'));
    await _settle(t, 3);
    expect(state.strokes.length, 2);

    // Goma sobre el segundo trazo: lo parte en dos.
    await t.tap(find.byTooltip('Goma'));
    await _settle(t, 3);
    await _drag(t, [at(300, 400), at(300, 440)]);
    expect(state.strokes.length, 3);
    state.tool = BoardTool.pen;

    await t.tap(find.byTooltip('Volver al texto'));
    await _settle(t);
    expect(find.byType(Whiteboard), findsNothing);
    final n = repo.byId(id)!;
    expect(n.title, title);
    expect(BoardData.of(n.rich)!.active, isFalse);
    expect(BoardData.of(n.rich)!.strokes.length, 3);
    await _end(t, repo);
  });

  testWidgets('abrir la pizarra sin dibujar no cambia la nota', (t) async {
    final repo = await _open(t, '');
    final n = repo.notes.first;
    final before = n.rich;
    await t.tap(find.byTooltip('Modo pizarra'));
    await _settle(t);
    await t.tap(find.byTooltip('Volver al texto'));
    await _settle(t);
    expect(repo.byId(n.id)!.rich, before);
    await _end(t, repo);
  });

  testWidgets('captura de la pizarra', (t) async {
    final out = Platform.environment['BOARD_SHOT'];
    if (out == null) return;
    await t.runAsync(_loadIcons);
    final repo = await _open(t, '');
    await t.tap(find.byTooltip('Modo pizarra'));
    await _settle(t);
    final box = t.getRect(find.byType(Whiteboard));
    await _drag(t, [
      for (var i = 0; i < 60; i++)
        box.topLeft + Offset(160 + i * 9.0, 240 + 70 * (i % 12 < 6 ? 1 : -1.0))
    ]);
    await _settle(t);
    await expectLater(
        find.byType(NoteEditor), matchesGoldenFile(Uri.file(out)));
    await _end(t, repo);
  });
}
