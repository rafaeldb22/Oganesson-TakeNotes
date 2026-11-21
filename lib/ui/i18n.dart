import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'i18n_en.dart';

/// Idioma de la app: español (por defecto) o inglés.
///
/// Los textos se escriben en español en el código y se traducen con [tr]:
/// `Text(tr('Buscar'))`. Las traducciones al inglés están en `i18n_en.dart`
/// (si falta alguna se muestra el texto en español).
class AppLanguage extends ChangeNotifier {
  static const _key = 'idioma';
  static const supported = {'es': 'Español', 'en': 'English'};

  String code = _systemDefault();

  static String _systemDefault() {
    final sys = WidgetsBinding.instance.platformDispatcher.locale.languageCode;
    return sys == 'en' ? 'en' : 'es';
  }

  bool get isEnglish => code == 'en';
  Locale get locale => Locale(code);

  Future<void> load() async {
    try {
      final saved = (await SharedPreferences.getInstance()).getString(_key);
      if (saved != null && supported.containsKey(saved) && saved != code) {
        code = saved;
        notifyListeners();
      }
    } catch (_) {}
  }

  Future<void> set(String c) async {
    if (c == code || !supported.containsKey(c)) return;
    code = c;
    notifyListeners();
    try {
      await (await SharedPreferences.getInstance()).setString(_key, c);
    } catch (_) {}
  }
}

final appLanguage = AppLanguage();

/// Traduce un texto escrito en español al idioma actual.
String tr(String es) => appLanguage.isEnglish ? (enStrings[es] ?? es) : es;

/// Traduce una plantilla con `{0}`, `{1}`… y la rellena.
/// `trf('Quedan {0} días', [3])`.
String trf(String es, List<Object?> args) {
  var s = tr(es);
  for (var i = 0; i < args.length; i++) {
    s = s.replaceAll('{$i}', '${args[i]}');
  }
  return s;
}

/// Singular/plural: `trn(n, '{0} nota', '{0} notas')`.
String trn(int n, String one, String many) => trf(n == 1 ? one : many, [n]);
