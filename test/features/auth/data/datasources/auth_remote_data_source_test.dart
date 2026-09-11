import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:sinapsis/core/error/exceptions.dart';
import 'package:sinapsis/features/auth/data/datasources/auth_remote_data_source.dart';
import 'package:sinapsis/features/auth/domain/errors/auth_exceptions.dart';

class MockDio extends Mock implements Dio {}

void main() {
  late MockDio dio;
  late AuthRemoteDataSourceImpl dataSource;

  const tPath = '/login';
  const tEmail = 'ana@example.com';
  const tPassword = 'secret123';
  const tRequestData = {'email': tEmail, 'password': tPassword};

  setUp(() {
    dio = MockDio();
    dataSource = AuthRemoteDataSourceImpl(dio);
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

  group('login', () {
    test('retorna un LoginResponseDto con el token y el UserDTO del backend '
        'cuando la respuesta es HTTP 200', () async {
      // Arrange
      final tJson = {
        'token': 'mock-token-1',
        'user': {'id': '1', 'name': 'Ana Ejemplo', 'email': tEmail},
      };
      when(
        () => dio.post<Map<String, dynamic>>(tPath, data: tRequestData),
      ).thenAnswer((_) async => responseWith(statusCode: 200, data: tJson));

      // Act
      final result = await dataSource.login(email: tEmail, password: tPassword);

      // Assert
      expect(result.token, 'mock-token-1');
      expect(result.user.id, '1');
      expect(result.user.name, 'Ana Ejemplo');
      expect(result.user.email, tEmail);
    });

    test(
      'lanza InvalidCredentialsException cuando el backend responde 401',
      () async {
        // Arrange
        when(
          () => dio.post<Map<String, dynamic>>(tPath, data: tRequestData),
        ).thenThrow(
          dioExceptionWith(
            type: DioExceptionType.badResponse,
            response: responseWith(statusCode: 401),
          ),
        );

        // Act
        final call = dataSource.login(email: tEmail, password: tPassword);

        // Assert
        await expectLater(call, throwsA(isA<InvalidCredentialsException>()));
      },
    );

    test('lanza ServerException cuando el backend responde 500', () async {
      // Arrange
      when(
        () => dio.post<Map<String, dynamic>>(tPath, data: tRequestData),
      ).thenThrow(
        dioExceptionWith(
          type: DioExceptionType.badResponse,
          response: responseWith(statusCode: 500),
        ),
      );

      // Act
      final call = dataSource.login(email: tEmail, password: tPassword);

      // Assert
      await expectLater(call, throwsA(isA<ServerException>()));
    });

    test(
      'lanza NetworkException cuando hay timeout de conexión (sin response)',
      () async {
        // Arrange
        when(
          () => dio.post<Map<String, dynamic>>(tPath, data: tRequestData),
        ).thenThrow(dioExceptionWith(type: DioExceptionType.connectionTimeout));

        // Act
        final call = dataSource.login(email: tEmail, password: tPassword);

        // Assert
        await expectLater(call, throwsA(isA<NetworkException>()));
      },
    );

    test(
      'edge case: JSON malformado (200 sin el campo "user") propaga el '
      'error de parseo tal cual, sin envolverlo en una excepción de dominio',
      () async {
        // Arrange
        when(
          () => dio.post<Map<String, dynamic>>(tPath, data: tRequestData),
        ).thenAnswer(
          (_) async => responseWith(statusCode: 200, data: {'token': 'x'}),
        );

        // Act
        final call = dataSource.login(email: tEmail, password: tPassword);

        // Assert: AuthRemoteDataSource solo atrapa DioException; un fallo de
        // deserialización (TypeError, campo requerido ausente) no es de
        // red, así que se deja pasar — AuthRepositoryImpl es quien lo
        // convierte en Failure.unexpected (ver auth_repository_impl_test).
        await expectLater(call, throwsA(isA<TypeError>()));
      },
    );
  });
}
