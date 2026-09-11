import 'dart:io';

import 'package:sinapsis/core/storage/file_store.dart';
import 'package:sinapsis/features/transform/data/services/sherpa_onnx_audio_transcriber_io.dart';
import 'package:sinapsis/features/transform/domain/services/audio_transcriber.dart';
import 'package:sinapsis/features/transform/domain/services/whisper_model_manager.dart';

/// El que transcribe audio fuera de la web: sherpa-onnx nativo, en un
/// isolate. [files] no se usa —el origen se lee por su ruta absoluta, no
/// por sus bytes— y queda solo para que la firma sea la misma en las dos
/// plataformas.
AudioTranscriber createAudioTranscriber({
  required WhisperModelManager model,
  required FileStore files,
  required Future<Directory> Function() temporaryDirectory,
}) {
  return SherpaOnnxAudioTranscriberIo(
    model: model,
    temporaryDirectory: temporaryDirectory,
  );
}
