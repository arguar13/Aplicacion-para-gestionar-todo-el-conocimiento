import 'dart:io';

import 'package:sinapsis/core/storage/file_store.dart';
import 'package:sinapsis/features/transform/data/services/opfs_whisper_model_manager.dart';
import 'package:sinapsis/features/transform/data/services/sherpa_onnx_audio_transcriber_web.dart';
import 'package:sinapsis/features/transform/domain/services/audio_transcriber.dart';
import 'package:sinapsis/features/transform/domain/services/whisper_model_manager.dart';

/// El que transcribe audio en la web: sherpa-onnx en WebAssembly, en el
/// hilo principal. [temporaryDirectory] no se usa —nada se escribe a
/// disco— y queda solo para que la firma sea la misma en las dos
/// plataformas.
///
/// [model] llega siempre como `OpfsWhisperModelManager`: es lo único que
/// `createWhisperModelManager` construye en la web (ver
/// `platform_whisper_model_manager_web.dart`), así que el elenco es
/// seguro.
AudioTranscriber createAudioTranscriber({
  required WhisperModelManager model,
  required FileStore files,
  required Future<Directory> Function() temporaryDirectory,
}) {
  return SherpaOnnxAudioTranscriberWeb(
    model: model as OpfsWhisperModelManager,
    files: files,
  );
}
