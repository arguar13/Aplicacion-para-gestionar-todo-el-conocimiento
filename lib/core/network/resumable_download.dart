import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';

/// Baja un archivo grande —un modelo de cientos de megas a varios gigas—
/// retomando por rango lo que ya está en el disco, y dice cuándo quedó
/// **entero**.
///
/// Lo comparten las descargas de los modelos de Gemma y la de Whisper. Cada
/// una tenía la suya, y las dos fallaban en los bordes:
///
/// - con el archivo ya completo, pedir `bytes=<tamaño>-` hace que Hugging
///   Face conteste **416** (también después de la redirección al CDN). Dio lo
///   tomaba por un error, se reintentaba ocho veces —unos 84 s— y la
///   descarga terminaba fallando sin salida: el archivo estaba bien, pero
///   nada lo daba por bueno. Acá un 416 cuyo `Content-Range: bytes */N` dice
///   el mismo tamaño que lo local es lo que es: «ya está entero»;
/// - Whisper volvía a empezar de cero cada archivo cortado;
/// - una conexión que se queda colgada a mitad del cuerpo no terminaba
///   nunca: ver [stallTimeout].
///
/// El cuerpo se escribe en [fetch]`(partial: …)`, que es siempre el archivo
/// **a medias**: quien llama lo renombra al nombre definitivo cuando [fetch]
/// vuelve, así un archivo con el nombre final nunca está cortado.
class ResumableDownload {
  ResumableDownload({
    required Dio dio,
    this.maxAttempts = 8,
    this.stallTimeout = const Duration(seconds: 60),
    Duration Function(int attempt)? retryDelay,
  }) : _dio = dio,
       _retryDelay = retryDelay ?? _defaultRetryDelay;

  final Dio _dio;

  /// Cuántos intentos en total ante un corte transitorio —la conexión se cae,
  /// el servidor contesta 5xx, el cuerpo se queda quieto—. Alto a propósito:
  /// cada intento retoma desde donde quedó, así que insistir no vuelve a
  /// pagar lo ya bajado.
  final int maxAttempts;

  /// Cuánto puede pasar sin que llegue **ningún** byte del cuerpo antes de
  /// dar la conexión por colgada, cortarla y retomar en otro intento.
  ///
  /// Hace falta aparte del `receiveTimeout` de Dio: en dio 5.11 ese límite
  /// cubre solo la espera de las cabeceras (`io_adapter.dart`, el `timeout`
  /// sobre `request.close()`), no el cuerpo de una respuesta en streaming.
  /// Con solo ese, una conexión que mandó las cabeceras y después se quedó
  /// muda —un cambio de red, un CDN que no cierra— dejaba la descarga
  /// esperando para siempre.
  ///
  /// Mide silencio, no lentitud: una conexión de 10 KB/s manda un fragmento
  /// cada fracción de segundo y nunca llega a este límite. Un minuto entero
  /// sin un solo byte no es una conexión lenta, es una muerta.
  final Duration stallTimeout;

  final Duration Function(int attempt) _retryDelay;

  /// La espera entre intentos crece con cada uno: un corte de un segundo no
  /// necesita el mismo respiro que uno de treinta.
  static Duration _defaultRetryDelay(int attempt) =>
      Duration(seconds: attempt * 3);

  /// Lleva [partial] hasta el archivo entero que sirve [url] y devuelve su
  /// tamaño en bytes.
  ///
  /// Lo que ya tiene [partial] se retoma con un pedido `Range`; si el
  /// servidor no lo admite y manda el archivo entero (200), se reescribe
  /// desde cero en vez de agregarle bytes repetidos.
  ///
  /// [expectedBytes] es el tamaño que tiene que tener el archivo entero, si
  /// se sabe: el verificado (Whisper) o el que dijo el servidor cuando
  /// empezó esta misma descarga (Gemma). Si el servidor ahora dice otro, lo
  /// que hay a medias es de otro archivo —cambió en el servidor— y se empieza
  /// de cero. Si [partial] ya tiene exactamente ese tamaño, ni se pregunta.
  ///
  /// [onTotal] avisa el tamaño total apenas el servidor lo dice, para que
  /// quien llama lo anote junto al archivo a medias.
  ///
  /// [cancelToken] corta la descarga: falla con el [DioException] de tipo
  /// `cancel`, sin reintentar.
  ///
  /// Lanza [DioException] si el servidor dice que no (401, 403, 404, o
  /// cualquier otro estado después de agotar los intentos), y lo que lance
  /// el disco —sin lugar, sin permiso— sin reintentar: eso no se arregla
  /// insistiendo.
  Future<int> fetch({
    required String url,
    required File partial,
    Map<String, String> headers = const {},
    int? expectedBytes,
    void Function(int total)? onTotal,
    void Function(int received, int? total)? onProgress,
    CancelToken? cancelToken,
  }) async {
    var expected = expectedBytes;
    for (var attempt = 1; ; attempt++) {
      try {
        return await _attempt(
          url: url,
          partial: partial,
          headers: headers,
          expectedBytes: expected,
          onTotal: (total) {
            expected = total;
            onTotal?.call(total);
          },
          onProgress: onProgress,
          cancelToken: cancelToken,
        );
      } on Object catch (e) {
        if (!_isTransient(e) || attempt >= maxAttempts) rethrow;
        await Future<void>.delayed(_retryDelay(attempt));
        // Cancelada durante la espera: el próximo intento ni empieza.
        if (cancelToken?.cancelError case final cancelled?) throw cancelled;
      }
    }
  }

