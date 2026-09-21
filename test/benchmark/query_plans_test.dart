import 'package:drift/drift.dart' show Variable;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/database/search_index.dart';
import 'package:sinapsis/features/library/data/repositories/library_query_sql.dart';
import 'package:sinapsis/features/library/domain/entities/library_query.dart';

import 'synthetic_vault.dart';

/// Las consultas que crecen con la bóveda tienen que resolverse por un índice.
///
/// Es la mitad del benchmark que corre SIEMPRE, con un cronómetro que no
/// miente porque no hay ninguno: no mide cuánto tarda, mira el plan que
/// SQLite elige. Un recorrido completo de una tabla de 300.000 filas no se
/// nota con 120 elementos y arruina la pantalla con 10.000, y este test lo
/// atrapa con cualquiera de los dos tamaños.
void main() {
  late AppDatabase db;
  late SyntheticVault vault;

  setUpAll(() async {
    db = AppDatabase(NativeDatabase.memory());
    vault = await buildSyntheticVault(
      db,
      profile: const VaultProfile(items: 200),
    );
  });

  tearDownAll(() => db.close());

  Future<String> planOf(String sql, [List<Object> args = const []]) async {
    final rows = await db
        .customSelect(
          'EXPLAIN QUERY PLAN $sql',
          variables: [for (final a in args) Variable(a)],
        )
        .get();
    return rows.map((r) => r.read<String>('detail')).join('\n');
  }

  /// Si el plan recorre TODA la tabla [table]. Se compara el nombre entero: con
  /// `contains('SCAN item')` un recorrido de `item_search` pasaría por uno de
  /// `item`.
  bool scans(String plan, String table) =>
      RegExp('SCAN $table(?![A-Za-z0-9_])').hasMatch(plan);

  /// Ningún recorrido completo de [table]: cada acceso es una búsqueda por un
  /// índice.
  Future<void> expectSearched(
    String table,
    String sql, [
    List<Object> args = const [],
  ]) async {
    final plan = await planOf(sql, args);
    expect(
      scans(plan, table),
      isFalse,
      reason: 'recorre toda la tabla $table:\n$plan',
    );
    expect(plan, contains('SEARCH $table'), reason: plan);
  }

  final id = ['x'];

  test('los vínculos de un elemento, en los dos sentidos', () async {
    await expectSearched(
      'relations',
      'SELECT * FROM relations WHERE from_item_id = ?',
      id,
    );
    await expectSearched(
      'relations',
      'SELECT * FROM relations WHERE to_item_id = ?',
      id,
    );
  });

  test('las formas y los chunks de un elemento', () async {
    await expectSearched(
      'renditions',
      'SELECT * FROM renditions WHERE item_id = ?',
      id,
    );
    await expectSearched(
      'chunks',
      'SELECT * FROM chunks WHERE item_id = ? ORDER BY seq',
      id,
    );
  });

  test('los resaltados de una forma y las tarjetas que vencen', () async {
    await expectSearched(
      'highlights',
      'SELECT * FROM highlights WHERE rendition_id = ?',
      id,
    );
    await expectSearched(
      'flashcards',
      'SELECT * FROM flashcards WHERE due_at <= ?',
      [0],
    );
  });

  test('las propiedades de un elemento y los elementos de un valor', () async {
    await expectSearched(
      'item_property_values',
      'SELECT * FROM item_property_values WHERE item_id = ?',
      id,
    );
    await expectSearched(
      'item_property_values',
      'SELECT * FROM item_property_values WHERE property_value_id = ?',
      id,
    );
  });

  test('los enlaces de una nota y los que apuntan a un elemento', () async {
    await expectSearched(
      'inline_link',
      'SELECT * FROM inline_link WHERE from_item_id = ?',
      id,
    );
    await expectSearched(
      'inline_link',
      'SELECT * FROM inline_link WHERE to_item_id = ?',
      id,
    );
  });

  test('los elementos por estado y tipo, y por espacio', () async {
    await expectSearched(
      'item',
      "SELECT * FROM item WHERE state = 'captured' AND kind = 'source'",
    );
    await expectSearched('item', 'SELECT * FROM item WHERE space_id = ?', id);
  });

  test('la búsqueda de texto entra por el índice de texto completo', () async {
    final plan = await planOf(
      'SELECT item_id FROM item_search WHERE item_search MATCH ? '
      'ORDER BY rank',
      [vault.mediumTerm],
    );
    expect(plan, contains('VIRTUAL TABLE INDEX'), reason: plan);
  });

  test('la búsqueda por chunks entra por el índice y vuelve al chunk por su '
      'clave entera', () async {
    final plan = await planOf(
      'SELECT chunks.item_id FROM chunk_search '
      'JOIN chunks ON chunks.row_key = chunk_search.rowid '
      'WHERE chunk_search MATCH ? ORDER BY chunk_search.rank LIMIT 50',
      [vault.mediumTerm],
    );
    expect(plan, contains('VIRTUAL TABLE INDEX'), reason: plan);
    // Un salto por la clave primaria, no un recorrido de la tabla.
    expect(plan, isNot(contains('SCAN chunks')), reason: plan);
    expect(
      plan,
      contains('SEARCH chunks USING INTEGER PRIMARY KEY'),
      reason: plan,
    );
  });

  test('los chunks de un elemento, en orden, y su vocabulario', () async {
    await expectSearched(
      'chunks',
      'SELECT * FROM chunks WHERE item_id = ? AND start_ms IS NOT NULL',
      ['x'],
    );
  });

  test('la búsqueda de la biblioteca resuelve el orden y la página en la '
      'base, sin traer todas las coincidencias', () async {
    final ids = LibraryQuerySql(
      LibraryQuery(
        searchText: vault.mediumTerm,
        sortBy: LibrarySort.relevance,
        limit: 50,
      ),
    ).ids();
    expect(ids.sql, contains('LIMIT ? OFFSET ?'));

    final rows = await db
        .customSelect('EXPLAIN QUERY PLAN ${ids.sql}', variables: ids.variables)
        .get();
    final plan = rows.map((r) => r.read<String>('detail')).join('\n');
    expect(plan, contains('VIRTUAL TABLE INDEX'), reason: plan);
    for (final table in ['item', 'source']) {
      expect(scans(plan, table), isFalse, reason: plan);
    }
  });

  test(
    'la búsqueda con citas pide los mejores chunks al índice SOLO y recién '
    'después los une con chunks: no una búsqueda por cada coincidencia',
    () async {
      final sql = LibraryQuerySql(
        LibraryQuery(
          searchText: vault.mediumTerm,
          sortBy: LibrarySort.relevance,
          limit: 50,
        ),
        plan: TextSearchPlan(match: buildSearchQuery(vault.mediumTerm)),
      );
      final merged = sql.mergedIds(everyWord: false)!;

      // El corte por relevancia es parte de la consulta al índice, no de la
      // unión: la unión va sobre un `LIMIT`, sobre el resultado del corte.
      expect(
        merged.sql,
        contains('ORDER BY chunk_search.rank LIMIT ?) top JOIN chunks'),
      );

      final rows = await db
          .customSelect(
            'EXPLAIN QUERY PLAN ${merged.sql}',
            variables: merged.variables,
          )
          .get();
      final plan = rows.map((r) => r.read<String>('detail')).join('\n');
      expect(plan, contains('VIRTUAL TABLE INDEX'), reason: plan);
      // `ti` y `tc` son `item` y `chunks` dentro de la exclusión de la
      // papelera: EXPLAIN muestra el alias, no la tabla.
      for (final table in ['item', 'source', 'chunks', 'ti', 'tc']) {
        expect(scans(plan, table), isFalse, reason: plan);
      }
      // Y lo borrado se saca ANTES del corte, por el índice de la papelera.
      expect(plan, contains('idx_item_trashed'), reason: plan);
    },
  );

  test('la ventana de una palabra en casi todo no le encarga el orden a FTS5: '
      'con un prefijo, eso es leer todas las coincidencias antes de la '
      'primera', () async {
    final match = buildSearchQuery(vault.commonTerm);

    // FTS5 dice en el plan qué le piden: `INDEX <número>:<letras>`. Los bits
    // 0x40 y 0x80 del número son «ordenar por rowid» y «al revés».
    const rowidDescending = 0x40 | 0x80;
    Future<int> flagsOf(String sql, List<Object> args) async {
      final plan = await planOf(sql, args);
      final found = RegExp(
        r'SCAN chunk_search VIRTUAL TABLE INDEX (\d+):',
      ).firstMatch(plan);
      expect(found, isNotNull, reason: plan);
      return int.parse(found!.group(1)!);
    }

    // El control: pedirle el orden al índice SÍ queda marcado. Si SQLite
    // cambia los números, avisa este y no el de abajo, que pasaría sin decir
    // nada.
    final asked = await flagsOf(
      'SELECT rowid FROM chunk_search WHERE chunk_search MATCH ? '
      'ORDER BY rowid DESC LIMIT ?',
      [match, kSearchWindowChunks],
    );
    expect(
      asked & rowidDescending,
      rowidDescending,
      reason: 'los números del plan de FTS5 ya no son los que este test supone',
    );

    final window = await flagsOf(kSearchWindowSql, [
      match,
      0,
      kSearchWindowChunks,
    ]);
    expect(
      window & rowidDescending,
      0,
      reason: 'la ventana le pide el orden a FTS5: ver kSearchWindowSql',
    );

    // Y la consulta de la página usa esa ventana tal cual.
    final ids = LibraryQuerySql(
      LibraryQuery(
        searchText: vault.commonTerm,
        sortBy: LibrarySort.relevance,
        limit: 50,
      ),
      plan: TextSearchPlan(match: match, windowed: true),
    ).ids();
    expect(ids.sql, contains(kSearchWindowSql));
  });

  test('filtrar por un valor con su rama recorre el árbol por su índice y no '
      'la tabla de valores (F13)', () async {
    final ids = LibraryQuerySql(
      const LibraryQuery(propertyValueIds: {'un-valor'}, limit: 50),
    ).ids();

    final plan = await planOf(ids.sql, [
      for (final v in ids.variables) v.value!,
    ]);

    // El paso recursivo busca a los hijos por `parent_id`, no recorre todo.
    expect(plan, contains('idx_property_values_parent'), reason: plan);
    expect(scans(plan, 'property_values'), isFalse, reason: plan);
    expect(scans(plan, 'child'), isFalse, reason: plan);
    // Y lo que se une después sigue siendo una búsqueda por el índice de la
    // asignación, no un recorrido de `item_property_values`.
    expect(scans(plan, 'item_property_values'), isFalse, reason: plan);
  });

  test('lo que está en la papelera se lee por su índice parcial; lo vivo, '
      'por la clave', () async {
    final trash = await planOf(
      'SELECT ti.id FROM item ti WHERE ti.deleted_at IS NOT NULL',
    );
    expect(trash, contains('SEARCH ti USING INDEX idx_item_trashed'));
    expect(scans(trash, 'ti'), isFalse, reason: trash);

    // Pedir elementos por id con el filtro de lo vivo sigue siendo una
    // búsqueda por la clave: un índice común sobre `deleted_at` habría hecho
    // que SQLite recorriera el índice entero para cada consulta.
    final ids = LibraryQuerySql(const LibraryQuery(ids: {'a', 'b', 'c'})).ids();
    final live = await planOf(ids.sql, [
      for (final v in ids.variables) v.value!,
    ]);
    expect(live, contains('sqlite_autoindex_item_1'), reason: live);
    expect(
      live,
      isNot(contains('SEARCH item USING INDEX idx_item')),
      reason: live,
    );
  });
}
