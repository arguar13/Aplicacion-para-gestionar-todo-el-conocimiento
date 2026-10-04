import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:sinapsis/features/chat/data/services/gemma_engine.dart';
import 'package:sinapsis/features/chat/data/services/gemma_reply.dart';
import 'package:sinapsis/features/chat/data/services/language_model_backend_store.dart';
import 'package:sinapsis/features/chat/domain/entities/language_model_performance.dart';
import 'package:sinapsis/features/chat/domain/services/language_model_gate.dart';
import 'package:sinapsis/features/chat/domain/services/language_model_meter.dart';

/// Lo que se le pide al modelo para medirlo: siempre lo mismo, para que las
/// formas de cargarlo se comparen con el mismo trabajo.
const kBenchmarkPrompt =
    'Escribí un párrafo de unas ochenta palabras sobre la historia de la '
    'escritura, desde las tablillas de arcilla hasta la imprenta.';

/// El tope de la respuesta al medir: lo bastante para medir la velocidad de
/// escritura sin hacer esperar de más.
const kBenchmarkReplyTokens = 96;

/// Mide en el teléfono de verdad en qué parte corre más rápido el modelo de
/// lenguaje, y lo deja elegido (F30). Lo pide la persona desde la pantalla
/// del modelo: carga el modelo de cada forma —unos segundos cada una— y le
/// pide el mismo párrafo.
///
/// Prueba, en orden: la GPU, la CPU y, en la que haya sido más rápida, la
/// decodificación especulativa —el modelo adivina varios tokens por paso y
/// el grande los confirma; con Gemma 4 y `flutter_gemma` ≥ 0.15 puede
/// rendir más, pero depende del teléfono y del archivo del modelo—. Elige
/// la que escribe más tokens por segundo, la recuerda y suelta el modelo:
/// el próximo uso lo carga así. Una forma que no arranca —o la GPU que cae
/// a la CPU sola— queda anotada como que no anduvo.
class LanguageModelBenchmark {
  LanguageModelBenchmark({
    required LanguageModelGate gate,
    required GemmaEngine engine,
    required LanguageModelBackendStore store,
  }) : _gate = gate,
       _engine = engine,
       _store = store;

  final LanguageModelGate _gate;
  final GemmaEngine _engine;
  final LanguageModelBackendStore _store;

  /// Cuántas formas se prueban.
  static const steps = 3;

  /// Mide, elige y recuerda. [progress] avisa cuántas formas van probadas.
  /// Toma el turno del modelo de parte de la persona: la IA de fondo espera.
  Future<List<LanguageModelBenchmarkResult>> run({
    void Function(int done)? progress,
  }) => _gate.runForUser(() async {
    final results = <LanguageModelBenchmarkResult>[];
    try {
      for (final backend in const [
        LanguageModelBackend.gpu,
        LanguageModelBackend.cpu,
      ]) {
        results.add(await _measure(backend));
        progress?.call(results.length);
      }
      final faster = _fastest(results);
      if (faster != null) {
        results.add(await _measure(faster.backend, speculative: true));
        progress?.call(results.length);
      }

      final best = _fastest(results);
      if (best != null) {
        await _store.saveChoice(
          LanguageModelBackendChoice(
            backend: best.backend,
            speculative: best.speculative,
            reason: LanguageModelBackendReason.measured,
          ),
        );
      }
      await _store.saveResults(results);
      return results;
    } finally {
      // El próximo uso lo carga con lo elegido.
      await _engine.release();
    }
  });

  Future<LanguageModelBenchmarkResult> _measure(
    LanguageModelBackend backend, {
    bool? speculative,
  }) async {
    final InferenceModel model;
    try {
      model = await _engine.loadToMeasure(
        backend: backend,
        speculative: speculative,
      );
      // El motor falla de formas sin un tipo propio: lo que importa es que
      // esta forma no anduvo, y por qué.
    } on Object catch (error) {
      return LanguageModelBenchmarkResult(
        backend: backend,
        speculative: speculative,
        failure: '$error',
      );
    }
    if (model.activeBackend != _preferred(backend)) {
      return LanguageModelBenchmarkResult(
        backend: backend,
        speculative: speculative,
        failure: 'cayó a ${model.activeBackend?.name ?? 'otra'}',
      );
    }

    final meter = LanguageModelMeter();
    final chat = await model.createChat(
      systemInstruction: 'Respondé siempre en español.',
      maxOutputTokens: kBenchmarkReplyTokens,
      tokenBuffer: 0,
    );
    try {
      await chat.addQueryChunk(
        Message.text(text: kBenchmarkPrompt, isUser: true),
      );
      await collectReply(chat, meter: meter);
      // Ver arriba.
    } on Object catch (error) {
      return LanguageModelBenchmarkResult(
        backend: backend,
        speculative: speculative,
        failure: '$error',
      );
    } finally {
      await chat.close();
    }
    return LanguageModelBenchmarkResult(
      backend: backend,
      speculative: speculative,
      reply: meter.performance.value.taskReply,
    );
  }

  static LanguageModelBenchmarkResult? _fastest(
    List<LanguageModelBenchmarkResult> results,
  ) {
    LanguageModelBenchmarkResult? best;
    for (final result in results) {
      if (!result.worked) continue;
      if (best == null || result.speed > best.speed) best = result;
    }
    return best;
  }

  static PreferredBackend _preferred(LanguageModelBackend backend) =>
      switch (backend) {
        LanguageModelBackend.gpu => PreferredBackend.gpu,
        LanguageModelBackend.cpu => PreferredBackend.cpu,
        LanguageModelBackend.npu => PreferredBackend.npu,
      };
}
