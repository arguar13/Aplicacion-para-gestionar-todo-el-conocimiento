import 'package:cristo_es_el_salvador/core/data/dtos/user_dto.dart';
import 'package:cristo_es_el_salvador/core/domain/entities/user.dart';
import 'package:cristo_es_el_salvador/core/error/exceptions.dart';
import 'package:cristo_es_el_salvador/core/error/failures.dart';
import 'package:cristo_es_el_salvador/core/network/token_storage.dart';
import 'package:cristo_es_el_salvador/core/telemetry/telemetry_service.dart';
import 'package:cristo_es_el_salvador/features/auth/data/datasources/auth_remote_data_source.dart';
import 'package:cristo_es_el_salvador/features/auth/data/datasources/sign_up_remote_data_source.dart';
import 'package:cristo_es_el_salvador/features/auth/data/dtos/login_response_dto.dart';
import 'package:cristo_es_el_salvador/features/auth/data/repositories/auth_repository_impl.dart';
import 'package:cristo_es_el_salvador/features/auth/domain/errors/auth_exceptions.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:mocktail/mocktail.dart';

class MockAuthRemoteDataSource extends Mock implements AuthRemoteDataSource {}

class MockSignUpRemoteDataSource extends Mock
    implements SignUpRemoteDataSource {}

class MockTokenStorage extends Mock implements TokenStorage {}

class MockTelemetryService extends Mock implements TelemetryService {}

