import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift_dev/api/migrations_native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/database/search_index.dart';
import 'package:sinapsis/core/domain/entities/rendition_kind.dart';

import '../../generated_migrations/schema.dart';
import '../../generated_migrations/schema_v16.dart' as v16;

/// El índice de texto de los elementos (`item_search`) al migrar desde v16
/// (F10): deja de guardar el texto de las fuentes, que pasa a `chunk_search`, y
/// queda con título, subtítulo y el texto de las notas, calculado sobre `item`.
///
/// Se siembra desde v16 —el snapshot más reciente anterior a v18— y se migra
/// hasta la versión actual: el paso que rehace el índice es el de v18, que
/// absorbió al de v17, y completa además el espejo `item` que esta bóveda
/// sembrada a mano no trae.
void main() {
  final verifier = SchemaVerifier(GeneratedHelper());
  const seconds = 1789000000;

  Future<void> seedItem(
    v16.DatabaseAtV16 db,
    String id,
    String title, {
    required String kind,
    required String renditionKind,
    required String content,
  }) async {
    await db
        .into(db.sources)
        .insert(
          v16.SourcesCompanion.insert(
            id: 'src-$id',
            kind: kind,
            capturedAt: seconds,
          ),
        );
    await db
        .into(db.items)
        .insert(
          v16.ItemsCompanion.insert(
            id: id,
            title: title,
            sourceId: 'src-$id',
            processingState: 'ready',
            createdAt: seconds,
            updatedAt: seconds,
          ),
        );
    await db
        .into(db.renditions)
        .insert(
          v16.RenditionsCompanion.insert(
            id: 'r-$id',
            itemId: id,
            kind: renditionKind,
            content: Value(content),
            isPrimary: 1,
            createdAt: seconds,
          ),
        );
  }

  /// Una bóveda como la deja v16: el índice de elementos con el cuerpo de TODAS
  /// las formas, y sus triggers de entonces.
  Future<void> seedV16Vault(v16.DatabaseAtV16 db) async {
    await db.customStatement(createSearchTable);
    await db.customStatement('''
CREATE TRIGGER renditions_search_ai AFTER INSERT ON renditions BEGIN
  UPDATE item_search SET body = (SELECT COALESCE(GROUP_CONCAT(content, char(10)), '')
     FROM renditions WHERE item_id = NEW.item_id AND content IS NOT NULL)
   WHERE item_id = NEW.item_id;
END''');

    await seedItem(
      db,
      'art',
      'Un artículo',
      kind: 'webPage',
      renditionKind: 'markdown',
      content: 'Hablamos del paradigma científico.',
    );
    await seedItem(
      db,
      'nota',
      'Una nota',
      kind: 'manualNote',
      renditionKind: 'blocks',
      content: '[{"type":"paragraph","text":"Pienso en la epistemología."}]',
    );
    // El índice de v16: cada fila con el cuerpo de todas sus formas.
    await db.customStatement(
      'INSERT INTO item_search (item_id, title, subtitle, body) VALUES '
      "('art', 'Un artículo', '', 'Hablamos del paradigma científico.'), "
      "('nota', 'Una nota', '', "
      '\'[{"type":"paragraph","text":"Pienso en la epistemología."}]\')',
    );
  }

  Future<AppDatabase> migrateFrom16({
    Future<void> Function(v16.DatabaseAtV16 oldDb)? seed,
  }) async {
    final schema = await verifier.schemaAt(16);
    final oldDb = v16.DatabaseAtV16(schema.newConnection());
    if (seed != null) await seed(oldDb);
    await oldDb.close();

    final db = AppDatabase(schema.newConnection());
    addTearDown(db.close);
    // `migrateAndValidate` afirma que la versión de destino es la que se le
    // pasa: con solo abrir la base, drift la migra de la 16 a la actual.
    await db.customSelect('SELECT 1').get();
    return db;
  }

  Future<List<String>> searchItems(AppDatabase db, String term) async {
    final rows = await db
        .customSelect(
          'SELECT item_id FROM item_search WHERE item_search MATCH ?',
          variables: [Variable.withString(buildSearchQuery(term))],
        )
        .get();
    return [for (final r in rows) r.read<String>('item_id')]..sort();
  }

  test('el índice queda con una entrada por elemento', () async {
    final db = await migrateFrom16(seed: seedV16Vault);

    final row = await db
        .customSelect('SELECT COUNT(*) AS n FROM item_search')
        .getSingle();
    expect(row.read<int>('n'), 2);
  });

  test('el texto de una fuente ya no está en este índice, pero su título sí, '
      'y el texto de una nota sigue estando', () async {
    final db = await migrateFrom16(seed: seedV16Vault);

    expect(await searchItems(db, 'paradigma'), isEmpty);
    expect(await searchItems(db, 'artículo'), ['art']);
    expect(await searchItems(db, 'epistemología'), ['nota']);
  });

  test(
    'los triggers de las formas ya no reescriben la fila de una fuente, y sí '
    'la de una nota, sea cual sea su tipo de forma',
    () async {
      final db = await migrateFrom16(seed: seedV16Vault);

      await db
          .into(db.renditions)
          .insert(
            RenditionsCompanion.insert(
              id: 'r-otra',
              itemId: 'art',
              kind: RenditionKind.markdown,
              isPrimary: false,
              createdAt: DateTime(2026, 9, 19),
              content: const Value('Una segunda forma sobre el paradigma.'),
            ),
          );

      expect(await searchItems(db, 'paradigma'), isEmpty);

      // Una nota escrita como texto y no con bloques también se indexa.
      await db
          .into(db.renditions)
          .insert(
            RenditionsCompanion.insert(
              id: 'r-texto',
              itemId: 'nota',
              kind: RenditionKind.plainText,
              isPrimary: false,
              createdAt: DateTime(2026, 9, 19),
              content: const Value('Y además pienso en Kuhn.'),
            ),
          );
      expect(await searchItems(db, 'kuhn'), ['nota']);
    },
  );

  test(
    'reemplaza el trigger de antes por el de ahora, que mira item',
    () async {
      final db = await migrateFrom16(seed: seedV16Vault);

      final trigger = await db
          .customSelect(
            "SELECT sql FROM sqlite_master WHERE name = 'renditions_search_ai'",
          )
          .getSingle();
      expect(trigger.read<String>('sql'), contains("ni.kind = 'note'"));
      expect(trigger.read<String>('sql'), isNot(contains('sources')));
    },
  );

  test('los triggers de título y subtítulo cuelgan de item; los de items ya no '
      'existen', () async {
    final db = await migrateFrom16(seed: seedV16Vault);

    final rows = await db
        .customSelect(
          "SELECT name, tbl_name FROM sqlite_master WHERE type = 'trigger' "
          "AND name LIKE '%search%'",
        )
        .get();
    final byName = {
      for (final r in rows) r.read<String>('name'): r.read<String>('tbl_name'),
    };

    expect(byName['entry_search_ai'], 'item');
    expect(byName['entry_search_au'], 'item');
    expect(byName['entry_search_ad'], 'item');
    expect(byName.keys.where((n) => n.startsWith('items_search')), isEmpty);
  });

  test('una base sin índice de antes también migra', () async {
    final db = await migrateFrom16();

    final row = await db
        .customSelect('SELECT COUNT(*) AS n FROM item_search')
        .getSingle();
    expect(row.read<int>('n'), 0);
  });
}
