import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:notas/data/note_images.dart';
import 'package:notas/models/note.dart';
import 'package:notas/ui/i18n.dart';

Uint8List _png(int w, int h) {
  final i = img.Image(width: w, height: h);
  for (final p in i) {
    p
      ..r = (p.x * 255 ~/ w)
      ..g = (p.y * 255 ~/ h)
      ..b = 120;
  }
  return img.encodePng(i);
}

void main() {
  setUp(() => appLanguage.code = 'es');

  test('fuentes sb://: ruta, tamaño y rutas dentro de una nota', () {
    const src = 'sb://u1/abc-123?w=1600&h=900';
    expect(NoteImages.isOurs(src), isTrue);
    expect(NoteImages.isOurs('https://x.com/a.png'), isFalse);
    expect(NoteImages.pathOf(src), 'u1/abc-123');
    final size = NoteImages.sizeOf(src)!;
    expect(size.width, 1600);
    expect(size.height, 900);
    expect(NoteImages.sizeOf('sb://u1/x'), isNull);

    const rich =
        '[{"insert":"Hola\\n"},{"insert":{"image":"sb://u1/a?w=1&h=1"}},'
        '{"insert":{"image":"sb://u1/b?w=2&h=2"}},{"insert":"\\n"}]';
    expect(NoteImages.pathsIn(rich), {'u1/a', 'u1/b'});
    expect(NoteImages.pathsIn(null), isEmpty);
    expect(NoteImages.firstPathIn(rich), 'u1/a');
    expect(NoteImages.firstPathIn('[]'), isNull);
    expect(NoteImages.pathsIn('[{"insert":"texto\\n"}]'), isEmpty);
  });

  test('extensión por los primeros bytes', () {
    expect(NoteImages.extensionOf(_png(4, 4)), 'png');
    expect(
        NoteImages.extensionOf(img.encodeJpg(img.Image(width: 4, height: 4))),
        'jpg');
    expect(
        NoteImages.extensionOf(img.encodeGif(img.Image(width: 4, height: 4))),
        'gif');
  });

  test('compresión: capturas pequeñas intactas, fotos grandes reducidas', () {
    final small = _png(300, 200);
    expect(identical(compressImage(small), small), isTrue);

    final big = img.encodeJpg(img.Image(width: 3000, height: 1500)
      ..clear(img.ColorRgb8(200, 60, 40)));
    final out = compressImage(big);
    final decoded = img.decodeImage(out)!;
    expect(decoded.width, NoteImages.maxSide);
    expect(decoded.height, NoteImages.maxSide ~/ 2);
    expect(NoteImages.extensionOf(out), 'jpg');

    // Vertical: se limita el alto.
    final tall = img.encodeJpg(img.Image(width: 1000, height: 4000));
    final t = img.decodeImage(compressImage(tall))!;
    expect(t.height, NoteImages.maxSide);
    expect(t.width, 512);
  });

  test('las imágenes no cuentan para el título ni la vista previa', () {
    final t = DateTime(2026);
    Note n(String c) => Note(id: 'x', content: c, createdAt: t, updatedAt: t);
    expect(n('\uFFFC\nCompra\npan').title, 'Compra');
    expect(n('\uFFFC\nCompra\npan').preview, 'pan');
    expect(n('\uFFFC').title, 'Imagen');
    expect(n('\uFFFC').hasImages, isTrue);
    expect(n('\uFFFC').isEmpty, isFalse);
    expect(n('Hola\n\uFFFC').preview, 'Sin texto adicional');
  });
}
