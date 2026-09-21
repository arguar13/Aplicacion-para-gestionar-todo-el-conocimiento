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

  group('cuándo se ofrece por su cuenta', () {
    const mib = 1024 * 1024;

    /// Un archivo de [pages] páginas de 4 KiB, de las cuales [free] libres.
    CompactionAssessment vault({
      required int pages,
      required int free,
      int? freeSpaceBytes = 100 * 1024 * mib,
      AutoVacuumMode autoVacuum = AutoVacuumMode.none,
    }) => assessment(
      pageSize: 4096,
      pageCount: pages,
      freePages: free,
      freeSpaceBytes: freeSpaceBytes,
      autoVacuum: autoVacuum,
    );

    test('con bastante para devolver y disco de sobra, se ofrece', () {
      // 1 GiB de archivo, 512 MiB de páginas libres.
      expect(vault(pages: 262144, free: 131072).worthOffering, isTrue);
    });

    test('justo el mínimo de bytes se ofrece; una página menos, no', () {
      const minPages = kCompactionOfferMinBytes ~/ 4096;

      // 200 MiB de archivo: el 15 % no es lo que decide.
      expect(vault(pages: 51200, free: minPages).worthOffering, isTrue);
      expect(vault(pages: 51200, free: minPages - 1).worthOffering, isFalse);
    });

    test('justo el 15 % del archivo se ofrece; una página menos, no', () {
      // 4 GiB de archivo: el 15 % son 150.000 páginas y pesa más que el mínimo.
      expect(vault(pages: 1000000, free: 150000).worthOffering, isTrue);
      expect(vault(pages: 1000000, free: 149999).worthOffering, isFalse);
    });

    test('con el disco justo, sin lugar, no: sería una queja sin salida', () {
      final tight = vault(
        pages: 262144,
        free: 131072,
        freeSpaceBytes: 10 * mib,
      );

      expect(tight.verdict, CompactionVerdict.notEnoughSpace);
      expect(tight.worthOffering, isFalse);
    });

    test('sin dato de disco, sí: se puede intentar', () {
      expect(
        vault(pages: 262144, free: 131072, freeSpaceBytes: null).worthOffering,
        isTrue,
      );
    });

    test('ya en modo incremental también se ofrece, si hay bastante', () {
      expect(
        vault(
          pages: 262144,
          free: 131072,
          autoVacuum: AutoVacuumMode.incremental,
          freeSpaceBytes: 32 * mib,
        ).worthOffering,
        isTrue,
      );
    });

    test('sin nada que recuperar, no', () {
      expect(vault(pages: 262144, free: 0).worthOffering, isFalse);
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
