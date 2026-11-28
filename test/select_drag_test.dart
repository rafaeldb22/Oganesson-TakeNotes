import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notas/data/notes_repository.dart';
import 'package:notas/ui/i18n.dart';
import 'package:notas/ui/note_editor.dart';
import 'package:notas/ui/theme.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  testWidgets('drag-select down past the bottom scrolls without bouncing',
      (t) async {
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
    repo.updateContent(
        n.id,
        ['Título', for (var i = 0; i < 120; i++) 'Línea número $i del texto']
            .join('\n'));
    await t.pumpWidget(MaterialApp(
      theme: buildTheme(appThemes.first, Brightness.light),
      localizationsDelegates: const [FlutterQuillLocalizations.delegate],
      home: Scaffold(
        body: NoteEditor(
            repo: repo,
            noteId: n.id,
            onClose: () {},
            onDelete: (_) {},
            showBack: false),
      ),
    ));
    await t.pump(const Duration(milliseconds: 600));
    final editor = t.getRect(find.byType(QuillEditor));
    final g = await t.startGesture(editor.topLeft + const Offset(60, 120),
        kind: PointerDeviceKind.mouse, buttons: kPrimaryButton);
    await t.pump(const Duration(milliseconds: 50));
    final scrollable = find.descendant(
        of: find.byType(QuillEditor), matching: find.byType(Scrollable));
    final offsets = <double>[];
    for (var i = 0; i < 40; i++) {
      final y = editor.top + 120 + i * 20.0;
      await g.moveTo(Offset(editor.left + 60, y.clamp(0, editor.bottom + 30)));
      await t.pump(const Duration(milliseconds: 16));
      await t.pump(const Duration(milliseconds: 16));
      final s = t.state<ScrollableState>(scrollable.first).position.pixels;
      offsets.add(s);
    }
    await g.up();
    await t.pump(const Duration(seconds: 1));
    var backs = 0;
    for (var i = 1; i < offsets.length; i++) {
      if (offsets[i] < offsets[i - 1] - 1) backs++;
    }
    // Antes volvía a subir hasta el inicio de la selección.
    expect(backs, 0);
    expect(offsets.last, greaterThan(300));
    await t.pumpWidget(const SizedBox());
    repo.dispose();
    await t.pump(const Duration(minutes: 5));
  });
}
