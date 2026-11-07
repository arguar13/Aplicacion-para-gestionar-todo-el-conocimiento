import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/database/chunk_search_text_backfill.dart';
import 'package:sinapsis/core/database/search_index.dart';
import 'package:sinapsis/core/domain/entities/source_kind.dart';

import '../../support/item_rows.dart';

/// El relleno de lo que se busca de los chunks que ya estaban (F46, paso 5i),
/// contra SQLite real.
void main() {
  late AppDatabase db;
  var seq = 0;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    seq = 0;
    await insertItemRows(db, id: 'web', title: 'Fotosíntesis');
    await insertItemRows(
      db,
      id: 'video',
      title: 'Charla',
      kind: SourceKind.youtube,
    );
  });

  tearDown(() => db.close());

  /// Un chunk como los de antes de v52: sin lo que se busca ni su versión.
  Future<void> addOld(String itemId, String content, {int? rule}) => db
      .into(db.chunks)
      .insert(
        ChunksCompanion.insert(
          id: 'c-${seq++}',
          itemId: itemId,
          seq: seq,
          content: content,
          charStart: 0,
          charEnd: content.length,
          searchTextRule: Value(rule),
        ),
      );

  Future<int> matches(String input) async =>
      (await db
              .customSelect(
                'SELECT COUNT(*) AS n FROM chunk_search '
                'WHERE chunk_search MATCH ?',
                variables: [Variable.withString(buildSearchQuery(input))],
              )
              .getSingle())
          .read<int>('n');

  const link = 'La [fotosíntesis](https://es.wikipedia.org/wiki/F) sube.';

  test('pone al día lo de Markdown, le da la versión a lo demás, y el índice '
      'queda exacto', () async {
    await addOld('web', link);
    await addOld('video', '[00:10] Ver https://es.wikipedia.org/wiki/F');
    expect(await matches('wikipedia'), 2);

    expect(await ChunkSearchTextBackfill(database: db).run(), 2);

    final chunks = await db.select(db.chunks).get();
    expect(chunks.first.searchText, 'La fotosíntesis sube.');
    expect(chunks.last.searchText, isNull);
    expect(chunks.map((c) => c.searchTextRule).toSet(), {kChunkSearchTextRule});
    // La transcripción se lee tal cual: su dirección sigue encontrándose.
    expect(await matches('wikipedia'), 1);
    expect(await matches('fotosintesis'), 1);
    await db.customStatement(
      "INSERT INTO chunk_search (chunk_search) VALUES ('integrity-check')",
    );
  });

  test('lo calculado con una regla vieja se rehace; lo de hoy, no', () async {
    await addOld('web', link, rule: kChunkSearchTextRule - 1);
    await addOld(
      'web',
      'Otra [hoja](https://x.org).',
      rule: kChunkSearchTextRule,
    );

    expect(await ChunkSearchTextBackfill(database: db).run(), 1);
    final chunks = await db.select(db.chunks).get();
    expect(chunks.first.searchText, 'La fotosíntesis sube.');
    expect(chunks.last.searchText, isNull);
  });

  test(
    'por tandas: cortado, lo hecho queda hecho y la próxima vez sigue',
    () async {
      for (var i = 0; i < 5; i++) {
        await addOld('web', link);
      }
      final backfill = ChunkSearchTextBackfill(database: db, chunksPerBatch: 2);

      final first = backfill.run();
      backfill.stop();
      expect(await first, 2);
      final pending = await (db.select(
        db.chunks,
      )..where((c) => c.searchTextRule.isNull())).get();
      expect(pending, hasLength(3));

      expect(await ChunkSearchTextBackfill(database: db).run(), 3);
      expect(await matches('wikipedia'), 0);
    },
  );

  test(
    'lo que dejó de ser Markdown pierde lo que se le había calculado',
    () async {
      await db
          .into(db.chunks)
          .insert(
            ChunksCompanion.insert(
              id: 'viejo',
              itemId: 'video',
              seq: 99,
              content: 'Ver https://es.wikipedia.org/wiki/F',
              charStart: 0,
              charEnd: 10,
              searchText: const Value('Ver.'),
              searchTextRule: const Value(kChunkSearchTextRule - 1),
            ),
          );
      expect(await matches('wikipedia'), 0);

      expect(await ChunkSearchTextBackfill(database: db).run(), 1);

      final chunk = await db.select(db.chunks).getSingle();
      expect(chunk.searchText, isNull);
      expect(chunk.searchTextRule, kChunkSearchTextRule);
      expect(await matches('wikipedia'), 1);
    },
  );

  test('lo calculado con una regla vieja que hoy se lee igual que el texto '
      'vuelve a nulo', () async {
    await db
        .into(db.chunks)
        .insert(
          ChunksCompanion.insert(
            id: 'llano',
            itemId: 'web',
            seq: 98,
            content: 'Texto llano.',
            charStart: 0,
            charEnd: 12,
            searchText: const Value('Otra cosa.'),
            searchTextRule: const Value(kChunkSearchTextRule - 1),
          ),
        );

    await ChunkSearchTextBackfill(database: db).run();

    expect((await db.select(db.chunks).getSingle()).searchText, isNull);
    expect(await matches('llano'), 1);
  });

  test('dos pedidos a la vez comparten la misma pasada', () async {
    await addOld('web', link);
    final backfill = ChunkSearchTextBackfill(database: db);

    final results = await Future.wait([backfill.run(), backfill.run()]);

    expect(results, [1, 1]);
  });
}
