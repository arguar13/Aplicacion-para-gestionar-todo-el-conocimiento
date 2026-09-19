import 'package:async/async.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/domain/entities/duplicate_match_kind.dart';
import 'package:sinapsis/core/domain/entities/item_property.dart';
import 'package:sinapsis/core/domain/entities/item_property_origin.dart';
import 'package:sinapsis/core/domain/entities/knowledge_item.dart';
import 'package:sinapsis/core/domain/entities/processing_state.dart';
import 'package:sinapsis/core/domain/entities/property_definition.dart';
import 'package:sinapsis/core/domain/entities/relation_kind.dart';
import 'package:sinapsis/core/domain/entities/source.dart';
import 'package:sinapsis/core/domain/entities/source_kind.dart';
import 'package:sinapsis/core/domain/entities/suggestion.dart';
import 'package:sinapsis/core/domain/entities/suggestion_status.dart';
import 'package:sinapsis/core/error/failures.dart';
import 'package:sinapsis/core/telemetry/telemetry_service.dart';
import 'package:sinapsis/features/duplicates/data/usecases/merge_duplicate_items_usecase_impl.dart';
import 'package:sinapsis/features/library/data/repositories/library_repository_impl.dart';
import 'package:sinapsis/features/library/domain/entities/library_query.dart';
import 'package:sinapsis/features/organize/data/repositories/organize_repository_impl.dart';
import 'package:sinapsis/features/suggestions/data/repositories/suggestion_repository_impl.dart';
import 'package:sinapsis/features/suggestions/domain/entities/property_suggestion_group.dart';

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

  /// Un segundo más con cada llamada: las sugerencias que se crean primero
  /// son más viejas sin depender del orden alfabético de identificadores
  /// como `id-10`.
  var tick = 0;
  DateTime tickingClock() => now.add(Duration(seconds: tick++));

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
      clock: tickingClock,
    );
    counter = 0;
    tick = 0;
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

  group('revertAccepted', () {
    late PropertyDefinition region;

    setUp(() async {
      region = (await organizeRepository.getOrCreatePropertyDefinition(
        'Región',
      )).getRight().toNullable()!;
    });

    Future<Suggestion> suggest(
      KnowledgeItem item, {
      String value = 'Roma',
      bool isNewValue = true,
    }) async => (await repository.createPropertySuggestion(
      targetItemId: item.id,
      definitionId: region.id,
      definitionName: 'Región',
      value: value,
      isNewValue: isNewValue,
    )).getRight().toNullable()!;

    Future<List<ItemProperty>> propertiesOf(KnowledgeItem item) async =>
        (await libraryRepository.findById(
          item.id,
        )).getRight().toNullable()!.properties;

    Future<List<PropertyValueRow>> valuesOfRegion() => (db.select(
      db.propertyValues,
    )..where((v) => v.definitionId.equals(region.id))).get();

    test('quita la propiedad que puso y la deja pendiente de nuevo', () async {
      final item = await seedItem();
      final suggestion = await suggest(item);
      await repository.accept(suggestion.id);
      expect(await propertiesOf(item), hasLength(1));

      final result = await repository.revertAccepted(suggestion.id);

      expect(result.isRight(), isTrue);
      expect(await propertiesOf(item), isEmpty);
      final pending = await repository.watchPendingSuggestions(item.id).first;
      expect(pending.map((s) => s.id), [suggestion.id]);
    });

    test(
      'el valor que la aceptación creó y nadie más usa se va con ella',
      () async {
        final item = await seedItem();
        final suggestion = await suggest(item);
        await repository.accept(suggestion.id);
        expect(await valuesOfRegion(), hasLength(1));

        await repository.revertAccepted(suggestion.id);

        expect(await valuesOfRegion(), isEmpty);
      },
    );

    test('un valor que otro elemento usa se queda, y el otro elemento lo '
        'conserva', () async {
      final item = await seedItem();
      final other = await seedItem(title: 'Otro');
      final suggestion = await suggest(item);
      await repository.accept(suggestion.id);
      await organizeRepository.assignProperty(
        itemId: other.id,
        definitionId: region.id,
        value: 'Roma',
      );

      await repository.revertAccepted(suggestion.id);

      expect(await propertiesOf(item), isEmpty);
      expect((await propertiesOf(other)).map((p) => p.value), ['Roma']);
      expect(await valuesOfRegion(), hasLength(1));
    });

    test(
      'un valor que ya existía antes se queda aunque nadie lo use',
      () async {
        await organizeRepository.getOrCreatePropertyDefinition('Región');
        final other = await seedItem(title: 'Otro');
        await organizeRepository.assignProperty(
          itemId: other.id,
          definitionId: region.id,
          value: 'Roma',
        );
        await organizeRepository.removeItemProperty(
          itemId: other.id,
          propertyValueId: (await valuesOfRegion()).single.id,
        );
        final item = await seedItem();
        final suggestion = await suggest(item, isNewValue: false);
        await repository.accept(suggestion.id);

        await repository.revertAccepted(suggestion.id);

        expect(await valuesOfRegion(), hasLength(1));
      },
    );

    test('aceptar una que el elemento ya tenía a mano no le cambia el '
        'origen', () async {
      final item = await seedItem();
      await organizeRepository.assignProperty(
        itemId: item.id,
        definitionId: region.id,
        value: 'Roma',
      );
      final suggestion = await suggest(item, isNewValue: false);

      await repository.accept(suggestion.id);

      final properties = await propertiesOf(item);
      expect(properties, hasLength(1));
      expect(properties.single.origin, ItemPropertyOrigin.manual);
    });

    test('deshacer una que el elemento ya tenía a mano no le quita la '
        'propiedad', () async {
      final item = await seedItem();
      await organizeRepository.assignProperty(
        itemId: item.id,
        definitionId: region.id,
        value: 'Roma',
      );
      final suggestion = await suggest(item, isNewValue: false);
      await repository.accept(suggestion.id);

      final result = await repository.revertAccepted(suggestion.id);

      expect(result.isRight(), isTrue);
      final properties = await propertiesOf(item);
      expect(properties.map((p) => p.value), ['Roma']);
      expect(properties.single.origin, ItemPropertyOrigin.manual);
      final pending = await repository.watchPendingSuggestions(item.id).first;
      expect(pending, hasLength(1));
    });

    test(
      'si después el usuario la puso a mano, es suya y no se quita',
      () async {
        final item = await seedItem();
        final suggestion = await suggest(item);
        await repository.accept(suggestion.id);
        await organizeRepository.assignProperty(
          itemId: item.id,
          definitionId: region.id,
          value: 'Roma',
        );

        await repository.revertAccepted(suggestion.id);

        final properties = await propertiesOf(item);
        expect(properties.map((p) => p.value), ['Roma']);
        expect(properties.single.origin, ItemPropertyOrigin.manual);
      },
    );

    test('se puede volver a aceptar después de deshacer', () async {
      final item = await seedItem();
      final suggestion = await suggest(item);
      await repository.accept(suggestion.id);
      await repository.revertAccepted(suggestion.id);

      final result = await repository.accept(suggestion.id);

      expect(result.isRight(), isTrue);
      final properties = await propertiesOf(item);
      expect(properties.map((p) => p.value), ['Roma']);
      expect(properties.single.origin, ItemPropertyOrigin.suggestedAccepted);
    });

    test('una sugerencia pendiente no se puede deshacer', () async {
      final item = await seedItem();
      final suggestion = await suggest(item);

      final result = await repository.revertAccepted(suggestion.id);

      expect(result.getLeft().toNullable(), isA<ValidationFailure>());
    });

    test('una rechazada tampoco', () async {
      final item = await seedItem();
      final suggestion = await suggest(item);
      await repository.reject(suggestion.id);

      final result = await repository.revertAccepted(suggestion.id);

      expect(result.getLeft().toNullable(), isA<ValidationFailure>());
    });

    test('una sugerencia de relación aceptada no se deshace por acá', () async {
      final itemA = await seedItem(title: 'A');
      final itemB = await seedItem(title: 'B');
      final relation = (await repository.createRelationSuggestion(
        targetItemId: itemA.id,
        relatedItemId: itemB.id,
        relatedItemTitle: 'B',
        kind: RelationKind.relatedTo,
        reason: 'Hablan de lo mismo.',
      )).getRight().toNullable()!;
      await repository.accept(relation.id);

      final result = await repository.revertAccepted(relation.id);

      expect(result.getLeft().toNullable(), isA<ValidationFailure>());
    });

    test('un id inexistente falla', () async {
      final result = await repository.revertAccepted('no-existe');

      expect(result.isLeft(), isTrue);
    });
  });

  group('sugerencias de propiedad en lote (F9)', () {
    Future<void> seedDefinition(String id, String name) => db
        .into(db.propertyDefinitions)
        .insert(
          PropertyDefinitionsCompanion.insert(
            id: id,
            name: name,
            createdAt: now,
          ),
        );

    Future<void> seedRegion() => seedDefinition('def-region', 'Región');

    Future<PropertySuggestion> suggest(
      KnowledgeItem item,
      String value, {
      String definitionId = 'def-region',
      String definitionName = 'Región',
    }) async =>
        (await repository.createPropertySuggestion(
              targetItemId: item.id,
              definitionId: definitionId,
              definitionName: definitionName,
              value: value,
              isNewValue: true,
            )).getRight().toNullable()!
            as PropertySuggestion;

    Future<List<PropertySuggestionGroup>> groups() =>
        repository.watchPendingPropertySuggestionGroups().first;

    Future<Set<(String, String)>> assignedPairs() async => {
      for (final row in await db.select(db.itemPropertyValues).get())
        (row.itemId, row.propertyValueId),
    };

    group('watchPendingPropertySuggestionGroups', () {
      test('agrupa por categoría y valor, sin distinguir mayúsculas ni '
          'acentos', () async {
        await seedRegion();
        await seedDefinition('def-epoca', 'Época');
        final a = await seedItem(title: 'A');
        final b = await seedItem(title: 'B');
        final c = await seedItem(title: 'C');
        final d = await seedItem(title: 'D');
        await suggest(a, 'Roma');
        await suggest(b, 'roma');
        await suggest(c, 'ROMA');
        await suggest(a, 'Cartago');
        await suggest(
          d,
          'Roma',
          definitionId: 'def-epoca',
          definitionName: 'Época',
        );

        final result = await groups();

        // Los grupos con más elementos primero; a igual cantidad, por
        // categoría sin acentos ("Época" antes que "Región").
        expect(
          result.map((g) => (g.definitionName, g.value, g.suggestions.length)),
          [
            ('Región', 'Roma', 3),
            ('Época', 'Roma', 1),
            ('Región', 'Cartago', 1),
          ],
        );
        expect(result.first.normalizedValue, 'roma');
        expect(result.first.suggestions.map((s) => s.targetItemId), [
          a.id,
          b.id,
          c.id,
        ]);
      });

      test('el valor lo da la escritura más común; a igual cantidad, la '
          'primera propuesta', () async {
        await seedRegion();
        final items = [
          for (var i = 0; i < 4; i++) await seedItem(title: 'E$i'),
        ];
        await suggest(items[0], 'Roma');
        await suggest(items[1], 'roma');
        await suggest(items[2], 'roma');

        expect((await groups()).single.value, 'roma');

        await suggest(items[3], 'Roma');
        // Ahora "Roma" y "roma" tienen dos cada una: gana la primera.
        expect((await groups()).single.value, 'Roma');
      });

      test(
        'dice si el valor ya existe, por su nombre o por un alias',
        () async {
          await seedRegion();
          await db
              .into(db.propertyValues)
              .insert(
                PropertyValuesCompanion.insert(
                  id: 'v-roma',
                  definitionId: 'def-region',
                  value: 'Roma',
                  createdAt: now,
                ),
              );
          await db
              .into(db.propertyAliases)
              .insert(
                PropertyAliasesCompanion.insert(
                  id: 'al-urbe',
                  propertyValueId: 'v-roma',
                  definitionId: 'def-region',
                  alias: 'Urbe',
                  createdAt: now,
                ),
              );
          final a = await seedItem(title: 'A');
          final b = await seedItem(title: 'B');
          final c = await seedItem(title: 'C');
          await suggest(a, 'roma');
          await suggest(b, 'Urbe');
          await suggest(c, 'Cartago');

          final byValue = {for (final g in await groups()) g.value: g};

          expect(byValue['roma']!.valueExists, isTrue);
          expect(byValue['Urbe']!.valueExists, isTrue);
          expect(byValue['Cartago']!.valueExists, isFalse);
        },
      );

      test('deja afuera lo que ya no está pendiente y lo que no es de '
          'propiedad', () async {
        await seedRegion();
        final a = await seedItem(title: 'A');
        final b = await seedItem(title: 'B');
        final c = await seedItem(title: 'C');
        final accepted = await suggest(a, 'Roma');
        final rejected = await suggest(b, 'Roma');
        await suggest(c, 'Roma');
        await repository.accept(accepted.id);
        await repository.reject(rejected.id);
        await repository.createRelationSuggestion(
          targetItemId: a.id,
          relatedItemId: b.id,
          relatedItemTitle: 'B',
          kind: RelationKind.relatedTo,
          reason: 'se parecen',
        );

        final result = await groups();

        expect(result, hasLength(1));
        expect(result.single.suggestions.map((s) => s.targetItemId), [c.id]);
      });

      test('deja afuera las de una categoría que ya no existe: una sola que '
          'no se pudiera aplicar haría fallar el lote', () async {
        final a = await seedItem(title: 'A');
        await suggest(
          a,
          'Roma',
          definitionId: 'def-borrada',
          definitionName: 'Borrada',
        );

        expect(await groups(), isEmpty);
      });

      test('muestra el nombre vigente de la categoría, no el que llevaba la '
          'sugerencia', () async {
        await seedRegion();
        final a = await seedItem(title: 'A');
        await suggest(a, 'Roma');
        await (db.update(db.propertyDefinitions)
              ..where((d) => d.id.equals('def-region')))
            .write(const PropertyDefinitionsCompanion(name: Value('Zona')));

        expect((await groups()).single.definitionName, 'Zona');
      });

      test('se actualiza sola cuando se acepta una sugerencia', () async {
        await seedRegion();
        final a = await seedItem(title: 'A');
        final b = await seedItem(title: 'B');
        final first = await suggest(a, 'Roma');
        await suggest(b, 'Roma');
        final queue = StreamQueue(
          repository.watchPendingPropertySuggestionGroups(),
        );
        addTearDown(queue.cancel);
        expect((await queue.next).single.suggestions, hasLength(2));

        await repository.accept(first.id);

        var latest = await queue.next;
        while (latest.single.suggestions.length != 1) {
          latest = await queue.next.timeout(const Duration(seconds: 5));
        }
        expect(latest.single.suggestions.single.targetItemId, b.id);
      });
    });

    group('acceptMany', () {
      test('aplica cada una como sugerida aceptada, las marca aceptadas y '
          'crea el valor una sola vez', () async {
        await seedRegion();
        final items = [
          for (var i = 0; i < 3; i++) await seedItem(title: 'E$i'),
        ];
        final suggestions = [
          await suggest(items[0], 'Roma'),
          await suggest(items[1], 'roma'),
          await suggest(items[2], 'ROMA'),
        ];

        final result = await repository.acceptMany([
          for (final s in suggestions) s.id,
        ]);

        expect(result.getRight().toNullable(), 3);
        // Un solo valor, no uno por sugerencia, y los tres elementos lo
        // tienen.
        final values = await db.select(db.propertyValues).get();
        expect(values, hasLength(1));
        expect(await assignedPairs(), {
          for (final item in items) (item.id, values.single.id),
        });
        final origins = await db.select(db.itemPropertyValues).get();
        expect(
          origins.every(
            (r) => r.origin == ItemPropertyOrigin.suggestedAccepted,
          ),
          isTrue,
        );
        expect(await groups(), isEmpty);
        final stored = await db.select(db.suggestions).get();
        expect(
          stored.every((s) => s.status == SuggestionStatus.accepted),
          isTrue,
        );
      });

      test('es atómico: si una no se puede aplicar, ninguna queda aplicada y '
          'todas siguen pendientes', () async {
        await seedRegion();
        final a = await seedItem(title: 'A');
        final b = await seedItem(title: 'B');
        final good = await suggest(a, 'Roma');
        // Su categoría no existe: aplicarla viola una clave foránea.
        final bad = await suggest(
          b,
          'Roma',
          definitionId: 'def-borrada',
          definitionName: 'Borrada',
        );

        final result = await repository.acceptMany([good.id, bad.id]);

        expect(result.isLeft(), isTrue);
        expect(await assignedPairs(), isEmpty);
        // Ni siquiera el valor que la primera había creado queda.
        expect(await db.select(db.propertyValues).get(), isEmpty);
        final stored = await db.select(db.suggestions).get();
        expect(
          stored.every((s) => s.status == SuggestionStatus.pending),
          isTrue,
        );
      });

      test('falla sin aplicar nada si alguna no existe, ya no está pendiente '
          'o no es de propiedad', () async {
        await seedRegion();
        final a = await seedItem(title: 'A');
        final b = await seedItem(title: 'B');
        final good = await suggest(a, 'Roma');
        final done = await suggest(b, 'Roma');
        await repository.accept(done.id);
        final relation = (await repository.createRelationSuggestion(
          targetItemId: a.id,
          relatedItemId: b.id,
          relatedItemTitle: 'B',
          kind: RelationKind.relatedTo,
          reason: 'se parecen',
        )).getRight().toNullable()!;
        final before = await assignedPairs();

        for (final other in ['no-existe', done.id, relation.id]) {
          final result = await repository.acceptMany([good.id, other]);

          expect(
            result.getLeft().toNullable(),
            isA<ValidationFailure>(),
            reason: other,
          );
        }
        expect(await assignedPairs(), before);
        final pending = await (db.select(
          db.suggestions,
        )..where((s) => s.id.equals(good.id))).getSingle();
        expect(pending.status, SuggestionStatus.pending);
      });

      test('un id repetido cuenta una vez', () async {
        await seedRegion();
        final a = await seedItem(title: 'A');
        final one = await suggest(a, 'Roma');

        final result = await repository.acceptMany([one.id, one.id]);

        expect(result.getRight().toNullable(), 1);
      });

      test('una lista vacía no hace nada', () async {
        final result = await repository.acceptMany(const []);

        expect(result.getRight().toNullable(), 0);
      });
    });

    group('rejectMany', () {
      test('marca rechazadas las pendientes, devuelve cuántas y no toca las '
          'ya aceptadas ni aplica nada', () async {
        await seedRegion();
        final a = await seedItem(title: 'A');
        final b = await seedItem(title: 'B');
        final c = await seedItem(title: 'C');
        final one = await suggest(a, 'Roma');
        final two = await suggest(b, 'Roma');
        final accepted = await suggest(c, 'Roma');
        await repository.accept(accepted.id);

        final result = await repository.rejectMany([
          one.id,
          two.id,
          accepted.id,
        ]);

        expect(result.getRight().toNullable(), 2);
        final statuses = {
          for (final s in await db.select(db.suggestions).get()) s.id: s.status,
        };
        expect(statuses[one.id], SuggestionStatus.rejected);
        expect(statuses[two.id], SuggestionStatus.rejected);
        expect(statuses[accepted.id], SuggestionStatus.accepted);
        // Solo la aceptada asignó algo.
        expect(await assignedPairs(), hasLength(1));
      });

      test('una lista vacía no hace nada', () async {
        final result = await repository.rejectMany(const []);

        expect(result.getRight().toNullable(), 0);
      });
    });
  });
}
