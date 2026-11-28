import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_quill/flutter_quill.dart'
    show FlutterQuillLocalizations;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:window_manager/window_manager.dart';

import 'config.dart';
import 'data/desktop_integration.dart';
import 'data/reminders.dart';
import 'data/widget_bridge.dart';
import 'ui/anim.dart' show ResumeFade;
import 'ui/auth_gate.dart';
import 'ui/i18n.dart';
import 'ui/logo.dart';
import 'ui/theme.dart';
import 'ui/title_bar.dart';

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  // Windows: si ya hay una Oganesson abierta (p. ej. en segundo plano), se
  // le pasa el aviso y esta se cierra.
  await DesktopIntegration.instance.ensureSingleInstance(args);

  // Ventana de Windows: tamaño inicial, centrada y con tamaño mínimo
  // para que el contenido nunca se desborde al hacerla pequeña.
  if (!kIsWeb && Platform.isWindows) {
    await windowManager.ensureInitialized();
    const options = WindowOptions(
      size: Size(1100, 720),
      minimumSize: Size(760, 540),
      center: true,
      title: 'Oganesson',
      // Sin la barra de Windows: la app dibuja la suya (como Chrome).
      titleBarStyle: TitleBarStyle.hidden,
      // Mismo azul que la animación de inicio: sin destello blanco al abrir.
      backgroundColor: logoNavyTop,
    );
    // Se muestra cuando Flutter ya ha pintado (ver el final de main): así
    // no se ve un fotograma blanco antes de la animación de inicio.
    windowManager.waitUntilReadyToShow(options);
    windowManager.addListener(_RepaintOnWindowChange());
  }

  await themeSettings.load();
  await appLanguage.load();
  // Bandeja del sistema, Ctrl+Alt+N y cerrar = ocultar.
  if (!kIsWeb && Platform.isWindows) {
    unawaited(DesktopIntegration.instance.init());
  }
  unawaited(Reminders.instance.init());
  if (const bool.fromEnvironment('TEST_TOAST')) {
    unawaited(Reminders.instance.scheduleTest(const Duration(minutes: 1)));
  }
  themeSettings.onThemeChanged = WidgetBridge.refresh;

  if (AppConfig.isConfigured) {
    await Supabase.initialize(
      url: AppConfig.supabaseUrl,
      publishableKey: AppConfig.supabaseAnonKey,
    );
  }
  runApp(const NotasApp());
  // Abierta con Windows (--background): se queda oculta en la bandeja.
  if (!kIsWeb &&
      Platform.isWindows &&
      !DesktopIntegration.instance.startedHidden) {
    // Se enseña transparente y se hace opaca cuando la superficie de dibujo
    // ya tiene imagen: si no, Windows enseña la ventana en blanco un instante.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await windowManager.setOpacity(0);
      await windowManager.show();
      await windowManager.focus();
      for (var i = 0; i < 3; i++) {
        WidgetsBinding.instance.scheduleFrame();
        await WidgetsBinding.instance.endOfFrame;
      }
      await Future<void>.delayed(const Duration(milliseconds: 60));
      await windowManager.setOpacity(1);
    });
  }
}

/// Algunas gráficas en Windows dejan zonas negras o sin texto tras cambiar
/// el tamaño de la ventana. Al terminar cada cambio forzamos a repintar
/// toda la interfaz desde cero (sin perder nada de lo que haya abierto).
class _RepaintOnWindowChange with WindowListener {
  Timer? _debounce;
  bool _framePending = false;

  void _schedule() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 220), forceFullRepaint);
  }

  /// Mientras se arrastra el borde: repintar en cada frame (como mucho una
  /// vez por frame) para que todo siga a la ventana sin retraso.
  void _duringResize() {
    if (!_framePending) {
      _framePending = true;
      SchedulerBinding.instance.addPostFrameCallback((_) {
        _framePending = false;
        forceFullRepaint();
      });
      SchedulerBinding.instance.scheduleFrame();
    }
    _schedule();
  }

  @override
  void onWindowResized() => _schedule();
  @override
  void onWindowResize() => _duringResize();
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
}

class NotasApp extends StatelessWidget {
  const NotasApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([themeSettings, appLanguage]),
      builder: (context, _) => MaterialApp(
        title: 'Oganesson',
        debugShowCheckedModeBanner: false,
        theme: buildTheme(
            themeSettings.theme, Brightness.light, themeSettings.font),
        darkTheme: buildTheme(
            themeSettings.theme, Brightness.dark, themeSettings.font),
        themeMode: themeSettings.mode,
        // Cambio de tema animado: los colores se funden en vez de saltar.
        themeAnimationDuration: const Duration(milliseconds: 450),
        themeAnimationCurve: Curves.easeInOutCubic,
        locale: appLanguage.locale,
        supportedLocales: const [Locale('es'), Locale('en')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
          FlutterQuillLocalizations.delegate,
        ],
        // En Windows, barra de título propia encima de todas las pantallas.
        // Animación de inicio (el logo se dibuja) por encima de toda la app.
        builder: (context, child) => StartupSplash(
          child: ResumeFade(
              child: isDesktopWindows
                  ? Column(
                      children: [
                        const AppTitleBar(),
                        Expanded(child: child ?? const SizedBox()),
                      ],
                    )
                  : (child ?? const SizedBox())),
        ),
        // Al cambiar de idioma se vuelve a montar la app con los textos nuevos.
        home: KeyedSubtree(
          key: ValueKey(appLanguage.code),
          child: AppConfig.isConfigured
              ? const AuthGate()
              : const _MissingConfig(),
        ),
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
