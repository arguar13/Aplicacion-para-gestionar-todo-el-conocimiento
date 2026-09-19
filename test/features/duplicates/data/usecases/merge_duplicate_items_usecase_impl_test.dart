import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/database/tema_category.dart';
import 'package:sinapsis/core/domain/entities/knowledge_item.dart';
import 'package:sinapsis/core/domain/entities/processing_state.dart';
import 'package:sinapsis/core/domain/entities/relation_kind.dart';
import 'package:sinapsis/core/domain/entities/rendition.dart';
import 'package:sinapsis/core/domain/entities/rendition_kind.dart';
import 'package:sinapsis/core/domain/entities/source.dart';
import 'package:sinapsis/core/domain/entities/source_kind.dart';
import 'package:sinapsis/core/telemetry/telemetry_service.dart';
import 'package:sinapsis/features/duplicates/data/usecases/merge_duplicate_items_usecase_impl.dart';
import 'package:sinapsis/features/library/data/repositories/library_repository_impl.dart';

import '../../../../support/fake_id_generator.dart';
import '../../../../support/in_memory_file_store.dart';

class MockTelemetryService extends Mock implements TelemetryService {}

/// Contra SQLite real, en memoria: guarda los dos elementos con
/// `LibraryRepositoryImpl.save` —para que Items/Sources/Renditions y su
/// espejo nazcan por el camino real—, después siembra relaciones,
/// etiquetas, propiedades, tarjetas y resaltados directo en las tablas
/// que `MergeDuplicateItemsUseCaseImpl` no toca por sí sola.
void main() {
  late AppDatabase db;
  late LibraryRepositoryImpl library;
  late MergeDuplicateItemsUseCaseImpl useCase;
  late FakeIdGenerator ids;

  final now = DateTime(2026, 9, 19, 10);
  var counter = 0;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    library = LibraryRepositoryImpl(
      database: db,
      telemetry: MockTelemetryService(),
      files: InMemoryFileStore(),
    );
    ids = FakeIdGenerator(prefix: 'merged');
    useCase = MergeDuplicateItemsUseCaseImpl(
      database: db,
      library: library,
      ids: ids,
      clock: () => now,
      telemetry: MockTelemetryService(),
    );
    counter = 0;
  });

  tearDown(() => db.close());

  Future<String> seedItem({
    required String title,
    String text = 'texto',
  }) async {
    final n = counter++;
    final itemId = 'item-$n';
    final item = KnowledgeItem(
      id: itemId,
      title: title,
      source: Source(
        id: 'src-$n',
        kind: SourceKind.webPage,
        capturedAt: now,
        url: 'https://ejemplo.org/$n',
        authorName: 'Autora $n',
      ),
      processingState: ProcessingState.ready,
      createdAt: now,
      updatedAt: now,
      renditions: [
        Rendition.text(
          id: 'rend-$n',
          itemId: itemId,
          kind: RenditionKind.plainText,
          content: text,
          isPrimary: true,
          createdAt: now,
        ),
      ],
    );
    final result = await library.save(item);
    return result.getRight().toNullable()!.id;
  }

  /// Una etiqueta como existe desde F8: un valor de la categoría Tema.
  Future<void> seedTag(String id, String name) async {
    await db
        .into(db.propertyValues)
        .insert(
          PropertyValuesCompanion.insert(
            id: id,
            definitionId: await temaDefinitionId(db),
            value: name,
            createdAt: now,
          ),
        );
  }

  Future<void> tagItem(String itemId, String tagId) => db
      .into(db.itemPropertyValues)
      .insert(
        ItemPropertyValuesCompanion.insert(
          itemId: itemId,
          propertyValueId: tagId,
        ),
      );

  test('fusionar un elemento consigo mismo devuelve un fallo', () async {
    final id = await seedItem(title: 'Solo');

    final result = await useCase(keepItemId: id, discardItemId: id);

    expect(result.isLeft(), isTrue);
  });

  test(
    'si uno de los dos ya no existe devuelve un fallo, no revienta',
    () async {
      final keepId = await seedItem(title: 'El que queda');

      final result = await useCase(
        keepItemId: keepId,
        discardItemId: 'no-existe',
      );

      expect(result.isLeft(), isTrue);
    },
  );

  test('relaciones, etiquetas, propiedades y tarjetas del descartado '
      'terminan en el que queda', () async {
    final keepId = await seedItem(title: 'El que queda');
    final discardId = await seedItem(title: 'El descartado');
    final otherId = await seedItem(title: 'Un tercero');

    await db
        .into(db.relations)
        .insert(
          RelationsCompanion.insert(
            id: 'rel-1',
            fromItemId: discardId,
            toItemId: otherId,
            kind: RelationKind.relatedTo,
            createdAt: now,
          ),
        );
    await seedTag('tag-1', 'Filosofía');
    await tagItem(discardId, 'tag-1');
    await db
        .into(db.propertyDefinitions)
        .insert(
          PropertyDefinitionsCompanion.insert(
            id: 'def-1',
            name: 'Región',
            createdAt: now,
          ),
        );
    await db
        .into(db.propertyValues)
        .insert(
          PropertyValuesCompanion.insert(
            id: 'val-1',
            definitionId: 'def-1',
            value: 'Roma',
            createdAt: now,
          ),
        );
    await db
        .into(db.itemPropertyValues)
        .insert(
          ItemPropertyValuesCompanion.insert(
            itemId: discardId,
            propertyValueId: 'val-1',
          ),
        );
    await db
        .into(db.flashcards)
        .insert(
          FlashcardsCompanion.insert(
            id: 'fc-1',
            itemId: discardId,
            front: 'Pregunta',
            back: 'Respuesta',
            dueAt: now,
            createdAt: now,
          ),
        );

    final result = await useCase(keepItemId: keepId, discardItemId: discardId);

    expect(result.isRight(), isTrue);

    final relation = await (db.select(
      db.relations,
    )..where((r) => r.id.equals('rel-1'))).getSingle();
    expect(relation.fromItemId, keepId);
    expect(relation.toItemId, otherId);

    // La etiqueta viaja como cualquier otro valor: es un valor de Tema.
    final itemTag = await (db.select(
      db.itemPropertyValues,
    )..where((t) => t.propertyValueId.equals('tag-1'))).getSingle();
    expect(itemTag.itemId, keepId);

    final propertyAssignment = await (db.select(
      db.itemPropertyValues,
    )..where((p) => p.propertyValueId.equals('val-1'))).getSingle();
    expect(propertyAssignment.itemId, keepId);

    final flashcard = await (db.select(
      db.flashcards,
    )..where((f) => f.id.equals('fc-1'))).getSingle();
    expect(flashcard.itemId, keepId);
  });

  test('un tag que ya tenía el que queda no se duplica', () async {
    final keepId = await seedItem(title: 'El que queda');
    final discardId = await seedItem(title: 'El descartado');
    await seedTag('tag-1', 'Filosofía');
    await tagItem(keepId, 'tag-1');
    await tagItem(discardId, 'tag-1');

    final result = await useCase(keepItemId: keepId, discardItemId: discardId);

    expect(result.isRight(), isTrue);
    final rows = await (db.select(
      db.itemPropertyValues,
    )..where((t) => t.propertyValueId.equals('tag-1'))).get();
    expect(rows, hasLength(1));
    expect(rows.single.itemId, keepId);
  });

  test('una relación entre ambos duplicados desaparece sin romper la '
      'fusión', () async {
    final keepId = await seedItem(title: 'El que queda');
    final discardId = await seedItem(title: 'El descartado');
    await db
        .into(db.relations)
        .insert(
          RelationsCompanion.insert(
            id: 'rel-1',
            fromItemId: discardId,
            toItemId: keepId,
            kind: RelationKind.relatedTo,
            createdAt: now,
          ),
        );

    final result = await useCase(keepItemId: keepId, discardItemId: discardId);

    expect(result.isRight(), isTrue);
    final rows = await db.select(db.relations).get();
    expect(rows, isEmpty);
  });

  test('las dos renditions de texto sobreviven, la más larga queda '
      'primaria', () async {
    final keepId = await seedItem(title: 'El que queda', text: 'corto');
    final discardId = await seedItem(
      title: 'El descartado',
      text: 'un texto bastante más largo que el otro',
    );

    final result = await useCase(keepItemId: keepId, discardItemId: discardId);

    expect(result.isRight(), isTrue);
    final renditions = await (db.select(
      db.renditions,
    )..where((r) => r.itemId.equals(keepId))).get();
    expect(renditions, hasLength(2));

    final primary = renditions.singleWhere((r) => r.isPrimary);
    expect(primary.content, 'un texto bastante más largo que el otro');
    final secondary = renditions.singleWhere((r) => !r.isPrimary);
    expect(secondary.content, 'corto');
  });

  test(
    'un resaltado del descartado sigue existiendo después de fusionar',
    () async {
      final keepId = await seedItem(title: 'El que queda');
      final discardId = await seedItem(
        title: 'El descartado',
        text: 'una frase',
      );
      await db
          .into(db.highlights)
          .insert(
            HighlightsCompanion.insert(
              id: 'hl-1',
              renditionId: 'rend-1',
              startOffset: 0,
              endOffset: 4,
              excerpt: 'una',
              createdAt: now,
            ),
          );

      final result = await useCase(
        keepItemId: keepId,
        discardItemId: discardId,
      );

      expect(result.isRight(), isTrue);
      final highlight = await (db.select(
        db.highlights,
      )..where((h) => h.id.equals('hl-1'))).getSingle();
      final rendition = await (db.select(
        db.renditions,
      )..where((r) => r.id.equals(highlight.renditionId))).getSingle();
      expect(rendition.itemId, keepId);
    },
  );

  test('guarda un registro con la procedencia del descartado', () async {
    final keepId = await seedItem(title: 'El que queda');
    final discardId = await seedItem(title: 'El descartado');

    await useCase(keepItemId: keepId, discardItemId: discardId);

    final provenance = await db.select(db.mergedProvenances).getSingle();
    expect(provenance.itemId, keepId);
    expect(provenance.sourceKind, SourceKind.webPage);
    expect(provenance.url, isNotNull);
    expect(provenance.mergedAt, now);
  });

  test('el descartado deja de existir', () async {
    final keepId = await seedItem(title: 'El que queda');
    final discardId = await seedItem(title: 'El descartado');

    await useCase(keepItemId: keepId, discardItemId: discardId);

    final item = await (db.select(
      db.items,
    )..where((i) => i.id.equals(discardId))).getSingleOrNull();
    expect(item, isNull);
    final entry = await (db.select(
      db.knowledgeEntries,
    )..where((e) => e.id.equals(discardId))).getSingleOrNull();
    expect(entry, isNull);
  });

  group('enlaces en línea (F9)', () {
    var linkCounter = 0;

    Future<void> link(String from, String title, {String? to}) => db
        .into(db.inlineLinks)
        .insert(
          InlineLinksCompanion.insert(
            id: 'link-${linkCounter++}',
            fromItemId: from,
            targetTitle: title,
            normalizedTitle: title.toLowerCase(),
            toItemId: Value(to),
            createdAt: now,
          ),
        );

    Future<Set<(String, String, String?)>> links() async => {
      for (final l in await db.select(db.inlineLinks).get())
        (l.fromItemId, l.normalizedTitle, l.toItemId),
    };

    setUp(() => linkCounter = 0);

    test('los enlaces que apuntaban al descartado apuntan al que queda, en '
        'vez de quedar rotos al borrarlo', () async {
      final keepId = await seedItem(title: 'El que queda');
      final discardId = await seedItem(title: 'El descartado');
      final otherId = await seedItem(title: 'Otra nota');
      await link(otherId, 'El descartado', to: discardId);

      await useCase(keepItemId: keepId, discardItemId: discardId);

      expect(await links(), {(otherId, 'el descartado', keepId)});
    });

    test('los enlaces que escribía el descartado pasan al que queda', () async {
      final keepId = await seedItem(title: 'El que queda');
      final discardId = await seedItem(title: 'El descartado');
      final romaId = await seedItem(title: 'Roma');
      await link(discardId, 'Roma', to: romaId);
      await link(discardId, 'Cartago');

      await useCase(keepItemId: keepId, discardItemId: discardId);

      expect(await links(), {
        (keepId, 'roma', romaId),
        (keepId, 'cartago', null),
      });
    });

    test('un destino que los dos ya tenían no se duplica', () async {
      final keepId = await seedItem(title: 'El que queda');
      final discardId = await seedItem(title: 'El descartado');
      final romaId = await seedItem(title: 'Roma');
      await link(keepId, 'Roma', to: romaId);
      await link(discardId, 'Roma', to: romaId);

      final result = await useCase(
        keepItemId: keepId,
        discardItemId: discardId,
      );

      expect(result.isRight(), isTrue);
      expect(await links(), {(keepId, 'roma', romaId)});
    });

    test('si el que queda lo tenía roto y el descartado no, se conserva el '
        'que tiene destino', () async {
      final keepId = await seedItem(title: 'El que queda');
      final discardId = await seedItem(title: 'El descartado');
      final romaId = await seedItem(title: 'Roma');
      await link(keepId, 'Roma');
      await link(discardId, 'Roma', to: romaId);

      await useCase(keepItemId: keepId, discardItemId: discardId);

      expect(await links(), {(keepId, 'roma', romaId)});
    });

    test('dos duplicados que se enlazaban entre sí no dejan a la nota '
        'enlazada a sí misma', () async {
      final keepId = await seedItem(title: 'El que queda');
      final discardId = await seedItem(title: 'El descartado');
      await link(keepId, 'El descartado', to: discardId);
      await link(discardId, 'El que queda', to: keepId);

      await useCase(keepItemId: keepId, discardItemId: discardId);

      expect(await links(), isEmpty);
    });
  });
}
