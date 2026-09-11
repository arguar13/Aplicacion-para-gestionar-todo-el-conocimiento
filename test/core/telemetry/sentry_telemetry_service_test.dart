import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:sinapsis/core/logging/app_logger.dart';
import 'package:sinapsis/core/telemetry/sentry_telemetry_service.dart';

class MockAppLogger extends Mock implements AppLogger {}

void main() {
  late MockAppLogger logger;

  setUp(() {
    logger = MockAppLogger();
  });

  group('con enableRemoteReporting en false (dev, o sin DSN)', () {
    late SentryTelemetryService service;

    setUp(() {
      service = SentryTelemetryService(
        logger: logger,
        enableRemoteReporting: false,
        dsn: '',
        environment: 'test',
      );
    });

    test('init() es un no-op: no lanza y no intenta llamar a Sentry', () async {
      // Act / Assert: si esto llamara a `SentryFlutter.init` de verdad,
      // fallaría en un entorno de test sin bindings de plataforma.
      await expectLater(service.init(), completes);
    });

    test('recordError() solo loguea localmente, cumpliendo el requisito de '
        '"en dev, solo consola"', () {
      // Arrange
      final exception = Exception('boom');
      final stackTrace = StackTrace.current;

      // Act
      service.recordError(exception, stackTrace, hint: 'un-hint');

      // Assert
      verify(() => logger.error('un-hint', exception, stackTrace)).called(1);
    });

    test('recordError() nunca lanza, ni siquiera sin hint', () {
      expect(
        () => service.recordError(Exception('boom'), null),
        returnsNormally,
      );
    });

    test('setUserContext() no lanza (no hay conexión remota que usar)', () {
      expect(() => service.setUserContext('user-1'), returnsNormally);
      expect(() => service.setUserContext(null), returnsNormally);
    });
  });

  test(
    'un DSN vacío desactiva el reporte remoto aunque enableRemoteReporting '
    'venga en true — falla cerrado en vez de arrancar Sentry sin config',
    () async {
      // Arrange: pedirlo prendido mientras el DSN está vacío no debe hacer
      // que init() intente conectarse a Sentry (eso fallaría en test).
      final service = SentryTelemetryService(
        logger: logger,
        enableRemoteReporting: true,
        dsn: '',
        environment: 'test',
      );

      // Act / Assert
      await expectLater(service.init(), completes);
      expect(
        () => service.recordError(Exception('boom'), null),
        returnsNormally,
      );
    },
  );
}
