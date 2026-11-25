// Graba la portada, las capturas y los GIF animados del README (docs/) con la
// app de verdad, en un test de Flutter: los toques son simulados dentro del
// test, sin tocar el ratón ni el teclado del ordenador.
//
//   flutter test tool/record_gifs_test.dart
//
// Usa las fuentes Roboto y Material Icons de la caché de Flutter para que el
// texto y los iconos salgan como en la app (no los cuadros de los tests).
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:notas/data/ai_assistant.dart';
import 'package:notas/data/note_images.dart';
import 'package:notas/data/notes_repository.dart';
import 'package:notas/ui/assistant_panel.dart';
import 'package:notas/ui/logo.dart';
import 'package:notas/ui/new_note_icon.dart';
import 'package:notas/ui/note_image.dart';
import 'package:notas/ui/notes_home.dart';
import 'package:notas/ui/reminder_settings.dart';
import 'package:notas/ui/shortcuts_sheet.dart';
import 'package:notas/ui/theme.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final _root = GlobalKey();

Future<void> _loadFonts() async {
  // Sube desde el ejecutable del test hasta la carpeta de Flutter.
  var d = File(Platform.resolvedExecutable).parent;
  while (
      !Directory('${d.path}/bin/cache/artifacts/material_fonts').existsSync()) {
    if (d.parent.path == d.path) throw StateError('Flutter no encontrado');
    d = d.parent;
  }
  final dir = Directory('${d.path}/bin/cache/artifacts/material_fonts');
  Future<void> load(String family, Iterable<File> files) async {
    final loader = FontLoader(family);
    for (final f in files) {
      final bytes = f.readAsBytesSync();
      loader.addFont(Future.value(ByteData.sublistView(bytes)));
    }
    await loader.load();
  }

  final all = dir.listSync().whereType<File>().toList();
  final roboto = all.where((f) => f.path.contains('roboto-')).toList();
  await load('Roboto', roboto);
  await load('MaterialIcons',
      all.where((f) => f.path.toLowerCase().contains('materialicons')));
  await load('Shrikhand', [File('assets/fonts/Shrikhand-Regular.ttf')]);
}

/// Graba [steps] fotogramas cada [stepMs] ms mientras corre [script]
/// (que avanza el tiempo con `frame()`), y guarda el GIF en [path].
class _Recorder {
  _Recorder(this.tester, {required this.pixelRatio, this.stepMs = 50});
  final WidgetTester tester;
  final double pixelRatio;
  final int stepMs;
  final frames = <img.Image>[];

  Future<void> frame([int count = 1]) async {
    for (var i = 0; i < count; i++) {
      await tester.pump(Duration(milliseconds: stepMs));
      await tester.runAsync(() async {
        final b =
            _root.currentContext!.findRenderObject() as RenderRepaintBoundary;
        final image = await b.toImage(pixelRatio: pixelRatio);
        final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
        frames.add(img.Image.fromBytes(
          width: image.width,
          height: image.height,
          bytes: data!.buffer,
          numChannels: 4,
          order: img.ChannelOrder.rgba,
        ));
        image.dispose();
      });
    }
  }

  /// Guarda lo que hay ahora en pantalla como PNG (tamaño real).
  static Future<void> png(String path, {double pixelRatio = 1}) async {
    final b = _root.currentContext!.findRenderObject() as RenderRepaintBoundary;
    final image = await b.toImage(pixelRatio: pixelRatio);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    File(path).writeAsBytesSync(data!.buffer.asUint8List());
  }

  /// Espera [ms] grabando.
  Future<void> hold(int ms) => frame((ms / stepMs).round());

  void save(String path) {
    final enc = img.GifEncoder(repeat: 0, samplingFactor: 4);
    for (final f in frames) {
      enc.addFrame(f, duration: (stepMs / 10).round());
    }
    File(path).writeAsBytesSync(enc.finish()!);
    // GIF_PREVIEW=<carpeta>: guarda también algunos fotogramas en PNG.
    final preview = Platform.environment['GIF_PREVIEW'];
    if (preview != null) {
      final name = path.split('/').last.replaceAll('.gif', '');
      for (var i = 0; i < frames.length; i += (frames.length / 6).ceil()) {
        File('$preview/${name}_$i.png')
            .writeAsBytesSync(img.encodePng(frames[i]));
      }
    }
    // ignore: avoid_print
    print('$path: ${frames.length} fotogramas, '
        '${(File(path).lengthSync() / 1024).round()} KB');
  }
}

