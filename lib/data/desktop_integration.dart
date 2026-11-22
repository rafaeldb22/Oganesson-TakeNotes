import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:hotkey_manager/hotkey_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';
import 'package:windows_single_instance/windows_single_instance.dart';

import '../ui/i18n.dart';

/// Windows: la app vive en segundo plano.
///
/// - Se abre con Windows sin mostrarse (`--background`) y queda en la bandeja
///   del sistema (junto al reloj).
/// - Cerrar la ventana la oculta; "Salir" (bandeja o ⋯) la cierra de verdad.
/// - **Ctrl+Alt+N** en cualquier sitio de Windows abre una nota nueva.
/// - Una sola instancia: abrirla otra vez muestra la que ya está en marcha.
class DesktopIntegration with WindowListener, TrayListener {
  DesktopIntegration._();
  static final instance = DesktopIntegration._();

  static const backgroundFlag = '--background';
  static const newNoteFlag = '--new-note';
  static const _runKey = r'HKCU\Software\Microsoft\Windows\CurrentVersion\Run';
  static const _runValue = 'Oganesson';
  static const _kStartupAsked = 'arranque_windows_configurado';
  static const _kCloseChoice = 'cerrar_ventana';

  /// La primera vez que se cierra la ventana se pregunta qué hacer
  /// (la pone la pantalla principal): true = salir, false = segundo plano,
  /// null = cancelar.
  Future<bool?> Function()? askOnFirstClose;

  bool get supported => !kIsWeb && Platform.isWindows;

  /// Se abrió con Windows, sin enseñar la ventana.
  bool startedHidden = false;

  final _newNote = StreamController<void>.broadcast();

  /// Peticiones de "nota nueva" (la bandeja).
  Stream<void> get newNoteRequests => _newNote.stream;

  final _capture = StreamController<void>.broadcast();

  /// Peticiones de nota rápida (Ctrl+Alt+N).
  Stream<void> get captureRequests => _capture.stream;

  bool _capturing = false;

  /// La pone la pantalla principal mientras la nota rápida está abierta.
  VoidCallback? _cancelCapture;
  set cancelCapture(VoidCallback? f) => _cancelCapture = f;
  bool _wasVisible = false;
  bool _wasMaximized = false;
  Rect? _bounds;

  bool _quitting = false;

  /// Antes de nada: si ya hay otra Oganesson abierta, le pasa los
  /// argumentos (la otra se muestra o abre una nota) y esta se cierra.
  Future<void> ensureSingleInstance(List<String> args) async {
    if (!supported) return;
    startedHidden = args.contains(backgroundFlag);
    try {
      await WindowsSingleInstance.ensureSingleInstance(
        args,
        'oganesson_takenotes',
        bringWindowToFront: false,
        onSecondWindow: (a) {
          if (a.contains(newNoteFlag)) {
            requestNewNote();
          } else {
            showWindow();
          }
        },
      );
    } catch (e) {
      debugPrint('Escritorio: instancia única no disponible ($e)');
    }
  }

  /// Bandeja, atajo global y cerrar = ocultar. Se llama con la ventana ya
  /// inicializada.
  Future<void> init() async {
    if (!supported) return;
    windowManager.addListener(this);
    await windowManager.setPreventClose(true);
    await _setupTray();
    await _setupHotKey();
    await _firstRunStartup();
  }

  Future<void> _setupTray() async {
    try {
      // En Windows el icono de la bandeja tiene que ser un .ico.
      await trayManager.setIcon('assets/icon/tray.ico');
      await trayManager.setToolTip('Oganesson');
      await trayManager.setContextMenu(Menu(items: [
        MenuItem(key: 'abrir', label: tr('Abrir Oganesson')),
        MenuItem(key: 'nueva', label: tr('Nueva nota  (Ctrl+Alt+N)')),
        MenuItem.separator(),
        MenuItem(key: 'salir', label: tr('Salir')),
      ]));
      trayManager.addListener(this);
    } catch (e) {
      debugPrint('Escritorio: no se pudo crear el icono de la bandeja ($e)');
    }
  }

  // Clic en el icono: abrir la ventana. Clic derecho: el menú.
  @override
  void onTrayIconMouseDown() => showWindow();

  @override
  void onTrayIconRightMouseDown() => trayManager.popUpContextMenu();

  @override
  void onTrayMenuItemClick(MenuItem menuItem) {
    switch (menuItem.key) {
      case 'abrir':
        showWindow();
      case 'nueva':
        requestNewNote();
      case 'salir':
        quit();
    }
  }

  Future<void> _setupHotKey() async {
    try {
      await hotKeyManager.unregisterAll();
      await hotKeyManager.register(
        HotKey(
          key: PhysicalKeyboardKey.keyN,
          modifiers: [HotKeyModifier.control, HotKeyModifier.alt],
          scope: HotKeyScope.system,
        ),
        keyDownHandler: (_) => beginCapture(),
      );
    } catch (e) {
      debugPrint('Escritorio: no se pudo registrar Ctrl+Alt+N ($e)');
    }
  }

