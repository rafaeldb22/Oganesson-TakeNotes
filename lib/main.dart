import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:window_manager/window_manager.dart';

import 'config.dart';
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
  }

  await themeSettings.load();
  themeSettings.onThemeChanged = WidgetBridge.refresh;

  if (AppConfig.isConfigured) {
    await Supabase.initialize(
      url: AppConfig.supabaseUrl,
      anonKey: AppConfig.supabaseAnonKey,
    );
  }
  runApp(const NotasApp());
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
