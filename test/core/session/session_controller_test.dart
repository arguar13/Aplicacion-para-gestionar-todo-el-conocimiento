import 'package:cristo_es_el_salvador/core/logging/app_logger.dart';
import 'package:cristo_es_el_salvador/core/network/token_storage.dart';
import 'package:cristo_es_el_salvador/core/session/session_controller.dart';
import 'package:cristo_es_el_salvador/core/session/session_state.dart';
import 'package:cristo_es_el_salvador/core/telemetry/telemetry_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockTokenStorage extends Mock implements TokenStorage {}

class MockAppLogger extends Mock implements AppLogger {}

class MockTelemetryService extends Mock implements TelemetryService {}

void main() {
  late MockTokenStorage tokenStorage;
  late MockAppLogger logger;
  late MockTelemetryService telemetry;
  late SessionController controller;

  setUp(() {
    tokenStorage = MockTokenStorage();
    logger = MockAppLogger();
    telemetry = MockTelemetryService();
    controller = SessionController(
      tokenStorage: tokenStorage,
      logger: logger,
      telemetry: telemetry,
    );
  });

  test('el estado inicial es SessionState.unknown, antes de revisar '
      'el almacenamiento', () {
    // Assert
    expect(controller.state, const SessionState.unknown());
  });

  group('checkInitialSession', () {
    test('emite authenticated cuando hay un token guardado', () async {
      // Arrange
      when(
        () => tokenStorage.readAccessToken(),
      ).thenAnswer((_) async => 'a-valid-token');

      // Act
      await controller.checkInitialSession();

      // Assert
      expect(controller.state, const SessionState.authenticated());
    });

    test('emite unauthenticated cuando no hay token guardado (null)', () async {
      // Arrange
      when(() => tokenStorage.readAccessToken()).thenAnswer((_) async => null);

      // Act
      await controller.checkInitialSession();

      // Assert
      expect(controller.state, const SessionState.unauthenticated());
    });

    test('edge case: emite unauthenticated cuando el token guardado '
        'es un string vacío', () async {
      // Arrange
      when(() => tokenStorage.readAccessToken()).thenAnswer((_) async => '');

      // Act
      await controller.checkInitialSession();

      // Assert
      expect(controller.state, const SessionState.unauthenticated());
    });

    test('edge case: si leer el almacenamiento lanza, cae a unauthenticated '
        '(fail closed) y lo registra en los logs', () async {
      // Arrange
      final tException = Exception('Keychain no disponible');
      when(() => tokenStorage.readAccessToken()).thenThrow(tException);

      // Act
      await controller.checkInitialSession();

      // Assert
      expect(controller.state, const SessionState.unauthenticated());
      verify(() => logger.error(any(), tException, any())).called(1);
    });

    test('edge case: una vez resuelto el estado, una segunda llamada no '
        'vuelve a leer el almacenamiento (guard de "solo una vez")', () async {
      // Arrange
      when(
        () => tokenStorage.readAccessToken(),
      ).thenAnswer((_) async => 'a-valid-token');
      await controller.checkInitialSession();

      // Act
      await controller.checkInitialSession();

      // Assert
      verify(() => tokenStorage.readAccessToken()).called(1);
    });
  });

  test(
    'markAuthenticated cambia el estado a authenticated de forma síncrona',
    () {
      // Act
      controller.markAuthenticated();

      // Assert
      expect(controller.state, const SessionState.authenticated());
    },
  );

  group('logout', () {
    test(
      'borra el token guardado y cambia el estado a unauthenticated',
      () async {
        // Arrange
        when(() => tokenStorage.clearTokens()).thenAnswer((_) async {});
        controller.markAuthenticated();

        // Act
        await controller.logout();

        // Assert
        expect(controller.state, const SessionState.unauthenticated());
        verify(() => tokenStorage.clearTokens()).called(1);
      },
    );

    test('borra el id de usuario asociado a telemetría (nunca debe quedar '
        'un reporte posterior atribuido a quien ya cerró sesión)', () async {
      // Arrange
      when(() => tokenStorage.clearTokens()).thenAnswer((_) async {});

      // Act
      await controller.logout();

      // Assert
      verify(() => telemetry.setUserContext(null)).called(1);
    });
  });
}
