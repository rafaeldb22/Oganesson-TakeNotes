import 'package:flutter_test/flutter_test.dart';
import 'package:notas/data/updater.dart';

void main() {
  test('saca la versión y el instalador de la redirección', () {
    final r = releaseFromRedirect(
        'https://github.com/u/app/releases/tag/v2.6.0',
        'u/app',
        'Oganesson-Setup.exe')!;
    expect(r.version, '2.6.0');
    expect(r.downloadUrl,
        'https://github.com/u/app/releases/download/v2.6.0/Oganesson-Setup.exe');
    expect(compareVersions(r.version, '2.5.0'), greaterThan(0));
  });

  test('sin versiones publicadas no ofrece nada', () {
    expect(
        releaseFromRedirect('https://github.com/u/app/releases', 'u/app', 'a'),
        isNull);
    expect(releaseFromRedirect(null, 'u/app', 'a'), isNull);
  });
}
