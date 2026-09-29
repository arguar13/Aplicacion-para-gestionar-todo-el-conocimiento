import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/error/exceptions.dart';
import 'package:sinapsis/features/transform/data/clients/dio_web_page_client.dart';

/// Responde lo que diga [respond], sin salir a la red.
class _FakeAdapter implements HttpClientAdapter {
  _FakeAdapter(this.respond);

  final Future<ResponseBody> Function(RequestOptions options) respond;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) => respond(options);

  @override
  void close({bool force = false}) {}
}

void main() {
  DioWebPageClient clientWith(_FakeAdapter adapter) =>
      DioWebPageClient(Dio()..httpClientAdapter = adapter);

  final url = Uri.parse('https://ejemplo.org/articulo');

  test('trae el HTML', () async {
    final client = clientWith(
      _FakeAdapter(
        (_) async => ResponseBody.fromString(
          '<html>hola</html>',
          200,
          headers: {
            Headers.contentTypeHeader: ['text/html'],
          },
        ),
      ),
    );

    expect(await client.fetchHtml(url), '<html>hola</html>');
  });

  test('sin conexión: NetworkException, para guardarlo como "sin '
      'conexión" (F21)', () async {
    final client = clientWith(
      _FakeAdapter(
        (options) async => throw DioException.connectionError(
          requestOptions: options,
          reason: 'sin red',
        ),
      ),
    );

    await expectLater(client.fetchHtml(url), throwsA(isA<NetworkException>()));
  });

  test('una página que ya no existe: ServerException con su código', () async {
    final client = clientWith(
      _FakeAdapter(
        (_) async => ResponseBody.fromBytes(utf8.encode('no está'), 404),
      ),
    );

    await expectLater(
      client.fetchHtml(url),
      throwsA(
        isA<ServerException>().having((e) => e.statusCode, 'código', 404),
      ),
    );
  });
}
