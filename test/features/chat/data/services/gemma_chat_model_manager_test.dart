import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/features/chat/data/services/gemma_chat_model_manager.dart';
import 'package:sinapsis/features/chat/domain/entities/chat_model_option.dart';

/// De dónde se baja cada modelo de lenguaje. La instalación no se puede
/// probar sin el plugin real (ver `gemma_embedding_model_manager_test.dart`),
/// pero la dirección sí, y es lo que falló en el teléfono: Gemma 4 se
/// resolvía leyendo un `litertlm_manifest.json` que sus repositorios no
/// publican, y la descarga terminaba en un 404.
void main() {
  // Los archivos que publica cada repositorio, tal cual los lista Hugging
  // Face (consultado el 2026-10-03).
  const published = {
    ChatModelOption.gemma4E4b:
        'https://huggingface.co/litert-community/gemma-4-E4B-it-litert-lm/resolve/main/gemma-4-E4B-it.litertlm',
    ChatModelOption.gemma3nE4b:
        'https://huggingface.co/google/gemma-3n-E4B-it-litert-lm/resolve/main/gemma-3n-E4B-it-int4.litertlm',
    ChatModelOption.gemma412b:
        'https://huggingface.co/litert-community/gemma-4-12B-it-litert-lm/resolve/main/gemma-4-12B-it.litertlm',
  };

  test('cada opción baja un archivo concreto de su repositorio, sin '
      'depender de un manifiesto', () {
    for (final option in ChatModelOption.values) {
      expect(
        GemmaChatModelManager.downloadUrlOf(option),
        published[option],
        reason: option.name,
      );
    }
  });

  test('para teléfonos, el archivo general y no las variantes de escritorio '
      'o de navegador', () {
    final url = GemmaChatModelManager.downloadUrlOf(ChatModelOption.gemma4E4b);

    expect(url, isNot(contains('-gpu')));
    expect(url, isNot(contains('-web')));
  });
}
