import 'dart:ui';

import 'package:cristo_es_el_salvador/core/domain/entities/user.dart';
import 'package:cristo_es_el_salvador/core/error/failures.dart';
import 'package:cristo_es_el_salvador/core/logging/app_logger.dart';
import 'package:cristo_es_el_salvador/core/session/session_controller.dart';
import 'package:cristo_es_el_salvador/features/auth/domain/usecases/sign_up_usecase.dart';
import 'package:cristo_es_el_salvador/features/auth/presentation/providers/auth_state.dart';
import 'package:cristo_es_el_salvador/features/auth/presentation/providers/sign_up_notifier.dart';
import 'package:cristo_es_el_salvador/l10n/generated/app_localizations_en.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:mocktail/mocktail.dart';

class MockSignUpUseCase extends Mock implements SignUpUseCase {}

class MockAppLogger extends Mock implements AppLogger {}

class MockSessionController extends Mock implements SessionController {}

void main() {
  late MockSignUpUseCase signUpUseCase;
  late MockAppLogger logger;
  late MockSessionController sessionController;
  late SignUpNotifier notifier;

  const tName = 'Ana Ejemplo';
  const tEmail = 'ana@example.com';
  const tPassword = 'secret123';
  const tParams = SignUpParams(name: tName, email: tEmail, password: tPassword);
  const tUser = User(id: '1', name: tName, email: tEmail);

  setUpAll(() {
    // Requerido por mocktail para poder usar `any()` con `SignUpParams`
    // (un tipo propio, no uno de los primitivos que ya trae registrados)
    // en `verifyNever(() => signUpUseCase(any()))`.
    registerFallbackValue(
      const SignUpParams(name: '', email: '', password: ''),
    );
  });

  setUp(() {
    signUpUseCase = MockSignUpUseCase();
    logger = MockAppLogger();
    sessionController = MockSessionController();
    notifier = SignUpNotifier(
      signUpUseCase: signUpUseCase,
      logger: logger,
      sessionController: sessionController,
      locale: const Locale('en'),
    );
  });

  test('el estado inicial es AuthState.initial', () {
    // Assert
    expect(notifier.state, const AuthState.initial());
  });

  group('signUp', () {
    test('happy path: Initial -> Loading -> Success, y marca la sesión '
        'autenticada cuando las contraseñas coinciden y el caso de uso '
        'responde con éxito', () async {
      // Arrange
      when(
        () => signUpUseCase(tParams),
      ).thenAnswer((_) async => const Right(tUser));
      final emittedStates = <AuthState>[];
      notifier.addListener(emittedStates.add, fireImmediately: false);

      // Act
      await notifier.signUp(
        name: tName,
        email: tEmail,
        password: tPassword,
        confirmPassword: tPassword,
      );

      // Assert
      expect(emittedStates, [
        const AuthState.loading(),
        const AuthState.success(tUser),
      ]);
      verify(() => sessionController.markAuthenticated()).called(1);
    });

    test('si las contraseñas no coinciden, va directo a Error SIN pasar por '
        'Loading, y nunca llama al caso de uso', () async {
      // Arrange
      final emittedStates = <AuthState>[];
      notifier.addListener(emittedStates.add, fireImmediately: false);

      // Act
      await notifier.signUp(
        name: tName,
        email: tEmail,
        password: tPassword,
        confirmPassword: 'otra-contraseña',
      );

      // Assert: un solo estado emitido — nunca pasó por loading, porque
      // esta validación es síncrona y no depende de ningún caso de uso.
      // El mensaje esperado sale del mismo AppLocalizations generado que
      // usa el notifier (locale 'en', el que se le inyectó en el setUp).
      expect(emittedStates, [
        AuthState.error(AppLocalizationsEn().passwordsDoNotMatchError),
      ]);
      verifyNever(() => signUpUseCase(any()));
      verifyNever(() => sessionController.markAuthenticated());
    });

    test('error path: Initial -> Loading -> Error, y NO marca la sesión '
        'autenticada cuando las contraseñas coinciden pero el caso de uso '
        'falla (ej. correo ya registrado)', () async {
      // Arrange
      const tFailure = Failure.validation(
        message: 'Ese correo ya está registrado.',
      );
      when(
        () => signUpUseCase(tParams),
      ).thenAnswer((_) async => const Left(tFailure));
      final emittedStates = <AuthState>[];
      notifier.addListener(emittedStates.add, fireImmediately: false);

      // Act
      await notifier.signUp(
        name: tName,
        email: tEmail,
        password: tPassword,
        confirmPassword: tPassword,
      );

      // Assert
      expect(emittedStates, [
        const AuthState.loading(),
        const AuthState.error('Ese correo ya está registrado.'),
      ]);
      verifyNever(() => sessionController.markAuthenticated());
    });
  });
}
