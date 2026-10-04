import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sinapsis/core/logging/logger_provider.dart';
import 'package:sinapsis/core/network/in_app_model_file_transfer.dart';
import 'package:sinapsis/core/network/interceptors/logging_interceptor.dart';
import 'package:sinapsis/core/network/model_file_transfer.dart';
import 'package:sinapsis/core/network/network_providers.dart';
import 'package:sinapsis/core/network/system_downloads.dart';
import 'package:sinapsis/core/network/system_model_file_transfer.dart';

/// El gestor de descargas del sistema, si este dispositivo lo tiene (F29):
/// Android con el gestor habilitado y el almacenamiento compartido montado.
///
/// Lo resuelve el arranque (`bootstrap`, con
/// `MethodChannelSystemDownloads.resolve`) antes de levantar la app, porque
/// de él depende dónde viven los modelos y eso no puede cambiar a mitad de
/// la sesión. Sin él —el escritorio, la web, las pruebas— se baja dentro de
/// la app.
final systemDownloadsProvider = Provider<SystemDownloads?>((ref) => null);

/// Cliente HTTP para bajar los modelos dentro de la app: los de Gemma y el
/// de Whisper.
///
/// Deliberadamente sin `GlobalErrorInterceptor`, por el mismo motivo que
/// `resourceFetchDioProvider`: la pantalla que dispara la descarga ya
/// muestra su propio estado de error con un botón para reintentar, y el
/// aviso global duplicaría el mensaje sin agregar nada. Con los límites de
/// [modelDownloadBaseOptions]: los de una descarga de cientos de megas, que
/// no puede cortar una conexión lenta pero tiene que cortar una muerta.
final modelDownloadDioProvider = Provider<Dio>((ref) {
  final logger = ref.watch(appLoggerProvider);

  return Dio(modelDownloadBaseOptions())
    ..interceptors.add(NetworkLoggingInterceptor(logger: logger));
});

/// Cómo llegan los modelos al dispositivo: con el gestor del sistema si lo
/// hay —sigue con la app cerrada—, si no dentro de la app. Una sola para
/// todos los modelos: sabe qué descargas está siguiendo, y dos instancias
/// no sabrían de las de la otra.
final modelFileTransferProvider = Provider<ModelFileTransfer>((ref) {
  final system = ref.watch(systemDownloadsProvider);
  if (system != null) return SystemModelFileTransfer(downloads: system);
  return InAppModelFileTransfer(dio: ref.watch(modelDownloadDioProvider));
});

/// Dónde viven los modelos.
typedef ModelStorage = ({
  /// Donde se bajan ahora.
  Future<Directory> Function() root,

  /// Donde se bajaban antes: lo que quedó entero ahí se sigue usando sin
  /// volver a bajarlo.
  List<Future<Directory> Function()> earlierRoots,
});

/// Con el gestor del sistema, en la carpeta propia de la app en el
/// almacenamiento compartido —la única donde el sistema puede escribir por
/// ella—, reconociendo lo que se bajó antes en la carpeta interna (hasta
/// F29). Sin él, en la carpeta interna, como siempre.
final modelStorageProvider = Provider<ModelStorage>((ref) {
  final system = ref.watch(systemDownloadsProvider);
  if (system == null) {
    return (root: getApplicationDocumentsDirectory, earlierRoots: const []);
  }
  return (
    root: () async => system.directory,
    earlierRoots: const [getApplicationDocumentsDirectory],
  );
});