NotesRepository _demoRepo() {
  final client = SupabaseClient('http://127.0.0.1:9', 'clave-de-prueba',
      authOptions: const AuthClientOptions(autoRefreshToken: false));
  return NotesRepository(client, 'demo')
    ..loaded = true
    ..seedDemo();
}

Future<void> _cleanUp(WidgetTester tester, NotesRepository repo) async {
  await tester.pumpWidget(const SizedBox());
  repo.dispose();
  await tester.pump(const Duration(minutes: 5));
}

void _setSize(WidgetTester tester, Size logical) {
  tester.view.physicalSize = logical * 2;
  tester.view.devicePixelRatio = 2;
}

/// App de demostración con el límite de captura por encima del Navigator
/// (así también salen los diálogos, el visor de imágenes y los avisos).
Widget _app(ThemeData theme, Widget home, {GlobalKey? boundary}) => MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: theme,
      builder: (context, child) => boundary == null
          ? child!
          : RepaintBoundary(key: boundary, child: child),
      home: home,
    );

// ------------------------------------------------- foto de ejemplo

/// Paisaje de atardecer dibujado píxel a píxel (sin archivos externos).
Uint8List _photo() {
  const w = 1200, h = 760;
  final im = img.Image(width: w, height: h);
  int lerp(int a, int b, double t) => (a + (b - a) * t).round();
  const horizon = 0.6;
  for (var y = 0; y < h; y++) {
    final t = y / h;
    late int r, g, b;
    if (t < horizon) {
      final k = t / horizon;
      // Azul noche → violeta → naranja en el horizonte.
      if (k < 0.55) {
        final q = k / 0.55;
        r = lerp(28, 120, q);
        g = lerp(36, 70, q);
        b = lerp(92, 130, q);
      } else {
        final q = (k - 0.55) / 0.45;
        r = lerp(120, 252, q);
        g = lerp(70, 168, q);
        b = lerp(130, 96, q);
      }
    } else {
      // Lago: reflejo más oscuro.
      final q = (t - horizon) / (1 - horizon);
      r = lerp(150, 24, q);
      g = lerp(96, 30, q);
      b = lerp(96, 70, q);
    }
    for (var x = 0; x < w; x++) {
      im.setPixelRgb(x, y, r, g, b);
    }
  }
  // Sol con halo.
  const sx = 760, sy = 420;
  for (var rad = 150; rad > 60; rad -= 6) {
    final a = (1 - (rad - 60) / 90) * 40;
    img.fillCircle(im,
        x: sx,
        y: sy,
        radius: rad,
        color: img.ColorRgba8(255, 214, 150, a.round()),
        antialias: true);
  }
  img.fillCircle(im,
      x: sx,
      y: sy,
      radius: 58,
      color: img.ColorRgb8(255, 232, 178),
      antialias: true);
  // Montañas (dos capas).
  img.Point p(num x, num y) => img.Point(x, y);
  img.fillPolygon(im,
      vertices: [
        p(0, 470),
        p(160, 330),
        p(300, 420),
        p(470, 280),
        p(640, 430),
        p(820, 340),
        p(1000, 440),
        p(1200, 360),
        p(1200, 456),
        p(0, 456),
      ],
      color: img.ColorRgb8(70, 48, 90));
  img.fillPolygon(im,
      vertices: [
        p(0, 456),
        p(120, 400),
        p(260, 456),
        p(420, 380),
        p(600, 456),
        p(760, 410),
        p(940, 456),
        p(1080, 396),
        p(1200, 456),
      ],
      color: img.ColorRgb8(40, 30, 62));
  // Brillo del sol en el agua.
  for (var i = 0; i < 9; i++) {
    final y = 470 + i * 22;
    final half = 90 - i * 8;
    img.fillRect(im,
        x1: sx - half,
        y1: y,
        x2: sx + half,
        y2: y + 4,
        color: img.ColorRgba8(255, 214, 150, 110 - i * 10));
  }
  return img.encodeJpg(im, quality: 92);
}

