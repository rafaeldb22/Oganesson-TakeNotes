// Graba los GIF animados del README (docs/*.gif) con la app de verdad, en un
// test de Flutter: los toques son simulados dentro del test, sin tocar el
// ratón ni el teclado del ordenador.
//
//   flutter test tool/record_gifs_test.dart
//
// Usa las fuentes Roboto y Material Icons de la caché de Flutter para que el
// texto y los iconos salgan como en la app (no los cuadros de los tests).
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:notas/data/notes_repository.dart';
import 'package:notas/ui/logo.dart';
import 'package:notas/ui/notes_home.dart';
import 'package:notas/ui/theme.dart';
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
  static Future<void> png(String path) async {
    final b = _root.currentContext!.findRenderObject() as RenderRepaintBoundary;
    final image = await b.toImage(pixelRatio: 1);
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

void main() {
  setUpAll(() async {
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({});
    await _loadFonts();
  });

  testWidgets('Portada (README y vista previa de GitHub)', (tester) async {
    tester.view.physicalSize = const Size(1280, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
        debugShowCheckedModeBanner: false,
        home: RepaintBoundary(
          key: _root,
          child: const Material(
            type: MaterialType.transparency,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [logoNavyTop, logoNavyBottom],
                ),
              ),
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 90),
                child: Row(
                  children: [
                    SizedBox.square(
                      dimension: 360,
                      child: CustomPaint(
                        painter: LogoStrokePainter(progress: 1, glow: 0.7),
                      ),
                    ),
                    SizedBox(width: 40),
                    Expanded(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('oganesson',
                              style: TextStyle(
                                  fontFamily: 'Shrikhand',
                                  fontSize: 96,
                                  color: Color(0xFFE2B866))),
                          Text('TakeNotes',
                              style: TextStyle(
                                  fontFamily: 'Roboto',
                                  fontWeight: FontWeight.w300,
                                  fontSize: 44,
                                  letterSpacing: 6,
                                  color: Color(0xFFFBE6A8))),
                          SizedBox(height: 28),
                          Text(
                              'Notes on your phone and your PC,\n'
                              'synced in real time.',
                              style: TextStyle(
                                  fontFamily: 'Roboto',
                                  fontSize: 30,
                                  height: 1.35,
                                  color: Color(0xFFB9C2D6))),
                          SizedBox(height: 22),
                          Text('Windows  ·  Android',
                              style: TextStyle(
                                  fontFamily: 'Roboto',
                                  fontWeight: FontWeight.w500,
                                  fontSize: 22,
                                  letterSpacing: 2,
                                  color: Color(0xFFB07C2E))),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        )));
    await tester.runAsync(() async {
      final b =
          _root.currentContext!.findRenderObject() as RenderRepaintBoundary;
      final image = await b.toImage(pixelRatio: 1);
      final png = await image.toByteData(format: ui.ImageByteFormat.png);
      File('docs/banner.png').writeAsBytesSync(png!.buffer.asUint8List());
    });
  });

  Future<void> shot(String path) => _Recorder.png(path);

  testWidgets('Capturas de escritorio', (tester) async {
    _setSize(tester, const Size(1100, 680));
    addTearDown(tester.view.reset);
    final repo = _demoRepo();
    final theme =
        ValueNotifier(buildTheme(themeById('clasico'), Brightness.dark));
    await tester.pumpWidget(ValueListenableBuilder<ThemeData>(
      valueListenable: theme,
      builder: (_, t, __) => MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: t,
        home: RepaintBoundary(key: _root, child: NotesHome(repo: repo)),
      ),
    ));
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
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
    await tester.pumpWidget(MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: buildTheme(themeById('galaxia'), Brightness.dark),
      home: RepaintBoundary(key: _root, child: NotesHome(repo: repo)),
    ));
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
    await rec.hold(800);
    // Deslizar una nota a la izquierda (archivar) y soltarla antes de tiempo.
    final tile = find.text('Ideas para el proyecto').first;
    final g = await tester.startGesture(tester.getCenter(tile));
    for (var i = 0; i < 8; i++) {
      await g.moveBy(const Offset(-12, 0));
      await rec.frame();
    }
    await rec.hold(500);
    await g.up();
    await rec.hold(900);
    rec.save('docs/mobile.gif');
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
      builder: (_, t, __) => MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: t,
        home: RepaintBoundary(key: _root, child: NotesHome(repo: repo)),
      ),
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
}
