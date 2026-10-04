import 'dart:io';

import 'package:dio/dio.dart';
import 'package:sinapsis/core/network/model_file_transfer.dart';
import 'package:sinapsis/features/transform/data/services/http_whisper_model_manager.dart';
import 'package:sinapsis/features/transform/domain/services/whisper_model_manager.dart';

/// El que guarda el modelo de Whisper fuera de la web: en archivos, bajados
/// con [transfer] (en Android, el gestor de descargas del sistema). [dio] no
/// se usa: queda para que la firma sea la misma en las dos plataformas.
WhisperModelManager createWhisperModelManager({
  required Dio dio,
  required ModelFileTransfer transfer,
  required Future<Directory> Function() rootDirectory,
  List<Future<Directory> Function()> earlierRoots = const [],
}) {
  return HttpWhisperModelManager(
    transfer: transfer,
    rootDirectory: rootDirectory,
    earlierRoots: earlierRoots,
  );
}