/// Añade a la demo una nota con una foto (para enseñar las imágenes).
Future<String> _addPhotoNote(WidgetTester tester, NotesRepository repo) async {
  await NoteImages.instance.attach(null, 'demo');
  final src = (await tester.runAsync(() async {
    final s = await NoteImages.instance.add(_photo());
    // Deja terminar la compresión en segundo plano.
    await Future<void>.delayed(const Duration(seconds: 2));
    return s;
  }))!;
  final n = repo.createNote();
  repo.updateContent(
    n.id,
    'Escapada a la montaña\n￼\nSalir el viernes a las 8. '
    'Llevar botas, frontal y la cámara.',
    rich: jsonEncode([
      {'insert': 'Escapada a la montaña'},
      {
        'insert': '\n',
        'attributes': {'header': 1}
      },
      {
        'insert': {'image': src}
      },
      {'insert': '\n'},
      {
        'insert': 'Salir el viernes a las 8. Llevar botas, frontal y la '
            'cámara.\n'
      },
    ]),
  );
  repo.togglePin(n.id);
  return n.id;
}

/// Decodifica de verdad las imágenes que hay en pantalla (en los tests la
/// decodificación necesita tiempo real).
Future<void> _decodeImages(WidgetTester tester) async {
  await tester.runAsync(() async {
    for (final e in find.byType(Image).evaluate()) {
      final w = e.widget as Image;
      await precacheImage(w.image, e);
    }
    await Future<void>.delayed(const Duration(milliseconds: 300));
  });
  await tester.pump();
}

// ---------------------------------------------------------- portada

/// La app real, encogida dentro de un marco (ventana de PC o móvil).
Widget _device({
  required Widget app,
  required Size logical,
  required double width,
  required double radius,
  double bezel = 0,
}) {
  final h = width * logical.height / logical.width;
  return Container(
    width: width + bezel * 2,
    height: h + bezel * 2,
    padding: EdgeInsets.all(bezel),
    decoration: BoxDecoration(
      color: const Color(0xFF05070C),
      borderRadius: BorderRadius.circular(radius + bezel),
      border: Border.all(color: const Color(0x33FFE2A0), width: 1.2),
      boxShadow: const [
        BoxShadow(
            color: Color(0x99000000), blurRadius: 50, offset: Offset(0, 24)),
        BoxShadow(color: Color(0x22E2B866), blurRadius: 80, spreadRadius: 4),
      ],
    ),
    child: ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: FittedBox(
        child: SizedBox.fromSize(
          size: logical,
          child: MediaQuery(
            data: MediaQueryData(size: logical, devicePixelRatio: 2),
            child: app,
          ),
        ),
      ),
    ),
  );
}

class _Pill extends StatelessWidget {
  const _Pill(this.icon, this.label);
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: const Color(0x1AE2B866),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0x40E2B866)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 16, color: const Color(0xFFE2B866)),
          const SizedBox(width: 7),
          Text(label,
              style: const TextStyle(
                  fontFamily: 'Roboto',
                  fontSize: 14.5,
                  fontWeight: FontWeight.w500,
                  color: Color(0xFFF3E3BC))),
        ]),
      );
}

/// Fondo de puntos suaves.
class _Dots extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()..color = const Color(0x14FFFFFF);
    for (var y = 12.0; y < size.height; y += 24) {
      for (var x = 12.0; x < size.width; x += 24) {
        canvas.drawCircle(Offset(x, y), 1.1, p);
      }
    }
  }

  @override
  bool shouldRepaint(_Dots old) => false;
}

