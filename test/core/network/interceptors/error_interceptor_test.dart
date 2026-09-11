import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:sinapsis/core/error/exceptions.dart';
import 'package:sinapsis/core/logging/app_logger.dart';
import 'package:sinapsis/core/network/interceptors/error_interceptor.dart';
import 'package:sinapsis/core/telemetry/telemetry_service.dart';

class MockAppLogger extends Mock implements AppLogger {}

class MockTelemetryService extends Mock implements TelemetryService {}

class _FailingHttpClientAdapter implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    return ResponseBody.fromString(
      '{"message":"boom"}',
      500,
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
  late MockTelemetryService telemetry;
  late Exception? reportedToBus;
  late Dio dio;

  setUp(() {
    logger = MockAppLogger();
    telemetry = MockTelemetryService();
    reportedToBus = null;
    dio = Dio(BaseOptions(baseUrl: 'https://example.com'))
      ..httpClientAdapter = _FailingHttpClientAdapter()
      ..interceptors.add(
        GlobalErrorInterceptor(
          logger: logger,
          telemetry: telemetry,
          onDomainError: (exception) => reportedToBus = exception,
        ),
      );
  });

  test('registra el fallo en el logger y deja pasar el DioException intacto '
      '(sin transformarlo)', () async {
    // Act
    DioException? caught;
    try {
      await dio.get<void>('/user');
    } on DioException catch (e) {
      caught = e;
    }

    // Assert: el interceptor no cambia nada del error, solo lo observa.
    expect(caught, isNotNull);
    expect(caught!.response?.statusCode, 500);
    expect(caught.type, DioExceptionType.badResponse);
    verify(() => logger.error(any(), caught, any())).called(1);
  });

  test(
    'reporta la excepción de dominio mapeada al bus global de errores',
    () async {
      // Act
      try {
        await dio.get<void>('/user');
      } on DioException {
        // Ignorado: lo que importa acá es el side-effect sobre el bus.
      }

      // Assert: 500 sin ser 401/403 mapea a ServerException (ver
      // dio_exception_mapper.dart).
      expect(reportedToBus, isA<ServerException>());
    },
  );

  test('reporta a telemetría un ServerException (posible bug real), a '
      'diferencia de un fallo esperado como NetworkException/401', () async {
    // Act
    try {
      await dio.get<void>('/user');
    } on DioException {
      // Ignorado: lo que importa acá es el side-effect sobre telemetría.
    }

    // Assert
    verify(
      () => telemetry.recordError(
        any<dynamic>(),
        any<StackTrace?>(),
        hint: any<String?>(named: 'hint'),
      ),
    ).called(1);
  });
}
