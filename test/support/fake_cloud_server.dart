import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';

/// Una respuesta grabada: estado, cuerpo (que llega de a `chunk` bytes) y
/// cabeceras.
typedef FakeCloudReply = ({
  int status,
  String body,
  int chunk,
  Map<String, List<String>> headers,
});

/// Un proveedor en la nube de mentira (F32): devuelve las respuestas
/// grabadas en orden y anota cada pedido. Nunca sale a internet.
class FakeCloudServer implements HttpClientAdapter {
  final replies = <FakeCloudReply>[];
  final requests = <RequestOptions>[];
  final bodies = <Map<String, dynamic>>[];

  void reply(
    String body, {
    int status = 200,
    int chunk = 5,
    Map<String, String> headers = const {},
  }) => replies.add((
    status: status,
    body: body,
    chunk: chunk,
    headers: {
      Headers.contentTypeHeader: ['application/json'],
      for (final MapEntry(:key, :value) in headers.entries) key: [value],
    },
  ));

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    if (requestStream != null) {
      final bytes = await requestStream.fold<List<int>>(
        [],
        (all, c) => all..addAll(c),
      );
      bodies.add(jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>);
    }
    final next = replies.removeAt(0);
    final bytes = utf8.encode(next.body);
    return ResponseBody(
      Stream.fromIterable([
        for (var i = 0; i < bytes.length; i += next.chunk)
          Uint8List.fromList(
            bytes.sublist(i, (i + next.chunk).clamp(0, bytes.length)),
          ),
      ]),
      next.status,
      headers: next.headers,
    );
  }

  @override
  void close({bool force = false}) {}
}

/// Sin conexión: cada pedido falla antes de llegar.
class OfflineCloudServer implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) => Future.error(
    DioException.connectionError(requestOptions: options, reason: 'sin red'),
  );

  @override
  void close({bool force = false}) {}
}

/// Eventos SSE con nombre (`event:`), como los manda Anthropic.
String namedSse(List<Map<String, Object?>> events) =>
    events.map((e) => 'event: ${e['type']}\ndata: ${jsonEncode(e)}\n\n').join();

/// Eventos SSE sin nombre, como los manda OpenAI, y el `[DONE]` del final.
String plainSse(List<Map<String, Object?>> events, {bool done = true}) =>
    '${events.map((e) => 'data: ${jsonEncode(e)}\n\n').join()}'
    '${done ? 'data: [DONE]\n\n' : ''}';
