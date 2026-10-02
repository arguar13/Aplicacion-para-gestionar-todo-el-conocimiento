import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;

import 'package:path/path.dart' as p;
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa_onnx;
import 'package:sinapsis/features/transform/data/services/audio_wav_converter.dart';
import 'package:sinapsis/features/transform/data/services/pcm16_samples.dart';
import 'package:sinapsis/features/transform/data/services/speech_windows.dart';
import 'package:sinapsis/features/transform/domain/entities/timed_text.dart';
import 'package:sinapsis/features/transform/domain/services/audio_transcriber.dart';
import 'package:sinapsis/features/transform/domain/services/whisper_model_manager.dart';

/// `AudioTranscriber` sobre Whisper sherpa-onnx, corriendo en el
/// dispositivo.
///
/// Dos pasos, con una frontera clara entre ellos:
///
/// 1. Convertir el archivo de origen —cualquier audio, o la pista de audio
///    de un video— a WAV de 16 kHz mono con [AudioWavConverter]: es el
///    formato exacto que espera un modelo de Whisper, sea cual sea el
///    formato de origen. En Android, con el conversor propio que lee el
///    formato real del decodificador (F22). Archivo a archivo, no bytes a
///    bytes: así el origen —que puede ser un video de varios GB— nunca se
///    carga en la memoria de Dart, solo lo lee el decodificador nativo. El
///    WAV queda en disco hasta terminar: si la app se cierra a mitad de
///    camino, al retomar no se reconvierte
///    (F21).
/// 2. Transcribirlo por tramos de hasta 14,5 segundos cortados en pausas,
///    con protección contra los bucles del motor y sin mandarle el silencio
///    —ver `speech_windows.dart` (F22)—, en un isolate aparte, leyendo del
///    WAV de a un tramo: una hora de audio son 115 MB de WAV y 230 MB de
///    muestras, y no se cargan enteros (F21). Dónde cortar sale de recorrer
///    el WAV una vez, por partes, midiendo su energía. Cada tramo terminado
///    vuelve al isolate principal, que lo guarda y avisa el avance; al
///    retomar, los tramos ya guardados no se repiten. Ver
///    `runSegmentedTranscription`.
///
/// Por qué en dos pasos y no todo junto: el conversor habla con las APIs
/// nativas de la plataforma por un canal de método, y esos canales no
/// existen en un isolate de fondo sin configuración extra. sherpa-onnx, en
/// cambio, son llamadas FFI directas —sin canal de por medio— pero
/// **síncronas y bloqueantes**: decodificar una hora de podcast congelaría
/// la interfaz entera si corriera en el isolate principal.
///
/// Abandonar —el elemento se borró— mata el isolate: una llamada nativa en
/// curso no se puede interrumpir desde Dart, pero no hay por qué esperarla.
///
/// Sin pruebas propias, igual que `MlKitImageTextExtractor` y
/// `HttpWhisperModelManager`: envuelve un motor real —FFI nativo, en un
/// isolate— que no tiene con qué correr en un test. Lo que sí se prueba es
/// `runSegmentedTranscription` —qué se retoma, qué se guarda, cómo se
/// corta— y `AudioTranscriptTransformer`, contra dobles.
class SherpaOnnxAudioTranscriberIo implements AudioTranscriber {
  const SherpaOnnxAudioTranscriberIo({
    required WhisperModelManager model,
    required Future<Directory> Function() temporaryDirectory,
    AudioWavConverter converter = const PlatformAudioWavConverter(),
    int? threads,
  }) : _model = model,
       _temporaryDirectory = temporaryDirectory,
       _converter = converter,
       _threadsOverride = threads;

  final WhisperModelManager _model;
  final Future<Directory> Function() _temporaryDirectory;

  /// Del archivo de origen al WAV de Whisper: ver [AudioWavConverter].
  final AudioWavConverter _converter;

  /// Cuántos hilos usar en vez de los de [_threads]: solo para medir en el
  /// dispositivo cuál rinde más (F22, `transcription_fidelity_test.dart`).
  final int? _threadsOverride;

  /// El tamaño de la cabecera RIFF/WAV que escribe el conversor: 44 bytes
  /// fijos, sin fragmentos extra.
  static const _wavHeaderBytes = 44;

