import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/logging/app_logger.dart';
import 'package:sinapsis/features/vault/domain/entities/compaction_assessment.dart';
import 'package:sinapsis/features/vault/domain/entities/compaction_progress.dart';
import 'package:sinapsis/features/vault/domain/entities/compaction_result.dart';
import 'package:sinapsis/features/vault/domain/services/vault_compactor.dart';
import 'package:sinapsis/features/vault/presentation/providers/compaction_notifier.dart';
import 'package:sinapsis/features/vault/presentation/providers/compaction_state.dart';

/// Un compactador al que la prueba le dice cuándo y cómo termina.
class _FakeCompactor implements VaultCompactor {
  var _outcome = Completer<CompactionResult>();
  void Function(CompactionProgress)? onProgress;
  CompactionCancellation? cancellation;
  int calls = 0;

  @override
  Future<CompactionResult> compact({
    void Function(CompactionProgress progress)? onProgress,
    CompactionCancellation? cancellation,
  }) {
    calls++;
    // Cada compactación tiene su propio final.
    _outcome = Completer<CompactionResult>();
    this.onProgress = onProgress;
    this.cancellation = cancellation;
    return _outcome.future;
  }

  void finish(CompactionResult result) => _outcome.complete(result);

  void fail(Object error) => _outcome.completeError(error);
}

class _RecordingLogger implements AppLogger {
  final errors = <(String, Object?)>[];

  @override
  void error(String message, [Object? error, StackTrace? stackTrace]) =>
      errors.add((message, error));

  @override
  void debug(String message, [Object? error, StackTrace? stackTrace]) {}

  @override
  void info(String message, [Object? error, StackTrace? stackTrace]) {}

  @override
  void warning(String message, [Object? error, StackTrace? stackTrace]) {}

  @override
  void fatal(String message, [Object? error, StackTrace? stackTrace]) {}
}

const _result = CompactionResult(
  bytesBefore: 900,
  bytesAfter: 400,
  elapsed: Duration(seconds: 2),
  sourcesVerified: 7,
);

void main() {
  late _FakeCompactor compactor;
  late _RecordingLogger logger;
  late CompactionNotifier notifier;

  setUp(() {
    compactor = _FakeCompactor();
    logger = _RecordingLogger();
    notifier = CompactionNotifier(compactor: compactor, logger: logger);
  });

  tearDown(() {
    if (notifier.mounted) notifier.dispose();
  });

  test('empieza en reposo', () {
    expect(notifier.state, const CompactionState.idle());
  });

  test('empezar pasa a compactando, sigue las fases y termina con lo que '
      'devolvió', () async {
    final started = notifier.start();
    expect(
      notifier.state,
      const CompactionState.running(
        CompactionProgress(CompactionPhase.checking),
      ),
    );

    compactor.onProgress!(const CompactionProgress(CompactionPhase.rewriting));
    expect(
      notifier.state,
      const CompactionState.running(
        CompactionProgress(CompactionPhase.rewriting),
      ),
    );
    compactor.onProgress!(
      const CompactionProgress(CompactionPhase.verifying, done: 3, total: 7),
    );
    expect(
      notifier.state,
      const CompactionState.running(
        CompactionProgress(CompactionPhase.verifying, done: 3, total: 7),
      ),
    );

    compactor.finish(_result);
    await started;

    expect(notifier.state, const CompactionState.finished(_result));
  });

  test('pedir empezar con una en curso no lanza otra', () async {
    unawaited(notifier.start());
    await notifier.start();

    expect(compactor.calls, 1);
  });

  group('cuando no se pudo', () {
    test('sin lugar en el disco, guarda la medición para decir cuánto falta '
        'y no lo cuenta como error', () async {
      const assessment = CompactionAssessment(
        pageSize: 4096,
        pageCount: 1000,
        freePages: 400,
        autoVacuum: AutoVacuumMode.none,
        freeSpaceBytes: 1024,
      );
      final started = notifier.start();

      compactor.fail(const VaultCompactionNoSpaceException(assessment));
      await started;

      expect(notifier.state, const CompactionState.noSpace(assessment));
      expect(logger.errors, isEmpty);
    });

    test('si SQLite falló, lo registra con su causa y falla', () async {
      final started = notifier.start();

      compactor.fail(const VaultCompactionFailedException('disco lleno'));
      await started;

      expect(notifier.state, const CompactionState.failed());
      expect(logger.errors.single.$2, 'disco lleno');
    });

    test('si la comprobación encontró una diferencia, la lleva a la pantalla '
        'y la registra', () async {
      final started = notifier.start();

      compactor.fail(
        const VaultCompactionVerificationException('chunks 40 → 39'),
      );
      await started;

      expect(
        notifier.state,
        const CompactionState.verificationFailed('chunks 40 → 39'),
      );
      expect(logger.errors, hasLength(1));
    });

    test('un fallo que nadie previó tampoco deja la pantalla compactando '
        'para siempre', () async {
      final started = notifier.start();

      compactor.fail(StateError('no debía pasar'));
      await started;

      expect(notifier.state, const CompactionState.failed());
      expect(logger.errors, hasLength(1));
    });
  });

  group('parar', () {
    test('le pasa el pedido al compactador', () async {
      final started = notifier.start();
      expect(compactor.cancellation!.isRequested, isFalse);

      notifier.cancel();

      expect(compactor.cancellation!.isRequested, isTrue);
      compactor.finish(_result);
      await started;
    });

    test('sin nada en curso no hace nada', () {
      notifier.cancel();

      expect(notifier.state, const CompactionState.idle());
    });

    test('la siguiente arranca sin el pedido de la anterior', () async {
      final started = notifier.start();
      notifier.cancel();
      compactor.finish(_result);
      await started;

      unawaited(notifier.start());

      expect(compactor.calls, 2);
      expect(compactor.cancellation!.isRequested, isFalse);
    });
  });

  group('volver al reposo', () {
    test('después de un resultado, la pantalla vuelve a la medición', () async {
      final started = notifier.start();
      compactor.finish(_result);
      await started;

      notifier.reset();

      expect(notifier.state, const CompactionState.idle());
    });

    test('con una compactación en curso no se puede', () {
      unawaited(notifier.start());

      notifier.reset();

      expect(notifier.state, isA<CompactionRunning>());
    });
  });

  test('si la pantalla se fue compactando, terminar no rompe nada', () async {
    final started = notifier.start();
    notifier.dispose();

    compactor.onProgress!(const CompactionProgress(CompactionPhase.rewriting));
    compactor.finish(_result);
    await started;

    expect(notifier.mounted, isFalse);
  });
}
