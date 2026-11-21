import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/updater.dart';
import 'theme.dart';
import 'toast.dart';
import 'i18n.dart';

/// Abre un enlace en el navegador del sistema.
Future<void> openLink(BuildContext context, String url) async {
  final ok =
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  if (!ok && context.mounted) {
    showToast(context, tr('No se pudo abrir el enlace'),
        icon: Icons.link_off_rounded);
  }
}

/// Comprobación silenciosa al arrancar: solo muestra algo si hay versión nueva.
Future<void> checkForUpdatesOnStart(BuildContext context) async {
  await Future<void>.delayed(const Duration(seconds: 4));
  final release = await Updater.instance.check();
  if (release != null && context.mounted) {
    await showUpdateDialog(context, release);
  }
}

/// Comprobación desde el menú: informa también si ya está al día o si falla.
Future<void> checkForUpdatesManually(BuildContext context) async {
  showToast(context, tr('Buscando actualizaciones…'), icon: Icons.sync_rounded);
  try {
    final release = await Updater.instance.check(manual: true);
    if (release != null) {
      if (context.mounted) await showUpdateDialog(context, release);
    } else {
      final v = await Updater.instance.currentVersion();
      if (context.mounted) {
        showToast(context, trf('Tienes la última versión ({0})', [v]),
            icon: Icons.check_circle_outline_rounded);
      }
    }
  } catch (_) {
    if (context.mounted) {
      showToast(context, tr('No se pudo comprobar. Revisa la conexión.'),
          icon: Icons.cloud_off_rounded);
    }
  }
}

Future<void> showUpdateDialog(BuildContext context, AppRelease release) {
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _UpdateDialog(release: release),
  );
}

class _UpdateDialog extends StatefulWidget {
  const _UpdateDialog({required this.release});
  final AppRelease release;

  @override
  State<_UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<_UpdateDialog> {
  double? _progress; // null = sin empezar; 0..1 = descargando
  String? _error;

  Future<void> _install() async {
    setState(() {
      _progress = 0;
      _error = null;
    });
    try {
      await Updater.instance.install(widget.release,
          onProgress: (p) => mounted ? setState(() => _progress = p) : null);
      // Android: el instalador del sistema ya está abierto.
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        setState(() {
          _progress = null;
          _error = 'No se pudo instalar: $e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.release;
    final secondary = Palette.secondary(context);
    final downloading = _progress != null;
    return AlertDialog(
      icon:
          Icon(Icons.system_update_alt_rounded, color: Palette.accent(context)),
      title: Text(trf('Nueva versión {0}', [r.version])),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420, maxHeight: 320),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (r.notes.isNotEmpty) ...[
              Text(tr('Novedades'),
                  style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 6),
              Flexible(
                child: SingleChildScrollView(
                  child: Text(_cleanNotes(r.notes),
                      style: TextStyle(color: secondary, height: 1.35)),
                ),
              ),
            ],
            if (downloading) ...[
              const SizedBox(height: 16),
              LinearProgressIndicator(value: _progress == 0 ? null : _progress),
              const SizedBox(height: 6),
              Text(
                  Platform.isWindows
                      ? tr(
                          'Descargando… la app se cerrará y se abrirá actualizada.')
                      : 'Descargando…',
                  style: TextStyle(color: secondary, fontSize: 12)),
            ],
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!,
                  style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                      fontSize: 12)),
            ],
          ],
        ),
      ),
      actions: downloading
          ? const []
          : [
              // Si la instalación falla: descargar desde el navegador.
              if (_error != null)
                TextButton(
                  onPressed: () =>
                      openLink(context, r.downloadUrl ?? r.pageUrl),
                  child: Text(tr('Descargar en el navegador')),
                ),
              TextButton(
                onPressed: () {
                  Updater.instance.skip(r.version);
                  Navigator.pop(context);
                },
                child: Text(tr('Omitir')),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(tr('Más tarde')),
              ),
              FilledButton(
                onPressed: r.downloadUrl == null
                    ? () => openLink(context, r.pageUrl)
                    : _install,
                child: Text(r.downloadUrl == null
                    ? tr('Ver descarga')
                    : tr('Actualizar')),
              ),
            ],
    );
  }

  /// Las notas de la release vienen en Markdown: quita la tabla de
  /// descargas y los símbolos más visibles para leerlas como texto.
  static String _cleanNotes(String md) {
    final lines = md
        .split('\n')
        .where((l) => !l.trimLeft().startsWith('|'))
        .map((l) => l
            .replaceAll(RegExp(r'^#+\s*'), '')
            .replaceAll('**', '')
            .replaceAll(RegExp(r'^\s*[-*]\s+'), '• '))
        .toList();
    return lines.join('\n').replaceAll(RegExp(r'\n{3,}'), '\n\n').trim();
  }
}
