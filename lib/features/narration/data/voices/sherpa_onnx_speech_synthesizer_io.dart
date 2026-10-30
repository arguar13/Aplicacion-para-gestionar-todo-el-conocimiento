import 'dart:async';
import 'dart:isolate';
import 'dart:math' as math;

import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa_onnx;
import 'package:sinapsis/features/narration/domain/services/offline_speech_synthesizer.dart';
import 'package:sinapsis/features/narration/domain/voices/offline_voice_catalog.dart';

/// El motor de las voces sin conexión fuera de la web: sherpa-onnx nativo
/// (F47, paso 3).
OfflineSpeechSynthesizer? createOfflineSpeechSynthesizer() =>
    SherpaOnnxSpeechSynthesizer();

/// [OfflineSpeechSynthesizer] sobre el TTS sin conexión de `sherpa_onnx`
/// (1.13.8): VITS para Piper y Kokoro con su `sid`, en un isolate que vive
/// mientras la app lee.
///
/// - **Un isolate para todo**, nacido con el primer pedido: armar el motor de
///   una voz lleva de uno a varios segundos —leer el modelo, los datos de
///   espeak-ng—, y se arma una vez, no por oración.
/// - **Hasta dos motores armados**, los últimos usados: un texto con partes
///   en dos idiomas alterna dos voces (decisión L), y volver a armar cada una
///   en cada cambio sería una pausa de segundos entre oración y oración. Más
///   de dos sería memoria de más: un Kokoro son cientos de megas.
/// - El isolate escribe el WAV él mismo (`writeWave`): los cientos de miles
///   de muestras de una oración no cruzan al isolate de la pantalla.
class SherpaOnnxSpeechSynthesizer implements OfflineSpeechSynthesizer {
  Future<SendPort>? _worker;
  ReceivePort? _replies;
  final _pending = <int, Completer<Duration>>{};
  var _nextId = 0;

  Future<SendPort> _start() {
    return _worker ??= () async {
      final replies = ReceivePort();
      _replies = replies;
      final ready = Completer<SendPort>();
      replies.listen((message) {
        switch (message) {
          case final SendPort port:
            ready.complete(port);
          case (final int id, final int micros):
            _pending.remove(id)?.complete(Duration(microseconds: micros));
          case (final int id, final String error):
            _pending.remove(id)?.completeError(OfflineSpeechException(error));
        }
      });
      await Isolate.spawn(_speechWorker, replies.sendPort);
      return ready.future;
    }();
  }

  @override
  Future<Duration> synthesize({
    required OfflineVoiceEngineConfig engine,
    required int speakerId,
    required String text,
    required double speed,
    required String outputPath,
  }) async {
    final worker = await _start();
    final id = _nextId++;
    final done = Completer<Duration>();
    _pending[id] = done;
    worker.send(
      _SynthesisRequest(
        id: id,
        engine: engine,
        speakerId: speakerId,
        text: text,
        speed: speed,
        outputPath: outputPath,
      ),
    );
    return done.future;
  }

  @override
  Future<void> release() async {
    final worker = _worker;
    if (worker == null) return;
    (await worker).send(const _Release());
  }

  @override
  Future<void> dispose() async {
    final worker = _worker;
    _worker = null;
    if (worker != null) (await worker).send(const _Shutdown());
    _replies?.close();
    for (final pending in _pending.values) {
      pending.completeError(const OfflineSpeechException('motor cerrado'));
    }
    _pending.clear();
  }
}

class _SynthesisRequest {
  const _SynthesisRequest({
    required this.id,
    required this.engine,
    required this.speakerId,
    required this.text,
    required this.speed,
    required this.outputPath,
  });

  final int id;
  final OfflineVoiceEngineConfig engine;
  final int speakerId;
  final String text;
  final double speed;
  final String outputPath;
}

class _Release {
  const _Release();
}

class _Shutdown {
  const _Shutdown();
}

/// Cuántos motores quedan armados a la vez: ver [SherpaOnnxSpeechSynthesizer].
const _kMaxEngines = 2;

/// El isolate: arma los motores a medida que se piden, dice cada texto y
/// contesta cuánto dura, o por qué no pudo.
void _speechWorker(SendPort replies) {
  final requests = ReceivePort();
  replies.send(requests.sendPort);
  sherpa_onnx.initBindings();

  // Los motores armados, del menos al más usado.
  final engines = <String, sherpa_onnx.OfflineTts>{};

  void freeAll() {
    for (final engine in engines.values) {
      engine.free();
    }
    engines.clear();
  }

  sherpa_onnx.OfflineTts engineFor(OfflineVoiceEngineConfig config) {
    final ready = engines.remove(config.key);
    if (ready != null) return engines[config.key] = ready;
    if (engines.length >= _kMaxEngines) {
      final oldest = engines.keys.first;
      engines.remove(oldest)!.free();
    }
    return engines[config.key] = sherpa_onnx.OfflineTts(_configOf(config));
  }

  requests.listen((message) {
    switch (message) {
      case final _SynthesisRequest request:
        try {
          final engine = engineFor(request.engine);
          final audio = engine.generateWithConfig(
            text: request.text,
            config: sherpa_onnx.OfflineTtsGenerationConfig(
              sid: request.speakerId,
              speed: request.speed,
            ),
          );
          if (audio.samples.isEmpty || audio.sampleRate <= 0) {
            replies.send((request.id, 'no generó audio'));
            return;
          }
          final written = sherpa_onnx.writeWave(
            filename: request.outputPath,
            samples: audio.samples,
            sampleRate: audio.sampleRate,
          );
          if (!written) {
            replies.send((request.id, 'no pudo escribir el audio'));
            return;
          }
          final micros =
              audio.samples.length *
              Duration.microsecondsPerSecond ~/
              math.max(1, audio.sampleRate);
          replies.send((request.id, micros));
          // Un modelo que no se pudo cargar, un texto que el motor no acepta:
          // vuelve como respuesta, no como un isolate muerto.
          // ignore: avoid_catches_without_on_clauses
        } catch (error) {
          replies.send((request.id, '$error'));
        }
      case _Release():
        freeAll();
      case _Shutdown():
        freeAll();
        requests.close();
    }
  });
}

/// Lo que sherpa-onnx necesita para armar el motor de [config].
sherpa_onnx.OfflineTtsConfig _configOf(OfflineVoiceEngineConfig config) {
  final model = switch (config.family) {
    OfflineVoiceFamily.piper => sherpa_onnx.OfflineTtsModelConfig(
      vits: sherpa_onnx.OfflineTtsVitsModelConfig(
        model: config.model,
        tokens: config.tokens,
        dataDir: config.dataDir,
      ),
      numThreads: 2,
      // De fábrica, sherpa-onnx escribe en el registro todo lo que hace.
      debug: false,
    ),
    // `lang` es la voz de espeak-ng con que Kokoro pronuncia lo que no es
    // chino (sherpa-onnx, #2303); vacío, usa el léxico.
    OfflineVoiceFamily.kokoro => sherpa_onnx.OfflineTtsModelConfig(
      kokoro: sherpa_onnx.OfflineTtsKokoroModelConfig(
        model: config.model,
        voices: config.voices ?? '',
        tokens: config.tokens,
        dataDir: config.dataDir,
        lexicon: config.lexicon ?? '',
        lang: config.espeakVoice ?? '',
      ),
      numThreads: 2,
      debug: false,
    ),
  };
  return sherpa_onnx.OfflineTtsConfig(model: model);
}