  @override
  Future<Transcript> transcribe(
    String path, {
    TranscriptionSession session = TranscriptionSession.detached,
    String language = defaultTranscriptionLanguage,
  }) async {
    if (!await _model.isReady()) throw const WhisperModelNotReadyException();

    final modelPaths = await _model.paths();
    final tempDirectory = await _temporaryDirectory();
    final wav = File(p.join(tempDirectory.path, _wavName(session.workKey)));
    // Marca de que la conversión terminó: un WAV sin ella quedó a medias
    // —la app se cerró mientras se convertía— y se rehace. Con versión: un
    // WAV que dejó a medias el conversor de antes de F22 —el que estiraba
    // los AAC eficientes al doble— no se reaprovecha.
    final converted = File('${wav.path}.convertido-v2');

    var keepForResume = false;
    try {
      if (!converted.existsSync() || !wav.existsSync()) {
        await _converter.convert(path, wav.path);
        converted.writeAsStringSync('');
      }
      session.context.throwIfCancelled();

      final wavPath = wav.path;
      final windows = await Isolate.run(
        () => planWindows(_energyProfileOf(wavPath)),
      );
      session.context.throwIfCancelled();

      final job = _TranscriptionJob(
        wavPath: wav.path,
        windows: windows,
        encoder: modelPaths.encoder,
        decoder: modelPaths.decoder,
        tokens: modelPaths.tokens,
        threads: _threadsOverride ?? _threads,
        language: language,
      );
      return await runSegmentedTranscription(
        segmentCount: windows.length,
        session: session,
        segmentStart: (segment) => windows[segment].startTime,
        stitch: stitchOverlapping,
        transcribe: job.run,
      );
    } on Object {
      // Interrumpido por un fallo que un reintento puede salvar: el WAV
      // convertido se conserva si hay dónde retomarlo. Abandonado —se borró
      // el elemento— no: no hay nada que retomar.
      keepForResume = session.workKey != null && !session.context.isCancelled;
      rethrow;
    } finally {
      if (!keepForResume) {
        if (wav.existsSync()) await wav.delete();
        if (converted.existsSync()) await converted.delete();
      }
    }
  }

  /// Cuántos hilos usa Whisper. Con uno —el valor por defecto de
  /// sherpa-onnx— una hora de audio tardaba horas en un teléfono de ocho
  /// núcleos (F21). Más de cuatro no rinde: en un teléfono los núcleos de
  /// más son los de bajo consumo, que frenan al resto.
  static int get _threads => math.min(Platform.numberOfProcessors, 4);

  /// La energía del WAV en [path], leyéndolo de a 1 MB: no se carga entero.
  static EnergyProfile _energyProfileOf(String path) {
    final builder = EnergyProfileBuilder();
    final file = File(path).openSync();
    try {
      file.setPositionSync(_wavHeaderBytes);
      while (true) {
        final bytes = file.readSync(1 << 20);
        if (bytes.isEmpty) break;
        builder.add(pcm16ToFloat32Samples(bytes));
      }
    } finally {
      file.closeSync();
    }
    return builder.build();
  }

  /// Un WAV por elemento, para retomar el suyo; uno suelto si no se sabe de
  /// quién es.
  static String _wavName(String? workKey) {
    final safe = workKey?.replaceAll(RegExp('[^A-Za-z0-9_-]'), '_');
    return safe == null
        ? 'sinapsis-transcripcion.wav'
        : 'sinapsis-transcripcion-$safe.wav';
  }
}

/// Transcribir los tramos que faltan de un WAV, en un isolate aparte.
class _TranscriptionJob {
  const _TranscriptionJob({
    required this.wavPath,
    required this.windows,
    required this.encoder,
    required this.decoder,
    required this.tokens,
    required this.threads,
    required this.language,
  });

  final String wavPath;

  /// Los tramos en que se parte el audio, en orden: el número de tramo es
  /// su posición acá.
  final List<AudioWindow> windows;
  final String encoder;
  final String decoder;
  final String tokens;
  final int threads;

  /// El idioma en que se habla: ver `AudioTranscriber.transcribe`.
  final String language;

