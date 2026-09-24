import 'dart:convert';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/telemetry/telemetry_service.dart';
import 'package:sinapsis/features/capture/domain/entities/captured_file.dart';
import 'package:sinapsis/features/duplicates/data/usecases/merge_duplicate_items_usecase_impl.dart';
import 'package:sinapsis/features/library/data/repositories/library_repository_impl.dart';
import 'package:sinapsis/features/organize/data/repositories/organize_repository_impl.dart';
import 'package:sinapsis/features/reference/data/repositories/reference_fuzzy_match_repository_impl.dart';
import 'package:sinapsis/features/reference/data/repositories/reference_identity_repository_impl.dart';
import 'package:sinapsis/features/reference/data/repositories/reference_repository_impl.dart';
import 'package:sinapsis/features/reference/domain/usecases/attach_reference_file_usecase.dart';
import 'package:sinapsis/features/reference/domain/usecases/import_reference_entry_usecase.dart';
import 'package:sinapsis/features/reference/domain/usecases/import_references_file_usecase.dart';
import 'package:sinapsis/features/suggestions/data/repositories/suggestion_repository_impl.dart';

import '../../../../support/fake_id_generator.dart';
import '../../../../support/in_memory_file_store.dart';

class _MockTelemetryService extends Mock implements TelemetryService {}

CapturedFile _textFile(String name, String content) =>
    CapturedFile(name: name, bytes: Uint8List.fromList(utf8.encode(content)));

/// El caso de uso de un archivo entero (F15, D9/D14/D15.3): arma los
/// índices una sola vez, importa cada entrada y suma el informe. Contra
/// SQLite real, con todas las piezas reales —nada de dobles a propósito—:
/// lo que importa acá es que el conjunto encaje.
void main() {
  late AppDatabase db;
  late ImportReferencesFileUseCase useCase;

  final now = DateTime(2026, 9, 24, 10);

  setUp(() {
    db = AppDatabase(NativeDatabase.memory(), deviceId: 'telefono');
    final ids = FakeIdGenerator(prefix: 'item');
    final files = InMemoryFileStore();
    final library = LibraryRepositoryImpl(
      database: db,
      telemetry: _MockTelemetryService(),
      files: files,
      ids: ids,
      clock: () => now,
    );
    final reference = ReferenceRepositoryImpl(
      database: db,
      telemetry: _MockTelemetryService(),
      clock: () => now,
    );
    final organize = OrganizeRepositoryImpl(
      database: db,
      telemetry: _MockTelemetryService(),
      ids: ids,
      clock: () => now,
    );
    final merge = MergeDuplicateItemsUseCaseImpl(
      database: db,
      library: library,
      ids: ids,
      clock: () => now,
      telemetry: _MockTelemetryService(),
    );
    final suggestions = SuggestionRepositoryImpl(
      database: db,
      telemetry: _MockTelemetryService(),
      organize: organize,
      merge: merge,
      ids: ids,
      clock: () => now,
    );
    useCase = ImportReferencesFileUseCase(
      identity: ReferenceIdentityRepositoryImpl(db),
      fuzzyMatch: ReferenceFuzzyMatchRepositoryImpl(db),
      importEntry: ImportReferenceEntryUseCase(
        library: library,
        reference: reference,
        suggestions: suggestions,
        ids: ids,
        clock: () => now,
      ),
      attachFile: AttachReferenceFileUseCase(library: library, files: files),
    );
  });

  tearDown(() => db.close());

  // Con DOI: sin identificador, reimportar no encontraría el mismo elemento
  // por identidad exacta (D9), y una coincidencia por título recién entra
  // por la coincidencia DIFUSA, que da un resultado distinto (creado +
  // propuesto), no el «unchanged» que este archivo necesita para probar la
  // idempotencia de verdad.
  const validBib = '''
@book{turing1950,
  title = {Computing Machinery and Intelligence},
  author = {Turing, Alan},
  year = {1950},
  doi = {10.1000/turing1950},
}

@article{shannon1948,
  title = {A Mathematical Theory of Communication},
  author = {Shannon, Claude},
  year = {1948},
  doi = {10.1000/shannon1948},
}
''';

  test('crea las dos entradas de un .bib válido', () async {
    final result = await useCase([_textFile('bib.bib', validBib)]);

    final report = result.getRight().toNullable()!;
    expect(report.created, 2);
    expect(report.updated, 0);
    expect(report.skipped, isEmpty);
    expect(report.total, 2);
  });

  test('reimportar el mismo archivo: unchanged, idempotente', () async {
    await useCase([_textFile('bib.bib', validBib)]);

    final result = await useCase([_textFile('bib.bib', validBib)]);

    final report = result.getRight().toNullable()!;
    expect(report.unchanged, 2);
    expect(report.created, 0);
  });

  test('un tipo no reconocido se salta y queda en el informe', () async {
    const withPatent =
        '''
$validBib
@patent{x2020, title = {Una patente}}
''';

    final result = await useCase([_textFile('bib.bib', withPatent)]);

    final report = result.getRight().toNullable()!;
    expect(report.created, 2);
    expect(report.skipped, hasLength(1));
    expect(report.skipped.single.key, 'x2020');
    expect(report.total, 3);
  });

  test('un .ris se enruta por su extensión', () async {
    const ris = '''
TY  - BOOK
ID  - turing1950
TI  - Computing Machinery and Intelligence
AU  - Turing, Alan
PY  - 1950///
ER  -
''';

    final result = await useCase([_textFile('archivo.ris', ris)]);

    expect(result.getRight().toNullable()!.created, 1);
  });

  test('ninguno de los archivos elegidos es .bib ni .ris: falla', () async {
    final result = await useCase([_textFile('imagen.png', 'no es esto')]);

    expect(result.isLeft(), isTrue);
  });

  test('un adjunto elegido junto con el .bib se vincula', () async {
    const withFile = '''
@book{turing1950,
  title = {Computing Machinery and Intelligence},
  file = {articulo.pdf},
}
''';
    final pdf = CapturedFile(
      name: 'articulo.pdf',
      bytes: Uint8List.fromList(utf8.encode('%PDF-1.7 contenido')),
    );

    final result = await useCase([_textFile('bib.bib', withFile), pdf]);

    final report = result.getRight().toNullable()!;
    expect(report.attached, 1);
  });

  test(
    'sin ningún archivo que coincida con el nombre: no se vincula nada',
    () async {
      const withFile = '''
@book{turing1950,
  title = {Computing Machinery and Intelligence},
  file = {no-esta.pdf},
}
''';

      final result = await useCase([_textFile('bib.bib', withFile)]);

      expect(result.getRight().toNullable()!.attached, 0);
    },
  );

  test('una coincidencia difusa entre dos importaciones se cuenta', () async {
    const first = '''
@book{a,
  title = {Cien años de soledad},
  author = {García Márquez, Gabriel},
}
''';
    const second = '''
@book{b,
  title = {CIEN AÑOS DE SOLEDAD},
  author = {García Márquez, Gabriel},
}
''';
    await useCase([_textFile('primero.bib', first)]);

    final result = await useCase([_textFile('segundo.bib', second)]);

    expect(result.getRight().toNullable()!.possibleDuplicates, 1);
  });
}
