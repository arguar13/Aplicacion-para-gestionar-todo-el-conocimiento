import 'package:cristo_es_el_salvador/core/data/dtos/user_dto.dart';
import 'package:cristo_es_el_salvador/core/domain/entities/user.dart';
import 'package:cristo_es_el_salvador/core/error/exceptions.dart';
import 'package:cristo_es_el_salvador/core/error/failures.dart';
import 'package:cristo_es_el_salvador/core/telemetry/telemetry_service.dart';
import 'package:cristo_es_el_salvador/features/dashboard/data/datasources/dashboard_remote_data_source.dart';
import 'package:cristo_es_el_salvador/features/dashboard/data/repositories/dashboard_repository_impl.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:mocktail/mocktail.dart';

class MockDashboardRemoteDataSource extends Mock
    implements DashboardRemoteDataSource {}

class MockTelemetryService extends Mock implements TelemetryService {}

void main() {
  late MockDashboardRemoteDataSource remoteDataSource;
  late MockTelemetryService telemetry;
  late DashboardRepositoryImpl repository;

  const tUserDto = UserDTO(
    id: '1',
    name: 'Ana Ejemplo',
    email: 'ana@example.com',
  );
  const tUser = User(id: '1', name: 'Ana Ejemplo', email: 'ana@example.com');

  setUp(() {
    remoteDataSource = MockDashboardRemoteDataSource();
    telemetry = MockTelemetryService();
    repository = DashboardRepositoryImpl(
      remoteDataSource: remoteDataSource,
      telemetry: telemetry,
    );
  });

  group('getCurrentUser', () {
    test('mapea el UserDTO a la entidad User cuando el data source '
        'responde con éxito', () async {
      // Arrange
      when(
        () => remoteDataSource.getCurrentUser(),
      ).thenAnswer((_) async => tUserDto);

      // Act
      final result = await repository.getCurrentUser();

      // Assert
      expect(result, equals(const Right<Failure, User>(tUser)));
    });

    test('retorna Failure.unauthorized cuando el data source lanza '
        'UnauthorizedException', () async {
      // Arrange
      when(
        () => remoteDataSource.getCurrentUser(),
      ).thenThrow(const UnauthorizedException(message: 'Tu sesión expiró.'));

      // Act
      final result = await repository.getCurrentUser();

      // Assert
      expect(
        result,
        equals(
          const Left<Failure, User>(
            Failure.unauthorized(message: 'Tu sesión expiró.'),
          ),
        ),
      );
    });

    test(
      'retorna Failure.server cuando el data source lanza ServerException',
      () async {
        // Arrange
        when(
          () => remoteDataSource.getCurrentUser(),
        ).thenThrow(const ServerException(message: 'Boom', statusCode: 500));

        // Act
        final result = await repository.getCurrentUser();

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
          () => remoteDataSource.getCurrentUser(),
        ).thenThrow(const NetworkException(message: 'Sin conexión'));

        // Act
        final result = await repository.getCurrentUser();

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
      when(() => remoteDataSource.getCurrentUser()).thenThrow(TypeError());

      // Act
      final result = await repository.getCurrentUser();

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
