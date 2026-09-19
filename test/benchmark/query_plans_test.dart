import 'package:drift/drift.dart' show Variable;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/database/app_database.dart';
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

  /// Ningún recorrido completo de [table]: cada acceso es una búsqueda por un
  /// índice.
  Future<void> expectSearched(
    String table,
    String sql, [
    List<Object> args = const [],
  ]) async {
    final plan = await planOf(sql, args);
    expect(
      plan,
      isNot(contains('SCAN $table')),
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
    await expectSearched('items', 'SELECT * FROM items WHERE space_id = ?', id);
  });

  test('la búsqueda de texto entra por el índice de texto completo', () async {
    final plan = await planOf(
      'SELECT item_id FROM item_search WHERE item_search MATCH ? '
      'ORDER BY rank',
      [vault.mediumTerm],
    );
    expect(plan, contains('VIRTUAL TABLE INDEX'), reason: plan);
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
    for (final table in ['items', 'sources']) {
      expect(plan, isNot(contains('SCAN $table')), reason: plan);
    }
  });
}
