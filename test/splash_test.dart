import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notas/ui/logo.dart';

void main() {
  testWidgets('animación de inicio: se dibuja y deja ver la app',
      (tester) async {
    final key = GlobalKey();
    await tester.pumpWidget(MaterialApp(
      home: RepaintBoundary(
        key: key,
        child: const StartupSplash(
          child: Scaffold(body: Center(child: Text('APP'))),
        ),
      ),
    ));
    // A mitad: el logo se está dibujando por encima.
    await tester.pump(const Duration(milliseconds: 700));
    expect(tester.takeException(), isNull);
    expect(
        find.byWidgetPredicate(
            (w) => w is CustomPaint && w.painter is LogoStrokePainter),
        findsOneWidget);

    final out = Platform.environment['SPLASH_PREVIEW'];
    if (out != null) {
      for (final ms in [0, 500, 400]) {
        await tester.pump(Duration(milliseconds: ms));
        await tester.runAsync(() async {
          final b =
              key.currentContext!.findRenderObject() as RenderRepaintBoundary;
          final img = await b.toImage(pixelRatio: 1);
          final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
          File('$out/splash_${DateTime.now().microsecondsSinceEpoch}.png')
              .writeAsBytesSync(bytes!.buffer.asUint8List());
        });
      }
    }

    // Al terminar desaparece y solo queda la app. (Se avanza el reloj a
    // mano: la espera a que la ventana sea visible usa temporizadores.)
    for (var i = 0; i < 70; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.text('APP'), findsOneWidget);
    expect(
        find.byWidgetPredicate(
            (w) => w is CustomPaint && w.painter is LogoStrokePainter),
        findsNothing);
  });
}
