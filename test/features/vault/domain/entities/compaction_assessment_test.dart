import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/features/vault/domain/entities/compaction_assessment.dart';

CompactionAssessment assessment({
  int pageSize = 1000,
  int pageCount = 1000,
  int freePages = 400,
  AutoVacuumMode autoVacuum = AutoVacuumMode.none,
  int? freeSpaceBytes,
}) => CompactionAssessment(
  pageSize: pageSize,
  pageCount: pageCount,
  freePages: freePages,
  autoVacuum: autoVacuum,
  freeSpaceBytes: freeSpaceBytes,
);

void main() {
  group('lo que ocupa y lo que se recupera', () {
    test('el archivo son sus páginas, y lo recuperable las libres', () {
      final a = assessment();

      expect(a.fileBytes, 1000000);
      expect(a.reclaimableBytes, 400000);
      expect(a.usefulBytes, 600000);
    });
  });

  group('cuánto disco hace falta', () {
    test('reescribir la base pide el doble de lo útil más 10 % y lo que se le '
        'deja al resto', () {
      // Útil: 600.000. Doble: 1.200.000. Holgura del 10 %: 120.000.
      expect(
        assessment().requiredBytes,
        1200000 + 120000 + kCompactionSpareBytes,
      );
    });

    test('es el doble de lo ÚTIL, no del archivo: las páginas libres no se '
        'copian', () {
      final mostlyFree = assessment(freePages: 900);
      final mostlyFull = assessment(freePages: 100);

      expect(mostlyFree.requiredBytes, lessThan(mostlyFull.requiredBytes));
      expect(
        mostlyFree.requiredBytes,
        lessThan(2 * mostlyFree.fileBytes + kCompactionSpareBytes),
      );
    });

    test('la compactación incremental solo pide lo de un tramo, con su '
        'diario', () {
      final incremental = assessment(
        pageSize: 4096,
        pageCount: 250000,
        freePages: 100000,
        autoVacuum: AutoVacuumMode.incremental,
      );

      expect(incremental.needsFullRewrite, isFalse);
      expect(incremental.requiredBytes, 2 * kIncrementalStepPages * 4096);
      // Y es una fracción de lo que pide reescribirla entera.
      expect(
        incremental.requiredBytes,
        lessThan(
          assessment(
            pageSize: 4096,
            pageCount: 250000,
            freePages: 100000,
          ).requiredBytes,
        ),
      );
    });

    test('el modo completo, que no se usa, también se reescribe para '
        'cambiarlo', () {
      expect(
        assessment(autoVacuum: AutoVacuumMode.full).needsFullRewrite,
        isTrue,
      );
    });
  });

  group('el veredicto', () {
    test('sin páginas libres no hay nada que recuperar, sobre lo que sea el '
        'disco', () {
      expect(
        assessment(freePages: 0, freeSpaceBytes: 0).verdict,
        CompactionVerdict.nothingToReclaim,
      );
      expect(
        assessment(freePages: 0).verdict,
        CompactionVerdict.nothingToReclaim,
      );
    });

    test('sin dato de disco, se puede intentar', () {
      expect(assessment().verdict, CompactionVerdict.spaceUnknown);
    });

    test('justo lo que hace falta alcanza; un byte menos, no', () {
      final need = assessment().requiredBytes;

      expect(assessment(freeSpaceBytes: need).verdict, CompactionVerdict.ready);
      final short = assessment(freeSpaceBytes: need - 1);
      expect(short.verdict, CompactionVerdict.notEnoughSpace);
      expect(short.missingBytes, 1);
    });

    test('falta lo que falta, y nada si no falta', () {
      final need = assessment().requiredBytes;

      expect(assessment(freeSpaceBytes: 0).missingBytes, need);
      expect(assessment(freeSpaceBytes: need + 5).missingBytes, 0);
      expect(assessment().missingBytes, 0);
    });
  });

  group('AutoVacuumMode.fromPragma', () {
    test('0 es ninguno, 1 completo y 2 incremental', () {
      expect(AutoVacuumMode.fromPragma(0), AutoVacuumMode.none);
      expect(AutoVacuumMode.fromPragma(1), AutoVacuumMode.full);
      expect(AutoVacuumMode.fromPragma(2), AutoVacuumMode.incremental);
    });

    test('un valor que no conoce es como ninguno', () {
      expect(AutoVacuumMode.fromPragma(7), AutoVacuumMode.none);
    });
  });

  test('dos mediciones iguales son iguales', () {
    expect(assessment(), assessment());
    expect(assessment().hashCode, assessment().hashCode);
    expect(assessment(freePages: 3), isNot(assessment(freePages: 4)));
  });
}
