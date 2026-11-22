import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:notas/ui/i18n.dart';
import 'package:notas/ui/image_tools.dart';
import 'package:notas/ui/theme.dart';

const _src = 'sb://u/foto?w=10&h=10';

/// Nota: "Uno\nDos\n[imagen]\nTres\n".
QuillController _doc() {
  final c = QuillController.basic();
  c.document.insert(0, 'Uno\nDos\nTres');
  insertImageBlock(c, 8, _src);
  return c;
}

/// El documento como texto, con [IMG] en lugar de la imagen.
String _text(QuillController c) =>
    c.document.toPlainText().replaceAll('￼', '[IMG]');

int _imageAt(QuillController c) => c.document.toPlainText().indexOf('￼');

void main() {
  test('documento de partida', () {
    expect(_text(_doc()), 'Uno\nDos\n[IMG]\nTres\n');
  });

  test('el cursor se oculta solo al lado de una imagen', () {
    final c = _doc(); // "Uno", "Dos", imagen, "Tres"
    void at(int o) => c.updateSelection(
        TextSelection.collapsed(offset: o), ChangeSource.local);
    final img = _imageAt(c);
    at(img);
    expect(caretNextToImage(c), isTrue); // a la izquierda
    at(img + 1);
    expect(caretNextToImage(c), isTrue); // a la derecha
    at(1);
    expect(caretNextToImage(c), isFalse); // entre letras
    at(img + 3);
    expect(caretNextToImage(c), isFalse); // en "Tres"
    c.updateSelection(TextSelection(baseOffset: img, extentOffset: img + 1),
        ChangeSource.local);
    expect(caretNextToImage(c), isFalse); // imagen seleccionada: sin cursor
  });

  test('subir y bajar una imagen línea a línea', () {
    final c = _doc();
    expect(moveImageUp(c, _imageAt(c), _src), isTrue);
    expect(_text(c), 'Uno\n[IMG]\nDos\nTres\n');
    expect(moveImageUp(c, _imageAt(c), _src), isTrue);
    expect(_text(c), '[IMG]\nUno\nDos\nTres\n');
    expect(moveImageUp(c, _imageAt(c), _src), isFalse); // ya arriba del todo

    expect(moveImageDown(c, _imageAt(c), _src), isTrue);
    expect(_text(c), 'Uno\n[IMG]\nDos\nTres\n');
    expect(moveImageDown(c, _imageAt(c), _src), isTrue);
    expect(moveImageDown(c, _imageAt(c), _src), isTrue);
    expect(_text(c).replaceAll('\n\n', '\n'), 'Uno\nDos\nTres\n[IMG]\n');
  });

  test('mover a una línea concreta (soltar al arrastrar)', () {
    final c = _doc();
    // Antes de "Uno" (inicio del documento).
    expect(moveImageTo(c, _imageAt(c), _src, 0), isTrue);
    expect(_text(c), '[IMG]\nUno\nDos\nTres\n');
    // Delante de "Tres": inicio de esa línea en el documento actual.
    final tres = c.document.toPlainText().indexOf('Tres');
    expect(moveImageTo(c, _imageAt(c), _src, tres), isTrue);
    expect(_text(c), 'Uno\nDos\n[IMG]\nTres\n');
    // Soltarla donde ya está no hace nada.
    expect(moveImageTo(c, _imageAt(c), _src, _imageAt(c)), isFalse);
  });

  testWidgets('el editor de recorte se abre y se cancela con Esc',
      (tester) async {
    appLanguage.code = 'es';
    tester.view.physicalSize = const Size(1000, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final png = img.encodePng(img.Image(width: 200, height: 120));
    Uint8List? result = Uint8List(1);
    await tester.pumpWidget(MaterialApp(
      theme: buildTheme(themeById(''), Brightness.dark),
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () async =>
                result = await openImageCropper(context, png),
            child: const Text('abrir'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('abrir'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('Recortar'), findsOneWidget);
    for (final r in ['Libre', '1:1', '4:3', '16:9', '3:4']) {
      expect(find.text(r), findsOneWidget);
    }
    await tester.tap(find.text('1:1'));
    await tester.pump(const Duration(milliseconds: 400));

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('Recortar'), findsNothing);
    expect(result, isNull);
  });
}
