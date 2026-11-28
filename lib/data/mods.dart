import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../ui/theme.dart';

/// Mods de la comunidad: un archivo `.ogmod` (un zip) con un `mod.json` que
/// puede traer temas, plantillas, acciones de IA y fuentes. Nunca código:
/// solo datos que la app valida (formato en `docs/MODS.md`).
class ModError implements Exception {
  ModError(this.message);
  final String message;
  @override
  String toString() => message;
}

class ModTemplate {
  const ModTemplate(this.name, this.text);
  final String name;

  /// Markdown; la primera línea es el título.
  final String text;
}

class ModAiAction {
  const ModAiAction(this.name, this.prompt);
  final String name, prompt;
}

class ModFont {
  const ModFont(this.name, this.family, this.file);
  final String name, family, file;
}

class Mod {
  Mod({
    required this.id,
    required this.name,
    required this.author,
    required this.version,
    required this.description,
    this.themes = const [],
    this.templates = const [],
    this.aiActions = const [],
    this.fonts = const [],
  });

  final String id, name, author, version, description;
  final List<AppTheme> themes;
  final List<ModTemplate> templates;
  final List<ModAiAction> aiActions;
  final List<ModFont> fonts;

  /// "2 temas · 3 plantillas" (para la lista).
  Map<String, int> get counts => {
        'themes': themes.length,
        'templates': templates.length,
        'ai': aiActions.length,
        'fonts': fonts.length,
      };

  static const format = 1;
  static const maxZip = 8 << 20; // 8 MB
  static const maxFont = 3 << 20;

  static String _s(Object? v, int max, {String fallback = ''}) {
    final t = v is String ? v.trim() : fallback;
    return t.length > max ? t.substring(0, max) : t;
  }

  static Color _color(Object? v, String where) {
    final s = v is String ? v.trim() : '';
    final m = RegExp(r'^#?([0-9a-fA-F]{6})$').firstMatch(s);
    if (m == null) throw ModError('Color no válido en $where: "$s"');
    return Color(0xFF000000 | int.parse(m[1]!, radix: 16));
  }

  static NotasColors _colors(Object? v, String where) {
    if (v is! Map) throw ModError('Faltan los colores de $where');
    Color c(String k) => _color(v[k], '$where.$k');
    return NotasColors(
      accent: c('accent'),
      onAccent: v['onAccent'] == null ? const Color(0xFFFFFFFF) : c('onAccent'),
      background: c('background'),
      card: c('card'),
      secondary: c('secondary'),
      separator: c('separator'),
      selected: c('selected'),
      searchFill: v['searchFill'] == null ? c('background') : c('searchFill'),
      hover: v['hover'] == null ? c('background') : c('hover'),
    );
  }

  /// Lee y valida `mod.json`. [hasFile] dice si el zip trae un archivo.
  static Mod parse(Map<String, dynamic> j, bool Function(String) hasFile) {
    if (j['format'] != format) {
      throw ModError('Formato de mod no compatible (se espera "format": 1)');
    }
    final rawId = _s(j['id'], 60).toLowerCase();
    if (!RegExp(r'^[a-z0-9][a-z0-9._-]{2,59}$').hasMatch(rawId)) {
      throw ModError('El "id" debe tener de 3 a 60 letras, números, . _ o -');
    }
    final name = _s(j['name'], 60);
    if (name.isEmpty) throw ModError('Falta "name"');
    List<Map> list(String k, int max) {
      final v = j[k];
      if (v == null) return const [];
      if (v is! List) throw ModError('"$k" debe ser una lista');
      if (v.length > max) throw ModError('Como mucho $max en "$k"');
      return v.whereType<Map>().toList();
    }

    final themes = [
      for (final (i, t) in list('themes', 12).indexed)
        AppTheme(
          id: 'mod:$rawId:${_s(t['id'], 40, fallback: '$i')}',
          name: _s(t['name'], 40, fallback: name),
          description: _s(t['description'], 80),
          light: _colors(t['light'], 'themes[$i].light'),
          dark: _colors(t['dark'], 'themes[$i].dark'),
        ),
    ];
    final templates = [
      for (final t in list('templates', 40))
        if (_s(t['text'], 20000).isNotEmpty)
          ModTemplate(_s(t['name'], 60, fallback: name), _s(t['text'], 20000)),
    ];
    final actions = [
      for (final a in list('aiActions', 20))
        if (_s(a['prompt'], 2000).isNotEmpty)
          ModAiAction(_s(a['name'], 40, fallback: name), _s(a['prompt'], 2000)),
    ];
    final fonts = <ModFont>[];
    for (final (i, f) in list('fonts', 4).indexed) {
      final file = _s(f['file'], 120);
      if (!RegExp(r'^[\w./-]+\.(ttf|otf)$', caseSensitive: false)
              .hasMatch(file) ||
          file.contains('..')) {
        throw ModError('fonts[$i].file debe ser un .ttf u .otf del zip');
      }
      if (!hasFile(file)) throw ModError('Falta el archivo $file en el zip');
      fonts.add(
          ModFont(_s(f['name'], 40, fallback: name), 'Mod_${rawId}_$i', file));
    }
    if (themes.isEmpty &&
        templates.isEmpty &&
        actions.isEmpty &&
        fonts.isEmpty) {
      throw ModError('El mod no trae nada (temas, plantillas, IA o fuentes)');
    }
    return Mod(
      id: rawId,
      name: name,
      author: _s(j['author'], 60),
      version: _s(j['version'], 20, fallback: '1.0'),
      description: _s(j['description'], 300),
      themes: themes,
      templates: templates,
      aiActions: actions,
      fonts: fonts,
    );
  }
}

