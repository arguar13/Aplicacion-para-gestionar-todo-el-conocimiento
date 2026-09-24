import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/domain/entities/duplicate_match_kind.dart';
import 'package:sinapsis/core/domain/entities/imported_reference.dart';
import 'package:sinapsis/core/domain/entities/person_name.dart';
import 'package:sinapsis/core/domain/entities/publication_date.dart';
import 'package:sinapsis/core/domain/entities/reference_data.dart';
import 'package:sinapsis/core/domain/entities/suggestion.dart';
import 'package:sinapsis/core/telemetry/telemetry_service.dart';
import 'package:sinapsis/features/duplicates/data/usecases/merge_duplicate_items_usecase_impl.dart';
import 'package:sinapsis/features/library/data/repositories/library_repository_impl.dart';
import 'package:sinapsis/features/organize/data/repositories/organize_repository_impl.dart';
import 'package:sinapsis/features/reference/data/repositories/reference_fuzzy_match_repository_impl.dart';
import 'package:sinapsis/features/reference/data/repositories/reference_identity_repository_impl.dart';
import 'package:sinapsis/features/reference/data/repositories/reference_repository_impl.dart';
import 'package:sinapsis/features/reference/domain/usecases/import_reference_entry_usecase.dart';
import 'package:sinapsis/features/suggestions/data/repositories/suggestion_repository_impl.dart';

import '../../../../support/fake_id_generator.dart';
import '../../../../support/in_memory_file_store.dart';

class _MockTelemetryService extends Mock implements TelemetryService {}