  /// Los tramos [pending], transcritos, a medida que el isolate los
  /// termina. Dejar de escuchar mata el isolate.
  Stream<(int, TimedText)> run(List<int> pending) {
    late final StreamController<(int, TimedText)> controller;
    final port = ReceivePort();
    Isolate? isolate;

    void stop() {
      isolate?.kill(priority: Isolate.immediate);
      isolate = null;
      port.close();
    }

    controller = StreamController<(int, TimedText)>(
      onListen: () async {
        port.listen((message) {
          switch (message) {
            // Entre isolates viaja codificado: ver `TimedText.encode`.
            case (final int segment, final String encoded):
              controller.add((segment, TimedText.decode(encoded)));
            case _TranscriptionFailed(:final error):
              controller.addError(TranscriptionFailedException(error));
              stop();
              unawaited(controller.close());
            case null:
              stop();
              unawaited(controller.close());
          }
        });
        try {
          isolate = await Isolate.spawn(
            _transcribeSegments,
            _WorkerArgs(
              port.sendPort,
              job: this,
              pending: List.unmodifiable(pending),
            ),
          );
          // El isolate no pudo nacer: un fallo de la plataforma, no del audio.
          // ignore: avoid_catches_without_on_clauses
        } catch (error) {
          controller.addError(TranscriptionFailedException('$error'));
          stop();
          unawaited(controller.close());
        }
      },
      onCancel: stop,
    );
    return controller.stream;
  }
}

class _WorkerArgs {
  const _WorkerArgs(this.sendPort, {required this.job, required this.pending});

  final SendPort sendPort;
  final _TranscriptionJob job;
  final List<int> pending;
}

class _TranscriptionFailed {
  const _TranscriptionFailed(this.error);

  final String error;
}

/// El isolate: arma el reconocedor una vez, y transcribe cada tramo de
/// [_WorkerArgs.pending] leyéndolo del WAV —solo ese tramo—, mandando cada
/// uno apenas lo termina. `null` al final.
void _transcribeSegments(_WorkerArgs args) {
  final job = args.job;
  final out = args.sendPort;

  sherpa_onnx.OfflineRecognizer? recognizer;
  RandomAccessFile? wav;
  try {
    sherpa_onnx.initBindings();
    recognizer = sherpa_onnx.OfflineRecognizer(
      sherpa_onnx.OfflineRecognizerConfig(
        model: sherpa_onnx.OfflineModelConfig(
          whisper: sherpa_onnx.OfflineWhisperModelConfig(
            encoder: job.encoder,
            decoder: job.decoder,
            // Fijado siempre, nunca detectado: Whisper redetecta el idioma
            // en cada tramo por separado, y en español lo confunde con el
            // gallego y quita las tildes; fijado en otro idioma que el que
            // se habla, traduce (medido, F22). Es el idioma que se eligió
            // para este elemento, o español.
            language: job.language,
            task: 'transcribe',
            // Cuándo se dice cada palabra (F23): con el modelo con atención
            // —ver `WhisperModelSpec`— sale de la atención del
            // decodificador; un modelo sin ella devuelve el texto sin
            // tiempos, como antes. Medido: alrededor de 1 % más de tiempo.
            enableTokenTimestamps: true,
          ),
          tokens: job.tokens,
          modelType: 'whisper',
          numThreads: job.threads,
          debug: false,
        ),
      ),
    );

    wav = File(job.wavPath).openSync();
    final engine = recognizer;
    for (final segment in args.pending) {
      final window = job.windows[segment];
      if (window.silent) {
        out.send((segment, TimedText.empty.encode()));
        continue;
      }
      wav.setPositionSync(
        SherpaOnnxAudioTranscriberIo._wavHeaderBytes + window.from * 2,
      );
      final samples = pcm16ToFloat32Samples(
        wav.readSync(window.decodeLength * 2),
      );
      final text = transcribeGuarded(
        samples,
        (samples) => transcribeWindow(engine, samples),
        offset: window.from,
      );
      out.send((segment, text.encode()));
    }
    out.send(null);
    // Cualquier falla del motor nativo o del archivo: vuelve como un fallo
    // de la transcripción, con su motivo, en vez de dejar el isolate mudo.
    // ignore: avoid_catches_without_on_clauses
  } catch (error) {
    out.send(_TranscriptionFailed('$error'));
  } finally {
    wav?.closeSync();
    recognizer?.free();
  }
}

/// La transcripción falló en el motor, con [detail] como motivo.
class TranscriptionFailedException implements Exception {
  const TranscriptionFailedException(this.detail);

  final String detail;

  @override
  String toString() => 'La transcripción falló: $detail';
}
