import 'dart:async';

import 'package:dio/dio.dart';
import 'package:sinapsis/core/network/host_gate.dart';
import 'package:sinapsis/core/util/clock.dart';

/// Lo que dejó una bajada acotada.
class BoundedDownloadResult {
  const BoundedDownloadResult({
    required this.savedAs,
    required this.bytes,
    required this.contentType,
    required this.fileName,
    required this.finalUrl,
  });

  /// Lo que devolvió quien guardó el archivo: su ruta relativa.
  final String savedAs;

  /// Cuánto pesó.
  final int bytes;

  /// El tipo que dijo el servidor, en minúsculas y sin parámetros
  /// (`application/pdf`), o `null` si no dijo ninguno.
  final String? contentType;

  /// El nombre con el que el servidor lo ofrece (`Content-Disposition`), o
  /// el último tramo de la dirección.
  final String fileName;

  /// La dirección de la que vino, después de las redirecciones.
  final Uri finalUrl;
}

/// El archivo pesa más de lo que se le permite: se cortó sin guardar nada.
class DownloadTooLargeException implements Exception {
  const DownloadTooLargeException({required this.limit, this.declared});

  final int limit;

  /// Lo que dijo el servidor que pesa, si lo dijo antes de mandarlo.
  final int? declared;

  @override
  String toString() => declared == null
      ? 'El archivo pasa de $limit bytes.'
      : 'El archivo pasa de $limit bytes ($declared).';
}

/// No hay lugar en el teléfono para el archivo, dejando el margen de reserva.
class NotEnoughSpaceException implements Exception {
  const NotEnoughSpaceException({required this.needed, required this.free});

  final int needed;
  final int free;

  @override
  String toString() => 'Falta espacio: hacen falta $needed bytes y hay $free.';
}

/// Lo que llegó no es lo que se quería: una página en vez de un archivo,
/// por ejemplo, o un tipo que quien pidió no acepta.
class UnwantedContentException implements Exception {
  const UnwantedContentException(this.contentType);

  final String? contentType;

  @override
  String toString() => 'No es un archivo que se baje: $contentType.';
}

/// Guarda lo que va llegando y devuelve dónde quedó. Si [bytes] falla, no
/// tiene que quedar nada a medias.
typedef SaveDownloadedStream =
    Future<String> Function(Stream<List<int>> bytes, String fileName);

/// Baja un archivo **sin pasarse** (F30): de a un pedido por servidor
/// ([HostGate]), esperando lo que el servidor pida (429 o 503 con
/// `Retry-After`), con un tope de bytes que se aplica **mientras** baja —no
/// después: un archivo que se pasa se corta en el byte en que se pasa, sin
/// llegar a ocupar el disco— y mirando el espacio libre antes y durante.
///
/// Nunca tiene el archivo entero en memoria: cada parte que llega va
/// derecho a quien lo guarda ([SaveDownloadedStream]).
///
/// No sabe nada de redes privadas: eso lo pone el [Dio] que recibe, armado
/// con `createPublicOnlyHttpClient` (ver `public_network.dart`).
class BoundedDownloader {
  BoundedDownloader({
    required Dio dio,
    required HostGate hosts,
    required Future<int?> Function() freeBytes,
    this.reserveBytes = 200 * 1024 * 1024,
    this.maxAttempts = 3,
    this.stallTimeout = const Duration(seconds: 60),
    this.spaceCheckEvery = 16 * 1024 * 1024,
    Clock clock = DateTime.now,
  }) : _dio = dio,
       _hosts = hosts,
       _freeBytes = freeBytes,
       _clock = clock;

  final Dio _dio;
  final HostGate _hosts;
  final Future<int?> Function() _freeBytes;
  final Clock _clock;

  /// Lo que se deja libre siempre: un teléfono sin un byte libre no puede ni
  /// guardar la base de datos.
  final int reserveBytes;

  /// Cuántas veces se intenta ante un «esperá» del servidor o un corte de red.
  final int maxAttempts;

  /// Cuánto puede pasar sin que llegue un byte antes de dar la conexión por
  /// muerta (ver `ResumableDownload.stallTimeout`).
  final Duration stallTimeout;

  /// Cada cuántos bytes se vuelve a mirar el espacio libre.
  final int spaceCheckEvery;

