import 'package:flutter_test/flutter_test.dart';
import 'package:notas/data/ai_assistant.dart';
import 'package:notas/data/note_attachments.dart';
import 'package:notas/data/notes_repository.dart';
import 'package:notas/data/similar_notes.dart';
import 'package:notas/data/smart_groups.dart';
import 'package:notas/ui/i18n.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

NotesRepository _repo() => NotesRepository(
    SupabaseClient('http://127.0.0.1:9', 'k',
        authOptions: const AuthClientOptions(autoRefreshToken: false)),
    'demo')
  ..loaded = true;

void main() {
  setUp(() {
    appLanguage.code = 'es';
    SharedPreferences.setMockInitialValues({});
  });

  test('text can be inserted after a given line to continue a list', () {
    final (content, _) = withTextAfter(
        'Compra\n- leche\n- pan\nOtra cosa', null, '- pan', '- huevos');
    expect(content, 'Compra\n- leche\n- pan\nhuevos\nOtra cosa');
    final (fallback, _) =
        withTextAfter('Nota\nfin', null, 'no existe', 'extra');
    expect(fallback, 'Nota\nfin\nextra');
  });

  test('the AI can search the web and read what was written on a day',
      () async {
    final r = _repo();
    final n = r.createNote();
    r.updateContent(n.id, 'Diario\nHoy he estudiado física');
    final tools = AiTools(r,
        confirm: (_) async => true,
        webSearch: (q) async => {
              'answer': 'Respuesta sobre $q',
              'sources': [
                {'title': 'Fuente', 'url': 'https://example.com'}
              ],
            });
    final web = await tools.run('web_search', {'query': 'clima'});
    expect(web['answer'], 'Respuesta sobre clima');
    final today = DateTime.now();
    final day = await tools.run('notes_of_day', {
      'date':
          '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}'
    });
    expect((day['notes'] as List).single['title'], 'Diario');
    r.dispose();
  });

  test('AI groups notes by type and only asks for new ones', () async {
    final r = _repo();
    final a = r.createNote(), b = r.createNote();
    r.updateContent(a.id, 'Entrega de física');
    r.updateContent(b.id, 'Comprar pan');
    var calls = 0;
    Future<String> ask(String system, String user) async {
      calls++;
      expect(user, contains('Entrega de física'));
      return '{"0":"Entregas","1":"Compras"}';
    }

    final g = SmartGroups.instance;
    await g.classify(r.notes, ask: ask);
    expect(g.categoryOf(r.byId(a.id)!), isNotNull);
    expect({g.categoryOf(a), g.categoryOf(b)}, {'Entregas', 'Compras'});
    await g.classify(r.notes, ask: ask);
    expect(calls, 1);
    r.dispose();
  });

  test('similar notes are detected without AI and can be ignored', () async {
    final r = _repo();
    final a = r.createNote(), b = r.createNote(), c = r.createNote();
    r.updateContent(a.id,
        'Entrega física\nPracticas de laboratorio péndulo simple informe');
    r.updateContent(b.id,
        'Entrega de fisica\npracticas laboratorio pendulo informe simple');
    r.updateContent(c.id, 'Receta\nTortilla de patatas con cebolla y huevos');
    expect(SimilarNotes.mostSimilar(a, r.notes)?.id, b.id);
    expect(SimilarNotes.mostSimilar(c, r.notes), isNull);
    await SimilarNotes.ignore(a.id);
    expect(await SimilarNotes.ignored(), contains(a.id));
    r.dispose();
  });
}
