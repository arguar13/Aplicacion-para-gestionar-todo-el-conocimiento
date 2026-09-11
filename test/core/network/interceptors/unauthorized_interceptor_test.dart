import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:sinapsis/core/logging/app_logger.dart';
import 'package:sinapsis/core/network/interceptors/unauthorized_interceptor.dart';

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
  late bool onUnauthorizedCalled;

  setUp(() {
    logger = MockAppLogger();
    onUnauthorizedCalled = false;
  });

  Dio buildDio(int statusCode) {
    return Dio(BaseOptions(baseUrl: 'https://example.com'))
      ..httpClientAdapter = _StubHttpClientAdapter(statusCode)
      ..interceptors.add(
        UnauthorizedInterceptor(
          onUnauthorized: () async => onUnauthorizedCalled = true,
          logger: logger,
        ),
      );
  }

  test(
    'llama a onUnauthorized cuando el backend responde 401 fuera de /login',
    () async {
      // Arrange
      final dio = buildDio(401);

      // Act
      try {
        await dio.get<void>('/user');
      } on DioException catch (_) {}

      // Assert
      expect(onUnauthorizedCalled, isTrue);
    },
  );

  test('NO llama a onUnauthorized cuando el 401 viene de /login (eso lo '
      'maneja AuthRemoteDataSource como credenciales inválidas)', () async {
    // Arrange
    final dio = buildDio(401);

    // Act
    try {
      await dio.post<void>('/login');
    } on DioException catch (_) {}

    // Assert
    expect(onUnauthorizedCalled, isFalse);
  });

  test(
    'NO llama a onUnauthorized ante otros códigos de error (ej. 500)',
    () async {
      // Arrange
      final dio = buildDio(500);

      // Act
      try {
        await dio.get<void>('/user');
      } on DioException catch (_) {}

      // Assert
      expect(onUnauthorizedCalled, isFalse);
    },
  );

  test(
    'siempre deja pasar el error, incluso cuando dispara onUnauthorized',
    () async {
      // Arrange
      final dio = buildDio(401);

      // Act
      DioException? caught;
      try {
        await dio.get<void>('/user');
      } on DioException catch (e) {
        caught = e;
      }

      // Assert
      expect(caught?.response?.statusCode, 401);
    },
  );
}
