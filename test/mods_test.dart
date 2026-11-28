import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' show Color;

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notas/data/mods.dart';
import 'package:notas/ui/theme.dart';

Map<String, dynamic> _manifest() => {
      'format': 1,
      'id': 'rafa.otono',
      'name': 'Otoño',
      'author': 'Rafa',
      'themes': [
        {
          'id': 'otono',
          'name': 'Otoño',
          'light': {
            'accent': '#C2571A',
            'background': '#FAF3EC',
            'card': '#FFFCF8',
            'secondary': '#7A665A',
            'separator': '#EAD8C8',
            'selected': '#F8DCC8'
          },
          'dark': {
            'accent': '#F29A5B',
            'background': '#15100C',
            'card': '#231A14',
            'secondary': '#B09A8C',
            'separator': '#3D2E25',
            'selected': '#5A3323'
          },
        }
      ],
      'templates': [
        {'name': 'Estudio', 'text': 'Estudio\n- [ ] Leer'}
      ],
      'aiActions': [
        {'name': 'Preguntas', 'prompt': 'Haz 5 preguntas de examen.'}
      ],
    };

void main() {
  test('a valid mod.json is parsed into themes, templates and AI actions', () {
    final m = Mod.parse(_manifest(), (_) => false);
    expect(m.id, 'rafa.otono');
    expect(m.themes.single.id, 'mod:rafa.otono:otono');
    expect(m.themes.single.light.accent, const Color(0xFFC2571A));
    expect(m.templates.single.name, 'Estudio');
    expect(m.aiActions.single.prompt, contains('examen'));
  });

  test('invalid mods are rejected with a clear reason', () {
    expect(() => Mod.parse({..._manifest(), 'format': 2}, (_) => true),
        throwsA(isA<ModError>()));
    expect(() => Mod.parse({..._manifest(), 'id': '../x'}, (_) => true),
        throwsA(isA<ModError>()));
    final badColor = _manifest();
    ((badColor['themes'] as List).first['light'] as Map)['accent'] = 'rojo';
    expect(() => Mod.parse(badColor, (_) => true), throwsA(isA<ModError>()));
    expect(
        () => Mod.parse({
              ..._manifest(),
              'fonts': [
                {'name': 'X', 'file': '../evil.ttf'}
              ]
            }, (_) => true),
        throwsA(isA<ModError>()));
    expect(
        () => Mod.parse(
            {'format': 1, 'id': 'vacio.mod', 'name': 'Vacío'}, (_) => true),
        throwsA(isA<ModError>()));
  });

  test('a zip without mod.json is not a mod', () async {
    final zip = ZipEncoder().encode(
        Archive()..addFile(ArchiveFile('otro.json', 2, utf8.encode('{}'))));
    expect(() => Mods.instance.install(Uint8List.fromList(zip)),
        throwsA(isA<ModError>()));
  });

  test('mod themes join the theme list', () {
    final m = Mod.parse(_manifest(), (_) => false);
    modThemes.add(m.themes.single);
    addTearDown(modThemes.clear);
    expect(themeById('mod:rafa.otono:otono').name, 'Otoño');
    expect(appThemes.length, greaterThan(18));
  });
}
