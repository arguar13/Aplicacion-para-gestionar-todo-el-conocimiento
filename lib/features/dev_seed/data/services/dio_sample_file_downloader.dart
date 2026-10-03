import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:path/path.dart' as p;
import 'package:sinapsis/features/capture/data/services/captured_file_on_disk.dart';
import 'package:sinapsis/features/dev_seed/domain/entities/sample_resource.dart';
import 'package:sinapsis/features/dev_seed/domain/services/sample_file_downloader.dart';
import 'package:sinapsis/features/transform/domain/entities/cancellation_signal.dart';

/// [SampleFileDownloader] con el cliente HTTP de la app, directo a un
/// archivo temporal: Dio escribe lo que llega por partes, sin juntarlo en
/// memoria.
///
/// Lo bajado va a una carpeta propia dentro de la temporal
/// (`biblioteca_de_ejemplo`), para que `clearLeftovers` pueda borrar lo que
/// haya quedado sin tocar nada ajeno.
class DioSampleFileDownloader implements SampleFileDownloader {
  DioSampleFileDownloader({
    required Dio dio,
    required Future<Directory> Function() temporaryRoot,
    this.defaultThrottleWait = const Duration(seconds: 15),
    this.maxThrottleWait = const Duration(seconds: 60),
    this.maxThrottleRetries = 3,
  }) : _dio = dio,
       _temporaryRoot = temporaryRoot;

  final Dio _dio;
  final Future<Directory> Function() _temporaryRoot;

  /// Cuánto se espera ante un «demasiados pedidos» que no dice cuánto.
  final Duration defaultThrottleWait;

  /// Lo más que se espera, diga lo que diga el servidor: una carga en
  /// segundo plano no puede quedar colgada de un `Retry-After` de una hora.
  final Duration maxThrottleWait;

  /// Cuántas veces se vuelve a pedir lo que el servidor frenó.
  final int maxThrottleRetries;

  static const _folderName = 'biblioteca_de_ejemplo';

  Future<Directory> _folder() async =>
      Directory(p.join((await _temporaryRoot()).path, _folderName));

  @override
  Future<void> clearLeftovers() async {
    final folder = await _folder();
    if (folder.existsSync()) await folder.delete(recursive: true);
  }

  @override
  Future<DownloadedSample> download(
    SampleFile resource, {
    required CancellationSignal cancellation,
  }) async {
    cancellation.throwIfCancelled();

    final folder = await _folder();
    await folder.create(recursive: true);
    // El id y no el nombre del archivo: es único en la lista, así que dos
    // bajadas en paralelo no pueden pisarse.
    final target = File(
      p.join(folder.path, '${resource.id}${p.extension(resource.fileName)}'),
    );

    final cancelToken = CancelToken();
    unawaited(cancellation.whenCancelled.then((_) => cancelToken.cancel()));

    for (var attempt = 0; ; attempt++) {
      try {
        // Dio da por error lo que no sea un 2xx, y borra lo que haya
        // escrito: la página de un 404 no llega a pasar por el archivo
        // esperado.
        await _dio.download(
          resource.url,
          target.path,
          cancelToken: cancelToken,
        );
        break;
      } on DioException catch (e) {
        await _deleteQuietly(target);
        if (CancelToken.isCancel(e)) throw const ProcessingCancelledException();
        final wait = _throttleWait(e);
        if (wait == null || attempt >= maxThrottleRetries) {
          throw SampleDownloadException(_describe(e));
        }
        await _waitOrCancel(wait, cancellation);
      } on FileSystemException catch (e) {
        await _deleteQuietly(target);
        throw SampleDownloadException(
          'No se pudo escribir el temporal: ${e.message}',
        );
      }
    }

    final file = await capturedFileOnDisk(target, name: resource.fileName);
    if (file == null) {
      throw SampleDownloadException(
        'El temporal de ${resource.fileName} desapareció antes de guardarlo.',
      );
    }
    return DownloadedSample(file: file, discard: () => _deleteQuietly(target));
  }

  /// Si el servidor pidió esperar —un 429 o un 503—, cuánto: lo que diga su
  /// `Retry-After`, o [defaultThrottleWait] si no dice nada, y nunca más de
  /// [maxThrottleWait]. `null` para cualquier otro error, que no se
  /// reintenta.
  ///
  /// Hace falta de verdad, no por las dudas: Wikimedia, de donde salen las
  /// imágenes y varios audios, frena con un 429 a quien pide varios archivos
  /// seguidos —se vio al armar la lista—. Sin esperar y volver a pedir, esos
  /// recursos fallarían en cada pasada por llegar juntos, no por estar mal.
  Duration? _throttleWait(DioException e) {
    final status = e.response?.statusCode;
    if (status != 429 && status != 503) return null;
    final seconds = int.tryParse(
      e.response?.headers.value('retry-after')?.trim() ?? '',
    );
    final wait = seconds == null
        ? defaultThrottleWait
        : Duration(seconds: seconds);
    return wait > maxThrottleWait ? maxThrottleWait : wait;
  }

  /// Espera [wait], salvo que antes se pida cortar.
  Future<void> _waitOrCancel(
    Duration wait,
    CancellationSignal cancellation,
  ) async {
    await Future.any([Future<void>.delayed(wait), cancellation.whenCancelled]);
    cancellation.throwIfCancelled();
  }

  /// Borra [file] si todavía está. Que ya no esté no es un error: es
  /// justamente lo que se quería.
  Future<void> _deleteQuietly(File file) async {
    if (file.existsSync()) await file.delete();
  }

  String _describe(DioException e) {
    final status = e.response?.statusCode;
    if (status != null) return 'El servidor respondió $status.';
    return switch (e.type) {
      DioExceptionType.connectionTimeout ||
      DioExceptionType.sendTimeout ||
      DioExceptionType.receiveTimeout => 'Se cortó por tiempo: no respondió.',
      DioExceptionType.connectionError => 'Sin conexión con el servidor.',
      DioExceptionType.badCertificate => 'El certificado del servidor no vale.',
      DioExceptionType.badResponse ||
      DioExceptionType.cancel ||
      DioExceptionType.transformTimeout ||
      DioExceptionType.unknown => e.message ?? e.type.name,
    };
  }
}
