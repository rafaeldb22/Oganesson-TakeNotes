import 'package:flutter_test/flutter_test.dart';
import 'package:notas/data/ai_assistant.dart';

void main() {
  test('Gemini 4 Hydrogen gets thinkingLevel; older models get no config',
      () async {
    final bodies = <Map<String, dynamic>?>[];
    final c = GeminiClient(transport: (m, u, h, b) async {
      bodies.add(b);
      return (
        200,
        <String, dynamic>{
          'candidates': [
            {
              'content': {
                'parts': [
                  {'text': 'hola'}
                ]
              }
            }
          ]
        }
      );
    });
    for (final model in ['gemini-4-hydrogen', 'gemini-3.5-flash-lite']) {
      await c.complete(
          apiKey: 'k',
          model: model,
          system: 's',
          history: [c.userMessage('hola')],
          tools: const []);
    }
    expect(bodies[0]!['generationConfig'], {
      'thinkingConfig': {'thinkingLevel': 'low'}
    });
    expect(bodies[1]!.containsKey('generationConfig'), isFalse);
    await c.check('k', 'gemini-4-hydrogen');
    final probe = bodies.last!['generationConfig'] as Map;
    expect(probe['maxOutputTokens'], greaterThan(8));
    expect(probe['thinkingConfig'], {'thinkingLevel': 'low'});
    expect(AiProvider.gemini.models.map((m) => m.id),
        contains('gemini-4-hydrogen'));
  });
}
