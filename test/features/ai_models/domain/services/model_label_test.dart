import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/features/ai_models/domain/services/model_label.dart';
import 'package:sinapsis/features/chat/domain/entities/chat_model_option.dart';

/// Cómo se le muestra a la persona el modelo que hizo algo (F33).
void main() {
  test('Gemini, con cada palabra en mayúscula', () {
    expect(modelLabel('gemini-3.8-flash'), 'Gemini 3.8 Flash');
    expect(modelLabel('gemini-3.8-flash-lite'), 'Gemini 3.8 Flash Lite');
  });

  test('Claude, con la versión con punto y sin la fecha', () {
    expect(modelLabel('claude-opus-5-5'), 'Claude Opus 5.5');
    expect(modelLabel('claude-sonnet-5'), 'Claude Sonnet 5');
    expect(modelLabel('claude-haiku-4-5-20251001'), 'Claude Haiku 4.5');
  });

  test('GPT como lo escribe OpenAI, y la serie «o» tal cual', () {
    expect(modelLabel('gpt-5.2-mini'), 'GPT-5.2 mini');
    expect(modelLabel('gpt-5'), 'GPT-5');
    expect(modelLabel('o4-mini'), 'o4-mini');
  });

  test('Gemma en el teléfono, como la nombra la pantalla del modelo', () {
    expect(modelLabel('gemma4E4b'), 'Gemma 4 E4B');
    expect(modelLabel('gemma3nE4b'), 'Gemma 3n E4B');
    expect(modelLabel('gemma412b'), 'Gemma 4 12B');
    expect(isLocalGemma('gemma412b'), isTrue);
    expect(isLocalGemma('gemma-3-27b-it'), isFalse);
  });

  test('toda variante de Gemma tiene su nombre para leer', () {
    for (final option in ChatModelOption.values) {
      expect(isLocalGemma(option.name), isTrue, reason: option.name);
      expect(modelLabel(option.name), startsWith('Gemma '));
    }
  });

  test('lo que no se conoce, como viene', () {
    expect(modelLabel('Gemma 4 E4B'), 'Gemma 4 E4B');
    expect(modelLabel('  otro-modelo '), 'otro-modelo');
    expect(isLocalGemma('otro-modelo'), isFalse);
  });
}
