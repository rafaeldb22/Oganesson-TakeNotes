import 'dart:async';
import '../ui/i18n.dart';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:home_widget/home_widget.dart';

import '../models/note.dart';
import '../ui/calendar_widget_image.dart';
import '../ui/widget_images.dart';
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
    await _pushImages(real);
  }

  /// Widgets dibujados como imagen (Calendario, Tareas, Próxima tarea,
  /// Notas fijadas): la app los pinta y Android los muestra. Solo se dibujan
  /// los widgets que hay puestos en la pantalla de inicio, y solo cuando
  /// cambian las notas, el tema o la hora.
  static String _lastImagesSig = '';

  static Future<Set<String>> _installed() async {
    try {
      final list = await HomeWidget.getInstalledWidgets();
      return {
        for (final w in list)
          if (w.androidClassName != null) w.androidClassName!.split('.').last,
      };
    } catch (e) {
      debugPrint('Widgets instalados: $e');
      // Si no se puede saber, se dibujan todos.
      return {
        'CalendarioWidget',
        'TareasWidget',
        'ProximaWidget',
        'FijadasWidget'
      };
    }
  }

  static Future<void> _pushImages(List<Note> notes) async {
    final temporales = notes.where((n) => n.isTemporal && !n.done).toList()
      ..sort((a, b) => a.dueAt!.compareTo(b.dueAt!));
    final pinned = notes.where((n) => n.pinned).toList();
    final listNotes = pinned.isNotEmpty ? pinned : notes.take(12).toList();
    final next = temporales.isEmpty ? null : temporales.first;
    final mode = themeSettings.mode;
    final dark = mode == ThemeMode.dark ||
        (mode == ThemeMode.system &&
            WidgetsBinding.instance.platformDispatcher.platformBrightness ==
                Brightness.dark);
    final installed = await _installed();
    final now = DateTime.now();
    // La cuenta atrás de "Próxima tarea" cambia cada minuto.
    final sig = [
      themeSettings.themeId,
      dark,
      appLanguage.code,
      installed.join(','),
      '${now.year}-${now.month}-${now.day}-${now.hour}-${now.minute}',
      for (final n in temporales)
        '${n.id}${n.title}${n.dueAt}${n.remindAt}${n.color}',
      for (final n in listNotes) '${n.id}${n.title}${n.updatedAt}${n.color}',
    ].join('|');
    if (sig == _lastImagesSig) return;
    _lastImagesSig = sig;
    final t = themeSettings.theme;
    final colors = dark ? t.dark : t.lightSoft;

    Future<void> render(Widget w, String key, Size size) =>
        HomeWidget.renderFlutterWidget(
          MediaQuery(data: const MediaQueryData(), child: w),
          key: key,
          logicalSize: size,
          pixelRatio: 3,
        );

    try {
      // Fondo nativo de los widgets: mismo color que la tarjeta dibujada.
      await HomeWidget.saveWidgetData<int>(
          'calendario_bg', colors.card.toARGB32());

      if (installed.contains('CalendarioWidget')) {
        for (final size in CalendarWidgetSize.values) {
          await render(
              CalendarWidgetImage(
                  notes: temporales, colors: colors, dark: dark, size: size),
              size.key,
              size.logicalSize);
        }
        await HomeWidget.updateWidget(androidName: 'CalendarioWidget');
      }
      if (installed.contains('TareasWidget')) {
        for (final spec in [
          WidgetSpecs.tareasS,
          WidgetSpecs.tareasM,
          WidgetSpecs.tareasL
        ]) {
          await render(
              TasksWidgetImage(notes: temporales, colors: colors, dark: dark),
              spec.key,
              spec.size);
        }
        await HomeWidget.updateWidget(androidName: 'TareasWidget');
      }
      if (installed.contains('ProximaWidget')) {
        await HomeWidget.saveWidgetData<String>('proxima_id', next?.id ?? '');
        for (final spec in [WidgetSpecs.proximaW, WidgetSpecs.proximaS]) {
          await render(
              NextTaskWidgetImage(
                  note: next,
                  colors: colors,
                  dark: dark,
                  wide: spec == WidgetSpecs.proximaW),
              spec.key,
              spec.size);
        }
        await HomeWidget.updateWidget(androidName: 'ProximaWidget');
      }
      if (installed.contains('FijadasWidget')) {
        for (final spec in [WidgetSpecs.fijadasM, WidgetSpecs.fijadasL]) {
          await render(
              PinnedWidgetImage(
                  notes: listNotes,
                  pinned: pinned.isNotEmpty,
                  colors: colors,
                  dark: dark),
              spec.key,
              spec.size);
        }
        await HomeWidget.updateWidget(androidName: 'FijadasWidget');
      }
      if (installed.contains('AccionesWidget')) {
        await HomeWidget.updateWidget(androidName: 'AccionesWidget');
      }
    } catch (e) {
      debugPrint('Widgets con imagen: $e');
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
