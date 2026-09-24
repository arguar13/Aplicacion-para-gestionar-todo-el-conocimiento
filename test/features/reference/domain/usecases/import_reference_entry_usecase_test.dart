import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/domain/entities/imported_reference.dart';
import 'package:sinapsis/core/domain/entities/publication_date.dart';
import 'package:sinapsis/core/domain/entities/reference_data.dart';
import 'package:sinapsis/core/telemetry/telemetry_service.dart';
import 'package:sinapsis/features/library/data/repositories/library_repository_impl.dart';
import 'package:sinapsis/features/reference/data/repositories/reference_identity_repository_impl.dart';
import 'package:sinapsis/features/reference/data/repositories/reference_repository_impl.dart';
import 'package:sinapsis/features/reference/domain/usecases/import_reference_entry_usecase.dart';

import '../../../../support/fake_id_generator.dart';
import '../../../../support/in_memory_file_store.dart';

class _MockTelemetryService extends Mock implements TelemetryService {}

/// El núcleo de identidad e idempotencia al importar (F15, D9). Contra
/// SQLite real: lo que importa acá es qué termina guardado en la base, no
/// qué llamada se hizo.
void main() {
  late AppDatabase db;
  late LibraryRepositoryImpl library;
  late ReferenceRepositoryImpl reference;
  late ReferenceIdentityRepositoryImpl identity;
  late ImportReferenceEntryUseCase useCase;
  final now = DateTime(2026, 9, 24, 10);

  setUp(() {
    db = AppDatabase(NativeDatabase.memory(), deviceId: 'telefono');
    library = LibraryRepositoryImpl(
      database: db,
      telemetry: _MockTelemetryService(),
      files: InMemoryFileStore(),
      ids: FakeIdGenerator(prefix: 'item'),
      clock: () => now,
    );
    reference = ReferenceRepositoryImpl(
      database: db,
      telemetry: _MockTelemetryService(),
      clock: () => now,
    );
    identity = ReferenceIdentityRepositoryImpl(db);
    useCase = ImportReferenceEntryUseCase(
      library: library,
      reference: reference,
      ids: FakeIdGenerator(prefix: 'item'),
      clock: () => now,
    );
  });

  tearDown(() => db.close());

  group('sin nada que coincida', () {
    test('crea una fuente SourceKind.reference, triada', () async {
      final index = await identity.buildIndex();
      const entry = ImportedReference(
        title: 'Cien años de soledad',
        reference: ReferenceData(doi: '10.1000/xyz'),
      );

      final result = (await useCase(entry, index)).getRight().toNullable()!;

      expect(result.outcome, ImportedReferenceOutcome.created);
      final saved = (await library.findById(
        result.itemId,
      )).getRight().toNullable()!;
      expect(saved.title, 'Cien años de soledad');
      final savedReference = await reference.read(result.itemId);
      expect(savedReference.doi, '10.1000/xyz');
    });

    test('sin título, usa un título genérico en vez de fallar', () async {
      final index = await identity.buildIndex();
      const entry = ImportedReference();

      final result = (await useCase(entry, index)).getRight().toNullable()!;

      expect(result.outcome, ImportedReferenceOutcome.created);
    });
  });

  group('con una fuente que ya tiene el mismo DOI', () {
    Future<String> existing() async {
      final index = await identity.buildIndex();
      const first = ImportedReference(
        title: 'Ya guardada',
        reference: ReferenceData(doi: '10.1000/xyz', publisher: 'Editorial'),
      );
      final result = (await useCase(first, index)).getRight().toNullable()!;
      return result.itemId;
    }

    test('reimportar sin nada nuevo: unchanged, idempotente', () async {
      final itemId = await existing();
      final index = await identity.buildIndex();
      const again = ImportedReference(
        title: 'Ya guardada',
        reference: ReferenceData(doi: '10.1000/xyz', publisher: 'Editorial'),
      );

      final result = (await useCase(again, index)).getRight().toNullable()!;

      expect(result.itemId, itemId);
      expect(result.outcome, ImportedReferenceOutcome.unchanged);
    });

    test('completa lo que estaba vacío: updated', () async {
      final itemId = await existing();
      final index = await identity.buildIndex();
      const withIsbn = ImportedReference(
        reference: ReferenceData(doi: '10.1000/xyz', isbn: '9780306406157'),
      );

      final result = (await useCase(withIsbn, index)).getRight().toNullable()!;

      expect(result.outcome, ImportedReferenceOutcome.updated);
      final saved = await reference.read(itemId);
      expect(saved.publisher, 'Editorial');
      expect(saved.isbn, '9780306406157');
    });

    test('no pisa lo que ya tenía, salvo que se priorice el archivo', () async {
      final itemId = await existing();
      final index = await identity.buildIndex();
      const fromFile = ImportedReference(
        reference: ReferenceData(
          doi: '10.1000/xyz',
          publisher: 'Otra editorial',
        ),
      );

      await useCase(fromFile, index);
      expect((await reference.read(itemId)).publisher, 'Editorial');

      await useCase(fromFile, index, prioritizeIncoming: true);
      expect((await reference.read(itemId)).publisher, 'Otra editorial');
    });

    test('no toca el título del elemento ya guardado', () async {
      final itemId = await existing();
      final index = await identity.buildIndex();
      const renamed = ImportedReference(
        title: 'Un título distinto',
        reference: ReferenceData(doi: '10.1000/xyz'),
      );

      await useCase(renamed, index);

      final saved = (await library.findById(itemId)).getRight().toNullable()!;
      expect(saved.title, 'Ya guardada');
    });

    test('completa la fecha si no tenía', () async {
      final itemId = await existing();
      final index = await identity.buildIndex();
      final entry = ImportedReference(
        publishedAt: DateTime(1967),
        publicationPrecision: PublicationPrecision.year,
        reference: const ReferenceData(doi: '10.1000/xyz'),
      );

      final result = (await useCase(entry, index)).getRight().toNullable()!;

      expect(result.outcome, ImportedReferenceOutcome.updated);
      final saved = (await library.findById(itemId)).getRight().toNullable()!;
      expect(saved.source.publishedAt, DateTime(1967));
    });
  });

  test(
    'el elemento se borró entre armar el índice e importar: crea uno nuevo',
    () async {
      final index = await identity.buildIndex();
      const first = ImportedReference(
        title: 'Se va a borrar',
        reference: ReferenceData(doi: '10.1000/xyz'),
      );
      final created = (await useCase(first, index)).getRight().toNullable()!;
      await library.delete(created.itemId);
      await library.purge([created.itemId]);

      const again = ImportedReference(
        title: 'Reimportada',
        reference: ReferenceData(doi: '10.1000/xyz'),
      );
      final result = (await useCase(again, index)).getRight().toNullable()!;

      expect(result.outcome, ImportedReferenceOutcome.created);
      expect(result.itemId, isNot(created.itemId));
    },
  );
}
