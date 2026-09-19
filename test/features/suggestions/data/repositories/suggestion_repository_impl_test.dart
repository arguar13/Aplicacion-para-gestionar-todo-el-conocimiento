import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/domain/entities/duplicate_match_kind.dart';
import 'package:sinapsis/core/domain/entities/item_property_origin.dart';
import 'package:sinapsis/core/domain/entities/knowledge_item.dart';
import 'package:sinapsis/core/domain/entities/processing_state.dart';
import 'package:sinapsis/core/domain/entities/relation_kind.dart';
import 'package:sinapsis/core/domain/entities/source.dart';
import 'package:sinapsis/core/domain/entities/source_kind.dart';
import 'package:sinapsis/core/domain/entities/suggestion.dart';
import 'package:sinapsis/core/domain/entities/suggestion_status.dart';
import 'package:sinapsis/core/telemetry/telemetry_service.dart';
import 'package:sinapsis/features/duplicates/data/usecases/merge_duplicate_items_usecase_impl.dart';
import 'package:sinapsis/features/library/data/repositories/library_repository_impl.dart';
import 'package:sinapsis/features/library/domain/entities/library_query.dart';
import 'package:sinapsis/features/organize/data/repositories/organize_repository_impl.dart';
import 'package:sinapsis/features/suggestions/data/repositories/suggestion_repository_impl.dart';

import '../../../../support/fake_id_generator.dart';
import '../../../../support/in_memory_file_store.dart';

class MockTelemetryService extends Mock implements TelemetryService {}

