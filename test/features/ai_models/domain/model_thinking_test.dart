import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/features/ai_models/domain/entities/ai_provider.dart';
import 'package:sinapsis/features/ai_models/domain/services/model_thinking.dart';

void main() {
  group('quién puede «pensar más» (F42)', () {
    test('Gemma en el teléfono no tiene cómo, sea cual sea la variante', () {
      for (final model in ['gemma4E4b', 'gemma3nE4b', 'gemma412b']) {
        expect(
          thinkMoreSupport(AiProvider.gemma, model),
          ThinkMoreSupport.onDevice,
        );
      }
    });

    test('Gemini del 2.5 en adelante sí; los anteriores, no', () {
      for (final model in [
        'gemini-2.5-flash',
        'gemini-2.5-flash-lite',
        'gemini-2.5-pro',
        'gemini-3-pro',
        'gemini-3.8-flash',
        'gemini-4-argon',
      ]) {
        expect(
          thinkMoreSupport(AiProvider.gemini, model),
          ThinkMoreSupport.supported,
          reason: model,
        );
      }
      for (final model in ['gemini-2.0-flash', 'gemini-1.5-pro', 'otro']) {
        expect(
          thinkMoreSupport(AiProvider.gemini, model),
          ThinkMoreSupport.notThisModel,
          reason: model,
        );
      }
    });

    test('OpenAI: los que razonan; no los `-chat` ni los 4', () {
      for (final model in ['gpt-5.2', 'gpt-5-mini', 'o3', 'o4-mini']) {
        expect(
          thinkMoreSupport(AiProvider.openAi, model),
          ThinkMoreSupport.supported,
          reason: model,
        );
      }
      for (final model in ['gpt-4.1', 'gpt-4o-mini', 'gpt-5-chat-latest']) {
        expect(
          thinkMoreSupport(AiProvider.openAi, model),
          ThinkMoreSupport.notThisModel,
          reason: model,
        );
      }
    });

    test('Claude: la familia 5; no los 4', () {
      for (final model in [
        'claude-opus-5-5',
        'claude-sonnet-5-5',
        'claude-haiku-5-5',
        'claude-fable-5-1',
        'claude-opus-5',
      ]) {
        expect(
          thinkMoreSupport(AiProvider.anthropic, model),
          ThinkMoreSupport.supported,
          reason: model,
        );
      }
      for (final model in ['claude-opus-4-8', 'claude-sonnet-4-5']) {
        expect(
          thinkMoreSupport(AiProvider.anthropic, model),
          ThinkMoreSupport.notThisModel,
          reason: model,
        );
      }
    });

    test('los espacios de más no cambian nada', () {
      expect(
        thinkMoreSupport(AiProvider.gemini, ' gemini-3.8-flash '),
        ThinkMoreSupport.supported,
      );
    });

    test('la versión de un Gemini, como números', () {
      expect(geminiGeneration('gemini-2.5-flash'), (2, 5));
      expect(geminiGeneration('gemini-3-pro'), (3, 0));
      expect(geminiGeneration('gemini-3.10-flash'), (3, 10));
      expect(geminiGeneration('claude-opus-5'), isNull);
    });
  });
}
