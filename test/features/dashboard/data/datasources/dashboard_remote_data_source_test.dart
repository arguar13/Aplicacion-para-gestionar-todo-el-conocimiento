import 'package:cristo_es_el_salvador/core/error/exceptions.dart';
import 'package:cristo_es_el_salvador/features/dashboard/data/datasources/dashboard_remote_data_source.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockDio extends Mock implements Dio {}

void main() {
  late MockDio dio;
  late DashboardRemoteDataSourceImpl dataSource;

  const tPath = '/user';

  setUp(() {
    dio = MockDio();
    dataSource = DashboardRemoteDataSourceImpl(dio);
  });

  Response<Map<String, dynamic>> responseWith({
    required int statusCode,
    Map<String, dynamic>? data,
  }) {
    return Response(
      requestOptions: RequestOptions(path: tPath),
      statusCode: statusCode,
      data: data,
    );
  }

  DioException dioExceptionWith({
    required DioExceptionType type,
    Response<dynamic>? response,
  }) {
    return DioException(
      requestOptions: RequestOptions(path: tPath),
      type: type,
      response: response,
    );
  }

  group('getCurrentUser', () {
    test('retorna el UserDTO correcto cuando la respuesta es HTTP 200, sin '
        'tocar headers (el interceptor pone el Authorization)', () async {
      // Arrange
      final tJson = {
        'id': '1',
        'name': 'Ana Ejemplo',
        'email': 'ana@example.com',
      };
      when(
        () => dio.get<Map<String, dynamic>>(tPath),
      ).thenAnswer((_) async => responseWith(statusCode: 200, data: tJson));

      // Act
      final result = await dataSource.getCurrentUser();

      // Assert
      expect(result.id, '1');
      expect(result.name, 'Ana Ejemplo');
      expect(result.email, 'ana@example.com');
    });

    test('lanza UnauthorizedException cuando el backend responde 401 '
        '(token vencido/inválido, no login)', () async {
      // Arrange
      when(() => dio.get<Map<String, dynamic>>(tPath)).thenThrow(
        dioExceptionWith(
          type: DioExceptionType.badResponse,
          response: responseWith(statusCode: 401),
        ),
      );

      // Act
      final call = dataSource.getCurrentUser();

      // Assert
      await expectLater(call, throwsA(isA<UnauthorizedException>()));
    });

    test('lanza ServerException cuando el backend responde 500', () async {
      // Arrange
      when(() => dio.get<Map<String, dynamic>>(tPath)).thenThrow(
        dioExceptionWith(
          type: DioExceptionType.badResponse,
          response: responseWith(statusCode: 500),
        ),
      );

      // Act
      final call = dataSource.getCurrentUser();

      // Assert
      await expectLater(call, throwsA(isA<ServerException>()));
    });

    test(
      'lanza NetworkException cuando hay timeout de conexión (sin response)',
      () async {
        // Arrange
        when(
          () => dio.get<Map<String, dynamic>>(tPath),
        ).thenThrow(dioExceptionWith(type: DioExceptionType.connectionTimeout));

        // Act
        final call = dataSource.getCurrentUser();

        // Assert
        await expectLater(call, throwsA(isA<NetworkException>()));
      },
    );

    test(
      'edge case: JSON malformado (200 sin el campo "email") propaga el '
      'error de parseo tal cual, sin envolverlo en una excepción de dominio',
      () async {
        // Arrange
        when(() => dio.get<Map<String, dynamic>>(tPath)).thenAnswer(
          (_) async =>
              responseWith(statusCode: 200, data: {'id': '1', 'name': 'Ana'}),
        );

        // Act
        final call = dataSource.getCurrentUser();

        // Assert: igual que en auth_remote_data_source_test, el data source
        // solo atrapa DioException; DashboardRepositoryImpl es quien
        // convierte esto en Failure.unexpected.
        await expectLater(call, throwsA(isA<TypeError>()));
      },
    );
  });
}
