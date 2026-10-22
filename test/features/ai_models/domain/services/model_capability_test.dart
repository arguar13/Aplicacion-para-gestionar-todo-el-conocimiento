import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/features/ai_models/domain/services/model_capability.dart';

/// Cuándo un modelo es más capaz que otro (F33, decisión D): lo que decide
/// el aviso al cambiar de modelo.
void main() {
  bool better(String? previous, String next) =>
      isMoreCapableModel(previous: previous, next: next);

  test('uno en la nube, después de Gemma en el teléfono', () {
    for (final next in [
      'gemini-3.8-flash-lite',
      'claude-haiku-4-5',
      'gpt-5-nano',
    ]) {
      expect(better('gemma4E4b', next), isTrue, reason: next);
      expect(better('gemma412b', next), isTrue, reason: next);
      // Una pasada sin el modelo anotado era de Gemma.
      expect(better(null, next), isTrue, reason: next);
      expect(better(next, 'gemma412b'), isFalse, reason: next);
    }
  });

  test('entre las variantes de Gemma, la de 12B', () {
    expect(better('gemma4E4b', 'gemma412b'), isTrue);
    expect(better('gemma3nE4b', 'gemma412b'), isTrue);
    expect(better('gemma412b', 'gemma4E4b'), isFalse);
    expect(better('gemma4E4b', 'gemma3nE4b'), isFalse);
    // De una pasada sin el modelo no se sabe cuál era.
    expect(better(null, 'gemma412b'), isFalse);
  });

  test('en Gemini, Pro sobre Flash y Flash sobre Flash Lite', () {
    expect(better('gemini-3.8-flash-lite', 'gemini-3.8-flash'), isTrue);
    expect(better('gemini-3.8-flash', 'gemini-3.8-pro'), isTrue);
    expect(better('gemini-3.8-flash-lite', 'gemini-3.8-pro'), isTrue);
    expect(better('gemini-3.8-pro', 'gemini-3.8-flash'), isFalse);
    expect(better('gemini-3.8-flash', 'gemini-3.8-flash-lite'), isFalse);
    // Otra versión del mismo tamaño no es más grande.
    expect(better('gemini-3.5-flash', 'gemini-3.8-flash'), isFalse);
  });

  test('en Claude, Opus o Fable sobre Sonnet y Sonnet sobre Haiku', () {
    expect(better('claude-haiku-4-5-20251001', 'claude-sonnet-5'), isTrue);
    expect(better('claude-sonnet-5-5', 'claude-opus-5-5'), isTrue);
    expect(better('claude-sonnet-5-5', 'claude-fable-5-1'), isTrue);
    expect(better('claude-opus-5-5', 'claude-sonnet-5-5'), isFalse);
    expect(better('claude-opus-5-5', 'claude-fable-5-1'), isFalse);
  });

  test('en OpenAI, el entero sobre mini y mini sobre nano', () {
    expect(better('gpt-5-nano', 'gpt-5.2-mini'), isTrue);
    expect(better('gpt-5.2-mini', 'gpt-5.2'), isTrue);
    expect(better('o4-mini', 'o3'), isTrue);
    expect(better('gpt-5.2', 'gpt-5.2-mini'), isFalse);
  });

  test('entre proveedores distintos, o con uno que no se conoce, no se '
      'sabe', () {
    expect(better('gemini-3.8-flash-lite', 'claude-opus-5-5'), isFalse);
    expect(better('claude-haiku-4-5', 'gpt-5.2'), isFalse);
    expect(better('gpt-5-nano', 'gemini-3.8-pro'), isFalse);
    expect(better('otro-modelo', 'gemini-3.8-pro'), isFalse);
    expect(better('gemma4E4b', 'otro-modelo'), isFalse);
    // Gemma servida por Gemini en la nube no es la del teléfono.
    expect(better('gemma-3-27b-it', 'gemini-3.8-pro'), isFalse);
    expect(better('gemini-3.8-ultra', 'gemini-3.8-pro'), isFalse);
  });
}
