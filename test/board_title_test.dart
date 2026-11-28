import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notas/data/note_board.dart';
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

void main() {
  testWidgets('renaming a whiteboard-only note keeps the title', (t) async {
    appLanguage.code = 'es';
    SharedPreferences.setMockInitialValues({});
    t.view.physicalSize = const Size(1200, 800);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final repo = NotesRepository(
        SupabaseClient('http://127.0.0.1:9', 'k',
            authOptions: const AuthClientOptions(autoRefreshToken: false)),
        'demo')
      ..loaded = true;
    final n = repo.createNote();
    await t.pumpWidget(MaterialApp(
      theme: buildTheme(appThemes.first, Brightness.light),
      home: NoteEditor(
          repo: repo,
          noteId: n.id,
          showBack: false,
          onClose: () {},
          onDelete: (_) {}),
    ));
    await _settle(t);
    await t.tap(find.byTooltip('Modo pizarra'));
    await _settle(t);
    final box = t.getRect(find.byType(Whiteboard));
    final g = await t.startGesture(box.topLeft + const Offset(200, 200),
        kind: PointerDeviceKind.mouse);
    for (var x = 220.0; x < 420; x += 20) {
      await g.moveTo(box.topLeft + Offset(x, 220));
      await t.pump(const Duration(milliseconds: 16));
    }
    await g.up();
    await _settle(t);
    await t.enterText(find.byType(TextField).first, 'Mi pizarra');
    await t.testTextInput.receiveAction(TextInputAction.done);
    await _settle(t);
    // Más trazos después de renombrar: el guardado de la pizarra no debe
    // pisar el título.
    final g2 = await t.startGesture(box.topLeft + const Offset(200, 400),
        kind: PointerDeviceKind.mouse);
    for (var x = 220.0; x < 420; x += 20) {
      await g2.moveTo(box.topLeft + Offset(x, 420));
      await t.pump(const Duration(milliseconds: 16));
    }
    await g2.up();
    await _settle(t, 12);
    expect(repo.byId(n.id)!.title, 'Mi pizarra', reason: 'after drawing');
    await t.tap(find.byTooltip('Volver al texto'));
    await _settle(t);
    expect(repo.byId(n.id)!.title, 'Mi pizarra', reason: 'after leaving');
    expect(BoardData.of(repo.byId(n.id)!.rich)!.strokes, hasLength(2));
    await t.tap(find.byTooltip('Modo pizarra'));
    await _settle(t);
    expect(find.text('Mi pizarra'), findsWidgets);
    await t.pumpWidget(const SizedBox());
    repo.dispose();
    await t.pump(const Duration(minutes: 5));
  });
}