/// Mods instalados en este dispositivo (carpeta de la app + lista).
class Mods extends ChangeNotifier {
  Mods._();
  static final instance = Mods._();

  static const _kList = 'mods_instalados';
  final List<Mod> installed = [];
  bool _loaded = false;

  Iterable<ModTemplate> get templates => installed.expand((m) => m.templates);
  Iterable<ModAiAction> get aiActions => installed.expand((m) => m.aiActions);

  Future<Directory> _dir(String id) async {
    final base = await getApplicationSupportDirectory();
    return Directory('${base.path}${Platform.pathSeparator}mods'
        '${Platform.pathSeparator}$id');
  }

  /// Carga los instalados (antes de leer el tema elegido).
  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final ids =
          (await SharedPreferences.getInstance()).getStringList(_kList) ??
              const [];
      for (final id in ids) {
        try {
          final dir = await _dir(id);
          final j =
              jsonDecode(await File('${dir.path}/mod.json').readAsString())
                  as Map<String, dynamic>;
          final mod = Mod.parse(j, (f) => File('${dir.path}/$f').existsSync());
          await _activate(mod, (f) => File('${dir.path}/$f').readAsBytes());
          installed.add(mod);
        } catch (e) {
          debugPrint('Mod $id no se pudo cargar: $e');
        }
      }
    } catch (_) {}
    _publish();
  }

  /// Instala un `.ogmod`. Si ya estaba (mismo id), lo actualiza.
  Future<Mod> install(Uint8List zipBytes) async {
    if (zipBytes.length > Mod.maxZip) throw ModError('El mod pesa más de 8 MB');
    final Archive zip;
    try {
      zip = ZipDecoder().decodeBytes(zipBytes);
    } catch (_) {
      throw ModError('No es un archivo .ogmod válido (zip)');
    }
    ArchiveFile? find(String name) =>
        zip.files.where((f) => f.isFile && f.name == name).firstOrNull;
    final manifest = find('mod.json');
    if (manifest == null) throw ModError('Falta mod.json dentro del zip');
    final Map<String, dynamic> j;
    try {
      j = jsonDecode(utf8.decode(manifest.content as List<int>))
          as Map<String, dynamic>;
    } catch (_) {
      throw ModError('mod.json no es un JSON válido');
    }
    final mod = Mod.parse(j, (f) => find(f) != null);
    for (final f in mod.fonts) {
      if ((find(f.file)!.content as List<int>).length > Mod.maxFont) {
        throw ModError('La fuente ${f.file} pesa más de 3 MB');
      }
    }
    final dir = await _dir(mod.id);
    if (await dir.exists()) await dir.delete(recursive: true);
    await dir.create(recursive: true);
    await File('${dir.path}/mod.json')
        .writeAsBytes(manifest.content as List<int>);
    for (final f in mod.fonts) {
      final out = File('${dir.path}/${f.file}');
      await out.parent.create(recursive: true);
      await out.writeAsBytes(find(f.file)!.content as List<int>);
    }
    await _activate(
        mod, (f) async => Uint8List.fromList(find(f)!.content as List<int>));
    installed
      ..removeWhere((m) => m.id == mod.id)
      ..add(mod);
    await _save();
    _publish();
    return mod;
  }

  Future<void> remove(String id) async {
    installed.removeWhere((m) => m.id == id);
    try {
      final dir = await _dir(id);
      if (await dir.exists()) await dir.delete(recursive: true);
    } catch (_) {}
    await _save();
    _publish();
    // Si usabas su tema o su fuente, se vuelve a los de serie.
    if (themeById(themeSettings.themeId).id != themeSettings.themeId) {
      await themeSettings.setTheme(appThemes.first.id);
    }
    if (fontById(themeSettings.fontId).id != themeSettings.fontId) {
      await themeSettings.setFont(appFonts.first.id);
    }
  }

  Future<void> _activate(
      Mod mod, Future<Uint8List> Function(String file) read) async {
    for (final f in mod.fonts) {
      final loader = FontLoader(f.family)
        ..addFont(read(f.file).then(ByteData.sublistView));
      await loader.load();
    }
  }

  Future<void> _save() async {
    try {
      await (await SharedPreferences.getInstance())
          .setStringList(_kList, [for (final m in installed) m.id]);
    } catch (_) {}
  }

  /// Temas y fuentes de los mods pasan a las listas de la app.
  void _publish() {
    modThemes
      ..clear()
      ..addAll(installed.expand((m) => m.themes));
    modFonts
      ..clear()
      ..addAll([
        for (final m in installed)
          for (final f in m.fonts) AppFont('mod:${f.family}', f.name, f.family)
      ]);
    notifyListeners();
    themeSettings.refresh();
  }
}