  /// La primera vez, la app se apunta para abrirse con Windows (en segundo
  /// plano). Luego manda lo que elija el usuario en ⋯.
  Future<void> _firstRunStartup() async {
    try {
      final p = await SharedPreferences.getInstance();
      if (p.getBool(_kStartupAsked) == true) {
        // Si la app se movió (nueva versión instalada), se actualiza la ruta.
        if (await startsWithWindows()) await setStartsWithWindows(true);
        return;
      }
      await setStartsWithWindows(true);
      await p.setBool(_kStartupAsked, true);
    } catch (e) {
      debugPrint('Escritorio: arranque con Windows no configurado ($e)');
    }
  }

  // ------------------------------------------------- abrir con Windows

  /// ¿Se abre al iniciar Windows? (clave Run del usuario, sin permisos de
  /// administrador).
  Future<bool> startsWithWindows() async {
    if (!supported) return false;
    final r = await Process.run('reg', ['query', _runKey, '/v', _runValue]);
    return r.exitCode == 0;
  }

  Future<void> setStartsWithWindows(bool on) async {
    if (!supported) return;
    if (on) {
      await Process.run('reg', [
        'add',
        _runKey,
        '/v',
        _runValue,
        '/t',
        'REG_SZ',
        '/d',
        '"${Platform.resolvedExecutable}" $backgroundFlag',
        '/f',
      ]);
    } else {
      await Process.run('reg', ['delete', _runKey, '/v', _runValue, '/f']);
    }
  }

  // ------------------------------------------------------------ acciones

  Future<void> showWindow() async {
    if (!supported) return;
    if (await windowManager.isMinimized()) await windowManager.restore();
    await windowManager.setOpacity(1);
    await windowManager.show();
    await windowManager.focus();
  }

  /// Ctrl+Alt+N: enseña la ventana y abre una nota nueva.
  Future<void> requestNewNote() async {
    await showWindow();
    _newNote.add(null);
  }

  /// Ctrl+Alt+N: ventanita flotante para apuntar algo. Al terminar, todo
  /// vuelve a como estaba (también si la app estaba oculta).
  Future<void> beginCapture() async {
    if (!supported) return;
    if (_capturing) {
      await windowManager.focus();
      return;
    }
    _capturing = true;
    _wasVisible =
        await windowManager.isVisible() && !await windowManager.isMinimized();
    _wasMaximized = await windowManager.isMaximized();
    if (await windowManager.isMinimized()) await windowManager.restore();
    if (_wasMaximized) await windowManager.unmaximize();
    _bounds = await windowManager.getBounds();
    await windowManager.setMinimumSize(const Size(420, 240));
    await windowManager.setSize(const Size(560, 320));
    await windowManager.center();
    await windowManager.setAlwaysOnTop(true);
    await windowManager.setOpacity(1);
    await windowManager.show();
    await windowManager.focus();
    _capture.add(null);
  }

  /// Fin de la nota rápida. Con [keepOpen] la ventana se queda abierta.
  Future<void> endCapture({bool keepOpen = false}) async {
    if (!_capturing) return;
    _capturing = false;
    await windowManager.setAlwaysOnTop(false);
    await windowManager.setMinimumSize(const Size(760, 540));
    if (_bounds != null) await windowManager.setBounds(_bounds!);
    if (_wasMaximized) await windowManager.maximize();
    if (!_wasVisible && !keepOpen) await windowManager.hide();
  }

  /// Cierra la app de verdad (no solo la ventana).
  Future<void> quit() async {
    if (_quitting) return;
    _quitting = true;
    try {
      await hotKeyManager.unregisterAll();
    } catch (_) {}
    try {
      await trayManager.destroy();
    } catch (_) {}
    await windowManager.setPreventClose(false);
    await windowManager.destroy();
    exit(0);
  }

  /// Cerrar la ventana (la ✕) solo la oculta: la app sigue en la bandeja y
  /// Ctrl+Alt+N sigue funcionando.
  @override
  void onWindowClose() async {
    if (_quitting) return;
    if (_capturing) {
      // La ✕ en la nota rápida equivale a cancelarla.
      _cancelCapture?.call();
      return;
    }
    String? choice;
    try {
      choice = (await SharedPreferences.getInstance()).getString(_kCloseChoice);
    } catch (_) {}
    if (choice == null && askOnFirstClose != null) {
      final quitApp = await askOnFirstClose!();
      if (quitApp == null) return; // cancelado
      choice = quitApp ? 'salir' : 'ocultar';
      try {
        await (await SharedPreferences.getInstance())
            .setString(_kCloseChoice, choice);
      } catch (_) {}
    }
    if (choice == 'salir') {
      await quit();
    } else {
      await windowManager.hide();
    }
  }
}
