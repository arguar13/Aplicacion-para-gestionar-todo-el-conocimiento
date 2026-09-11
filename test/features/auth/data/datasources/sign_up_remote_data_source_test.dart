import 'package:cristo_es_el_salvador/core/error/exceptions.dart';
import 'package:cristo_es_el_salvador/features/auth/data/datasources/sign_up_remote_data_source.dart';
import 'package:cristo_es_el_salvador/features/auth/domain/errors/auth_exceptions.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockDio extends Mock implements Dio {}

void main() {
  late MockDio dio;
  late SignUpRemoteDataSourceImpl dataSource;

  const tPath = '/signup';
  const tName = 'Ana Ejemplo';
  const tEmail = 'ana@example.com';
  const tPassword = 'secret123';
  const tRequestData = {'name': tName, 'email': tEmail, 'password': tPassword};

  setUp(() {
    dio = MockDio();
    dataSource = SignUpRemoteDataSourceImpl(dio);
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

  group('signUp', () {
    test('retorna un LoginResponseDto con el token y el UserDTO del backend '
        'cuando la respuesta es HTTP 201', () async {
      // Arrange
      final tJson = {
        'token': 'mock-token-1',
        'user': {'id': '1', 'name': tName, 'email': tEmail},
      };
      when(
        () => dio.post<Map<String, dynamic>>(tPath, data: tRequestData),
      ).thenAnswer((_) async => responseWith(statusCode: 201, data: tJson));

      // Act
      final result = await dataSource.signUp(
        name: tName,
        email: tEmail,
        password: tPassword,
      );

      // Assert
      expect(result.token, 'mock-token-1');
      expect(result.user.id, '1');
      expect(result.user.name, tName);
      expect(result.user.email, tEmail);
    });

    test('lanza EmailAlreadyInUseException cuando el backend responde 400 '
        '(correo ya registrado)', () async {
      // Arrange
      when(
        () => dio.post<Map<String, dynamic>>(tPath, data: tRequestData),
      ).thenThrow(
        dioExceptionWith(
          type: DioExceptionType.badResponse,
          response: responseWith(statusCode: 400),
        ),
      );

      // Act
      final call = dataSource.signUp(
        name: tName,
        email: tEmail,
        password: tPassword,
      );

      // Assert
      await expectLater(call, throwsA(isA<EmailAlreadyInUseException>()));
    });

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
      final call = dataSource.signUp(
        name: tName,
        email: tEmail,
        password: tPassword,
      );

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
        final call = dataSource.signUp(
          name: tName,
          email: tEmail,
          password: tPassword,
        );

        // Assert
        await expectLater(call, throwsA(isA<NetworkException>()));
      },
    );

    test(
      'edge case: JSON malformado (201 sin el campo "user") propaga el '
      'error de parseo tal cual, sin envolverlo en una excepción de dominio',
      () async {
        // Arrange
        when(
          () => dio.post<Map<String, dynamic>>(tPath, data: tRequestData),
        ).thenAnswer(
          (_) async => responseWith(statusCode: 201, data: {'token': 'x'}),
        );

        // Act
        final call = dataSource.signUp(
          name: tName,
          email: tEmail,
          password: tPassword,
        );

        // Assert
        await expectLater(call, throwsA(isA<TypeError>()));
      },
    );
  });
}