/// El núcleo de identidad, idempotencia y coincidencia difusa al importar
/// (F15, D9). Contra SQLite real: lo que importa acá es qué termina
/// guardado en la base, no qué llamada se hizo.
void main() {
  late AppDatabase db;
  late LibraryRepositoryImpl library;
  late ReferenceRepositoryImpl reference;
  late ReferenceIdentityRepositoryImpl identity;
  late ReferenceFuzzyMatchRepositoryImpl fuzzyMatch;
  late SuggestionRepositoryImpl suggestions;
  late ImportReferenceEntryUseCase useCase;
  final now = DateTime(2026, 9, 24, 10);

  setUp(() {
    db = AppDatabase(NativeDatabase.memory(), deviceId: 'telefono');
    final ids = FakeIdGenerator(prefix: 'item');
    library = LibraryRepositoryImpl(
      database: db,
      telemetry: _MockTelemetryService(),
      files: InMemoryFileStore(),
      ids: ids,
      clock: () => now,
    );
    reference = ReferenceRepositoryImpl(
      database: db,
      telemetry: _MockTelemetryService(),
      clock: () => now,
    );
    identity = ReferenceIdentityRepositoryImpl(db);
    fuzzyMatch = ReferenceFuzzyMatchRepositoryImpl(db);
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
    suggestions = SuggestionRepositoryImpl(
      database: db,
      telemetry: _MockTelemetryService(),
      organize: organize,
      merge: merge,
      ids: ids,
      clock: () => now,
    );
    useCase = ImportReferenceEntryUseCase(
      library: library,
      reference: reference,
      suggestions: suggestions,
      ids: ids,
      clock: () => now,
    );
  });

  tearDown(() => db.close());

  group('sin nada que coincida', () {
    test('crea una fuente SourceKind.reference, triada', () async {
      final index = await identity.buildIndex();
      final fuzzy = await fuzzyMatch.buildIndex();
      const entry = ImportedReference(
        title: 'Cien años de soledad',
        reference: ReferenceData(doi: '10.1000/xyz'),
      );

      final result = (await useCase(
        entry,
        index,
        fuzzy,
      )).getRight().toNullable()!;

      expect(result.outcome, ImportedReferenceOutcome.created);
      expect(result.possibleDuplicates, 0);
      final saved = (await library.findById(
        result.itemId,
      )).getRight().toNullable()!;
      expect(saved.title, 'Cien años de soledad');
      final savedReference = await reference.read(result.itemId);
      expect(savedReference.doi, '10.1000/xyz');
    });

    test('sin título, usa un título genérico en vez de fallar', () async {
      final index = await identity.buildIndex();
      final fuzzy = await fuzzyMatch.buildIndex();
      const entry = ImportedReference();

      final result = (await useCase(
        entry,
        index,
        fuzzy,
      )).getRight().toNullable()!;

      expect(result.outcome, ImportedReferenceOutcome.created);
      expect(result.possibleDuplicates, 0);
    });
  });

  group('con una fuente que ya tiene el mismo DOI', () {
    Future<String> existing() async {
      final index = await identity.buildIndex();
      final fuzzy = await fuzzyMatch.buildIndex();
      const first = ImportedReference(
        title: 'Ya guardada',
        reference: ReferenceData(doi: '10.1000/xyz', publisher: 'Editorial'),
      );
      final result = (await useCase(
        first,
        index,
        fuzzy,
      )).getRight().toNullable()!;
      return result.itemId;
    }

    test('reimportar sin nada nuevo: unchanged, idempotente', () async {
      final itemId = await existing();
      final index = await identity.buildIndex();
      final fuzzy = await fuzzyMatch.buildIndex();
      const again = ImportedReference(
        title: 'Ya guardada',
        reference: ReferenceData(doi: '10.1000/xyz', publisher: 'Editorial'),
      );

      final result = (await useCase(
        again,
        index,
        fuzzy,
      )).getRight().toNullable()!;

      expect(result.itemId, itemId);
      expect(result.outcome, ImportedReferenceOutcome.unchanged);
    });

    test('completa lo que estaba vacío: updated', () async {
      final itemId = await existing();
      final index = await identity.buildIndex();
      final fuzzy = await fuzzyMatch.buildIndex();
      const withIsbn = ImportedReference(
        reference: ReferenceData(doi: '10.1000/xyz', isbn: '9780306406157'),
      );

      final result = (await useCase(
        withIsbn,
        index,
        fuzzy,
      )).getRight().toNullable()!;

      expect(result.outcome, ImportedReferenceOutcome.updated);
      final saved = await reference.read(itemId);
      expect(saved.publisher, 'Editorial');
      expect(saved.isbn, '9780306406157');
    });

    test('no pisa lo que ya tenía, salvo que se priorice el archivo', () async {
      final itemId = await existing();
      final index = await identity.buildIndex();
      final fuzzy = await fuzzyMatch.buildIndex();
      const fromFile = ImportedReference(
        reference: ReferenceData(
          doi: '10.1000/xyz',
          publisher: 'Otra editorial',
        ),
      );

      await useCase(fromFile, index, fuzzy);
      expect((await reference.read(itemId)).publisher, 'Editorial');

      await useCase(fromFile, index, fuzzy, prioritizeIncoming: true);
      expect((await reference.read(itemId)).publisher, 'Otra editorial');
    });

    test('no toca el título del elemento ya guardado', () async {
      final itemId = await existing();
      final index = await identity.buildIndex();
      final fuzzy = await fuzzyMatch.buildIndex();
      const renamed = ImportedReference(
        title: 'Un título distinto',
        reference: ReferenceData(doi: '10.1000/xyz'),
      );

      await useCase(renamed, index, fuzzy);

      final saved = (await library.findById(itemId)).getRight().toNullable()!;
      expect(saved.title, 'Ya guardada');
    });

    test('completa la fecha si no tenía', () async {
      final itemId = await existing();
      final index = await identity.buildIndex();
      final fuzzy = await fuzzyMatch.buildIndex();
      final entry = ImportedReference(
        publishedAt: DateTime(1967),
        publicationPrecision: PublicationPrecision.year,
        reference: const ReferenceData(doi: '10.1000/xyz'),
      );

      final result = (await useCase(
        entry,
        index,
        fuzzy,
      )).getRight().toNullable()!;

      expect(result.outcome, ImportedReferenceOutcome.updated);
      final saved = (await library.findById(itemId)).getRight().toNullable()!;
      expect(saved.source.publishedAt, DateTime(1967));
    });
  });

  test(
    'el elemento se borró entre armar el índice e importar: crea uno nuevo',
    () async {
      final index = await identity.buildIndex();
      final fuzzy = await fuzzyMatch.buildIndex();
      const first = ImportedReference(
        title: 'Se va a borrar',
        reference: ReferenceData(doi: '10.1000/xyz'),
      );
      final created = (await useCase(
        first,
        index,
        fuzzy,
      )).getRight().toNullable()!;
      await library.delete(created.itemId);
      await library.purge([created.itemId]);

      const again = ImportedReference(
        title: 'Reimportada',
        reference: ReferenceData(doi: '10.1000/xyz'),
      );
      final result = (await useCase(
        again,
        index,
        fuzzy,
      )).getRight().toNullable()!;

      expect(result.outcome, ImportedReferenceOutcome.created);
      expect(result.itemId, isNot(created.itemId));
    },
  );

  group('coincidencia difusa (F15, D9): sin identidad exacta', () {
    Future<String> alreadyThere() async {
      final index = await identity.buildIndex();
      final fuzzy = await fuzzyMatch.buildIndex();
      const first = ImportedReference(
        title: 'Cien años de soledad',
        reference: ReferenceData(
          contributors: [
            Contributor(name: PersonName(family: 'García Márquez')),
          ],
        ),
      );
      final result = (await useCase(
        first,
        index,
        fuzzy,
      )).getRight().toNullable()!;
      return result.itemId;
    }

    test(
      'mismo título, año y autor: crea Y propone el duplicado a F7',
      () async {
        final targetId = await alreadyThere();
        final index = await identity.buildIndex();
        final fuzzy = await fuzzyMatch.buildIndex();
        const again = ImportedReference(
          title: 'CIEN AÑOS DE SOLEDAD',
          reference: ReferenceData(
            contributors: [
              Contributor(name: PersonName(family: 'García Márquez')),
            ],
          ),
        );

        final result = (await useCase(
          again,
          index,
          fuzzy,
        )).getRight().toNullable()!;

        expect(result.outcome, ImportedReferenceOutcome.created);
        expect(result.itemId, isNot(targetId));
        expect(result.possibleDuplicates, 1);

        final pending = await suggestions
            .watchPendingDuplicateSuggestions()
            .first;
        expect(pending, hasLength(1));
        final proposed = pending.single as DuplicateSuggestionEntry;
        expect(proposed.targetItemId, targetId);
        expect(proposed.duplicateItemId, result.itemId);
        expect(proposed.matchKind, DuplicateMatchKind.bibliographic);
      },
    );

    test('título distinto: no propone nada', () async {
      await alreadyThere();
      final index = await identity.buildIndex();
      final fuzzy = await fuzzyMatch.buildIndex();
      const other = ImportedReference(title: 'Otro libro cualquiera');

      final result = (await useCase(
        other,
        index,
        fuzzy,
      )).getRight().toNullable()!;

      expect(result.possibleDuplicates, 0);
      expect(
        await suggestions.watchPendingDuplicateSuggestions().first,
        isEmpty,
      );
    });

    test('sin título propio, no compara contra nada', () async {
      final index = await identity.buildIndex();
      final fuzzy = await fuzzyMatch.buildIndex();
      const noTitle = ImportedReference();

      final result = (await useCase(
        noTitle,
        index,
        fuzzy,
      )).getRight().toNullable()!;

      expect(result.possibleDuplicates, 0);
    });

    test('una identidad exacta encontrada no pasa por lo difuso', () async {
      // Si ambos caminos se dispararan a la vez, esta entrada (mismo DOI que
      // una existente, y además mismo título que otra) propondría un
      // duplicado sin sentido: actualiza por DOI y no toca lo difuso.
      final index = await identity.buildIndex();
      final fuzzy = await fuzzyMatch.buildIndex();
      const withDoi = ImportedReference(
        title: 'Con DOI propio',
        reference: ReferenceData(doi: '10.1000/propio'),
      );
      await useCase(withDoi, index, fuzzy);

      final index2 = await identity.buildIndex();
      final fuzzy2 = await fuzzyMatch.buildIndex();
      const reimport = ImportedReference(
        title: 'Con DOI propio',
        reference: ReferenceData(doi: '10.1000/propio'),
      );
      final result = (await useCase(
        reimport,
        index2,
        fuzzy2,
      )).getRight().toNullable()!;

      expect(result.outcome, ImportedReferenceOutcome.unchanged);
      expect(result.possibleDuplicates, 0);
    });
  });
}
