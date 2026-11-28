import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:notas/data/ai_assistant.dart';
import 'package:notas/data/note_images.dart';
import 'package:notas/data/notes_repository.dart';
import 'package:notas/models/note.dart';
import 'package:notas/ui/i18n.dart';
import 'package:notas/ui/urgency.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

Note _note(String id, DateTime? remind, DateTime due, {int? color}) {
  final t = DateTime.utc(2030);
  return Note(
      id: id,
      content: id,
      createdAt: t,
      updatedAt: t,
      remindAt: remind?.toUtc(),
      dueAt: due.toUtc(),
      color: color);
}

void main() {
  setUp(() {
    appLanguage.code = 'es';
    SharedPreferences.setMockInitialValues({});
  });

  test('las de un solo día van primero y sin degradado', () {
    final day = DateTime(2030, 3, 15, 18);
    final single = _note('s', Note.dayStart(day), day, color: 0xFF3B6FE0);
    final period = _note('p', DateTime(2030, 3, 1), DateTime(2030, 3, 14),
        color: 0xFFE5484D);
    final list = [period, single]..sort(Note.calendarOrder);
    expect(list.first.id, 's');
    final colors = notePalette(single);
    expect(colors.toSet(), hasLength(1));
    expect(colors.first.toARGB32(), 0xFF3B6FE0);
    expect(notePalette(period).toSet().length, greaterThan(1));
  });

  test('el tamaño de la imagen no cambia su ruta', () {
    const src = 'sb://u/img?w=800&h=600';
    expect(NoteImages.scaleOf(src), 100);
    final small = NoteImages.withScale(src, 50);
    expect(NoteImages.scaleOf(small), 50);
    expect(NoteImages.pathOf(small), 'u/img');
    expect(NoteImages.sizeOf(small)!.width, 800);
    expect(NoteImages.pathsIn('{"image":"$small"}'), {'u/img'});
    expect(NoteImages.scaleOf(NoteImages.withScale(small, 100)), 100);
    expect(NoteImages.withScale(small, 100), src);
    expect(NoteImages.scaleOf('sb://u/i?w=1&h=1&z=1'), 20);
    expect(NoteImages.scaleOf('sb://u/i?w=1&h=1&z=abc'), 100);
  });

  group('la IA mira las imágenes', () {
    NotesRepository repo() => NotesRepository(
        SupabaseClient('http://127.0.0.1:9', 'clave-de-prueba',
            authOptions: const AuthClientOptions(autoRefreshToken: false)),
        'demo')
      ..loaded = true;

    const rich = '[{"insert":{"image":"sb://demo/a?w=1&h=1"}},'
        '{"insert":{"image":"sb://demo/b?w=1&h=1&z=50"}},{"insert":"x\\n"}]';

    test('devuelve el contenido y marca la nota como fuente', () async {
      final r = repo();
      final n = r.createNote();
      r.updateContent(n.id, '￼￼x\n', rich: rich);
      final asked = <String>[];
      final tools = AiTools(r,
          confirm: (_) async => false,
          loadImage: (p) async {
            asked.add(p);
            return p.endsWith('b') ? null : Uint8List.fromList([1, 2, 3]);
          },
          readImage: (_, __, prompt) async {
            expect(prompt, aiImagePrompt);
            return ' Factura de 20 euros ';
          });
      final res = await tools.run('read_note_images', {'id': n.id});
      expect(asked, ['demo/a', 'demo/b']);
      final images = res['images'] as List;
      expect(images[0]['content'], 'Factura de 20 euros');
      expect(images[1]['error'], isNotNull);
      expect(tools.sources, {n.id});
      r.dispose();
    });

    test('nunca lee imágenes del Vault', () async {
      final r = repo();
      final n = r.createNote();
      r.updateContent(n.id, '￼\n', rich: rich);
      r.setVault(n.id, true);
      var read = false;
      final tools = AiTools(r,
          confirm: (_) async => false,
          loadImage: (_) async {
            read = true;
            return Uint8List(1);
          },
          readImage: (_, __, ___) async => 'x');
      final res = await tools.run('read_note_images', {'id': n.id});
      expect(res['error'], isNotNull);
      expect(read, isFalse);
      r.dispose();
    });
  });
}
