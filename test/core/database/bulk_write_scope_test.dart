import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/database/bulk_write_scope.dart';
import 'package:sinapsis/core/database/search_index.dart';
import 'package:sinapsis/core/domain/entities/source_kind.dart';

import '../../support/item_rows.dart';

/// `withSuspendedSearchIndexes` (F19, 19.1): suspende los triggers del
/// índice de texto y repuebla los dos de una sola vez al terminar, contra
/// SQLite real —el único que puede confirmar que un trigger de verdad se
/// suspendió—.
void main() {
  late AppDatabase db;
  var counter = 0;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    counter = 0;
  });

  tearDown(() => db.close());

  Future<String> newNote(String title) async {
    final id = 'item-${counter++}';
    await insertItemRows(db, id: id, title: title, kind: SourceKind.manualNote);
    return id;
  }

  Future<void> addChunk(String itemId, String content, {int seq = 0}) => db
      .into(db.chunks)
      .insert(
        ChunksCompanion.insert(
          id: 'chunk-${counter++}',
          itemId: itemId,
          seq: seq,
          content: content,
          charStart: 0,
          charEnd: content.length,
        ),
      );

  Future<List<String>> searchItems(String userInput) async {
    final query = buildSearchQuery(userInput);
    if (query.isEmpty) return [];
    final rows = await db
        .customSelect(
          'SELECT item_id FROM item_search WHERE item_search MATCH ? '
          'ORDER BY rank',
          variables: [Variable.withString(query)],
        )
        .get();
    return rows.map((r) => r.data['item_id']! as String).toList();
  }

  Future<int> chunkMatches(String userInput) async {
    final query = buildSearchQuery(userInput);
    final rows = await db
        .customSelect(
          'SELECT COUNT(*) AS n FROM chunk_search WHERE chunk_search MATCH ?',
          variables: [Variable.withString(query)],
        )
        .get();
    return rows.single.data['n']! as int;
  }

  test('durante el lote, escribir no toca los índices; al terminar, quedan '
      'al día', () async {
    await withSuspendedSearchIndexes(db, () async {
      final id = await newNote('La estructura de las revoluciones');
      await addChunk(id, 'un fragmento sobre revoluciones científicas');

      // Adentro del lote, los triggers están suspendidos: los índices
      // todavía no saben nada de esto.
      expect(await searchItems('revoluciones'), isEmpty);
      expect(await chunkMatches('revoluciones'), 0);
    });

    // Al terminar, los dos quedan repoblados.
    expect(await searchItems('revoluciones'), hasLength(1));
    expect(await chunkMatches('revoluciones'), 1);
  });

  test('lo que ya existía antes del lote también queda en los índices al '
      'terminar', () async {
    final before = await newNote('Antes del lote');

    await withSuspendedSearchIndexes(db, () async {
      await newNote('Durante el lote');
    });

    expect(await searchItems('antes'), [before]);
    expect(await searchItems('durante'), hasLength(1));
  });

  test('los triggers vuelven a funcionar después del lote, fila por fila '
      'de nuevo', () async {
    await withSuspendedSearchIndexes(db, () async {
      await newNote('Adentro del lote');
    });

    // Fuera del lote: un guardado normal debe verse enseguida, sin esperar
    // otro `withSuspendedSearchIndexes`.
    final id = await newNote('Después del lote');
    expect(await searchItems('después'), [id]);
  });

  test('un fallo adentro del lote repuebla los índices igual, antes de '
      'propagar el error', () async {
    await expectLater(
      withSuspendedSearchIndexes(db, () async {
        await newNote('Antes de fallar');
        throw StateError('algo salió mal a mitad del lote');
      }),
      throwsA(isA<StateError>()),
    );

    // El índice no quedó desincronizado ni sin sus triggers.
    expect(await searchItems('fallar'), hasLength(1));
    final id = await newNote('Después del fallo');
    expect(await searchItems('después'), [id]);
  });

  test('un lote vacío no rompe nada', () async {
    await withSuspendedSearchIndexes(db, () async {});

    expect(await searchItems('lo que sea'), isEmpty);
  });

  group('touchedItemIds (F19, 19.4): repoblar acotado, no la tabla entera', () {
    test('solo repuebla los ids que se le dan, no toda la bóveda', () async {
      final before = await newNote('Ya estaba antes del lote');
      late String duringId;

      await withSuspendedSearchIndexes(db, () async {
        duringId = await newNote('Nueva durante el lote');
      }, touchedItemIds: () => [duringId]);

      // La nueva, tocada, queda indexada.
      expect(await searchItems('nueva'), [duringId]);
      // La de antes, JAMÁS tocada por este lote, sigue como estaba —no la
      // tira ni la vuelve a escribir, a diferencia del rebuild entero—.
      expect(await searchItems('antes'), [before]);
    });

    test('una lista vacía de ids no repuebla nada', () async {
      await withSuspendedSearchIndexes(db, () async {
        await newNote('Adentro, pero nadie la anuncia como tocada');
      }, touchedItemIds: () => const []);

      expect(await searchItems('adentro'), isEmpty);
    });

    test(
      'reindexa el valor de AHORA, no el de cuando se tocó primero',
      () async {
        late String id;

        await withSuspendedSearchIndexes(db, () async {
          id = await newNote('Título original');
          await db.customStatement('UPDATE item SET title = ? WHERE id = ?', [
            'Título final',
            id,
          ]);
        }, touchedItemIds: () => [id]);

        expect(await searchItems('final'), [id]);
        expect(await searchItems('original'), isEmpty);
      },
    );
  });

  group('chunks: false (F19, 19.4): no suspende chunk_search', () {
    test('un chunk agregado durante el lote se ve enseguida, sin esperar a '
        'que cierre', () async {
      final id = await newNote('Con chunk');

      await withSuspendedSearchIndexes(db, () async {
        await addChunk(id, 'contenido agregado durante el lote');
        // A diferencia del default: acá el trigger real de chunks sigue
        // activo, así que ya se ve DENTRO del lote.
        expect(await chunkMatches('agregado'), 1);
      }, chunks: false);

      expect(await chunkMatches('agregado'), 1);
    });
  });
}