void main() {
  setUpAll(() async {
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({});
    await _loadFonts();
  });

  testWidgets('Portada (README y vista previa de GitHub)', (tester) async {
    tester.view.physicalSize = const Size(1280, 640) * 2;
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    final desk = _demoRepo();
    final phone = _demoRepo();
    final noteId = await _addPhotoNote(tester, desk);
    await _addPhotoNote(tester, phone);
    final deskKey = GlobalKey();

    await tester.pumpWidget(MaterialApp(
      debugShowCheckedModeBanner: false,
      home: RepaintBoundary(
        key: _root,
        child: Material(
          type: MaterialType.transparency,
          child: Stack(
            children: [
              // Fondo: azul noche con dos halos dorados y puntos.
              const Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [Color(0xFF1C2742), logoNavyBottom],
                    ),
                  ),
                ),
              ),
              const Positioned(
                right: 120,
                top: -40,
                child: SizedBox(
                  width: 620,
                  height: 620,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(colors: [
                        Color(0x40E2B866),
                        Color(0x00E2B866),
                      ]),
                    ),
                  ),
                ),
              ),
              const Positioned(
                left: -160,
                bottom: -220,
                child: SizedBox(
                  width: 560,
                  height: 560,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(colors: [
                        Color(0x285C8DF6),
                        Color(0x005C8DF6),
                      ]),
                    ),
                  ),
                ),
              ),
              Positioned.fill(child: CustomPaint(painter: _Dots())),
              // Texto a la izquierda.
              const Positioned(
                left: 64,
                top: 96,
                width: 520,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      SizedBox.square(
                        dimension: 84,
                        child: CustomPaint(
                          painter: LogoStrokePainter(progress: 1, glow: 0.8),
                        ),
                      ),
                      SizedBox(width: 14),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('oganesson',
                              style: TextStyle(
                                  fontFamily: 'Shrikhand',
                                  fontSize: 64,
                                  height: 1.1,
                                  color: Color(0xFFE2B866))),
                          Text('TakeNotes',
                              style: TextStyle(
                                  fontFamily: 'Roboto',
                                  fontWeight: FontWeight.w300,
                                  fontSize: 28,
                                  letterSpacing: 6,
                                  color: Color(0xFFFBE6A8))),
                        ],
                      ),
                    ]),
                    SizedBox(height: 30),
                    Text(
                        'Notes, tasks and photos on your phone\n'
                        'and your PC — synced in real time.',
                        style: TextStyle(
                            fontFamily: 'Roboto',
                            fontSize: 25,
                            height: 1.35,
                            color: Color(0xFFD3DAEA))),
                    SizedBox(height: 26),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _Pill(Icons.image_outlined, 'Images & screenshots'),
                        _Pill(Icons.alarm_on, 'Deadlines'),
                        _Pill(Icons.calendar_month_outlined, 'Calendar'),
                        _Pill(Icons.hub_outlined, 'Note network'),
                        _Pill(Icons.lock_outline, 'Vault'),
                        _Pill(Icons.widgets_outlined, 'Widgets'),
                      ],
                    ),
                    SizedBox(height: 30),
                    Text('WINDOWS  ·  ANDROID  ·  FREE & OPEN SOURCE',
                        style: TextStyle(
                            fontFamily: 'Roboto',
                            fontWeight: FontWeight.w700,
                            fontSize: 13.5,
                            letterSpacing: 2.4,
                            color: Color(0xFFB98A3E))),
                  ],
                ),
              ),
              // La app de verdad: PC y móvil.
              Positioned(
                left: 610,
                top: 70,
                child: Transform.rotate(
                  angle: -0.012,
                  child: _device(
                    app: KeyedSubtree(
                      key: deskKey,
                      child: _app(
                          buildTheme(themeById('clasico'), Brightness.dark),
                          NotesHome(repo: desk)),
                    ),
                    logical: const Size(1180, 720),
                    width: 600,
                    radius: 12,
                  ),
                ),
              ),
              Positioned(
                left: 1040,
                top: 238,
                child: Transform.rotate(
                  angle: 0.03,
                  child: _device(
                    app: _app(buildTheme(themeById('galaxia'), Brightness.dark),
                        NotesHome(repo: phone)),
                    logical: const Size(390, 800),
                    width: 172,
                    radius: 22,
                    bezel: 6,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ));
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    // En el PC, la nota con la foto abierta.
    await tester.tap(find
        .descendant(
            of: find.byKey(deskKey),
            matching: find.text('Escapada a la montaña'))
        .first);
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await _decodeImages(tester);
    await tester.pump(const Duration(seconds: 1));
    expect(desk.byId(noteId), isNotNull);
    await tester.runAsync(() => _Recorder.png('docs/banner.png'));
    await tester.pumpWidget(const SizedBox());
    desk.dispose();
    phone.dispose();
    await tester.pump(const Duration(minutes: 5));
  });

  Future<void> shot(String path) => _Recorder.png(path);

  testWidgets('Capturas de escritorio', (tester) async {
    _setSize(tester, const Size(1100, 680));
    addTearDown(tester.view.reset);
    final repo = _demoRepo();
    await _addPhotoNote(tester, repo);
    final theme =
        ValueNotifier(buildTheme(themeById('clasico'), Brightness.dark));
    await tester.pumpWidget(ValueListenableBuilder<ThemeData>(
      valueListenable: theme,
      builder: (_, t, __) => _app(t, NotesHome(repo: repo), boundary: _root),
    ));
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await _decodeImages(tester);
    await tester.runAsync(() => shot('docs/screenshot-windows.png'));

    // Claro (Sepia) con una nota abierta en el editor.
    theme.value = buildTheme(themeById('sepia'), Brightness.light);
    await tester.pump(const Duration(seconds: 1));
    await tester.tap(find.text('Examen de historia').first);
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.runAsync(() => shot('docs/screenshot-calendar.png'));
    await _cleanUp(tester, repo);
  });

  testWidgets('GIF: animación de inicio', (tester) async {
    _setSize(tester, const Size(560, 340));
    addTearDown(tester.view.reset);
    final rec = _Recorder(tester, pixelRatio: 1, stepMs: 40);
    await tester.pumpWidget(MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: buildTheme(themeById('clasico'), Brightness.dark),
      home: RepaintBoundary(
        key: _root,
        child: const StartupSplash(child: ColoredBox(color: logoNavyBottom)),
      ),
    ));
    await rec.hold(2300);
    rec.save('docs/startup.gif');
  });

  testWidgets('GIF: móvil (lista, calendario, red)', (tester) async {
    _setSize(tester, const Size(390, 780));
    addTearDown(tester.view.reset);
    final repo = _demoRepo();
    final rec = _Recorder(tester, pixelRatio: 0.85, stepMs: 60);
    await tester.pumpWidget(_app(
        buildTheme(themeById('galaxia'), Brightness.dark),
        NotesHome(repo: repo),
        boundary: _root));
    await tester.pump(const Duration(seconds: 2));
    await rec.hold(1400);
    Future<void> tapTip(Pattern tip) async {
      await tester.tap(find.byTooltip(tip));
    }

    await tapTip(RegExp(r'^Calendar'));
    await rec.hold(1800);
    await tapTip(RegExp(r'^Note network'));
    await rec.hold(2600);
    await tapTip('Notes');
    await rec.hold(1000);
    rec.save('docs/mobile.gif');
    await _cleanUp(tester, repo);
  });

  testWidgets('GIF: notas (crear, borrar y archivar)', (tester) async {
    _setSize(tester, const Size(390, 780));
    addTearDown(tester.view.reset);
    final repo = _demoRepo();
    final rec = _Recorder(tester, pixelRatio: 0.7, stepMs: 70);
    await tester.pumpWidget(_app(
        buildTheme(themeById('oceano'), Brightness.dark), NotesHome(repo: repo),
        boundary: _root));
    await tester.pump(const Duration(seconds: 2));
    await rec.hold(900);

    // Nota nueva: el editor entra por encima de la lista…
    await tester.tap(find.byType(NewNoteIcon).first);
    await rec.hold(700);
    final id = repo.notes.firstWhere((n) => n.isEmpty).id;
    const title = 'Llamar al dentista';
    for (var i = 1; i <= title.length; i++) {
      repo.updateContent(id, title.substring(0, i));
      await rec.frame();
    }
    repo.updateContent(id, '$title\nMartes por la tarde');
    await rec.hold(700);
    // …y al volver, solo entra su fila: la lista no se mueve.
    await tester.tap(find.byTooltip('Back'));
    await rec.hold(1500);

    // Deslizar a la derecha: eliminar (con confirmación).
    Future<void> swipe(String text, double dx) async {
      final g =
          await tester.startGesture(tester.getCenter(find.text(text).first));
      for (var i = 0; i < 12; i++) {
        await g.moveBy(Offset(dx, 0));
        await rec.frame();
      }
      await g.up();
      await rec.hold(700);
      await tester.tap(find.byType(FilledButton).last);
      await rec.hold(1500);
    }

    await swipe('Pelis pendientes', 24);
    await swipe('Lista de la compra', -24);
    await rec.hold(600);
    rec.save('docs/notes.gif');
    await _cleanUp(tester, repo);
  });

  testWidgets('GIF: imágenes (ver, ampliar y mover)', (tester) async {
    _setSize(tester, const Size(1000, 620));
    addTearDown(tester.view.reset);
    final repo = _demoRepo();
    await _addPhotoNote(tester, repo);
    final rec = _Recorder(tester, pixelRatio: 0.55, stepMs: 70);
    await tester.pumpWidget(_app(
        buildTheme(themeById('clasico'), Brightness.dark),
        NotesHome(repo: repo),
        boundary: _root));
    await tester.pump(const Duration(seconds: 2));
    await _decodeImages(tester);
    await rec.hold(500);
    await tester.tap(find.text('Escapada a la montaña').first);
    await rec.hold(500);
    await _decodeImages(tester);
    await rec.hold(500);

    // Pasar el ratón: aparecen las acciones de la imagen.
    final image = find.byType(NoteImageView).first;
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: const Offset(5, 300));
    await mouse.moveTo(tester.getCenter(image));
    await rec.hold(1000);

    // Tocar: el visor la abre en grande; doble toque amplía.
    await tester.tap(image);
    await rec.hold(1000);
    final center = tester.getCenter(find.byType(InteractiveViewer));
    await tester.tapAt(center + const Offset(60, -20));
    await tester.pump(const Duration(milliseconds: 60));
    await tester.tapAt(center + const Offset(60, -20));
    await rec.hold(1200);
    await tester.tapAt(center);
    await tester.pump(const Duration(milliseconds: 60));
    await tester.tapAt(center);
    await rec.hold(700);
    await tester.tap(find.byTooltip('Close'));
    await rec.hold(900);

    // Clic derecho → Bajar: la imagen se mueve debajo del texto.
    await tester.tap(find.byType(NoteImageView).first,
        buttons: kSecondaryButton);
    await rec.hold(1100);
    await tester.tap(find.text('Move down').last);
    await rec.hold(1400);
    await mouse.removePointer();
    rec.save('docs/images.gif');
    await _cleanUp(tester, repo);
  });

  testWidgets('Captura: asistente de IA', (tester) async {
    _setSize(tester, const Size(430, 760));
    addTearDown(tester.view.reset);
    // ignore: invalid_use_of_visible_for_testing_member
    FlutterSecureStorage.setMockInitialValues({});
    await AiSettings.instance
        .save(apiKey: 'demo', model: 'gemini-3.5-flash-lite');
    final repo = _demoRepo();
    final session = AiSession(repo);
    final note = repo.notes.firstWhere((n) => n.title == 'Examen de historia');
    session.messages
      ..add(AiMessage(AiRole.user, 'What do I have pending this week?'))
      ..add(AiMessage(
          AiRole.assistant,
          'This week you have **2 tasks**:\n'
          '- **Examen de historia**: Thursday at 9:00\n'
          '- **Entregar trabajo de física**: Friday at 20:00'))
      ..add(AiMessage(AiRole.user,
          'Move the exam to Friday at 10 and create a note to revise'))
      ..add(AiMessage(
          AiRole.assistant,
          'Done: the exam is now on Friday at 10:00 and I created the note '
          '**Revise history** in Clase.',
          actions: [
            AiAction(
                icon: 'alarm',
                label: 'Deadline of “Examen de historia”: 2026-11-27 10:00',
                noteId: note.id,
                undo: () {}),
            AiAction(
                icon: 'note_add',
                label: 'Note created: Revise history',
                noteId: note.id,
                undo: () {}),
          ]));
    await tester.pumpWidget(_app(
      buildTheme(themeById('galaxia'), Brightness.dark),
      Scaffold(
        body: SafeArea(
          child: AssistantPanel(
              session: session, onOpenNote: (_) {}, onClose: () {}),
        ),
      ),
      boundary: _root,
    ));
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.runAsync(
        () => _Recorder.png('docs/screenshot-assistant.png', pixelRatio: 2));
    await _cleanUp(tester, repo);
  });

  testWidgets('GIF: temas', (tester) async {
    _setSize(tester, const Size(1000, 620));
    addTearDown(tester.view.reset);
    final repo = _demoRepo();
    final rec = _Recorder(tester, pixelRatio: 0.62, stepMs: 100);
    final theme =
        ValueNotifier(buildTheme(themeById('clasico'), Brightness.dark));
    await tester.pumpWidget(ValueListenableBuilder<ThemeData>(
      valueListenable: theme,
      builder: (_, t, __) => _app(t, NotesHome(repo: repo), boundary: _root),
    ));
    await tester.pump(const Duration(seconds: 2));
    for (final (id, b) in [
      ('clasico', Brightness.dark),
      ('oceano', Brightness.dark),
      ('sepia', Brightness.light),
      ('neon', Brightness.dark),
      ('matcha', Brightness.light),
      ('atardecer', Brightness.dark),
    ]) {
      theme.value = buildTheme(themeById(id), b);
      await rec.hold(1300);
    }
    rec.save('docs/themes.gif');
    await _cleanUp(tester, repo);
  });

  testWidgets('GIF: IA, aprobar varios cambios a la vez', (tester) async {
    _setSize(tester, const Size(430, 760));
    addTearDown(tester.view.reset);
    // ignore: invalid_use_of_visible_for_testing_member
    FlutterSecureStorage.setMockInitialValues({});
    await AiSettings.instance
        .save(apiKey: 'demo', model: 'gemini-3.5-flash-lite');
    final repo = _demoRepo();
    final session = AiSession(repo);
    session.messages.add(AiMessage(AiRole.user,
        'Plan my week: move the exam, add revision notes and a reminder'));
    final rec = _Recorder(tester, pixelRatio: 0.8, stepMs: 60);
    await tester.pumpWidget(_app(
      buildTheme(themeById('galaxia'), Brightness.dark),
      Scaffold(
        body: SafeArea(
          child: AssistantPanel(
              session: session, onOpenNote: (_) {}, onClose: () {}),
        ),
      ),
      boundary: _root,
    ));
    await tester.pump(const Duration(seconds: 1));
    await rec.hold(700);
    // El panel registra confirmMany: lo llamamos como lo haría la IA.
    final chosen = session.confirmMany!([
      'Deadline of “Examen de historia”: Friday 10:00',
      'Create note “Revise history” in Clase',
      'Create note “Physics formulas” in Clase',
      'Reminder for “Entregar trabajo de física” 1 h before',
    ]);
    await rec.hold(1600);
    for (final i in [1, 3]) {
      await tester.tap(find.byType(CheckboxListTile).at(i));
      await rec.hold(700);
    }
    await tester.tap(find.byType(CheckboxListTile).at(3));
    await rec.hold(900);
    await tester.tap(find.byType(FilledButton).last);
    await rec.hold(800);
    expect(await chosen, {0, 2, 3});
    rec.save('docs/ai-batch.gif');
    await _cleanUp(tester, repo);
  });

  testWidgets('GIF: atajos de teclado y avisos', (tester) async {
    _setSize(tester, const Size(1000, 620));
    addTearDown(tester.view.reset);
    final repo = _demoRepo();
    final rec = _Recorder(tester, pixelRatio: 0.62, stepMs: 70);
    await tester.pumpWidget(_app(
        buildTheme(themeById('clasico'), Brightness.dark),
        NotesHome(repo: repo),
        boundary: _root));
    await tester.pump(const Duration(seconds: 2));
    await rec.hold(800);
    final ctx = tester.element(find.byType(NotesHome));
    showShortcuts(ctx);
    await rec.hold(2600);
    Navigator.of(ctx).pop();
    await rec.hold(700);
    showReminderSettings(ctx);
    await rec.hold(2600);
    Navigator.of(ctx).pop();
    await rec.hold(700);
    rec.save('docs/shortcuts.gif');
    await _cleanUp(tester, repo);
  });

  // Silencia el aviso de import sin usar si se quitan pruebas.
  test('utilidades', () => expect(max(1, 2), 2));
}
