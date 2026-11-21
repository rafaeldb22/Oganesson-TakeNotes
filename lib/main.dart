import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_quill/flutter_quill.dart' show FlutterQuillLocalizations;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:window_manager/window_manager.dart';

import 'config.dart';
import 'data/reminders.dart';
import 'data/widget_bridge.dart';
import 'ui/auth_gate.dart';
import 'ui/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Ventana de Windows: tamaño inicial, centrada y con tamaño mínimo
  // para que el contenido nunca se desborde al hacerla pequeña.
  if (!kIsWeb && Platform.isWindows) {
    await windowManager.ensureInitialized();
    const options = WindowOptions(
      size: Size(1100, 720),
      minimumSize: Size(380, 560),
      center: true,
      title: 'Notas',
    );
    windowManager.waitUntilReadyToShow(options, () async {
      await windowManager.show();
      await windowManager.focus();
    });
    windowManager.addListener(_RepaintOnWindowChange());
  }

  await themeSettings.load();
  unawaited(Reminders.instance.init());
  themeSettings.onThemeChanged = WidgetBridge.refresh;

  if (AppConfig.isConfigured) {
    await Supabase.initialize(
      url: AppConfig.supabaseUrl,
      anonKey: AppConfig.supabaseAnonKey,
    );
  }
  runApp(const NotasApp());
}

/// Algunas gráficas en Windows dejan zonas negras o sin texto tras cambiar
/// el tamaño de la ventana. Al terminar cada cambio forzamos a repintar
/// toda la interfaz desde cero (sin perder nada de lo que haya abierto).
class _RepaintOnWindowChange with WindowListener {
  Timer? _debounce;

  void _schedule() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 120), forceFullRepaint);
  }

  @override
  void onWindowResized() => _schedule();
  @override
  void onWindowResize() => _schedule();
  @override
  void onWindowMaximize() => _schedule();
  @override
  void onWindowUnmaximize() => _schedule();
  @override
  void onWindowRestore() => _schedule();
}

void forceFullRepaint() {
  void visit(RenderObject o) {
    o.markNeedsPaint();
    o.visitChildren(visit);
  }

  for (final view in RendererBinding.instance.renderViews) {
    visit(view);
  }
  SchedulerBinding.instance.scheduleForcedFrame();
  // Un segundo pase un instante después, por si el primero llegó antes
  // de que la gráfica terminara de redimensionar su superficie.
  Timer(const Duration(milliseconds: 250), () {
    for (final view in RendererBinding.instance.renderViews) {
      visit(view);
    }
    SchedulerBinding.instance.scheduleForcedFrame();
  });
}

class NotasApp extends StatelessWidget {
  const NotasApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: themeSettings,
      builder: (context, _) => MaterialApp(
      title: 'Notas',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(themeSettings.theme, Brightness.light),
      darkTheme: buildTheme(themeSettings.theme, Brightness.dark),
      themeMode: themeSettings.mode,
      // Cambio de tema animado: los colores se funden en vez de saltar.
      themeAnimationDuration: const Duration(milliseconds: 450),
      themeAnimationCurve: Curves.easeInOutCubic,
      locale: const Locale('es'),
      supportedLocales: const [Locale('es'), Locale('en')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        FlutterQuillLocalizations.delegate,
      ],
      home: AppConfig.isConfigured ? const AuthGate() : const _MissingConfig(),
      ),
    );
  }
}

class _MissingConfig extends StatelessWidget {
  const _MissingConfig();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Text(
            'Falta la configuración de Supabase.',
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }
}
