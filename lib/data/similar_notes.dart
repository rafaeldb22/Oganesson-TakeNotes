import 'package:shared_preferences/shared_preferences.dart';

import '../models/note.dart';

/// Filtro de duplicados sin IA: compara las palabras con contenido de dos
/// notas (sin acentos, sin palabras vacías) y avisa si tratan de lo mismo.
class SimilarNotes {
  static const _stop = {
    'para',
    'como',
    'pero',
    'porque',
    'cuando',
    'donde',
    'este',
    'esta',
    'esto',
    'estos',
    'estas',
    'unos',
    'unas',
    'sobre',
    'entre',
    'hasta',
    'desde',
    'tambien',
    'muy',
    'todo',
    'toda',
    'todos',
    'todas',
    'that',
    'this',
    'with',
    'from',
    'have',
    'there',
    'their',
    'what',
    'about',
    'which',
    'when',
    'will',
    'your',
    'nota',
    'notas',
    'note',
    'notes',
  };

  static String _fold(String s) {
    const from = 'áàäâãéèëêíìïîóòöôõúùüûñç', to = 'aaaaaeeeeiiiiooooouuuunc';
    final out = StringBuffer();
    for (final c in s.toLowerCase().split('')) {
      final i = from.indexOf(c);
      out.write(i < 0 ? c : to[i]);
    }
    return out.toString();
  }

  /// Palabras de 4 letras o más, sin las vacías.
  static Set<String> words(String text) => {
        for (final w in _fold(text).split(RegExp(r'[^a-z0-9]+')))
          if (w.length >= 4 && !_stop.contains(w)) w,
      };

  static double _jaccard(Set<String> a, Set<String> b) {
    if (a.isEmpty || b.isEmpty) return 0;
    final inter = a.intersection(b).length;
    return inter / (a.length + b.length - inter);
  }

  /// Parecido entre 0 y 1: el título pesa más que el resto.
  static double score(Note a, Note b) {
    final ta = words(a.title), tb = words(b.title);
    final ca = words(a.content), cb = words(b.content);
    final title = _jaccard(ta, tb);
    final body = _jaccard(ca, cb);
    // Con muy poco texto no se puede decir nada.
    if (ca.length < 3 || cb.length < 3) return title >= 0.99 ? title : 0;
    final mix = title * 0.5 + body * 0.5;
    return mix > body ? mix : body;
  }

  static const threshold = 0.55;

  /// La nota más parecida a [n] (o null si ninguna llega al umbral).
  static Note? mostSimilar(Note n, Iterable<Note> others) {
    Note? best;
    var top = threshold;
    for (final o in others) {
      if (o.id == n.id || o.isEmpty || o.vault) continue;
      final s = score(n, o);
      if (s >= top) {
        top = s;
        best = o;
      }
    }
    return best;
  }

  static const _kIgnored = 'duplicados_ignorados';

  /// Notas para las que el usuario ya dijo "ignorar".
  static Future<Set<String>> ignored() async {
    try {
      return (await SharedPreferences.getInstance())
              .getStringList(_kIgnored)
              ?.toSet() ??
          {};
    } catch (_) {
      return {};
    }
  }

  static Future<void> ignore(String noteId) async {
    final all = await ignored()
      ..add(noteId);
    try {
      await (await SharedPreferences.getInstance())
          .setStringList(_kIgnored, all.take(500).toList());
    } catch (_) {}
  }
}
