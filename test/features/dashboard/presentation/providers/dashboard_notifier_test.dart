import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:mocktail/mocktail.dart';
import 'package:sinapsis/core/domain/entities/user.dart';
import 'package:sinapsis/core/error/failures.dart';
import 'package:sinapsis/core/logging/app_logger.dart';
import 'package:sinapsis/core/telemetry/telemetry_service.dart';
import 'package:sinapsis/core/usecase/usecase.dart';
import 'package:sinapsis/features/dashboard/domain/usecases/get_current_user_usecase.dart';
import 'package:sinapsis/features/dashboard/presentation/providers/dashboard_notifier.dart';
import 'package:sinapsis/features/dashboard/presentation/providers/dashboard_state.dart';

class MockGetCurrentUserUseCase extends Mock implements GetCurrentUserUseCase {}

class MockAppLogger extends Mock implements AppLogger {}

class MockTelemetryService extends Mock implements TelemetryService {}

void main() {
  late MockGetCurrentUserUseCase getCurrentUser;
  late MockAppLogger logger;
  late MockTelemetryService telemetry;
  late DashboardNotifier notifier;

  const tUser = User(id: '1', name: 'Ana Ejemplo', email: 'ana@example.com');

  setUp(() {
    getCurrentUser = MockGetCurrentUserUseCase();
    logger = MockAppLogger();
    telemetry = MockTelemetryService();
    notifier = DashboardNotifier(
      getCurrentUser: getCurrentUser,
      logger: logger,
      telemetry: telemetry,
    );
  });

  test('el estado inicial es DashboardState.initial', () {
    // Assert
    expect(notifier.state, const DashboardState.initial());
  });

  group('loadCurrentUser', () {
    test('happy path: Initial -> Loading -> Loaded(user) cuando el caso de '
        'uso responde con éxito tras la inicialización', () async {
      // Arrange
      when(
        () => getCurrentUser(const NoParams()),
      ).thenAnswer((_) async => const Right(tUser));
      final emittedStates = <DashboardState>[];
      notifier.addListener(emittedStates.add, fireImmediately: false);

      // Act
      await notifier.loadCurrentUser();

      // Assert
      expect(emittedStates, [
        const DashboardState.loading(),
        const DashboardState.loaded(tUser),
      ]);
      verify(() => telemetry.setUserContext(tUser.id)).called(1);
    });

    test(
      'error path: Initial -> Loading -> Error cuando el caso de uso falla',
      () async {
        // Arrange
        const tFailure = Failure.network(message: 'Sin conexión');
        when(
          () => getCurrentUser(const NoParams()),
        ).thenAnswer((_) async => const Left(tFailure));
        final emittedStates = <DashboardState>[];
        notifier.addListener(emittedStates.add, fireImmediately: false);

        // Act
        await notifier.loadCurrentUser();

        // Assert
        expect(emittedStates, [
          const DashboardState.loading(),
          const DashboardState.error('Sin conexión'),
        ]);
      },
    );
  });
}
