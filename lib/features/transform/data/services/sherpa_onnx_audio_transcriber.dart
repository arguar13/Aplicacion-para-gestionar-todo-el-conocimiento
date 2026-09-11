import 'dart:io';
import 'dart:isolate';

import 'package:audio_decoder/audio_decoder.dart';
import 'package:path/path.dart' as p;
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa_onnx;
import 'package:sinapsis/features/transform/domain/services/audio_transcriber.dart';
import 'package:sinapsis/features/transform/domain/services/whisper_model_manager.dart';

/// `AudioTranscriber` sobre Whisper sherpa-onnx, corriendo en el
/// dispositivo.
///
/// Dos pasos, con una frontera clara entre ellos:
///
/// 1. Convertir el archivo de origen —cualquier audio, o la pista de audio
///    de un video— a WAV de 16 kHz mono con `audio_decoder`: es el formato
///    exacto que espera un modelo de Whisper, sea cual sea el formato de
///    origen.
/// 2. Decodificar ese WAV con sherpa-onnx, en un isolate aparte.
///
/// Por qué en dos pasos y no todo junto: `audio_decoder` habla con las APIs
/// nativas de la plataforma por un canal de método, y esos canales no
/// existen en un isolate de fondo sin configuración extra. sherpa-onnx, en
/// cambio, son llamadas FFI directas —sin canal de por medio— pero
/// **síncronas y bloqueantes**: decodificar una hora de podcast congelaría
/// la interfaz entera si corriera en el isolate principal. `Isolate.run`
/// separa justo lo que hace falta separar, sin más.
///
/// Sin pruebas propias, igual que `MlKitImageTextExtractor` y
/// `HttpWhisperModelManager`: envuelve un motor real —FFI nativo, en un
/// isolate— que no tiene con qué correr en un test. Lo que sí se prueba es
/// `AudioTranscriptTransformer`, contra un doble de esta interfaz.
class SherpaOnnxAudioTranscriber implements AudioTranscriber {
  const SherpaOnnxAudioTranscriber({
    required WhisperModelManager model,
    required Future<Directory> Function() temporaryDirectory,
  }) : _model = model,
       _temporaryDirectory = temporaryDirectory;

  final WhisperModelManager _model;
  final Future<Directory> Function() _temporaryDirectory;

  /// La frecuencia con la que está entrenado Whisper. No es un ajuste: es
  /// parte del modelo, así que no se expone como parámetro.
  static const _sampleRate = 16000;

  /// Un solo nombre fijo, no uno por llamada: la cola procesa de a un
  /// elemento por vez, así que nunca hay dos conversiones en curso al mismo
  /// tiempo, y un nombre fijo es uno menos que limpiar si algo se
  /// interrumpe a mitad de camino.
  static const _tempFileName = 'sinapsis-transcripcion.wav';

  @override
  Future<String> transcribe(String absolutePath) async {
    if (!await _model.isReady()) throw const WhisperModelNotReadyException();

    final modelPaths = await _model.paths();
    final tempDirectory = await _temporaryDirectory();
    final wavPath = p.join(tempDirectory.path, _tempFileName);

    // Se sacan a variables sueltas antes de cruzar al isolate: son las que
    // de verdad importan que lleguen bien, y un `String` no deja ninguna
    // duda de que se puede enviar. `WhisperModelPaths` no necesita saberlo.
    final encoderPath = modelPaths.encoder;
    final decoderPath = modelPaths.decoder;
    final tokensPath = modelPaths.tokens;

    try {
      await AudioDecoder.convertToWav(
        absolutePath,
        wavPath,
        sampleRate: _sampleRate,
        channels: 1,
      );

      return await Isolate.run(() {
        sherpa_onnx.initBindings();

        final recognizer = sherpa_onnx.OfflineRecognizer(
          sherpa_onnx.OfflineRecognizerConfig(
            model: sherpa_onnx.OfflineModelConfig(
              whisper: sherpa_onnx.OfflineWhisperModelConfig(
                encoder: encoderPath,
                decoder: decoderPath,
              ),
              tokens: tokensPath,
              modelType: 'whisper',
              debug: false,
            ),
          ),
        );

        final wave = sherpa_onnx.readWave(wavPath);
        final stream = recognizer.createStream();
        try {
          stream.acceptWaveform(
            samples: wave.samples,
            sampleRate: wave.sampleRate,
          );
          recognizer.decode(stream);
          return recognizer.getResult(stream).text;
        } finally {
          stream.free();
          recognizer.free();
        }
      });
    } finally {
      final wavFile = File(wavPath);
      if (wavFile.existsSync()) await wavFile.delete();
    }
  }
}
