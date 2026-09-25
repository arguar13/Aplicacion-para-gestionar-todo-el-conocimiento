import 'package:drift/drift.dart' hide isNull;
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
import 'package:sinapsis/core/domain/services/embedding_similarity.dart';
import 'package:sinapsis/core/telemetry/telemetry_service.dart';
import 'package:sinapsis/features/export/data/services/anki_topic_resolver_impl.dart';
import 'package:sinapsis/features/flashcards/data/services/distractor_sourcer_impl.dart';
import 'package:sinapsis/features/library/data/repositories/library_repository_impl.dart';
import 'package:sinapsis/features/map/data/repositories/knowledge_map_repository_impl.dart';
import 'package:sinapsis/features/organize/data/repositories/organize_repository_impl.dart';
import 'package:sinapsis/features/relations/data/services/relation_candidate_selector_impl.dart';

import '../../../../support/fake_id_generator.dart';
import '../../../../support/in_memory_file_store.dart';
import '../../../../support/item_rows.dart';

class MockTelemetryService extends Mock implements TelemetryService {}

/// Contra SQLite real, con las cuatro piezas reales de la decisión C (F20):
/// `AnkiTopicResolver`/`KnowledgeMapRepository` para hermanos del Atlas,
/// `OrganizeRepository` para `contradicts`, `RelationCandidateSelector` para
/// embedding. No hay doble de ninguna: lo que hay que verificar es que las
/// tres fuentes reales se combinan bien, no solo que algo responda lo que se
/// le pida.
void main() {
  late AppDatabase db;
  late LibraryRepositoryImpl library;
  late DistractorSourcerImpl sourcer;

  final now = DateTime(2026, 9, 25, 12);
  var counter = 0;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    counter = 0;
    library = LibraryRepositoryImpl(
      database: db,
      telemetry: MockTelemetryService(),
      files: InMemoryFileStore(),
      ids: FakeIdGenerator(prefix: 'lib'),
      clock: () => now,
    );
    sourcer = DistractorSourcerImpl(
      database: db,
      topics: AnkiTopicResolverImpl(database: db),
      map: KnowledgeMapRepositoryImpl(database: db, library: library),
      organize: OrganizeRepositoryImpl(
        database: db,
        telemetry: MockTelemetryService(),
        ids: FakeIdGenerator(prefix: 'org'),
        clock: () => now,
      ),
      relations: RelationCandidateSelectorImpl(database: db),
    );
  });

  tearDown(() => db.close());

  /// Un elemento con texto real —para que tenga chunks de verdad, como
  /// cualquier fuente de la bóveda—.
  Future<String> seedItem(String content) async {
    final n = counter++;
    final id = 'item-$n';
    await library.save(
      KnowledgeItem(
        id: id,
        title: 'Elemento $n',
        source: Source(
          id: 'src-$n',
          kind: SourceKind.webPage,
          capturedAt: now,
          url: 'https://ejemplo.org/$n',
        ),
        processingState: ProcessingState.ready,
        createdAt: now,
        updatedAt: now,
        renditions: [
          Rendition.text(
            id: 'rend-$n',
            itemId: id,
            kind: RenditionKind.markdown,
            content: content,
            isPrimary: true,
            createdAt: now,
          ),
        ],
      ),
    );
    return id;
  }

  Future<String> addTema(String id, String label, {String? parentId}) async {
    final definitionId = await temaDefinitionId(db);
    await db
        .into(db.propertyValues)
        .insert(
          PropertyValuesCompanion.insert(
            id: id,
            definitionId: definitionId,
            value: label,
            parentId: Value(parentId),
            createdAt: now,
          ),
        );
    return id;
  }

  Future<void> assignTema(String itemId, String temaId) => db
      .into(db.itemPropertyValues)
      .insert(
        ItemPropertyValuesCompanion.insert(
          itemId: itemId,
          propertyValueId: temaId,
        ),
      );

  Future<void> addContradicts(String fromItemId, String toItemId) => db
      .into(db.relations)
      .insert(
        RelationsCompanion.insert(
          id: 'rel-${counter++}',
          fromItemId: fromItemId,
          toItemId: toItemId,
          kind: RelationKind.contradicts,
          createdAt: now,
        ),
      );

  Future<void> addEmbedding(String itemId, List<double> vector) async {
    final chunk = await (db.select(
      db.chunks,
    )..where((c) => c.itemId.equals(itemId))).getSingle();
    await db
        .into(db.embeddings)
        .insert(
          EmbeddingsCompanion.insert(
            chunkId: chunk.id,
            vector: encodeEmbeddingVector(vector),
            modelVersion: 'test',
            createdAt: now,
          ),
        );
  }

  test('sin ninguna fuente real, lista vacía —nunca inventa nada', () async {
    final seedId = await seedItem('El texto de la semilla.');

    final result = await sourcer.sourceDistractors(
      seedItemId: seedId,
      excludeContent: 'La respuesta correcta',
    );

    expect(result, isEmpty);
  });

  test('hermanos del Atlas: otro elemento bajo un tema hermano es '
      'candidato', () async {
    final seedId = await seedItem('Texto de la semilla, sobre Roma.');
    final siblingId = await seedItem('Texto de otro elemento, sobre Egipto.');
    await addTema('historia', 'Historia');
    await addTema('roma', 'Roma', parentId: 'historia');
    await addTema('egipto', 'Egipto', parentId: 'historia');
    await assignTema(seedId, 'roma');
    await assignTema(siblingId, 'egipto');

    final result = await sourcer.sourceDistractors(
      seedItemId: seedId,
      excludeContent: 'nada que coincida',
    );

    expect(result.map((c) => c.itemId), contains(siblingId));
  });

  test('un elemento bajo el MISMO tema —no hermano— no es candidato de '
      'Atlas', () async {
    final seedId = await seedItem('Texto de la semilla, sobre Roma.');
    final sameTopicId = await seedItem('Otro elemento, también sobre Roma.');
    await addTema('roma', 'Roma');
    await assignTema(seedId, 'roma');
    await assignTema(sameTopicId, 'roma');

    final result = await sourcer.sourceDistractors(
      seedItemId: seedId,
      excludeContent: 'nada que coincida',
    );

    expect(result, isEmpty);
  });

  test('contradicts: el otro lado de la relación es candidato, en '
      'cualquiera de los dos sentidos', () async {
    final seedId = await seedItem('La Tierra es redonda.');
    final otherId = await seedItem('Algunos creían que la Tierra era plana.');
    await addContradicts(seedId, otherId);

    final result = await sourcer.sourceDistractors(
      seedItemId: seedId,
      excludeContent: 'nada que coincida',
    );

    expect(result.map((c) => c.itemId), contains(otherId));
  });

  test('embedding: un elemento cercano por vector es candidato', () async {
    final seedId = await seedItem('Texto de la semilla.');
    final closeId = await seedItem('Texto parecido en significado.');
    await addEmbedding(seedId, [1, 0, 0]);
    await addEmbedding(closeId, [1, 0, 0]);

    final result = await sourcer.sourceDistractors(
      seedItemId: seedId,
      excludeContent: 'nada que coincida',
    );

    expect(result.map((c) => c.itemId), contains(closeId));
  });

  test('un distractor nunca puede ser también correcto: descarta el candidato '
      'cuyo texto coincide con la respuesta correcta', () async {
    const correctAnswer = 'Texto idéntico a la respuesta correcta.';
    final seedId = await seedItem('La pregunta sale de acá.');
    final matchingId = await seedItem(correctAnswer);
    await addContradicts(seedId, matchingId);

    final result = await sourcer.sourceDistractors(
      seedItemId: seedId,
      excludeContent: correctAnswer,
    );

    expect(result, isEmpty);
  });

  test('un elemento en la papelera no es candidato', () async {
    final seedId = await seedItem('La Tierra es redonda.');
    final trashedId = await seedItem('Contenido de un elemento borrado.');
    await addContradicts(seedId, trashedId);
    await trashItemRows(db, trashedId);

    final result = await sourcer.sourceDistractors(
      seedItemId: seedId,
      excludeContent: 'nada que coincida',
    );

    expect(result, isEmpty);
  });

  test('el propio elemento semilla nunca es su propio distractor', () async {
    final seedId = await seedItem('Semilla, sobre Roma.');
    await addTema('roma', 'Roma');
    await assignTema(seedId, 'roma');

    final result = await sourcer.sourceDistractors(
      seedItemId: seedId,
      excludeContent: 'nada que coincida',
    );

    expect(result, isEmpty);
  });

  test('no repite el mismo elemento entre fuentes distintas', () async {
    final seedId = await seedItem('Semilla, sobre Roma.');
    final otherId = await seedItem('Otro elemento, sobre Egipto.');
    await addTema('historia', 'Historia');
    await addTema('roma', 'Roma', parentId: 'historia');
    await addTema('egipto', 'Egipto', parentId: 'historia');
    await assignTema(seedId, 'roma');
    await assignTema(otherId, 'egipto');
    await addContradicts(seedId, otherId);

    final result = await sourcer.sourceDistractors(
      seedItemId: seedId,
      excludeContent: 'nada que coincida',
      count: 5,
    );

    expect(result.where((c) => c.itemId == otherId), hasLength(1));
  });

  test('respeta count aunque haya más candidatos reales', () async {
    final seedId = await seedItem('Semilla, sobre Roma.');
    await addTema('historia', 'Historia');
    await addTema('roma', 'Roma', parentId: 'historia');
    for (var i = 0; i < 5; i++) {
      final siblingTopic = 'sibling-$i';
      final itemId = await seedItem('Elemento hermano número $i.');
      await addTema(siblingTopic, 'Hermano $i', parentId: 'historia');
      await assignTema(itemId, siblingTopic);
    }
    await assignTema(seedId, 'roma');

    final result = await sourcer.sourceDistractors(
      seedItemId: seedId,
      excludeContent: 'nada que coincida',
      count: 2,
    );

    expect(result, hasLength(2));
  });

  test('cada candidato llega anclado a un chunk real', () async {
    final seedId = await seedItem('La Tierra es redonda.');
    final otherId = await seedItem('Algunos creían que la Tierra era plana.');
    await addContradicts(seedId, otherId);

    final result = await sourcer.sourceDistractors(
      seedItemId: seedId,
      excludeContent: 'nada que coincida',
    );

    final candidate = result.single;
    final chunk = await (db.select(
      db.chunks,
    )..where((c) => c.id.equals(candidate.sourceChunkId))).getSingle();
    expect(chunk.itemId, otherId);
    expect(
      candidate.content,
      chunk.content.substring(0, candidate.content.length),
    );
    expect(candidate.sourceCharStart, chunk.charStart);
  });
}
