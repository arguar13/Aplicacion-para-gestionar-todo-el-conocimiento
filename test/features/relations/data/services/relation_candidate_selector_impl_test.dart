import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/domain/entities/item_kind.dart';
import 'package:sinapsis/core/domain/entities/item_state.dart';
import 'package:sinapsis/core/domain/services/embedding_similarity.dart';
import 'package:sinapsis/features/relations/data/services/relation_candidate_selector_impl.dart';

import '../../../../support/item_rows.dart';

/// Contra SQLite real, en memoria, sembrando `KnowledgeEntries`/`Chunks`/
/// `Embeddings` directo a mano con vectores de juguete —no hace falta la
/// dimensión 768 real del modelo para probar que la selección ordena y
/// filtra bien.
void main() {
  late AppDatabase db;
  late RelationCandidateSelectorImpl selector;

  final now = DateTime(2026, 9, 18, 10);
  var counter = 0;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    selector = RelationCandidateSelectorImpl(database: db);
    counter = 0;
  });

  tearDown(() => db.close());

  Future<String> seedItemWithVector(
    List<double> vector, {
    String title = 'Un elemento',
  }) async {
    final n = counter++;
    final itemId = 'item-$n';
    await db
        .into(db.knowledgeEntries)
        .insert(
          KnowledgeEntriesCompanion.insert(
            id: itemId,
            title: title,
            kind: ItemKind.source,
            state: ItemState.processed,
            createdAt: now,
            updatedAt: now,
            deviceId: 'test',
          ),
        );
    final chunkId = '$itemId-chunk-0';
    await db
        .into(db.chunks)
        .insert(
          ChunksCompanion.insert(
            id: chunkId,
            itemId: itemId,
            seq: 0,
            content: 'Contenido de $title',
            charStart: 0,
            charEnd: 10,
          ),
        );
    await db
        .into(db.embeddings)
        .insert(
          EmbeddingsCompanion.insert(
            chunkId: chunkId,
            vector: encodeEmbeddingVector(vector),
            modelVersion: 'test',
            createdAt: now,
          ),
        );
    return itemId;
  }

  test('sin chunks el semilla, lista vacía', () async {
    final n = counter++;
    await db
        .into(db.knowledgeEntries)
        .insert(
          KnowledgeEntriesCompanion.insert(
            id: 'item-$n',
            title: 'Sin chunks',
            kind: ItemKind.source,
            state: ItemState.processed,
            createdAt: now,
            updatedAt: now,
            deviceId: 'test',
          ),
        );

    final result = await selector.selectCandidates(seedItemId: 'item-$n');

    expect(result, isEmpty);
  });

  test('un candidato con vector idéntico: score 1.0, primero', () async {
    final seedId = await seedItemWithVector([1, 0, 0], title: 'Semilla');
    final identicalId = await seedItemWithVector([
      2,
      0,
      0,
    ], title: 'Idéntico en dirección');
    await seedItemWithVector([0, 1, 0], title: 'Ortogonal');

    final result = await selector.selectCandidates(
      seedItemId: seedId,
      minSimilarity: -1,
    );

    expect(result.first.itemId, identicalId);
    expect(result.first.score, closeTo(1.0, 1e-9));
  });

  test('un candidato ortogonal queda filtrado por minSimilarity', () async {
    final seedId = await seedItemWithVector([1, 0, 0], title: 'Semilla');
    await seedItemWithVector([0, 1, 0], title: 'Ortogonal');

    final result = await selector.selectCandidates(seedItemId: seedId);

    expect(result, isEmpty);
  });

  test('el propio semilla nunca aparece en su lista', () async {
    final seedId = await seedItemWithVector([1, 0, 0], title: 'Semilla');

    final result = await selector.selectCandidates(
      seedItemId: seedId,
      minSimilarity: -1,
    );

    expect(result.map((c) => c.itemId), isNot(contains(seedId)));
  });

  test('respeta el límite', () async {
    final seedId = await seedItemWithVector([1, 0, 0], title: 'Semilla');
    for (var i = 0; i < 5; i++) {
      await seedItemWithVector([1, 0, 0], title: 'Candidato $i');
    }

    final result = await selector.selectCandidates(
      seedItemId: seedId,
      minSimilarity: -1,
      limit: 3,
    );

    expect(result, hasLength(3));
  });

  group('la papelera (F11)', () {
    test('no propone vincular con algo que está en la papelera', () async {
      final seedId = await seedItemWithVector([1, 0, 0], title: 'Semilla');
      final trashedId = await seedItemWithVector([1, 0, 0], title: 'Borrado');
      final liveId = await seedItemWithVector([1, 0, 0], title: 'Vivo');
      await trashItemRows(db, trashedId);

      final result = await selector.selectCandidates(seedItemId: seedId);

      expect(result.map((c) => c.itemId), [liveId]);

      await restoreItemRows(db, trashedId);

      expect(
        (await selector.selectCandidates(
          seedItemId: seedId,
        )).map((c) => c.itemId),
        unorderedEquals([liveId, trashedId]),
      );
    });
  });
}
