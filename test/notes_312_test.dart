import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:notas/data/ai_actions.dart';
import 'package:notas/data/note_board.dart';
import 'package:notas/data/note_export.dart';
import 'package:notas/data/notes_repository.dart';
import 'package:notas/data/vault.dart';
import 'package:notas/ui/i18n.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

NotesRepository _repo() => NotesRepository(
    SupabaseClient('http://127.0.0.1:9', 'k',
        authOptions: const AuthClientOptions(autoRefreshToken: false)),
    'demo')
  ..loaded = true;

BoardData _board(String id, double y) => BoardData(id: id, strokes: [
      BoardStroke(0, 3, [Offset(10, y), Offset(200, y)], [1, 1])
    ]);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    appLanguage.code = 'es';
    SharedPreferences.setMockInitialValues({});
  });

  test('a note keeps several whiteboards, each saved and removed by id', () {
    var (content, rich) = BoardData.store('Nota', null, _board('a', 10));
    (content, rich) = BoardData.store(content, rich, _board('b', 50));
    expect(BoardData.all(rich).map((b) => b.id), ['a', 'b']);
    // Guardar la "b" no toca la "a".
    final b2 = _board('b', 90)..strokes.add(_board('x', 120).strokes.first);
    (content, rich) = BoardData.store(content, rich, b2);
    expect(BoardData.of(rich, id: 'a')!.strokes, hasLength(1));
    expect(BoardData.of(rich, id: 'b')!.strokes, hasLength(2));
    (content, rich) = BoardData.remove(content, rich, id: 'a');
    expect(BoardData.all(rich).map((b) => b.id), ['b']);
  });

  test('board-only notes export the board; boards render to PNG', () async {
    final r = _repo();
    final n = r.createNote();
    final (content, rich) = BoardData.store('', null, _board('a', 10));
    r.updateContent(n.id, content, rich: rich);
    expect(isBoardOnly(r.byId(n.id)!), isTrue);
    final pngs = await boardImages(r.byId(n.id)!, load: (_) async => null);
    expect(pngs.single.length, greaterThan(100));
    r.updateContent(n.id, 'Título\n$content', rich: null);
    r.dispose();
  });

  test('trash items deleted forever elsewhere leave this device too', () {
    final r = _repo();
    final a = r.createNote(), b = r.createNote();
    r.updateContent(a.id, 'A');
    r.updateContent(b.id, 'B');
    r.delete(a.id);
    r.delete(b.id);
    // Como si ya se hubieran subido.
    r.debugMarkClean();
    expect(r.purgeMissing({b.id}), isTrue);
    expect(r.byId(a.id), isNull);
    expect(r.byId(b.id), isNotNull);
    r.dispose();
  });

  test('the Vault can open with a PIN, and the password still works', () async {
    final v = VaultLock.forUser('pin-user');
    await v.load();
    await v.setPassword('secreta1');
    expect(VaultLock.validPin('12'), isFalse);
    await v.setPin('2468');
    expect(v.hasPin && v.usePin, isTrue);
    v.lock();
    expect(await v.unlockWithPin('1111'), isFalse);
    expect(await v.unlockWithPin('2468'), isTrue);
    v.lock();
    expect(await v.unlock('secreta1'), isTrue);
    // Cambiar la contraseña conserva el PIN.
    await v.setPassword('otra-clave');
    v.lock();
    expect(await v.unlockWithPin('2468'), isTrue);
    await v.setUsePin(false);
    expect(v.usePin, isFalse);
    v.lock();
  });

  test('AI link suggestions map numbers back to notes', () async {
    final r = _repo();
    final a = r.createNote(), b = r.createNote(), c = r.createNote();
    r.updateContent(a.id, 'Física\nPráctica del péndulo');
    r.updateContent(b.id, 'Informe péndulo');
    r.updateContent(c.id, 'Compra');
    final ids = await suggestLinks(r, r.byId(a.id)!,
        ask: (s, u) async => u.contains('Informe péndulo') ? '[0, 99]' : '[]');
    // La más reciente sale la primera (índice 0): la "Compra".
    expect(ids, hasLength(1));
    expect(ids.single, isNot(a.id));
    r.dispose();
  });
}