  /// Baja [url] y la guarda con [save], sin pasar de [maxBytes].
  ///
  /// [accept] decide, por el tipo que dice el servidor, si es algo que se
  /// quiere: si no, lanza [UnwantedContentException] sin bajar el cuerpo.
  ///
  /// Lanza [DownloadTooLargeException], [NotEnoughSpaceException],
  /// [UnwantedContentException], o el [DioException] de un estado que no es
  /// un «esperá» (404, 403…) o de un corte que no se resolvió reintentando.
  Future<BoundedDownloadResult> download(
    Uri url, {
    required int maxBytes,
    required SaveDownloadedStream save,
    bool Function(String? contentType)? accept,
    CancelToken? cancelToken,
    void Function(int received, int? total)? onProgress,
  }) async {
    for (var attempt = 1; ; attempt++) {
      try {
        return await _hosts.run(
          url.host,
          () => _once(
            url,
            maxBytes: maxBytes,
            save: save,
            accept: accept,
            cancelToken: cancelToken,
            onProgress: onProgress,
          ),
        );
      } on DioException catch (e) {
        // El cuerpo de un error también llega como stream: se suelta.
        if (e.response?.data case final ResponseBody errorBody) {
          await errorBody.stream.listen(null).cancel();
        }
        if (e.type == DioExceptionType.cancel || attempt >= maxAttempts) {
          rethrow;
        }
        final status = e.response?.statusCode;
        if (status == 429 || status == 503) {
          final wait =
              parseRetryAfter(
                e.response?.headers.value('retry-after'),
                now: _clock(),
              ) ??
              Duration(seconds: 5 * attempt);
          _hosts.pause(url.host, wait);
          continue;
        }
        final transient =
            status == null ||
            status >= 500 ||
            e.type == DioExceptionType.connectionTimeout ||
            e.type == DioExceptionType.receiveTimeout;
        if (!transient) rethrow;
        _hosts.pause(url.host, Duration(seconds: 2 * attempt));
      } on TimeoutException {
        // El cuerpo se quedó quieto: se vuelve a pedir.
        if (attempt >= maxAttempts) rethrow;
      }
    }
  }

  Future<BoundedDownloadResult> _once(
    Uri url, {
    required int maxBytes,
    required SaveDownloadedStream save,
    required bool Function(String? contentType)? accept,
    required CancelToken? cancelToken,
    required void Function(int received, int? total)? onProgress,
  }) async {
    final response = await _dio.getUri<ResponseBody>(
      url,
      cancelToken: cancelToken,
      options: Options(
        responseType: ResponseType.stream,
        followRedirects: true,
        maxRedirects: 5,
      ),
    );
    final body = response.data!;

    Future<Never> refuse(Exception error) async {
      await body.stream.listen(null).cancel();
      throw error;
    }

    final contentType = _mimeOf(response.headers.value('content-type'));
    if (accept != null && !accept(contentType)) {
      return refuse(UnwantedContentException(contentType));
    }

    final declared = int.tryParse(
      response.headers.value(Headers.contentLengthHeader) ?? '',
    );
    if (declared != null && declared > maxBytes) {
      return refuse(
        DownloadTooLargeException(limit: maxBytes, declared: declared),
      );
    }
    final free = await _freeBytes();
    if (free != null) {
      final needed = (declared ?? 0) + reserveBytes;
      if (free < needed) {
        return refuse(NotEnoughSpaceException(needed: needed, free: free));
      }
    }

    final finalUrl = response.realUri;
    final fileName =
        _fileNameFromDisposition(
          response.headers.value('content-disposition'),
        ) ??
        _fileNameFromUrl(finalUrl);

    var received = 0;
    var nextSpaceCheck = spaceCheckEvery;
    final guarded = body.stream.timeout(stallTimeout).asyncMap<List<int>>((
      chunk,
    ) async {
      received += chunk.length;
      if (received > maxBytes) {
        throw DownloadTooLargeException(limit: maxBytes, declared: declared);
      }
      if (received >= nextSpaceCheck) {
        nextSpaceCheck += spaceCheckEvery;
        final free = await _freeBytes();
        if (free != null && free < reserveBytes) {
          throw NotEnoughSpaceException(needed: reserveBytes, free: free);
        }
      }
      onProgress?.call(received, declared);
      return chunk;
    });

    final savedAs = await save(guarded, fileName);
    return BoundedDownloadResult(
      savedAs: savedAs,
      bytes: received,
      contentType: contentType,
      fileName: fileName,
      finalUrl: finalUrl,
    );
  }

  static String? _mimeOf(String? header) {
    if (header == null) return null;
    final mime = header.split(';').first.trim().toLowerCase();
    return mime.isEmpty ? null : mime;
  }
}

/// El nombre de un `Content-Disposition`: el `filename*` (RFC 5987, con su
/// codificación) si lo trae, si no el `filename`. `null` si no trae ninguno.
String? fileNameFromContentDisposition(String? header) =>
    _fileNameFromDisposition(header);

String? _fileNameFromDisposition(String? header) {
  if (header == null) return null;
  final extended = RegExp(
    r"filename\*\s*=\s*([^']*)'[^']*'([^;]+)",
    caseSensitive: false,
  ).firstMatch(header);
  // Mal codificado —un `%` sin sus dos cifras, bytes que no son UTF-8—: se
  // prueba con el `filename` de siempre.
  final encoded = extended?[2]?.trim();
  if (encoded != null && !RegExp('%(?![0-9A-Fa-f]{2})').hasMatch(encoded)) {
    try {
      final decoded = Uri.decodeComponent(encoded).trim();
      if (decoded.isNotEmpty) return decoded;
    } on FormatException {
      // Ver arriba.
    }
  }
  final plain = RegExp(
    r'''filename\s*=\s*(?:"([^"]*)"|([^;]+))''',
    caseSensitive: false,
  ).firstMatch(header);
  final name = (plain?[1] ?? plain?[2])?.trim();
  return name == null || name.isEmpty ? null : name;
}

String _fileNameFromUrl(Uri url) {
  final segments = url.pathSegments.where((s) => s.isNotEmpty);
  if (segments.isEmpty) return url.host;
  return segments.last;
}
