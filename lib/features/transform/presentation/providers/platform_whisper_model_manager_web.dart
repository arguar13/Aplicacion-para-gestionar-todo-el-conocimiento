import 'dart:io';

import 'package:dio/dio.dart';
import 'package:sinapsis/features/transform/data/services/opfs_whisper_model_manager.dart';
import 'package:sinapsis/features/transform/domain/services/whisper_model_manager.dart';

/// El que guarda el modelo de Whisper en la web: en OPFS. [rootDirectory]
/// no se usa —no hay ningún directorio real que elegir— y queda solo para
/// que la firma sea la misma en las dos plataformas.
WhisperModelManager createWhisperModelManager({
  required Dio dio,
  required Future<Directory> Function() rootDirectory,
}) {
  return OpfsWhisperModelManager(dio: dio);
}
