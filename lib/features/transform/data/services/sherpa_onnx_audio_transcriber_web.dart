import 'dart:typed_data';
import 'package:audio_decoder/audio_decoder.dart';
import 'package:path/path.dart' as p;
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa_onnx;
import 'package:sinapsis/core/storage/file_store.dart';
import 'package:sinapsis/features/transform/data/services/opfs_whisper_model_manager.dart';
import 'package:sinapsis/features/transform/data/services/pcm16_samples.dart';
import 'package:sinapsis/features/transform/data/services/sherpa_onnx_offline_recognizer_fix.dart';
import 'package:sinapsis/features/transform/data/services/speech_windows.dart';
import 'package:sinapsis/features/transform/domain/documents/document_parser.dart';
import 'package:sinapsis/features/transform/domain/services/audio_transcriber.dart';
import 'package:sinapsis/features/transform/domain/services/whisper_model_manager.dart';

/// `AudioTranscriber` sobre Whisper sherpa-onnx, para la web: mismo modelo
/// y el mismo motor, pero cargado como WebAssembly en vez de una librería
/// nativa. Ver la decisión 10 en docs/arquitectura.md.
///
/// Tres diferencias reales con `SherpaOnnxAudioTranscriberIo`, cada una
/// consecuencia directa de estar en un navegador:
///
/// - No hay ninguna ruta de archivo que darle a nada: el origen se lee con
///   `FileStore.read()`, y `audio_decoder.convertToWavBytes()` —bytes a
///   bytes, no archivo a archivo— hace la conversión con la propia Web
///   Audio API del navegador, sin escribir nada a disco.
/// - `sherpa-onnx` no lee archivos por su cuenta en la web: antes de crear
///   el reconocedor hay que copiar los tres archivos del modelo al sistema
///   de archivos virtual del propio módulo de WebAssembly, con
///   `OpfsWhisperModelManager.loadIntoEngine()`.
/// - Nada de esto corre en un isolate: `dart:isolate` no compila para la
///   web, y la implementación web de sherpa-onnx tampoco lo necesita
///   —decodifica con llamadas directas a WebAssembly—. La interfaz se
///   congela mientras dura una transcripción larga: una molestia real,
///   documentada, no un fallo silencioso.
///
/// Sin pruebas propias, igual que `TesseractImageTextExtractor`: envuelve
/// un motor real de WebAssembly que no tiene con qué correr en un test. Lo
/// que sí se prueba es `AudioTranscriptTransformer`, contra un doble de
/// esta interfaz.
class SherpaOnnxAudioTranscriberWeb implements AudioTranscriber {
  const SherpaOnnxAudioTranscriberWeb({
    required OpfsWhisperModelManager model,
    required FileStore files,
  }) : _model = model,
       _files = files;

  final OpfsWhisperModelManager _model;
  final FileStore _files;

  /// La frecuencia con la que está entrenado Whisper. No es un ajuste: es
  /// parte del modelo, así que no se expone como parámetro.
  static const _sampleRate = 16000;

  @override
  Future<String> transcribe(
    String path, {
    TranscriptionSession session = TranscriptionSession.detached,
  }) async {
    if (!await _model.isReady()) throw const WhisperModelNotReadyException();

    final sourceBytes = await _files.read(path);
    if (sourceBytes == null) throw MissingOriginalFileException(path);

    await sherpa_onnx.initBindingsAsync();
    // Arregla un defecto real de sherpa_onnx_web: ver el porqué completo
    // en sherpa_onnx_offline_recognizer_fix.dart.
    await ensureOfflineRecognizerIsReachable();
    await _model.loadIntoEngine();

    final modelPaths = await _model.paths();
    final recognizer = sherpa_onnx.OfflineRecognizer(
      sherpa_onnx.OfflineRecognizerConfig(
        model: sherpa_onnx.OfflineModelConfig(
          whisper: sherpa_onnx.OfflineWhisperModelConfig(
            encoder: modelPaths.encoder,
            decoder: modelPaths.decoder,
            // Ver el comentario del mismo cambio en
            // `SherpaOnnxAudioTranscriberIo`: sin esto, Whisper redetecta
            // el idioma en cada ventana de 30 segundos por separado.
            language: 'es',
            task: 'transcribe',
          ),
          tokens: modelPaths.tokens,
          modelType: 'whisper',
          debug: false,
        ),
      ),
    );

    try {
      final pcmBytes = await AudioDecoder.convertToWavBytes(
        sourceBytes,
        // El formato real no importa acá: la Web Audio API lo reconoce por
        // el contenido de los bytes, no por esta pista. Se manda igual
        // porque el parámetro es obligatorio en las dos plataformas.
        formatHint: _formatHintFor(path),
        sampleRate: _sampleRate,
        channels: 1,
        bitDepth: 16,
        includeHeader: false,
      );
      final samples = pcm16ToFloat32Samples(pcmBytes);

      // Por tramos cortados en pausas, con protección contra los bucles del
      // motor, avance y retomable, igual que en el dispositivo (F21, F22).
      // Acá no hay isolates: entre tramo y tramo se le devuelve el turno a
      // la interfaz.
      final windows = planWindows(EnergyProfile.of(samples));
      return await runSegmentedTranscription(
        segmentCount: windows.length,
        session: session,
        transcribe: (pending) async* {
          for (final segment in pending) {
            final window = windows[segment];
            yield (
              segment,
              window.silent
                  ? ''
                  : transcribeGuarded(
                      Float32List.sublistView(
                        samples,
                        window.start,
                        window.end,
                      ),
                      (samples) => transcribeWindow(recognizer, samples),
                      offset: window.start,
                    ),
            );
            await Future<void>.delayed(Duration.zero);
          }
        },
      );
    } finally {
      recognizer.free();
    }
  }

  String _formatHintFor(String path) {
    final extension = p.extension(path);
    return extension.isEmpty ? 'wav' : extension.substring(1).toLowerCase();
  }
}
