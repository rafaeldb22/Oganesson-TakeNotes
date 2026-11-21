import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:open_filex/open_filex.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config.dart';

/// Versión publicada en GitHub Releases.
class AppRelease {
  const AppRelease({
    required this.version,
    required this.notes,
    required this.pageUrl,
    required this.downloadUrl,
    required this.size,
  });

  final String version;
  final String notes;
  final String pageUrl;

  /// Instalador para esta plataforma (null si la release no lo trae).
  final String? downloadUrl;
  final int size;
}

/// Comprueba si hay una versión nueva en GitHub Releases y la instala:
/// en Windows descarga `Oganesson-Setup.exe` y lo ejecuta en modo
/// silencioso (el instalador vuelve a abrir la app al terminar); en Android
/// descarga `Oganesson.apk` y abre el instalador del sistema.
class Updater {
  Updater._();
  static final instance = Updater._();

  static const _kSkipped = 'update_skipped_version';

  bool get supported => !kIsWeb && (Platform.isWindows || Platform.isAndroid);

  String get _assetName =>
      Platform.isWindows ? 'Oganesson-Setup.exe' : 'Oganesson.apk';

  Future<String> currentVersion() async =>
      (await PackageInfo.fromPlatform()).version;

  /// Última release si es más nueva que la instalada. Con [manual] = false
  /// ignora la versión que el usuario eligió omitir y no lanza errores;
  /// con [manual] = true los errores de red se propagan para mostrarlos.
  Future<AppRelease?> check({bool manual = false}) async {
    if (!supported) return null;
    AppRelease? latest;
    try {
      latest = await _fetchLatest();
    } catch (e) {
      debugPrint('Actualizaciones: no se pudo comprobar ($e)');
      if (manual) rethrow;
      return null;
    }
    if (latest == null) return null;
    final current = await currentVersion();
    if (compareVersions(latest.version, current) <= 0) return null;
    if (!manual) {
      try {
        final prefs = await SharedPreferences.getInstance();
        if (prefs.getString(_kSkipped) == latest.version) return null;
      } catch (_) {}
    }
    return latest;
  }

  Future<void> skip(String version) async {
    try {
      (await SharedPreferences.getInstance()).setString(_kSkipped, version);
    } catch (_) {}
  }

  Future<AppRelease?> _fetchLatest() async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 10);
    try {
      final req = await client.getUrl(Uri.parse(
          'https://api.github.com/repos/${AppConfig.githubRepo}/releases/latest'));
      req.headers
        ..set(HttpHeaders.acceptHeader, 'application/vnd.github+json')
        ..set(HttpHeaders.userAgentHeader, 'Oganesson-Updater');
      final res = await req.close().timeout(const Duration(seconds: 15));
      final body = await res.transform(utf8.decoder).join();
      // 404 = sin releases o repositorio privado: no hay nada que ofrecer.
      if (res.statusCode == 404) return null;
      if (res.statusCode != 200) {
        throw HttpException('GitHub respondió ${res.statusCode}');
      }
      final json = jsonDecode(body) as Map<String, dynamic>;
      final tag = (json['tag_name'] as String? ?? '').trim();
      final assets =
          (json['assets'] as List? ?? const []).cast<Map<String, dynamic>>();
      final asset = assets
          .where((a) => a['name'] == _assetName)
          .cast<Map<String, dynamic>?>()
          .firstWhere((_) => true, orElse: () => null);
      return AppRelease(
        version: tag.startsWith('v') ? tag.substring(1) : tag,
        notes: (json['body'] as String? ?? '').trim(),
        pageUrl: json['html_url'] as String? ?? AppConfig.githubUrl,
        downloadUrl: asset?['browser_download_url'] as String?,
        size: (asset?['size'] as num?)?.toInt() ?? 0,
      );
    } finally {
      client.close(force: true);
    }
  }

  /// Descarga el instalador informando del progreso (0..1) y lo lanza.
  /// En Windows cierra la app para que el instalador pueda sustituirla.
  Future<void> install(AppRelease r,
      {void Function(double)? onProgress}) async {
    final url = r.downloadUrl;
    if (url == null) throw StateError('La versión no incluye $_assetName');
    final dir = Platform.isAndroid
        ? (await getExternalCacheDirectories())?.first ??
            await getTemporaryDirectory()
        : await getTemporaryDirectory();
    final file = File('${dir.path}${Platform.pathSeparator}'
        '${_assetName.replaceFirst('.', '-${r.version}.')}');

    final client = HttpClient();
    try {
      final res = await (await client.getUrl(Uri.parse(url))).close();
      if (res.statusCode != 200) {
        throw HttpException('Descarga fallida (${res.statusCode})');
      }
      final total = res.contentLength > 0 ? res.contentLength : r.size;
      final sink = file.openWrite();
      var received = 0;
      await for (final chunk in res) {
        sink.add(chunk);
        received += chunk.length;
        if (total > 0) onProgress?.call(received / total);
      }
      await sink.close();
    } finally {
      client.close(force: true);
    }

    if (Platform.isWindows) {
      await Process.start(
        file.path,
        ['/SILENT', '/SUPPRESSMSGBOXES', '/NORESTART', '/CLOSEAPPLICATIONS'],
        mode: ProcessStartMode.detached,
      );
      exit(0);
    } else {
      final result = await OpenFilex.open(file.path,
          type: 'application/vnd.android.package-archive');
      if (result.type != ResultType.done) {
        throw StateError(result.message);
      }
    }
  }
}

/// Compara versiones "1.2.3" (ignora sufijos como "+4" o "-beta").
/// Negativo si a < b, 0 si iguales, positivo si a > b.
int compareVersions(String a, String b) {
  List<int> parts(String v) => v
      .split(RegExp(r'[+-]'))
      .first
      .split('.')
      .map((s) => int.tryParse(s) ?? 0)
      .toList();
  final pa = parts(a), pb = parts(b);
  for (var i = 0; i < 3; i++) {
    final x = i < pa.length ? pa[i] : 0;
    final y = i < pb.length ? pb[i] : 0;
    if (x != y) return x - y;
  }
  return 0;
}
