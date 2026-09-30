import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/error/exceptions.dart';
import 'package:sinapsis/features/transform/data/clients/dio_web_page_client.dart';

import '../../../../support/silent_logger.dart';

/// Un registro que se queda con los avisos, para ver que algo se registró.
class _RecordingLogger extends SilentLogger {
  final warnings = <String>[];

  @override
  void warning(String message, [Object? error, StackTrace? stackTrace]) =>
      warnings.add(message);
}

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

  test('respeta el charset que declara el servidor (F22)', () async {
    // Antes Dio decodificaba todo como UTF-8: "Año" en Latin-1 salía
    // "A�o".
    final client = clientWith(
      _FakeAdapter(
        (_) async => ResponseBody.fromBytes(
          latin1.encode('<p>Año, niño y café</p>'),
          200,
          headers: {
            Headers.contentTypeHeader: ['text/html; charset=ISO-8859-1'],
          },
        ),
      ),
    );

    expect(await client.fetchHtml(url), '<p>Año, niño y café</p>');
  });

  test('una codificación que la app no sabe leer queda registrada '
      '(F22)', () async {
    final logger = _RecordingLogger();
    final client = DioWebPageClient(
      Dio()
        ..httpClientAdapter = _FakeAdapter(
          (_) async => ResponseBody.fromBytes(
            utf8.encode('<p>hola</p>'),
            200,
            headers: {
              Headers.contentTypeHeader: ['text/html; charset=gb18030'],
            },
          ),
        ),
      logger: logger,
    );

    expect(await client.fetchHtml(url), '<p>hola</p>');
    expect(logger.warnings.single, contains('gb18030'));
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
