import 'dart:async';
import '../ui/i18n.dart';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:home_widget/home_widget.dart';

import '../models/note.dart';
import '../ui/calendar_widget_image.dart';
import '../ui/theme.dart';

/// Puente con los widgets de Android (nota rápida y calendario). En Windows no hace nada.
class WidgetBridge {
  static bool get supported => !kIsWeb && Platform.isAndroid;

  static Timer? _debounce;
  static bool _initialHandled = false;

  static List<Note> _last = const [];

  /// Vuelve a pintar el widget (p. ej. al cambiar de tema).
  static void refresh() => schedule(_last);

  static void schedule(List<Note> notes) {
    if (!supported) return;
    _last = notes;
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 700), () => _push(notes));
  }

  static Future<void> _push(List<Note> notes) async {
    // Las notas del Vault nunca salen en la pantalla de inicio.
    final real = notes
        .where((n) => !n.isEmpty && !n.deleted && !n.vault)
        .toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    final latest = real.isEmpty ? null : real.first;
    try {
      await HomeWidget.saveWidgetData<String>(
          'ultima_titulo', latest?.title ?? tr('Sin notas todavía'));
      await HomeWidget.saveWidgetData<String>(
          'ultima_preview',
          latest == null
              ? tr('Toca «Nueva nota» para escribir')
              : (!latest.hasPreview ? '' : latest.preview));
      await HomeWidget.saveWidgetData<String>(
          'total', trn(real.length, '{0} nota', '{0} notas'));
      final t = themeSettings.theme;
      await HomeWidget.saveWidgetData<int>(
          'acento_claro', t.light.accent.toARGB32());
      await HomeWidget.saveWidgetData<int>(
          'acento_oscuro', t.dark.accent.toARGB32());
      await HomeWidget.saveWidgetData<int>(
          'texto_boton_claro', t.light.onAccent.toARGB32());
      await HomeWidget.saveWidgetData<int>(
          'texto_boton_oscuro', t.dark.onAccent.toARGB32());
      await HomeWidget.updateWidget(androidName: 'NotasWidget');
    } catch (e) {
      debugPrint('Widget: $e');
    }
    await _pushCalendar(real);
  }

  /// Widget "Calendario" (2x2, 4x2 o 4x4): la app lo dibuja como imagen y Android
  /// la muestra. Solo cambia la imagen si cambian las tareas o el tema.
  static String _lastCalendarSig = '';

  static Future<void> _pushCalendar(List<Note> notes) async {
    final temporales = notes.where((n) => n.isTemporal && !n.done).toList();
    final mode = themeSettings.mode;
    final dark = mode == ThemeMode.dark ||
        (mode == ThemeMode.system &&
            WidgetsBinding.instance.platformDispatcher.platformBrightness ==
                Brightness.dark);
    final now = DateTime.now();
    final sig = [
      themeSettings.themeId,
      dark,
      '${now.year}-${now.month}-${now.day}-${now.hour}',
      for (final n in temporales)
        '${n.id}${n.title}${n.dueAt}${n.remindAt}${n.color}',
    ].join('|');
    if (sig == _lastCalendarSig) return;
    _lastCalendarSig = sig;
    final t = themeSettings.theme;
    final colors = dark ? t.dark : t.light;
    try {
      // Fondo nativo del widget: mismo color que la tarjeta dibujada.
      await HomeWidget.saveWidgetData<int>(
          'calendario_bg', colors.card.toARGB32());
      // Una imagen por tamaño; Android muestra la que encaja (S / M / L).
      for (final size in CalendarWidgetSize.values) {
        await HomeWidget.renderFlutterWidget(
          MediaQuery(
            data: const MediaQueryData(),
            child: CalendarWidgetImage(
              notes: temporales,
              colors: colors,
              dark: dark,
              size: size,
            ),
          ),
          key: size.key,
          logicalSize: size.logicalSize,
          pixelRatio: 3,
        );
      }
      await HomeWidget.updateWidget(androidName: 'CalendarioWidget');
    } catch (e) {
      debugPrint('Widget calendario: $e');
    }
  }

  static Stream<Uri?> get clicks =>
      supported ? HomeWidget.widgetClicked : const Stream<Uri?>.empty();

  /// URI con la que se abrió la app desde el widget (solo la primera vez).
  static Future<Uri?> initialUri() async {
    if (!supported || _initialHandled) return null;
    _initialHandled = true;
    try {
      return await HomeWidget.initiallyLaunchedFromHomeWidget();
    } catch (_) {
      return null;
    }
  }
}
