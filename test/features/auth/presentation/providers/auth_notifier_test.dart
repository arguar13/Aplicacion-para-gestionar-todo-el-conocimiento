import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:mocktail/mocktail.dart';
import 'package:sinapsis/core/domain/entities/user.dart';
import 'package:sinapsis/core/error/failures.dart';
import 'package:sinapsis/core/logging/app_logger.dart';
import 'package:sinapsis/core/session/session_controller.dart';
import 'package:sinapsis/features/auth/domain/usecases/login_usecase.dart';
import 'package:sinapsis/features/auth/presentation/providers/auth_notifier.dart';
import 'package:sinapsis/features/auth/presentation/providers/auth_state.dart';

class MockLoginUseCase extends Mock implements LoginUseCase {}

class MockAppLogger extends Mock implements AppLogger {}

class MockSessionController extends Mock implements SessionController {}

void main() {
  late MockLoginUseCase loginUseCase;
  late MockAppLogger logger;
  late MockSessionController sessionController;
  late AuthNotifier notifier;

  const tEmail = 'ana@example.com';
  const tPassword = 'secret123';
  const tParams = LoginParams(email: tEmail, password: tPassword);
  const tUser = User(id: '1', name: 'Ana Ejemplo', email: tEmail);

  setUp(() {
    loginUseCase = MockLoginUseCase();
    logger = MockAppLogger();
    sessionController = MockSessionController();
    notifier = AuthNotifier(
      loginUseCase: loginUseCase,
      logger: logger,
      sessionController: sessionController,
    );
  });

  test('el estado inicial es AuthState.initial', () {
    // Assert
    expect(notifier.state, const AuthState.initial());
  });

  group('login', () {
    test('happy path: Initial -> Loading -> Success, y marca la sesión '
        'autenticada cuando el caso de uso responde con éxito', () async {
      // Arrange
      when(
        () => loginUseCase(tParams),
      ).thenAnswer((_) async => const Right(tUser));
      final emittedStates = <AuthState>[];
      notifier.addListener(emittedStates.add, fireImmediately: false);

      // Act
      await notifier.login(email: tEmail, password: tPassword);

      // Assert
      expect(emittedStates, [
        const AuthState.loading(),
        const AuthState.success(tUser),
      ]);
      verify(() => sessionController.markAuthenticated()).called(1);
    });

    test('error path: Initial -> Loading -> Error, y NO marca la sesión '
        'autenticada cuando el caso de uso falla', () async {
      // Arrange
      const tFailure = Failure.unauthorized(message: 'Credenciales inválidas.');
      when(
        () => loginUseCase(tParams),
      ).thenAnswer((_) async => const Left(tFailure));
      final emittedStates = <AuthState>[];
      notifier.addListener(emittedStates.add, fireImmediately: false);

      // Act
      await notifier.login(email: tEmail, password: tPassword);

      // Assert
      expect(emittedStates, [
        const AuthState.loading(),
        const AuthState.error('Credenciales inválidas.'),
      ]);
      verifyNever(() => sessionController.markAuthenticated());
    });
  });
}
