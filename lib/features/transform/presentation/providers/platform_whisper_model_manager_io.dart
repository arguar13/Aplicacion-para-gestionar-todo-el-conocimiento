import 'dart:io';

import 'package:dio/dio.dart';
import 'package:sinapsis/features/transform/data/services/http_whisper_model_manager.dart';
import 'package:sinapsis/features/transform/domain/services/whisper_model_manager.dart';

/// El que guarda el modelo de Whisper fuera de la web: en un archivo, con
/// `dio`.
WhisperModelManager createWhisperModelManager({
  required Dio dio,
  required Future<Directory> Function() rootDirectory,
}) {
  return HttpWhisperModelManager(dio: dio, rootDirectory: rootDirectory);
}
