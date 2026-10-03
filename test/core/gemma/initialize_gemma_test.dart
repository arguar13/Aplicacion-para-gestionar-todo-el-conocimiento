import 'package:flutter_gemma/core/registry/embedding_backend_provider.dart';
import 'package:flutter_gemma/core/registry/inference_engine_provider.dart';
import 'package:flutter_gemma_litertlm/flutter_gemma_litertlm.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/gemma/initialize_gemma.dart';

/// `flutter_gemma` 1.8 no registra ningún motor por su cuenta: lo que no se
/// le pasa al arrancar falta recién al usarlo. Sin el de los vectores, el
/// modelo de relaciones se bajaba e instalaba, y el primer
/// `getActiveEmbedder()` lanzaba «No embedding backend registered».
void main() {
  late List<InferenceEngineProvider> engines;
  late List<EmbeddingBackendProvider> backends;

  Future<void> record({
    List<InferenceEngineProvider> inferenceEngines = const [],
    List<EmbeddingBackendProvider> embeddingBackends = const [],
  }) async {
    engines = inferenceEngines;
    backends = embeddingBackends;
  }

  test('registra el motor de vectores: sin él, el modelo de relaciones no '
      'calcula nada', () async {
    await initializeGemma(initialize: record);

    expect(backends, [isA<LiteRtEmbeddingBackend>()]);
  });

  test(
    'registra el motor del modelo de lenguaje, el que lee .litertlm',
    () async {
      await initializeGemma(initialize: record);

      expect(engines, [isA<LiteRtLmEngine>()]);
    },
  );
}
