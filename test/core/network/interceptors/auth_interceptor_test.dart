import 'dart:typed_data';

import 'package:cristo_es_el_salvador/core/network/interceptors/auth_interceptor.dart';
import 'package:cristo_es_el_salvador/core/network/token_storage.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockTokenStorage extends Mock implements TokenStorage {}

/// En vez de tocar los handlers internos de dio (protegidos, no pensados
/// para usarse fuera del propio paquete), se corre el interceptor dentro
/// de un `Dio` real con este adapter falso que solo graba qué
/// `RequestOptions` le llegaron — la forma que el propio dio documenta
/// para probar interceptors.
class _RecordingHttpClientAdapter implements HttpClientAdapter {
  RequestOptions? lastRequestOptions;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    lastRequestOptions = options;
    return ResponseBody.fromString(
      '{}',
      200,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  late MockTokenStorage tokenStorage;
  late _RecordingHttpClientAdapter adapter;
  late Dio dio;

  setUp(() {
    tokenStorage = MockTokenStorage();
    adapter = _RecordingHttpClientAdapter();
    dio = Dio(BaseOptions(baseUrl: 'https://example.com'))
      ..httpClientAdapter = adapter
      ..interceptors.add(AuthInterceptor(tokenStorage: tokenStorage));
  });

  test(
    'agrega Authorization: Bearer <token> cuando hay un token guardado',
    () async {
      // Arrange
      when(
        () => tokenStorage.readAccessToken(),
      ).thenAnswer((_) async => 'abc123');

      // Act
      await dio.get<void>('/user');

      // Assert
      expect(
        adapter.lastRequestOptions?.headers['Authorization'],
        'Bearer abc123',
      );
    },
  );

  test(
    'no agrega el header Authorization cuando no hay token guardado',
    () async {
      // Arrange
      when(() => tokenStorage.readAccessToken()).thenAnswer((_) async => null);

      // Act
      await dio.get<void>('/user');

      // Assert
      expect(
        adapter.lastRequestOptions?.headers.containsKey('Authorization'),
        isFalse,
      );
    },
  );

  test('edge case: no agrega el header Authorization cuando el token '
      'guardado es un string vacío', () async {
    // Arrange
    when(() => tokenStorage.readAccessToken()).thenAnswer((_) async => '');

    // Act
    await dio.get<void>('/user');

    // Assert
    expect(
      adapter.lastRequestOptions?.headers.containsKey('Authorization'),
      isFalse,
    );
  });
}
