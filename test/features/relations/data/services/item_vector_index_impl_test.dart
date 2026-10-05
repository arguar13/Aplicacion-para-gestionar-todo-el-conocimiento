import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/domain/entities/source_kind.dart';
import 'package:sinapsis/core/domain/services/embedding_similarity.dart';
import 'package:sinapsis/features/relations/data/services/item_vector_index_impl.dart';
import 'package:sinapsis/features/relations/domain/services/item_vector_index.dart';

import '../../../../support/item_rows.dart';

/// Contra SQLite real, en memoria, con vectores de juguete de tres
/// dimensiones sembrados a mano (F30).
void main() {
  late AppDatabase db;
  late ItemVectorIndexImpl index;
  final now = DateTime(2026, 10, 4, 10);

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    index = ItemVectorIndexImpl(database: db);
  });

  tearDown(() => db.close());

  /// Una fuente con un fragmento por vector.
  Future<void> source(String id, List<List<double>> vectors) async {
    await insertItemRows(db, id: id, title: 'Fuente $id');
    for (var i = 0; i < vectors.length; i++) {
      final chunkId = '$id-$i';
      await db
          .into(db.chunks)
          .insert(
            ChunksCompanion.insert(
              id: chunkId,
              itemId: id,
              seq: i,
              content: 'Fragmento $i de $id',
              charStart: i * 10,
              charEnd: i * 10 + 10,
            ),
          );
      await db
          .into(db.embeddings)
          .insert(
            EmbeddingsCompanion.insert(
              chunkId: chunkId,
              vector: encodeEmbeddingVector(vectors[i]),
              modelVersion: 'test',
              createdAt: now,
            ),
          );
    }
  }

  /// Una nota con un tramo.
  Future<void> note(String id, List<double> vector) async {
    await insertItemRows(
      db,
      id: id,
      title: 'Nota $id',
      kind: SourceKind.manualNote,
    );
    await db
        .into(db.noteEmbeddings)
        .insert(
          NoteEmbeddingsCompanion.insert(
            itemId: id,
            seq: 0,
            vector: encodeEmbeddingVector(vector),
            textHash: 'hash-$id',
            modelVersion: 'test',
            createdAt: now,
          ),
        );
  }

  group('nearestTo', () {
    test('cuenta el fragmento más parecido de cada elemento, no el promedio, '
        'y ordena del más parecido al menos', () async {
      // Un libro que habla de lo buscado en uno solo de sus fragmentos.
      await source('libro', [
        [0, 1, 0],
        [0, 1, 0],
        [1, 0, 0],
      ]);
      await source('cerca', [
        [1, 0.5, 0],
      ]);
      await source('lejos', [
        [0, 0, 1],
      ]);
      await note('nota', [1, 0.2, 0]);

      final found = await index.nearestTo(
        const [1, 0, 0],
        limit: 10,
        minSimilarity: 0.5,
      );

      expect(found.map((s) => s.itemId), ['libro', 'nota', 'cerca']);
      expect(found.first.score, closeTo(1, 1e-6));
    });

    test('deja afuera la papelera, respeta el tope y no compara vectores de '
        'otra dimensión', () async {
      await source('a', [
        [1, 0, 0],
      ]);
      await source('b', [
        [0.9, 0.1, 0],
      ]);
      await source('c', [
        [0.8, 0.2, 0],
      ]);
      await source('otro-modelo', [
        [1, 0, 0, 0],
      ]);
      await source('borrado', [
        [1, 0, 0],
      ]);
      await (db.update(db.knowledgeEntries)
            ..where((e) => e.id.equals('borrado')))
          .write(KnowledgeEntriesCompanion(deletedAt: Value(now)));

      final found = await index.nearestTo(
        const [1, 0, 0],
        limit: 2,
        minSimilarity: 0,
      );

      expect(found.map((s) => s.itemId), ['a', 'b']);
    });

    test('sin ningún vector guardado, nada', () async {
      await insertItemRows(db, id: 'sin', title: 'Sin vectores');

      expect(
        await index.nearestTo(const [1, 0, 0], limit: 5, minSimilarity: 0),
        isEmpty,
      );
    });
  });

  group('representativeOrder', () {
    test('primero el más central, después el más distinto de lo elegido; '
        'los que no tienen vectores, al final', () async {
      // Tres de Roma, casi iguales; uno de Grecia; uno de Egipto.
      await source('roma-1', [
        [1, 0.05, 0],
      ]);
      await source('roma-2', [
        [1, 0, 0.05],
      ]);
      await source('roma-3', [
        [1, 0.02, 0.02],
      ]);
      await source('grecia', [
        [0, 1, 0],
      ]);
      await source('egipto', [
        [0, 0, 1],
      ]);
      await insertItemRows(db, id: 'sin-vectores', title: 'Sin vectores');

      final order = await index.representativeOrder([
        'roma-1',
        'roma-2',
        'sin-vectores',
        'roma-3',
        'grecia',
        'egipto',
      ], take: 3);

      expect(order, hasLength(6));
      expect(order.take(3).toSet(), containsAll(['grecia', 'egipto']));
      expect(
        order.take(3).where((id) => id.startsWith('roma')),
        hasLength(1),
        reason: 'de lo que se repite, uno solo entre los primeros',
      );
      expect(order.toSet(), {
        'roma-1',
        'roma-2',
        'roma-3',
        'grecia',
        'egipto',
        'sin-vectores',
      });
    });

    test('sin ningún vector, la lista repartida parejo', () async {
      for (var i = 0; i < 5; i++) {
        await insertItemRows(db, id: 'e$i', title: 'Elemento $i');
      }

      final order = await index.representativeOrder([
        'e0',
        'e1',
        'e2',
        'e3',
        'e4',
      ], take: 2);

      expect(order, ['e2', 'e1', 'e3', 'e0', 'e4']);
    });

    test('ids repetidos cuentan una vez', () async {
      expect(await index.representativeOrder(['a', 'a'], take: 1), ['a']);
    });
  });

  test('spreadOrder va de lo grueso a lo fino, sin perder ni repetir', () {
    expect(spreadOrder([0, 1, 2, 3, 4, 5, 6, 7]), [4, 2, 6, 1, 3, 5, 7, 0]);
    expect(spreadOrder(<int>[]), isEmpty);
    expect(spreadOrder(['solo']), ['solo']);
  });

  test('ItemSimilarity se compara por valor', () {
    expect(
      const ItemSimilarity(itemId: 'a', score: 0.5),
      const ItemSimilarity(itemId: 'a', score: 0.5),
    );
  });
}
