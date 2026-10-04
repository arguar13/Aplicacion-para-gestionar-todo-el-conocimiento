import 'dart:io';

import 'package:dio/dio.dart';
import 'package:sinapsis/core/network/model_file_transfer.dart';
import 'package:sinapsis/features/transform/data/services/opfs_whisper_model_manager.dart';
import 'package:sinapsis/features/transform/domain/services/whisper_model_manager.dart';

/// El que guarda el modelo de Whisper en la web: en OPFS. [transfer],
/// [rootDirectory] y [earlierRoots] no se usan —no hay ningún directorio
/// real que elegir ni gestor de descargas del sistema— y quedan solo para
/// que la firma sea la misma en las dos plataformas.
WhisperModelManager createWhisperModelManager({
  required Dio dio,
  required ModelFileTransfer transfer,
  required Future<Directory> Function() rootDirectory,
  List<Future<Directory> Function()> earlierRoots = const [],
}) {
  return OpfsWhisperModelManager(dio: dio);
}
