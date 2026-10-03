import 'package:flutter_gemma/core/registry/embedding_backend_provider.dart';
import 'package:flutter_gemma/core/registry/inference_engine_provider.dart';
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:flutter_gemma_litertlm/flutter_gemma_litertlm.dart';

/// Lo que arranca `flutter_gemma`: `FlutterGemma.initialize` en la app, un
/// doble en las pruebas. Solo con los dos parámetros que la app usa; el
/// método real acepta más, todos opcionales.
typedef GemmaInitializer =
    Future<void> Function({
      List<InferenceEngineProvider> inferenceEngines,
      List<EmbeddingBackendProvider> embeddingBackends,
    });

/// Arranca `flutter_gemma` con todo lo que la app usa de él.
///
/// Requisito del propio paquete: ninguna otra API de `flutter_gemma`
/// —`installModel`, `hasActiveModel`, `getActiveModel`— funciona sin esto.
/// Sin inicializar, cualquier llamada revienta con un `StateError` interno
/// del paquete que no tiene nada que ver con la red ni con el token, y
/// terminaba mostrándose como el mismo error genérico de "no se pudo
/// descargar" sin importar la causa real.
///
/// Desde la versión 1.8 los motores son **opcionales y explícitos**: el
/// paquete no registra ninguno por su cuenta, y lo que falta se descubre
/// recién al usarlo.
///
/// - `LiteRtLmEngine` entiende el formato `.litertlm` del modelo de lenguaje
///   (ver la decisión 20 en docs/arquitectura.md).
/// - `LiteRtEmbeddingBackend` es el que calcula los vectores del modelo de
///   relaciones. Faltaba: el modelo se bajaba y se instalaba bien, pero el
///   primer `getActiveEmbedder()` lanzaba «No embedding backend registered»,
///   así que el modelo de relaciones no funcionaba nunca, ni siquiera en la
///   misma sesión en que se bajó.
Future<void> initializeGemma({
  GemmaInitializer initialize = FlutterGemma.initialize,
}) => initialize(
  inferenceEngines: const [LiteRtLmEngine()],
  embeddingBackends: const [LiteRtEmbeddingBackend()],
);
