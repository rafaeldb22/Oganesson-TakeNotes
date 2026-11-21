import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:home_widget/home_widget.dart';

import '../models/note.dart';
import '../ui/calendar_widget_image.dart';
import '../ui/theme.dart';

/// Puente con el widget 2x2 de Android. En Windows no hace nada.
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
    final real = notes.where((n) => !n.isEmpty && !n.deleted).toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    final latest = real.isEmpty ? null : real.first;
    try {
      await HomeWidget.saveWidgetData<String>(
          'ultima_titulo', latest?.title ?? 'Sin notas todavía');
      await HomeWidget.saveWidgetData<String>(
          'ultima_preview',
          latest == null
              ? 'Toca «Nueva nota» para escribir'
              : (latest.preview == 'Sin texto adicional' ? '' : latest.preview));
      await HomeWidget.saveWidgetData<String>(
          'total', real.length == 1 ? '1 nota' : '${real.length} notas');
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

  /// Widget "Calendario" (4x2): la app lo dibuja como imagen y Android
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
    try {
      await HomeWidget.renderFlutterWidget(
        MediaQuery(
          data: const MediaQueryData(),
          child: CalendarWidgetImage(
            notes: temporales,
            colors: dark ? t.dark : t.light,
            dark: dark,
          ),
        ),
        key: 'calendario_img',
        logicalSize: const Size(360, 180),
        pixelRatio: 3,
      );
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
