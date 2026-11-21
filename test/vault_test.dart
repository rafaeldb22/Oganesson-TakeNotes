import 'package:flutter_test/flutter_test.dart';
import 'package:notas/data/vault.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('crear contraseña, bloquear, desbloquear y cambiarla', () async {
    SharedPreferences.setMockInitialValues({});
    final v = VaultLock.forUser('u1');
    await v.load();
    expect(v.state, VaultState.notSet);
    await v.setPassword('secreta1');
    expect(v.unlocked, isTrue);
    final raw =
        (await SharedPreferences.getInstance()).getString('vault_pass_u1')!;
    expect(raw.contains('secreta1'), isFalse); // solo el hash
    v.lock();
    expect(await v.unlock('mala'), isFalse);
    expect(await v.unlock('secreta1'), isTrue);
    await v.setPassword('nueva-clave');
    v.lock();
    expect(await v.unlock('secreta1'), isFalse);
    expect(await v.unlock('nueva-clave'), isTrue);
    v.lock();
  });

  test('espera tras 5 intentos fallidos', () async {
    SharedPreferences.setMockInitialValues({});
    final v = VaultLock.forUser('u2');
    await v.load();
    await v.setPassword('secreta1');
    v.lock();
    for (var i = 0; i < 5; i++) {
      expect(await v.unlock('x$i'), isFalse);
    }
    expect(v.blockedSeconds, greaterThan(0));
    expect(await v.unlock('secreta1'), isFalse);
  });
}
