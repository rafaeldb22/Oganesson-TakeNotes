import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:notas/data/note_images.dart';
import 'package:notas/data/notes_repository.dart';
import 'package:notas/ui/i18n.dart';
import 'package:notas/ui/note_editor.dart';
import 'package:notas/ui/note_image.dart';
import 'package:notas/ui/theme.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  testWidgets('una imagen en la nota se ve, se abre en grande y se cierra',
      (tester) async {
    appLanguage.code = 'es';
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final client = SupabaseClient('http://127.0.0.1:9', 'clave-de-prueba',
        authOptions: const AuthClientOptions(autoRefreshToken: false));
    final repo = NotesRepository(client, 'demo');
    repo.loaded = true;
    await NoteImages.instance.attach(null, 'demo');

    // Imagen de 640x360: se añade como lo haría Ctrl+V.
    final png = img.encodePng(
        img.Image(width: 640, height: 360)..clear(img.ColorRgb8(40, 120, 220)));
    final src = (await tester.runAsync(() => NoteImages.instance.add(png)))!;
    expect(src, startsWith('sb://demo/'));
    expect(src, endsWith('?w=640&h=360'));

    final n = repo.createNote();
    repo.updateContent(n.id, 'Captura\n\uFFFC',
        rich: jsonEncode([
          {'insert': 'Captura'},
          {
            'insert': '\n',
            'attributes': {'header': 1}
          },
          {
            'insert': {'image': src}
          },
          {'insert': '\n'},
        ]));

    await tester.pumpWidget(MaterialApp(
      theme: buildTheme(themeById(''), Brightness.light),
      home: NoteEditor(
        repo: repo,
        noteId: n.id,
        onClose: () {},
        onDelete: (_) {},
      ),
    ));
    await tester.pump(const Duration(milliseconds: 600));

    expect(find.byType(NoteImageView), findsOneWidget);
    final box = tester.getSize(find.byType(NoteImageView));
    expect(box.width, greaterThan(300));

    // Toque: visor a pantalla completa.
    await tester.tap(find.byType(NoteImageView));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.byTooltip('Cerrar'), findsOneWidget);
    expect(find.byTooltip('Copiar imagen'), findsWidgets);

    // Esc lo cierra.
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.byTooltip('Cerrar'), findsNothing);
    expect(tester.takeException(), isNull);

    expect(repo.byId(n.id)!.title, 'Captura');

    // El cursor no se dibuja al lado de la imagen (sería gigante), sí en
    // el texto.
    bool showCursor() =>
        tester.widget<QuillEditor>(find.byType(QuillEditor)).config.showCursor!;
    final ctrl =
        tester.widget<QuillEditor>(find.byType(QuillEditor)).controller;
    ctrl.updateSelection(
        const TextSelection.collapsed(offset: 8), ChangeSource.local);
    await tester.pump();
    expect(showCursor(), isFalse);
    ctrl.updateSelection(
        const TextSelection.collapsed(offset: 3), ChangeSource.local);
    await tester.pump();
    expect(showCursor(), isTrue);

    await tester.pumpWidget(const SizedBox());
    repo.dispose();
    await tester.pump(const Duration(minutes: 5));
  });
}
