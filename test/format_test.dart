import 'package:flutter_test/flutter_test.dart';
import 'package:notas/ui/format.dart';
import 'package:notas/ui/i18n.dart';

void main() {
  setUp(() => appLanguage.code = 'es');

  test('duracionTexto redondea minutos y omite partes a cero', () {
    expect(duracionTexto(const Duration(hours: 6, minutes: 24, seconds: 40)),
        '6 h 25 min');
    expect(duracionTexto(const Duration(days: 2)), '2 d');
    expect(duracionTexto(const Duration(days: 2, hours: 3)), '2 d 3 h');
    expect(duracionTexto(const Duration(hours: 5)), '5 h');
    expect(duracionTexto(const Duration(minutes: 45)), '45 min');
    expect(duracionTexto(const Duration(minutes: 59, seconds: 50)), '1 h');
  });

  test('tiempoRestante: futuro, pasado y ahora', () {
    final now = DateTime.now().toUtc();
    expect(tiempoRestante(now.add(const Duration(hours: 6, minutes: 25))),
        'quedan 6 h 25 min');
    expect(tiempoRestante(now.subtract(const Duration(hours: 3))),
        'vencida hace 3 h');
    expect(tiempoRestante(now.add(const Duration(seconds: 10))), 'vence ahora');
    expect(tiempoRestante(now, done: true), 'completada');
  });

  test('inglés', () {
    appLanguage.code = 'en';
    final now = DateTime.now().toUtc();
    expect(tiempoRestante(now.add(const Duration(hours: 2))), '2 h left');
    expect(tr('Fijadas'), 'Pinned');
    expect(trn(3, '{0} nota', '{0} notas'), '3 notes');
  });
}
