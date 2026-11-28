import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/animation.dart' show Curves;
import 'package:flutter/services.dart';
import 'package:hotkey_manager/hotkey_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';
import 'package:windows_single_instance/windows_single_instance.dart';

import '../ui/anim.dart' show resumeTicks;
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

  /// Archivos .md abiertos con Oganesson (Explorador → Abrir con).
  final _openFile = StreamController<String>.broadcast();
  Stream<String> get openFileRequests => _openFile.stream;

  /// El .md con el que se abrió la app (lo recoge la pantalla principal).
  String? pendingFile;

  static String? markdownIn(List<String> args) => args.where((a) {
        final l = a.toLowerCase();
        return l.endsWith('.md') || l.endsWith('.markdown');
      }).firstOrNull;

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
    pendingFile = markdownIn(args);
    try {
      await WindowsSingleInstance.ensureSingleInstance(
        args,
        'oganesson_takenotes',
        bringWindowToFront: false,
        onSecondWindow: (a) {
          final file = markdownIn(a);
          if (file != null) {
            showWindow();
            _openFile.add(file);
          } else if (a.contains(newNoteFlag)) {
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
    try {
      await hotKeyManager.register(
        HotKey(
          key: PhysicalKeyboardKey.keyO,
          modifiers: [HotKeyModifier.control, HotKeyModifier.alt],
          scope: HotKeyScope.system,
        ),
        keyDownHandler: (_) => showWindow(),
      );
    } catch (e) {
      debugPrint('Escritorio: no se pudo registrar Ctrl+Alt+O ($e)');
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
    if (!await windowManager.isVisible()) resumeTicks.value++;
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
    // Invisible mientras cambia de tamaño: sin el destello de la ventana
    // grande; luego aparece con un fundido.
    if (_wasVisible) await _fade(1, 0);
    await windowManager.setOpacity(0);
    _bounds = await windowManager.getBounds();
    await windowManager.setMinimumSize(const Size(420, 240));
    await windowManager.setSize(const Size(560, 320));
    await windowManager.center();
    await windowManager.setAlwaysOnTop(true);
    _capture.add(null);
    await windowManager.show();
    await windowManager.focus();
    await Future<void>.delayed(const Duration(milliseconds: 60));
    await _fade(0, 1);
  }

  /// Widget de escritorio activo ('tareas', 'calendario'…) o null.
  final widgetMode = ValueNotifier<String?>(null);

  /// El widget que se queda en el escritorio: al cerrar la app (o al
  /// encender el PC) vuelve a salir. null = ninguno.
  String? keptWidget;
  final widgetOnTop = ValueNotifier<bool>(false);
  Rect? _widgetBounds;
  bool _widgetWasMaximized = false;
  static const _kWidget = 'widget_escritorio';
  static const _kWidgetRect = 'widget_escritorio_sitio';

  static const _widgetSizes = {
    'tareas': Size(320, 400),
    'calendario': Size(330, 340),
    'fijada': Size(320, 360),
  };

  /// Fundido de la ventana (sin que se vea la ventana grande un instante).
  Future<void> _fade(double from, double to) async {
    const steps = 9;
    for (var i = 1; i <= steps; i++) {
      final t = Curves.easeOutCubic.transform(i / steps);
      await windowManager.setOpacity(from + (to - from) * t);
      await Future<void>.delayed(const Duration(milliseconds: 14));
    }
  }

  /// La app pasa a ser una ventanita en el escritorio con el widget [kind],
  /// con un fundido de entrada. Se recuerda para que siga ahí.
  Future<void> enterWidget(String kind) async {
    if (!supported) return;
    final visible = await windowManager.isVisible();
    if (visible) await _fade(1, 0);
    await windowManager.setOpacity(0);
    if (widgetMode.value == null) {
      _widgetWasMaximized = await windowManager.isMaximized();
      if (_widgetWasMaximized) await windowManager.unmaximize();
      _widgetBounds = await windowManager.getBounds();
    }
    final size = _widgetSizes[kind] ?? const Size(320, 360);
    Rect? saved;
    try {
      final r = (await SharedPreferences.getInstance())
          .getStringList(_kWidgetRect)
          ?.map(double.parse)
          .toList();
      if (r != null && r.length == 2) {
        saved = Rect.fromLTWH(r[0], r[1], size.width, size.height);
      }
    } catch (_) {}
    final b = _widgetBounds!;
    widgetMode.value = kind;
    keptWidget = kind;
    await windowManager.setMinimumSize(const Size(220, 200));
    await windowManager.setBounds(saved ??
        Rect.fromLTWH(
            b.right - size.width - 24, b.top + 40, size.width, size.height));
    await windowManager.setSkipTaskbar(true);
    await windowManager.setAlwaysOnTop(widgetOnTop.value);
    await windowManager.show();
    // Un par de fotogramas para que pinte el widget antes de aparecer.
    await Future<void>.delayed(const Duration(milliseconds: 60));
    await _fade(0, 1);
    try {
      await (await SharedPreferences.getInstance()).setString(_kWidget, kind);
    } catch (_) {}
  }

  /// Vuelve a la ventana normal con un fundido. Con [close] el widget deja
  /// de estar en el escritorio (y la app se oculta en la bandeja).
  Future<void> exitWidget({bool close = false}) async {
    if (widgetMode.value == null) return;
    try {
      final r = await windowManager.getBounds();
      await (await SharedPreferences.getInstance())
          .setStringList(_kWidgetRect, ['${r.left}', '${r.top}']);
      if (close) {
        keptWidget = null;
        await (await SharedPreferences.getInstance()).remove(_kWidget);
      }
    } catch (_) {}
    await _fade(1, 0);
    widgetMode.value = null;
    await windowManager.setAlwaysOnTop(false);
    await windowManager.setSkipTaskbar(false);
    await windowManager.setMinimumSize(const Size(760, 540));
    if (_widgetBounds != null) await windowManager.setBounds(_widgetBounds!);
    if (_widgetWasMaximized) await windowManager.maximize();
    if (close) {
      await windowManager.hide();
      await windowManager.setOpacity(1);
      return;
    }
    await Future<void>.delayed(const Duration(milliseconds: 60));
    await windowManager.focus();
    await _fade(0, 1);
  }

  Future<void> setWidgetOnTop(bool v) async {
    widgetOnTop.value = v;
    if (widgetMode.value != null) await windowManager.setAlwaysOnTop(v);
  }

  /// Al arrancar: si había un widget en el escritorio, vuelve.
  Future<void> restoreWidget() async {
    if (!supported) return;
    try {
      final kind = (await SharedPreferences.getInstance()).getString(_kWidget);
      if (kind != null && _widgetSizes.containsKey(kind)) {
        keptWidget = kind;
        // Al encender el PC (app en segundo plano) sale el widget; si abres
        // la app tú, se ve la app y el widget vuelve al cerrarla.
        if (startedHidden) await enterWidget(kind);
      }
    } catch (_) {}
  }

  /// Fin de la nota rápida. Con [keepOpen] la ventana se queda abierta.
  Future<void> endCapture({bool keepOpen = false}) async {
    if (!_capturing) return;
    _capturing = false;
    await _fade(1, 0);
    await windowManager.setAlwaysOnTop(false);
    await windowManager.setMinimumSize(const Size(760, 540));
    if (_bounds != null) await windowManager.setBounds(_bounds!);
    if (_wasMaximized) await windowManager.maximize();
    if (!_wasVisible && !keepOpen) {
      await windowManager.hide();
      await windowManager.setOpacity(1);
      return;
    }
    await Future<void>.delayed(const Duration(milliseconds: 60));
    await _fade(0, 1);
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
    } else if (keptWidget != null && widgetMode.value == null) {
      // El widget sigue en el escritorio: la app vuelve a ser el widget.
      await enterWidget(keptWidget!);
    } else {
      await windowManager.hide();
    }
  }
}
