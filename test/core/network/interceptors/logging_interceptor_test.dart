import 'dart:typed_data';

import 'package:cristo_es_el_salvador/core/logging/app_logger.dart';
import 'package:cristo_es_el_salvador/core/network/interceptors/logging_interceptor.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockAppLogger extends Mock implements AppLogger {}

class _StubHttpClientAdapter implements HttpClientAdapter {
  _StubHttpClientAdapter(this.statusCode);

  final int statusCode;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    return ResponseBody.fromString(
      '{}',
      statusCode,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  late MockAppLogger logger;

  setUp(() {
    logger = MockAppLogger();
  });

  test(
    'registra el request y la respuesta, y deja pasar la respuesta sin tocarla',
    () async {
      // Arrange
      final dio = Dio(BaseOptions(baseUrl: 'https://example.com'))
        ..httpClientAdapter = _StubHttpClientAdapter(200)
        ..interceptors.add(NetworkLoggingInterceptor(logger: logger));

      // Act
      final response = await dio.get<void>('/user');

      // Assert
      expect(response.statusCode, 200);
      verify(() => logger.debug(any())).called(2);
    },
  );

  test('registra el error y deja pasar el DioException sin tocarlo', () async {
    // Arrange
    final dio = Dio(BaseOptions(baseUrl: 'https://example.com'))
      ..httpClientAdapter = _StubHttpClientAdapter(500)
      ..interceptors.add(NetworkLoggingInterceptor(logger: logger));

    // Act
    DioException? caught;
    try {
      await dio.get<void>('/user');
    } on DioException catch (e) {
      caught = e;
    }

    // Assert
    expect(caught?.response?.statusCode, 500);
    verify(() => logger.debug(any())).called(2); // request + error
  });
}