/// Contra SQLite real, en memoria, con un `OrganizeRepositoryImpl` real
/// también: `accept()` necesita que `assignProperty`/`createRelation`
/// funcionen de verdad, no solo que se los llame.
void main() {
  late AppDatabase db;
  late LibraryRepositoryImpl libraryRepository;
  late OrganizeRepositoryImpl organizeRepository;
  late SuggestionRepositoryImpl repository;
  late FakeIdGenerator ids;

  final now = DateTime(2026, 9, 18, 10);
  var counter = 0;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    ids = FakeIdGenerator();
    libraryRepository = LibraryRepositoryImpl(
      database: db,
      telemetry: MockTelemetryService(),
      files: InMemoryFileStore(),
    );
    organizeRepository = OrganizeRepositoryImpl(
      database: db,
      telemetry: MockTelemetryService(),
      ids: ids,
      clock: () => now,
    );
    repository = SuggestionRepositoryImpl(
      database: db,
      telemetry: MockTelemetryService(),
      organize: organizeRepository,
      merge: MergeDuplicateItemsUseCaseImpl(
        database: db,
        library: libraryRepository,
        ids: ids,
        clock: () => now,
        telemetry: MockTelemetryService(),
      ),
      ids: ids,
      clock: () => now,
    );
    counter = 0;
  });

  tearDown(() => db.close());

  Future<KnowledgeItem> seedItem({String title = 'Un elemento'}) async {
    final n = counter++;
    final item = KnowledgeItem(
      id: 'item-$n',
      title: title,
      source: Source(
        id: 'src-$n',
        kind: SourceKind.webPage,
        capturedAt: now,
        url: 'https://ejemplo.org/$n',
      ),
      processingState: ProcessingState.ready,
      createdAt: now,
      updatedAt: now,
    );

    final result = await libraryRepository.save(item);
    return result.getRight().toNullable()!;
  }

  group('createPropertySuggestion', () {
    test('inserta en pending y aparece en watchPendingSuggestions', () async {
      final item = await seedItem();

      final result = await repository.createPropertySuggestion(
        targetItemId: item.id,
        definitionId: 'def-region',
        definitionName: 'Región',
        value: 'Roma',
        isNewValue: true,
      );

      expect(result.isRight(), isTrue);
      final created = result.getRight().toNullable()! as PropertySuggestion;
      expect(created.status, SuggestionStatus.pending);

      final pending = await repository.watchPendingSuggestions(item.id).first;
      expect(pending.map((s) => s.id), [created.id]);
      final onlyPending = pending.single as PropertySuggestion;
      expect(onlyPending.definitionName, 'Región');
      expect(onlyPending.value, 'Roma');
      expect(onlyPending.isNewValue, isTrue);
    });
  });

  group('createRelationSuggestion', () {
    test('inserta en pending y aparece en watchPendingSuggestions', () async {
      final itemA = await seedItem(title: 'A');
      final itemB = await seedItem(title: 'B');

      final result = await repository.createRelationSuggestion(
        targetItemId: itemA.id,
        relatedItemId: itemB.id,
        relatedItemTitle: 'B',
        kind: RelationKind.contradicts,
        reason: 'Dicen lo contrario sobre el mismo hecho.',
        confidence: 0.87,
      );

      expect(result.isRight(), isTrue);
      final created =
          result.getRight().toNullable()! as RelationSuggestionEntry;
      expect(created.status, SuggestionStatus.pending);
      expect(created.confidence, 0.87);

      final pending = await repository.watchPendingSuggestions(itemA.id).first;
      final onlyPending = pending.single as RelationSuggestionEntry;
      expect(onlyPending.relatedItemId, itemB.id);
      expect(onlyPending.relatedItemTitle, 'B');
      expect(onlyPending.kind, RelationKind.contradicts);
      expect(onlyPending.reason, 'Dicen lo contrario sobre el mismo hecho.');
    });
  });

  group('createDuplicateSuggestion', () {
    test('inserta en pending y aparece en watchPendingSuggestions', () async {
      final keep = await seedItem(title: 'El que queda');
      final discard = await seedItem(title: 'El posible duplicado');

      final result = await repository.createDuplicateSuggestion(
        targetItemId: keep.id,
        duplicateItemId: discard.id,
        duplicateItemTitle: discard.title,
        matchKind: DuplicateMatchKind.near,
        confidence: 0.9,
      );

      expect(result.isRight(), isTrue);
      final created =
          result.getRight().toNullable()! as DuplicateSuggestionEntry;
      expect(created.status, SuggestionStatus.pending);
      expect(created.confidence, 0.9);

      final pending = await repository.watchPendingSuggestions(keep.id).first;
      final onlyPending = pending.single as DuplicateSuggestionEntry;
      expect(onlyPending.duplicateItemId, discard.id);
      expect(onlyPending.duplicateItemTitle, 'El posible duplicado');
      expect(onlyPending.matchKind, DuplicateMatchKind.near);
    });
  });

  group('watchPendingSuggestions', () {
    test('solo trae pending del itemId pedido, no de otro', () async {
      final itemA = await seedItem();
      final itemB = await seedItem();

      await repository.createPropertySuggestion(
        targetItemId: itemA.id,
        definitionId: 'def-region',
        definitionName: 'Región',
        value: 'Roma',
        isNewValue: true,
      );
      await repository.createPropertySuggestion(
        targetItemId: itemB.id,
        definitionId: 'def-region',
        definitionName: 'Región',
        value: 'Egipto',
        isNewValue: true,
      );

      final pendingA = await repository.watchPendingSuggestions(itemA.id).first;
      expect(pendingA.map((s) => (s as PropertySuggestion).value), ['Roma']);
    });

    test('no trae sugerencias ya aceptadas o rechazadas', () async {
      final item = await seedItem();
      final definition =
          (await organizeRepository.getOrCreatePropertyDefinition(
            'Región',
          )).getRight().toNullable()!;

      final accepted = (await repository.createPropertySuggestion(
        targetItemId: item.id,
        definitionId: definition.id,
        definitionName: 'Región',
        value: 'Roma',
        isNewValue: true,
      )).getRight().toNullable()!;
      final rejected = (await repository.createPropertySuggestion(
        targetItemId: item.id,
        definitionId: definition.id,
        definitionName: 'Región',
        value: 'Egipto',
        isNewValue: true,
      )).getRight().toNullable()!;

      await repository.accept(accepted.id);
      await repository.reject(rejected.id);

      final pending = await repository.watchPendingSuggestions(item.id).first;
      expect(pending, isEmpty);
    });
  });

  group('accept', () {
    test('property: aplica la propiedad de verdad y marca accepted', () async {
      final item = await seedItem();
      final definition =
          (await organizeRepository.getOrCreatePropertyDefinition(
            'Región',
          )).getRight().toNullable()!;
      final suggestion = (await repository.createPropertySuggestion(
        targetItemId: item.id,
        definitionId: definition.id,
        definitionName: 'Región',
        value: 'Roma',
        isNewValue: true,
      )).getRight().toNullable()!;

      final result = await repository.accept(suggestion.id);

      expect(result.isRight(), isTrue);
      final reloaded = (await libraryRepository.findById(
        item.id,
      )).getRight().toNullable()!;
      expect(reloaded.properties, hasLength(1));
      expect(reloaded.properties.single.value, 'Roma');
      expect(
        reloaded.properties.single.origin,
        ItemPropertyOrigin.suggestedAccepted,
      );

      final pending = await repository.watchPendingSuggestions(item.id).first;
      expect(pending, isEmpty);
    });

    test('relation: crea el vínculo de verdad y marca accepted', () async {
      final itemA = await seedItem(title: 'A');
      final itemB = await seedItem(title: 'B');
      final suggestion = (await repository.createRelationSuggestion(
        targetItemId: itemA.id,
        relatedItemId: itemB.id,
        relatedItemTitle: 'B',
        kind: RelationKind.relatedTo,
        reason: 'Hablan del mismo tema.',
      )).getRight().toNullable()!;

      final result = await repository.accept(suggestion.id);

      expect(result.isRight(), isTrue);
      final relations = await organizeRepository
          .watchRelationsForItem(itemA.id)
          .first;
      expect(relations, hasLength(1));
      expect(relations.single.kind, RelationKind.relatedTo);
      expect(relations.single.note, 'Hablan del mismo tema.');

      final pending = await repository.watchPendingSuggestions(itemA.id).first;
      expect(pending, isEmpty);
    });

    test(
      'duplicate: fusiona los dos elementos de verdad y marca accepted',
      () async {
        final keep = await seedItem(title: 'El que queda');
        final discard = await seedItem(title: 'El posible duplicado');
        final suggestion = (await repository.createDuplicateSuggestion(
          targetItemId: keep.id,
          duplicateItemId: discard.id,
          duplicateItemTitle: discard.title,
          matchKind: DuplicateMatchKind.exact,
        )).getRight().toNullable()!;

        final result = await repository.accept(suggestion.id);

        expect(result.isRight(), isTrue);
        final items = (await libraryRepository.list(
          const LibraryQuery(),
        )).getRight().toNullable()!;
        expect(items.map((i) => i.id), [keep.id]);

        final pending = await repository.watchPendingSuggestions(keep.id).first;
        expect(pending, isEmpty);
      },
    );

    test('un id inexistente devuelve left', () async {
      final result = await repository.accept('no-existe');

      expect(result.isLeft(), isTrue);
    });
  });

  group('reject', () {
    test('marca rejected sin tocar ItemPropertyValues', () async {
      final item = await seedItem();
      final definition =
          (await organizeRepository.getOrCreatePropertyDefinition(
            'Región',
          )).getRight().toNullable()!;
      final suggestion = (await repository.createPropertySuggestion(
        targetItemId: item.id,
        definitionId: definition.id,
        definitionName: 'Región',
        value: 'Roma',
        isNewValue: true,
      )).getRight().toNullable()!;

      final result = await repository.reject(suggestion.id);

      expect(result.isRight(), isTrue);
      final reloaded = (await libraryRepository.findById(
        item.id,
      )).getRight().toNullable()!;
      expect(reloaded.properties, isEmpty);

      final pending = await repository.watchPendingSuggestions(item.id).first;
      expect(pending, isEmpty);
    });

    test('un id inexistente devuelve left', () async {
      final result = await repository.reject('no-existe');

      expect(result.isLeft(), isTrue);
    });
  });
}
