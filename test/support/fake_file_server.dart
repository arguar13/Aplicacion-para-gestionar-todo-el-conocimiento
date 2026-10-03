import 'dart:async';
import 'dart:typed_data';

import 'package:dio/dio.dart';

/// Un servidor de archivos de mentira para las descargas grandes: atiende
/// pedidos `Range` como Hugging Face —206 con `Content-Range`, y 416 con
/// `bytes */<total>` si se pide desde el final—, y sabe portarse mal a
/// pedido: cortar el cuerpo, quedarse callado, ignorar el rango o negarse.
///
/// Va como adaptador de un `Dio` real, así lo que se prueba incluye cómo
/// Dio trata cada estado (por ejemplo, que un 416 no se vuelva excepción).
class FakeFileServer implements HttpClientAdapter {
  FakeFileServer(Map<String, List<int>> files)
    : files = {
        for (final entry in files.entries)
          entry.key: Uint8List.fromList(entry.value),
      };

  /// Lo que sirve cada dirección.
  final Map<String, Uint8List> files;

  /// Cada pedido, en orden.
  final requests = <RequestOptions>[];

  /// Los próximos pedidos se portan así, uno por pedido; después, normal.
  final misbehaviors = <Misbehavior>[];

  /// Si atiende pedidos `Range`; si no, manda siempre el archivo entero.
  bool acceptsRanges = true;

  /// Las cabeceras `range` de cada pedido (`null` si no la tenía).
  List<String?> get ranges => [
    for (final r in requests) r.headers['range'] as String?,
  ];

  /// Para [Misbehavior.stall]: los cuerpos que quedaron colgados, para
  /// cerrarlos al final de la prueba.
  final _stalled = <StreamController<Uint8List>>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    final misbehavior = misbehaviors.isEmpty ? null : misbehaviors.removeAt(0);

    if (misbehavior case Misbehavior(:final status?)) {
      return ResponseBody.fromString('', status);
    }

    final bytes = files[options.uri.toString()];
    if (bytes == null) return ResponseBody.fromString('', 404);

    var start = 0;
    final range = options.headers['range'] as String?;
    if (acceptsRanges && range != null) {
      start = int.parse(RegExp(r'bytes=(\d+)-').firstMatch(range)!.group(1)!);
      if (start >= bytes.length) {
        return ResponseBody.fromString(
          'Range Not Satisfiable',
          416,
          headers: {
            'content-range': ['bytes */${bytes.length}'],
          },
        );
      }
    }

    final partial = start > 0;
    final status = partial ? 206 : 200;
    final headers = {
      Headers.contentLengthHeader: ['${bytes.length - start}'],
      if (partial)
        'content-range': ['bytes $start-${bytes.length - 1}/${bytes.length}'],
    };
    final body = bytes.sublist(start);

    switch (misbehavior) {
      case Misbehavior(:final cutAfter?):
        // La conexión se cierra limpia antes de mandar todo.
        return ResponseBody(
          Stream.value(Uint8List.fromList(body.take(cutAfter).toList())),
          status,
          headers: headers,
        );
      case Misbehavior(stall: true):
        // Manda las cabeceras y un poco, y después se queda callado.
        final controller = StreamController<Uint8List>()
          ..add(Uint8List.fromList(body.take(1).toList()));
        _stalled.add(controller);
        return ResponseBody(controller.stream, status, headers: headers);
      case _:
        return ResponseBody(
          Stream.fromIterable([
            for (var i = 0; i < body.length; i += 2)
              Uint8List.fromList(body.skip(i).take(2).toList()),
          ]),
          status,
          headers: headers,
        );
    }
  }

  @override
  void close({bool force = false}) {
    for (final controller in _stalled) {
      unawaited(controller.close());
    }
  }
}

/// Cómo se porta mal un pedido.
class Misbehavior {
  /// Contesta [status] sin cuerpo.
  const Misbehavior.status(int this.status) : cutAfter = null, stall = false;

  /// Manda solo [cutAfter] bytes y cierra limpio.
  const Misbehavior.cut(int this.cutAfter) : status = null, stall = false;

  /// Manda un byte y se queda callado.
  const Misbehavior.stall() : status = null, cutAfter = null, stall = true;

  final int? status;
  final int? cutAfter;
  final bool stall;
}
