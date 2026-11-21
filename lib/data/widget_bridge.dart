import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:home_widget/home_widget.dart';

import '../models/note.dart';

/// Puente con el widget 2x2 de Android. En Windows no hace nada.
class WidgetBridge {
  static bool get supported => !kIsWeb && Platform.isAndroid;

  static Timer? _debounce;
  static bool _initialHandled = false;

  static void schedule(List<Note> notes) {
    if (!supported) return;
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
      await HomeWidget.updateWidget(androidName: 'NotasWidget');
    } catch (e) {
      debugPrint('Widget: $e');
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
