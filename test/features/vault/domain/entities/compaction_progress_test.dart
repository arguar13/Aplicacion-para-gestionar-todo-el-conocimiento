import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/features/vault/domain/entities/compaction_progress.dart';
import 'package:sinapsis/features/vault/domain/entities/compaction_result.dart';

void main() {
  group('CompactionProgress', () {
    test('el avance es lo hecho sobre el total', () {
      expect(
        const CompactionProgress(
          CompactionPhase.returning,
          done: 25,
          total: 100,
        ).fraction,
        0.25,
      );
    });

    test('sin total no hay avance que mostrar: indicador sin fin', () {
      expect(
        const CompactionProgress(CompactionPhase.rewriting).fraction,
        isNull,
      );
    });

    test('no se pasa de 1 ni baja de 0', () {
      expect(
        const CompactionProgress(
          CompactionPhase.verifying,
          done: 12,
          total: 10,
        ).fraction,
        1.0,
      );
      expect(
        const CompactionProgress(
          CompactionPhase.verifying,
          done: -3,
          total: 10,
        ).fraction,
        0.0,
      );
    });

    test('dos avisos iguales son iguales', () {
      const a = CompactionProgress(
        CompactionPhase.returning,
        done: 1,
        total: 2,
      );
      const b = CompactionProgress(
        CompactionPhase.returning,
        done: 1,
        total: 2,
      );

      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(
        a,
        isNot(const CompactionProgress(CompactionPhase.returning, total: 2)),
      );
    });
  });

  group('CompactionPhase.isCancellable', () {
    test('se puede parar antes de empezar y entre tramos', () {
      expect(CompactionPhase.checking.isCancellable, isTrue);
      expect(CompactionPhase.returning.isCancellable, isTrue);
    });

    test('no se puede parar una reescritura empezada ni la comprobación', () {
      expect(CompactionPhase.rewriting.isCancellable, isFalse);
      expect(CompactionPhase.verifying.isCancellable, isFalse);
    });
  });

  group('CompactionCancellation', () {
    test('empieza sin pedir nada y recuerda el pedido', () {
      final cancellation = CompactionCancellation();
      expect(cancellation.isRequested, isFalse);

      cancellation.cancel();

      expect(cancellation.isRequested, isTrue);
    });
  });

  group('CompactionResult.freedBytes', () {
    test('es lo que se devolvió', () {
      const result = CompactionResult(
        bytesBefore: 900,
        bytesAfter: 400,
        elapsed: Duration(seconds: 3),
      );

      expect(result.freedBytes, 500);
    });

    test('nunca es negativo: compactar no agranda', () {
      const result = CompactionResult(
        bytesBefore: 400,
        bytesAfter: 410,
        elapsed: Duration.zero,
      );

      expect(result.freedBytes, 0);
    });
  });
}