  /// Lo que vale la pena reintentar: lo de la red y lo del servidor que no
  /// sea un «no» definitivo. Un 401/403 —repositorio protegido, token
  /// vencido— o un 404 —el archivo ya no está ahí— no se arreglan solos. Una
  /// descarga cancelada a pedido, tampoco: no es un corte.
  static bool _isTransient(Object e) => switch (e) {
    DioException(type: DioExceptionType.cancel) => false,
    DioException(:final response?) => !const {
      401,
      403,
      404,
    }.contains(response.statusCode),
    DioException() ||
    TimeoutException() ||
    HttpException() ||
    SocketException() ||
    DownloadIncompleteException() ||
    _StartOver() => true,
    _ => false,
  };

  Future<int> _attempt({
    required String url,
    required File partial,
    required Map<String, String> headers,
    required int? expectedBytes,
    required void Function(int total) onTotal,
    required void Function(int received, int? total)? onProgress,
    required CancelToken? cancelToken,
  }) async {
    var existing = partial.existsSync() ? partial.lengthSync() : 0;
    if (expectedBytes != null && existing > expectedBytes) {
      // Más grande que el archivo entero: no es un pedazo de este.
      await partial.delete();
      existing = 0;
    }
    if (expectedBytes != null && existing == expectedBytes) {
      onProgress?.call(existing, expectedBytes);
      return existing;
    }

    final response = await _dio.get<ResponseBody>(
      url,
      cancelToken: cancelToken,
      options: Options(
        responseType: ResponseType.stream,
        headers: {...headers, if (existing > 0) 'range': 'bytes=$existing-'},
        // 416 no es un error acá: es la respuesta a pedir el resto de un
        // archivo que ya está entero.
        validateStatus: (status) =>
            status != null && (status >= 200 && status < 300 || status == 416),
      ),
    );
    final body = response.data!;

    if (response.statusCode == 416) {
      // El cuerpo de un 416 es un texto corto: se descarta sin leerlo.
      await body.stream.listen(null).cancel();
      final total = _contentRangeOf(response)?.total;
      if (existing > 0 && total == existing) {
        onTotal(total!);
        onProgress?.call(existing, total);
        return existing;
      }
      // El servidor tiene otro tamaño: lo que hay a medias no es de este
      // archivo. Se empieza de cero.
      if (partial.existsSync()) await partial.delete();
      throw const _StartOver();
    }

    final range = response.statusCode == 206 ? _contentRangeOf(response) : null;
    final resumed = existing > 0 && range != null && range.start == existing;
    if (existing > 0 && response.statusCode == 206 && !resumed) {
      // Un rango que no empieza donde quedó lo local no se puede pegar.
      await body.stream.listen(null).cancel();
      await partial.delete();
      throw const _StartOver();
    }

    // Un 206 dice el total en `Content-Range`; su `Content-Length` es solo
    // lo que falta. Un 200 trae el archivo entero.
    final total = range != null ? range.total : _lengthOf(response);
    if (total != null) {
      if (expectedBytes != null && total != expectedBytes && resumed) {
        // El archivo cambió en el servidor desde que se empezó a bajar: lo
        // que hay no se puede completar con lo de ahora.
        await body.stream.listen(null).cancel();
        await partial.delete();
        onTotal(total);
        throw const _StartOver();
      }
      onTotal(total);
    }

    final sink = partial.openWrite(
      mode: resumed ? FileMode.append : FileMode.write,
    );
    var received = resumed ? existing : 0;
    try {
      await for (final chunk in body.stream.timeout(stallTimeout)) {
        sink.add(chunk);
        received += chunk.length;
        onProgress?.call(received, total);
      }
      await sink.flush();
    } finally {
      await sink.close();
    }

    // Una conexión que se cierra limpia antes de tiempo no siempre avisa
    // con un error: sin esto, un archivo cortado se daba por entero.
    if (total != null && received != total) {
      throw DownloadIncompleteException(received: received, total: total);
    }
    return received;
  }

  /// `Content-Range: bytes <inicio>-<fin>/<total>` o `bytes */<total>`.
  static ({int? start, int? total})? _contentRangeOf(Response<Object?> r) {
    final header = r.headers.value('content-range');
    if (header == null) return null;
    final match = RegExp(
      r'^bytes\s+(?:(\d+)-\d+|\*)/(\d+|\*)$',
    ).firstMatch(header.trim());
    if (match == null) return null;
    return (
      start: int.tryParse(match.group(1) ?? ''),
      total: int.tryParse(match.group(2)!),
    );
  }

  static int? _lengthOf(Response<Object?> r) {
    final header = r.headers.value(Headers.contentLengthHeader);
    return header == null ? null : int.tryParse(header);
  }
}

/// La conexión se cerró antes de mandar todo lo que había anunciado. Se
/// reintenta: el próximo intento retoma desde [received].
class DownloadIncompleteException implements Exception {
  const DownloadIncompleteException({
    required this.received,
    required this.total,
  });

  final int received;
  final int total;

  @override
  String toString() => 'Descarga cortada: $received de $total bytes.';
}

/// Lo que había a medias no sirve: se borró y el próximo intento empieza de
/// cero.
class _StartOver implements Exception {
  const _StartOver();
}
