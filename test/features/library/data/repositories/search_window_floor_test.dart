import 'package:drift/drift.dart' show Variable, driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:sinapsis/core/database/active_entries.dart';
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/database/search_index.dart';
import 'package:sinapsis/core/telemetry/telemetry_service.dart';
import 'package:sinapsis/features/library/data/repositories/library_query_sql.dart';
import 'package:sinapsis/features/library/data/repositories/library_repository_impl.dart';
import 'package:sinapsis/features/library/data/repositories/search_window_floor.dart';
import 'package:sinapsis/features/library/domain/entities/library_query.dart';

import '../../../../benchmark/synthetic_vault.dart';
import '../../../../support/in_memory_file_store.dart';

class MockTelemetryService extends Mock implements TelemetryService {}

/// La ventana de la búsqueda con una palabra en casi todo (F12): los chunks
/// más recientes que coinciden, pedidos al índice desde una cota y ordenados
/// por SQLite, no por FTS5.
///
/// Lo que se cuida es que ESO NO CAMBIE EL RESULTADO: la ventana con cota tiene
/// que ser, chunk por chunk, la que daba pedirle al índice `ORDER BY rowid
/// DESC LIMIT n` —que en un teléfono costaba 300 ms por cada consulta y en un
/// escritorio, 8—.
///
/// Usa una bóveda sintética de 400 elementos, unos 12.000 chunks: más que el
/// primer tramo que se prueba, para que la cota tenga dónde crecer.
void main() {
  late AppDatabase db;
  late SyntheticVault vault;
  late int first;
  late int last;

  /// El primer tramo que prueba `searchWindowFloor`: cuatro ventanas.
  const firstSpan = kSearchWindowChunks * 4;

  Future<int> intOf(
    String sql, [
    List<Variable<Object>> variables = const [],
  ]) async =>
      (await db.customSelect(sql, variables: variables).getSingle())
              .data
              .values
              .first!
          as int;

  setUpAll(() async {
    db = AppDatabase(NativeDatabase.memory());
    vault = await buildSyntheticVault(
      db,
      profile: const VaultProfile(items: 400),
    );
    first = await intOf('SELECT MIN(row_key) FROM chunks');
    last = await intOf('SELECT MAX(row_key) FROM chunks');
    // Sin esto los tramos de abajo no dicen nada.
    expect(last - first, greaterThan(firstSpan * 2));
  });

  tearDownAll(() => db.close());

  /// La ventana como se pedía antes: al índice, ordenada por él.
  Future<List<int>> reference(String match) async {
    final rows = await db
        .customSelect(
          'SELECT chunk_search.rowid AS rid FROM chunk_search '
          'WHERE chunk_search MATCH ? AND $kChunkOutsideTrashSql '
          'ORDER BY chunk_search.rowid DESC LIMIT ?',
          variables: [
            Variable.withString(match),
            Variable.withInt(kSearchWindowChunks),
          ],
        )
        .get();
    return [for (final row in rows) row.read<int>('rid')];
  }

  /// La ventana como se pide ahora: desde [floor], ordenada por SQLite.
  Future<List<int>> windowFrom(String match, int floor) async {
    final rows = await db
        .customSelect(
          kSearchWindowSql,
          variables: [
            Variable.withString(match),
            Variable.withInt(floor),
            Variable.withInt(kSearchWindowChunks),
          ],
        )
        .get();
    return [for (final row in rows) row.read<int>('rid')];
  }

  Future<int> liveMatchesAbove(String match, int floor) => intOf(
    'SELECT COUNT(*) FROM chunk_search '
    'WHERE chunk_search MATCH ? AND chunk_search.rowid > ? '
    'AND $kChunkOutsideTrashSql',
    [Variable.withString(match), Variable.withInt(floor)],
  );

  test('con una palabra en casi todo, la cota es un tramo corto del final y '
      'deja la ventana entera', () async {
    final match = buildSearchQuery(vault.commonTerm);

    final floor = await searchWindowFloor(db, match);

    expect(floor, greaterThan(first));
    expect(last - floor, lessThanOrEqualTo(firstSpan));
    expect(
      await liveMatchesAbove(match, floor),
      greaterThanOrEqualTo(kSearchWindowChunks),
    );
  });

  test('la ventana desde la cota es la misma que pedirle al índice que '
      'ordene: los mismos chunks, del más nuevo al más viejo', () async {
    final match = buildSearchQuery(vault.commonTerm);
    final floor = await searchWindowFloor(db, match);

    final window = await windowFrom(match, floor);

    expect(window, hasLength(kSearchWindowChunks));
    expect(window, await reference(match));
    final newestFirst = [...window]..sort((a, b) => b.compareTo(a));
    expect(window, orderedEquals(newestFirst));
  });

  test('si el primer tramo no junta una ventana, prueba con uno más largo y '
      'la ventana sigue siendo la misma', () async {
    // Una palabra con coincidencias de sobra en toda la bóveda pero pocas en
    // el último tramo: entre una de cada cuatro filas y una de cada dieciséis.
    String? sparse;
    final candidates = await db
        .customSelect(
          'SELECT term FROM chunk_vocab WHERE doc BETWEEN ? AND ? '
          'ORDER BY doc DESC',
          variables: [
            Variable.withInt(last ~/ 12),
            Variable.withInt(last ~/ 5),
          ],
        )
        .get();
    for (final row in candidates) {
      final term = row.read<String>('term');
      final match = buildSearchQuery(term);
      if (await liveMatchesAbove(match, last - firstSpan) <
              kSearchWindowChunks &&
          await liveMatchesAbove(match, first - 1) >= kSearchWindowChunks) {
        sparse = term;
        break;
      }
    }
    expect(
      sparse,
      isNotNull,
      reason: 'ninguna palabra de la bóveda de prueba sirve para este caso',
    );
    final match = buildSearchQuery(sparse!);

    final floor = await searchWindowFloor(db, match);

    // Más atrás que el primer tramo, y con la ventana llena.
    expect(floor, lessThan(last - firstSpan));
    expect(
      await liveMatchesAbove(match, floor),
      greaterThanOrEqualTo(kSearchWindowChunks),
    );
    expect(await windowFrom(match, floor), await reference(match));
  });

  test('con menos coincidencias que una ventana, la cota deja pasar toda la '
      'bóveda y no se pierde ninguna', () async {
    final match = buildSearchQuery(vault.rareTerm);
    expect(
      await liveMatchesAbove(match, first - 1),
      lessThan(kSearchWindowChunks),
      reason: 'la palabra rara de la bóveda de prueba ya no es rara',
    );

    final floor = await searchWindowFloor(db, match);

    expect(floor, first - 1);
    final window = await windowFrom(match, floor);
    expect(window, isNotEmpty);
    expect(window, await reference(match));
  });

  test('sin chunks no hay cota que pedir', () async {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    addTearDown(
      () => driftRuntimeOptions.dontWarnAboutMultipleDatabases = false,
    );
    final empty = AppDatabase(NativeDatabase.memory());
    addTearDown(empty.close);

    expect(await searchWindowFloor(empty, '"algo"*'), 0);
  });

  test(
    'la búsqueda entera —los resultados y sus citas— sale de la ventana',
    () async {
      final library = LibraryRepositoryImpl(
        database: db,
        telemetry: MockTelemetryService(),
        files: InMemoryFileStore(),
        // Con el tope en 1, toda palabra que esté en más de un chunk pide
        // ventana.
        rankedHitsCap: 1,
      );
      final match = buildSearchQuery(vault.commonTerm);
      final windowKeys = await reference(match);
      final windowChunks = {
        for (final row
            in await db
                .customSelect(
                  'SELECT id, item_id FROM chunks WHERE row_key IN '
                  '(${List.filled(windowKeys.length, '?').join(', ')})',
                  variables: [
                    for (final key in windowKeys) Variable.withInt(key),
                  ],
                )
                .get())
          row.read<String>('id'): row.read<String>('item_id'),
      };
      final titled = {
        for (final row
            in await db
                .customSelect(
                  'SELECT item_id FROM item_search WHERE item_search MATCH ?',
                  variables: [Variable.withString(match)],
                )
                .get())
          row.read<String>('item_id'),
      };

      // Sin límite: todos los resultados, no solo una página.
      final hits = (await library.search(
        LibraryQuery(
          searchText: vault.commonTerm,
          sortBy: LibrarySort.relevance,
        ),
      )).getRight().toNullable()!;

      // Entran los elementos con la palabra en el título o las notas y los de
      // los chunks de la ventana: ni uno más ni uno menos.
      expect(
        {for (final hit in hits) hit.item.id},
        {...titled, ...windowChunks.values},
      );
      final cited = hits.where((hit) => hit.citation != null).toList();
      expect(cited, isNotEmpty);
      for (final hit in cited) {
        // La cita señala un chunk de la ventana, y es de ese elemento.
        expect(windowChunks[hit.citation!.chunkId], hit.item.id);
      }
    },
  );

  // Va al final: da de baja elementos de la bóveda compartida.
  test('lo que está en la papelera no llena la ventana: si el último tramo '
      'está borrado, la cota retrocede hasta encontrar lo vivo', () async {
    final match = buildSearchQuery(vault.commonTerm);
    await db.customStatement(
      'UPDATE item SET deleted_at = 1 WHERE id IN '
      '(SELECT item_id FROM chunks WHERE row_key > ${last - firstSpan})',
    );

    final floor = await searchWindowFloor(db, match);

    expect(floor, lessThan(last - firstSpan));
    final window = await windowFrom(match, floor);
    expect(window, hasLength(kSearchWindowChunks));
    expect(window, await reference(match));
  });
}