void main() {
  late MockAuthRemoteDataSource remoteDataSource;
  late MockSignUpRemoteDataSource signUpRemoteDataSource;
  late MockTokenStorage tokenStorage;
  late MockTelemetryService telemetry;
  late AuthRepositoryImpl repository;

  const tName = 'Ana Ejemplo';
  const tEmail = 'ana@example.com';
  const tPassword = 'secret123';
  const tUserDto = UserDTO(id: '1', name: tName, email: tEmail);
  const tUser = User(id: '1', name: tName, email: tEmail);
  const tLoginResponse = LoginResponseDto(
    token: 'mock-token-1',
    user: tUserDto,
  );

  setUp(() {
    remoteDataSource = MockAuthRemoteDataSource();
    signUpRemoteDataSource = MockSignUpRemoteDataSource();
    tokenStorage = MockTokenStorage();
    telemetry = MockTelemetryService();
    repository = AuthRepositoryImpl(
      remoteDataSource: remoteDataSource,
      signUpRemoteDataSource: signUpRemoteDataSource,
      tokenStorage: tokenStorage,
      telemetry: telemetry,
    );
    // Stub por defecto para no repetirlo en cada test que sí llega a
    // guardar el token; los tests de error nunca lo invocan (se verifica
    // con verifyNever donde corresponde).
    when(() => tokenStorage.saveAccessToken(any())).thenAnswer((_) async {});
  });

  group('login', () {
    test('mapea el UserDTO a la entidad User y guarda el token cuando el '
        'data source responde con éxito', () async {
      // Arrange
      when(
        () => remoteDataSource.login(email: tEmail, password: tPassword),
      ).thenAnswer((_) async => tLoginResponse);

      // Act
      final result = await repository.login(email: tEmail, password: tPassword);

      // Assert
      expect(result, equals(const Right<Failure, User>(tUser)));
      verify(() => tokenStorage.saveAccessToken('mock-token-1')).called(1);
    });

    test('retorna Failure.unauthorized cuando el data source lanza '
        'InvalidCredentialsException, y no guarda ningún token', () async {
      // Arrange
      when(
        () => remoteDataSource.login(email: tEmail, password: tPassword),
      ).thenThrow(const InvalidCredentialsException('Credenciales inválidas.'));

      // Act
      final result = await repository.login(email: tEmail, password: tPassword);

      // Assert
      expect(
        result,
        equals(
          const Left<Failure, User>(
            Failure.unauthorized(message: 'Credenciales inválidas.'),
          ),
        ),
      );
      verifyNever(() => tokenStorage.saveAccessToken(any()));
    });

    test(
      'retorna Failure.server cuando el data source lanza ServerException',
      () async {
        // Arrange
        when(
          () => remoteDataSource.login(email: tEmail, password: tPassword),
        ).thenThrow(const ServerException(message: 'Boom', statusCode: 500));

        // Act
        final result = await repository.login(
          email: tEmail,
          password: tPassword,
        );

        // Assert
        expect(
          result,
          equals(
            const Left<Failure, User>(
              Failure.server(message: 'Boom', statusCode: 500),
            ),
          ),
        );
      },
    );

    test(
      'retorna Failure.network cuando el data source lanza NetworkException',
      () async {
        // Arrange
        when(
          () => remoteDataSource.login(email: tEmail, password: tPassword),
        ).thenThrow(const NetworkException(message: 'Sin conexión'));

        // Act
        final result = await repository.login(
          email: tEmail,
          password: tPassword,
        );

        // Assert
        expect(
          result,
          equals(
            const Left<Failure, User>(Failure.network(message: 'Sin conexión')),
          ),
        );
      },
    );

    test('edge case: retorna Failure.unexpected (no lo deja escapar) cuando '
        'el data source lanza un TypeError por un JSON malformado', () async {
      // Arrange: simula lo que AuthRemoteDataSource deja pasar cuando
      // LoginResponseDto.fromJson falla (ver auth_remote_data_source_test).
      when(
        () => remoteDataSource.login(email: tEmail, password: tPassword),
      ).thenThrow(TypeError());

      // Act
      final result = await repository.login(email: tEmail, password: tPassword);

      // Assert
      expect(result.isLeft(), isTrue);
      result.match(
        (failure) => expect(failure, isA<UnexpectedFailure>()),
        (_) => fail('se esperaba un Left, llegó un Right'),
      );
      verify(
        () => telemetry.recordError(
          any<dynamic>(),
          any<StackTrace?>(),
          hint: any<String?>(named: 'hint'),
        ),
      ).called(1);
    });
  });

  group('signUp', () {
    test('mapea el UserDTO a la entidad User y guarda el token cuando el '
        'data source responde con éxito', () async {
      // Arrange
      when(
        () => signUpRemoteDataSource.signUp(
          name: tName,
          email: tEmail,
          password: tPassword,
        ),
      ).thenAnswer((_) async => tLoginResponse);

      // Act
      final result = await repository.signUp(
        name: tName,
        email: tEmail,
        password: tPassword,
      );

      // Assert
      expect(result, equals(const Right<Failure, User>(tUser)));
      verify(() => tokenStorage.saveAccessToken('mock-token-1')).called(1);
    });

    test('retorna Failure.validation cuando el data source lanza '
        'EmailAlreadyInUseException, y no guarda ningún token', () async {
      // Arrange
      when(
        () => signUpRemoteDataSource.signUp(
          name: tName,
          email: tEmail,
          password: tPassword,
        ),
      ).thenThrow(const EmailAlreadyInUseException());

      // Act
      final result = await repository.signUp(
        name: tName,
        email: tEmail,
        password: tPassword,
      );

      // Assert
      expect(
        result,
        equals(
          const Left<Failure, User>(
            Failure.validation(message: 'Ese correo ya está registrado.'),
          ),
        ),
      );
      verifyNever(() => tokenStorage.saveAccessToken(any()));
    });

    test(
      'retorna Failure.server cuando el data source lanza ServerException',
      () async {
        // Arrange
        when(
          () => signUpRemoteDataSource.signUp(
            name: tName,
            email: tEmail,
            password: tPassword,
          ),
        ).thenThrow(const ServerException(message: 'Boom', statusCode: 500));

        // Act
        final result = await repository.signUp(
          name: tName,
          email: tEmail,
          password: tPassword,
        );

        // Assert
        expect(
          result,
          equals(
            const Left<Failure, User>(
              Failure.server(message: 'Boom', statusCode: 500),
            ),
          ),
        );
      },
    );

    test(
      'retorna Failure.network cuando el data source lanza NetworkException',
      () async {
        // Arrange
        when(
          () => signUpRemoteDataSource.signUp(
            name: tName,
            email: tEmail,
            password: tPassword,
          ),
        ).thenThrow(const NetworkException(message: 'Sin conexión'));

        // Act
        final result = await repository.signUp(
          name: tName,
          email: tEmail,
          password: tPassword,
        );

        // Assert
        expect(
          result,
          equals(
            const Left<Failure, User>(Failure.network(message: 'Sin conexión')),
          ),
        );
      },
    );

    test('edge case: retorna Failure.unexpected (no lo deja escapar) cuando '
        'el data source lanza un TypeError por un JSON malformado', () async {
      // Arrange
      when(
        () => signUpRemoteDataSource.signUp(
          name: tName,
          email: tEmail,
          password: tPassword,
        ),
      ).thenThrow(TypeError());

      // Act
      final result = await repository.signUp(
        name: tName,
        email: tEmail,
        password: tPassword,
      );

      // Assert
      expect(result.isLeft(), isTrue);
      result.match(
        (failure) => expect(failure, isA<UnexpectedFailure>()),
        (_) => fail('se esperaba un Left, llegó un Right'),
      );
      verify(
        () => telemetry.recordError(
          any<dynamic>(),
          any<StackTrace?>(),
          hint: any<String?>(named: 'hint'),
        ),
      ).called(1);
    });
  });
}
