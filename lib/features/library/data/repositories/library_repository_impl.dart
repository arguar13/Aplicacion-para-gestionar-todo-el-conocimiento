import 'dart:async';

import 'package:drift/drift.dart';
import 'package:fpdart/fpdart.dart';
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/database/inline_link_sync.dart';
import 'package:sinapsis/core/database/knowledge_mirror_mapping.dart';
import 'package:sinapsis/core/database/knowledge_row_mapping.dart';
import 'package:sinapsis/core/database/knowledge_source_chunking.dart';
import 'package:sinapsis/core/database/search_index.dart';
import 'package:sinapsis/core/database/tema_category.dart';
import 'package:sinapsis/core/database/watching_query.dart';
import 'package:sinapsis/core/domain/entities/content_block.dart';
import 'package:sinapsis/core/domain/entities/item_kind.dart';
import 'package:sinapsis/core/domain/entities/item_property.dart';
import 'package:sinapsis/core/domain/entities/item_property_origin.dart';
import 'package:sinapsis/core/domain/entities/knowledge_item.dart';
import 'package:sinapsis/core/domain/entities/note_kind.dart';
import 'package:sinapsis/core/domain/entities/note_maturity.dart';
import 'package:sinapsis/core/domain/entities/rendition.dart';
import 'package:sinapsis/core/domain/entities/rendition_kind.dart';
import 'package:sinapsis/core/domain/entities/tag.dart';
import 'package:sinapsis/core/error/failures.dart';
import 'package:sinapsis/core/storage/file_store.dart';
import 'package:sinapsis/core/telemetry/telemetry_service.dart';
import 'package:sinapsis/core/util/clock.dart';
import 'package:sinapsis/core/util/id_generator.dart';
import 'package:sinapsis/features/duplicates/domain/services/duplicate_suggestion_generator.dart';
import 'package:sinapsis/features/library/data/repositories/chunk_hit_estimate.dart';
import 'package:sinapsis/features/library/data/repositories/library_query_sql.dart';
import 'package:sinapsis/features/library/domain/entities/library_query.dart';
import 'package:sinapsis/features/library/domain/entities/search_citation.dart';
import 'package:sinapsis/features/library/domain/entities/search_hit.dart';
import 'package:sinapsis/features/library/domain/repositories/library_repository.dart';
import 'package:sinapsis/features/library/domain/services/search_snippet.dart';

class LibraryRepositoryImpl implements LibraryRepository {
  const LibraryRepositoryImpl({
    required AppDatabase database,
    required TelemetryService telemetry,
    required FileStore files,

    /// Opcional —`null` por defecto no hace nada— para que las muchas
    /// pruebas unitarias que construyen este repositorio a mano y no les
    /// importa nada de F7 no tengan que enterarse de esta dependencia.
    /// La instancia real que llega acá desde `libraryRepositoryProvider`
    /// tiene su propia `SuggestionRepositoryImpl` dedicada —ver el doc
    /// comment de `duplicateSuggestionGeneratorProvider`— para no
    /// depender, ni siquiera transitivamente, de este mismo repositorio:
    /// eso sí sería un ciclo real de providers.
    DuplicateSuggestionGenerator? duplicateSuggestionGenerator,

    /// Con qué se numeran los enlaces en línea y las relaciones que nacen al
    /// guardar una nota. Con valores por defecto por el mismo motivo que el
    /// generador de arriba: las pruebas que no miran esto no tienen por qué
    /// enterarse.
    IdGenerator ids = const UuidV7Generator(),
    Clock clock = DateTime.now,

    /// Cuántos chunks puede tener una palabra para ordenar por relevancia:
    /// ver [kRankedHitsCap]. Las pruebas lo bajan para ejercitar el otro
    /// camino sin armar decenas de miles de chunks.
    int rankedHitsCap = kRankedHitsCap,
  }) : _rankedHitsCap = rankedHitsCap,
       _db = database,
       _telemetry = telemetry,
       _files = files,
       _duplicateSuggestionGenerator = duplicateSuggestionGenerator,
       _ids = ids,
       _clock = clock;

  final AppDatabase _db;
  final TelemetryService _telemetry;
  final FileStore _files;
  final DuplicateSuggestionGenerator? _duplicateSuggestionGenerator;
  final IdGenerator _ids;
  final Clock _clock;
  final int _rankedHitsCap;

  @override
  Future<Either<Failure, KnowledgeItem>> save(KnowledgeItem item) async {
    try {
      await _db.transaction(() async {
        // Primero el elemento: las formas, los vínculos y todo lo demás
        // cuelgan de `item`, y los enlaces en línea resuelven sus títulos
        // contra él —una nota que se guarda por primera vez, o que cambia de
        // título, tiene que estar ya ahí para reconocerse a sí misma—.
        await _upsertEntry(item);
        await _syncRenditions(item);
        await _syncInlineLinks(item);
        await resolveBrokenInlineLinks(
          _db,
          itemId: item.id,
          title: item.title,
          ids: _ids,
          clock: _clock,
        );
        final temaId = await temaDefinitionId(_db);
        await _syncTags(item, temaId);
        await _syncProperties(item, temaId);
        await _syncChunks(item);
      });
      _generateDuplicateSuggestionForNote(item);
      return right(item);
      // Ver `_unexpected`: un TypeError es Error, no Exception.
      // ignore: avoid_catches_without_on_clauses
    } catch (e, stackTrace) {
      return left(_unexpected(e, stackTrace, 'LibraryRepositoryImpl.save'));
    }
  }

  /// Deja los chunks de la fuente al día con el texto que se acaba de guardar.
  ///
  /// Van en la misma transacción que el resto: o queda la fuente con su texto
  /// y sus chunks, o no queda nada. Antes solo los escribían el motor de
  /// relaciones y las migraciones, así que una fuente capturada hoy no tenía
  /// chunks hasta que algo los pedía —y sin chunks no hay búsqueda por
  /// chunks—.
  ///
  /// Si el texto no cambió desde el último guardado no hace nada: comparar el
  /// hash es barato, fragmentar de nuevo no. Y si el fragmentador falla, se
  /// informa en `MigrationIssues` y el guardado sigue: reconstruir un índice
  /// no puede impedir que se guarde lo capturado.
  ///
  /// Las notas no se fragmentan: son texto del usuario, mutable, y el chunker
  /// las corta en trozos crudos del JSON de sus bloques —no en texto—. Su
  /// texto lo indexa `item_search`, y no tienen minuto ni página que citar.
  Future<void> _syncChunks(KnowledgeItem item) async {
    if (itemKindFor(item.source.kind) == ItemKind.note) return;
    await chunkAndPersistSource(
      _db,
      itemId: item.id,
      ids: _ids,
      reportedBy: 'f10_save',
      assignPages: true,
    );
  }

  /// Deja registrados los `[[ ]]` de las notas de bloques del elemento.
  ///
  /// Un elemento sin formas de bloques no tiene enlaces: si los tenía —la
  /// nota dejó de serlo—, se borran. Si los bloques de alguna forma no se
  /// pueden leer, los enlaces registrados se dejan como estaban y se
  /// informa: reconstruir un índice no puede impedir que se guarde el
  /// contenido del usuario, pero tampoco borrarlo a ciegas.
  Future<void> _syncInlineLinks(KnowledgeItem item) async {
    final blocks = <ContentBlock>[];
    for (final rendition in item.renditions.whereType<TextRendition>()) {
      if (rendition.kind != RenditionKind.blocks) continue;
      final decoded = tryDecodeContentBlocks(rendition.content);
      if (decoded == null) {
        _telemetry.recordError(
          FormatException(
            'Los bloques de la forma ${rendition.id} del elemento '
            '${item.id} no se pudieron leer: sus enlaces en línea no se '
            'actualizaron.',
          ),
          StackTrace.current,
          hint: 'LibraryRepositoryImpl.save',
        );
        return;
      }
      blocks.addAll(decoded);
    }

    await syncInlineLinks(
      _db,
      itemId: item.id,
      blocks: blocks,
      ids: _ids,
      clock: _clock,
    );
  }

  /// Fire-and-forget, solo para notas (D7, F7): una fuente igual pasa
  /// por acá al guardarse, pero su propia sugerencia de duplicado nace
  /// del hook en `ProcessItemUseCase`, no de este — dos puntos de
  /// enganche para el mismo generador, uno por cada camino por el que
  /// un elemento llega a tener texto completo. Sin comparar contra un
  /// hash anterior primero: a diferencia del chunking de F5, acá el
  /// cálculo es tan barato que no vale la pena optimizar recalcularlo en
  /// cada guardado.
  void _generateDuplicateSuggestionForNote(KnowledgeItem item) {
    if (itemKindFor(item.source.kind) != ItemKind.note) return;
    final generator = _duplicateSuggestionGenerator;
    if (generator == null) return;
    unawaited(generator.generate(item).catchError((_, __) {}));
  }

  @override
  Future<Either<Failure, KnowledgeItem?>> findById(String id) async {
    try {
      final rows = await (_db.select(
        _db.knowledgeEntries,
      )..where((e) => e.id.equals(id))).get();

      if (rows.isEmpty) return right(null);

      final items = await _assemble(rows);
      return right(items.single);
      // Ver `_unexpected`: un TypeError es Error, no Exception.
      // ignore: avoid_catches_without_on_clauses
    } catch (e, stackTrace) {
      return left(_unexpected(e, stackTrace, 'LibraryRepositoryImpl.findById'));
    }
  }

  @override
  Future<Either<Failure, List<KnowledgeItem>>> list(LibraryQuery query) async {
    try {
      return right(await _list(query));
      // Ver `_unexpected`: un TypeError es Error, no Exception.
      // ignore: avoid_catches_without_on_clauses
    } catch (e, stackTrace) {
      return left(_unexpected(e, stackTrace, 'LibraryRepositoryImpl.list'));
    }
  }

  @override
  Future<Either<Failure, int>> count(LibraryQuery query) async {
    try {
      // Se cuenta sin paginar: "hay 340 resultados" es el total, no cuántos
      // entraron en la página actual. Y se cuenta en la base: traer todos los
      // ids para medir la lista sería el costo de listar la biblioteca entera.
      return right(await _countMatching(query));
      // Ver `_unexpected`: un TypeError es Error, no Exception.
      // ignore: avoid_catches_without_on_clauses
    } catch (e, stackTrace) {
      return left(_unexpected(e, stackTrace, 'LibraryRepositoryImpl.count'));
    }
  }

  @override
  Future<Either<Failure, List<String>>> matchingIds(LibraryQuery query) async {
    try {
      return right(await _matchingIds(query));
      // Ver `_unexpected`: un TypeError es Error, no Exception.
      // ignore: avoid_catches_without_on_clauses
    } catch (e, stackTrace) {
      return left(
        _unexpected(e, stackTrace, 'LibraryRepositoryImpl.matchingIds'),
      );
    }
  }

  @override
  Stream<List<KnowledgeItem>> watch(LibraryQuery query) {
    // Se vuelve a consultar ante cualquier cambio en las tablas que componen
    // un elemento. Es deliberadamente grueso: reconstruir la lista cuesta
    // poco comparado con la alternativa, que sería razonar si tal escritura
    // concreta afecta o no a tal filtro concreto — y equivocarse ahí deja la
    // pantalla mostrando datos viejos sin que nadie se entere.
    //
    // Lo que sigue es más largo que un `await for` sobre las notificaciones,
    // y hay dos razones concretas para no tomar el camino corto.
    //
    // La primera: consultar la base desde adentro del flujo de
    // notificaciones de drift reentra en el controlador que está emitiendo
    // esa misma notificación, y revienta con "Cannot add event while adding
    // stream".
    //
    // La segunda importa más. Las notificaciones de drift son un stream de
    // difusión: lo que se emite mientras el consumidor está ocupado no se
    // encola, se pierde. Con un `asyncMap` —que pausa la fuente mientras
    // trabaja— una escritura que llegue justo durante el ensamblado anterior
    // no provocaría ninguna emisión nueva, y la pantalla se quedaría
    // mostrando datos viejos para siempre, sin error y sin forma de
    // enterarse.
    //
    // Como todos los avisos dicen lo mismo —"algo cambió"— alcanza con
    // recordar que quedó uno pendiente y volver a consultar al terminar. Eso
    // agrupa ráfagas de escrituras en una sola consulta y, sobre todo, no
    // pierde ninguna.
    return _watching(() => _list(query), hint: 'LibraryRepositoryImpl.watch');
  }

  /// La mecánica común de los dos métodos que observan cambios.
  ///
  /// Vuelve a ejecutar [read] ante cualquier escritura en las tablas que
  /// componen un elemento. Es deliberadamente grueso: recomponer cuesta poco
  /// comparado con la alternativa, que sería razonar si tal escritura
  /// concreta afecta o no a tal consulta concreta — y equivocarse ahí deja la
  /// pantalla con datos viejos sin que nadie se entere.
  ///
  /// Es más largo que un `await for` sobre las notificaciones, y hay dos
  /// razones para no tomar ese camino.
  ///
  /// La primera: consultar la base desde adentro del flujo de avisos de drift
  /// reentra en el controlador que está emitiendo ese mismo aviso, y revienta
  /// con "Cannot add event while adding stream".
  ///
  /// La segunda importa más. Los avisos de drift son un stream de difusión:
  /// lo que se emite mientras el consumidor está ocupado no se encola, se
  /// pierde. Con un `asyncMap` —que pausa la fuente mientras trabaja— una
  /// escritura que llegue justo durante la consulta anterior no provocaría
  /// ninguna emisión nueva, y la pantalla se quedaría con datos viejos para
  /// siempre, sin error y sin forma de enterarse.
  ///
  /// Como todos los avisos dicen lo mismo —"algo cambió"— alcanza con
  /// recordar que quedó uno pendiente y volver a consultar al terminar. Eso
  /// agrupa ráfagas de escrituras en una sola consulta y, sobre todo, no
  /// pierde ninguna.
  /// Envoltorio fino sobre `watchQuery`: fija las tablas de las que depende
  /// cualquier lectura de este repositorio, para no repetir la lista en cada
  /// método que observa.
  Stream<T> _watching<T>(Future<T> Function() read, {required String hint}) {
    return watchQuery<T>(
      db: _db,
      tables: [
        _db.knowledgeEntries,
        _db.knowledgeSources,
        _db.renditions,
        _db.propertyValues,
        _db.itemPropertyValues,
      ],
      read: read,
      telemetry: _telemetry,
      hint: hint,
    );
  }

  @override
  Stream<KnowledgeItem?> watchById(String id) {
    return _watching(() async {
      final rows = await (_db.select(
        _db.knowledgeEntries,
      )..where((e) => e.id.equals(id))).get();

      if (rows.isEmpty) return null;
      return (await _assemble(rows)).single;
    }, hint: 'LibraryRepositoryImpl.watchById');
  }

  @override
  Future<Either<Failure, List<SearchHit>>> search(LibraryQuery query) async {
    try {
      return right(await _search(query));
      // Ver `_unexpected`: un TypeError es Error, no Exception.
      // ignore: avoid_catches_without_on_clauses
    } catch (e, stackTrace) {
      return left(_unexpected(e, stackTrace, 'LibraryRepositoryImpl.search'));
    }
  }

  @override
  Stream<List<SearchHit>> watchSearch(LibraryQuery query) => _watching(
    () => _search(query),
    hint: 'LibraryRepositoryImpl.watchSearch',
  );

  /// Los resultados de [query], cada uno con dónde está lo que se encontró.
  ///
  /// Si la consulta es de texto puro por relevancia y con página, la página y
  /// los chunks salen de UNA pasada por el índice: ver
  /// [LibraryQuerySql.mergedIds]. Con otros filtros, otro orden o una palabra
  /// que está en casi todo, los resultados se resuelven como siempre y las
  /// citas se buscan aparte para esos elementos.
  Future<List<SearchHit>> _search(LibraryQuery query) async {
    if (!query.hasSearchText) {
      return [for (final item in await _list(query)) SearchHit(item: item)];
    }
    final sql = await _sqlFor(query);
    if (sql.matchesNothing) return [];

    if (!sql.canMerge) {
      final items = await _list(query);
      final citations = await _citationsByRanking(
        query.searchText!,
        items.map((i) => i.id),
      );
      return [
        for (final item in items)
          SearchHit(item: item, citation: citations[item.id]),
      ];
    }

    var merged = sql.mergedIds(everyWord: false)!;
    var rows = await _db
        .customSelect(merged.sql, variables: merged.variables)
        .get();
    // Los elementos que tienen todas las palabras pero en fragmentos distintos
    // van DESPUÉS de los que las tienen juntas: solo hace falta buscarlos si la
    // página no se llenó sin ellos.
    if (sql.hasEveryWordBranch && rows.length < query.limit!) {
      merged = sql.mergedIds(everyWord: true)!;
      rows = await _db
          .customSelect(merged.sql, variables: merged.variables)
          .get();
    }

    final ids = [for (final row in rows) row.read<String>('id')];
    final keys = {
      for (final row in rows)
        if (row.readNullable<int>('chunk_key') case final key?)
          row.read<String>('id'): key,
    };
    final items = await _itemsInOrder(ids);
    final citations = await _citationsFor(query.searchText!, keys);
    return [
      for (final item in items)
        SearchHit(item: item, citation: citations[item.id]),
    ];
  }

  /// Las citas de los chunks [keys] —el `row_key` del mejor chunk de cada
  /// elemento—: su posición y un fragmento con lo buscado resaltado.
  Future<Map<String, SearchCitation>> _citationsFor(
    String searchText,
    Map<String, int> keys,
  ) async {
    if (keys.isEmpty) return const {};
    final terms = searchTerms(searchText);
    final rows = await _db
        .customSelect(
          'SELECT item_id, id AS chunk_id, row_key, char_start, char_end, '
          'start_ms, end_ms, page_number, content FROM chunks '
          'WHERE row_key IN (${List.filled(keys.length, '?').join(', ')})',
          variables: [for (final key in keys.values) Variable.withInt(key)],
        )
        .get();
    return {
      for (final row in rows)
        row.read<String>('item_id'): SearchCitation(
          itemId: row.read<String>('item_id'),
          chunkId: row.read<String>('chunk_id'),
          snippet: buildSnippet(row.read<String>('content'), [
            for (final t in terms) t.term,
          ]),
          charStart: row.read<int>('char_start'),
          charEnd: row.read<int>('char_end'),
          startMs: row.readNullable<int>('start_ms'),
          endMs: row.readNullable<int>('end_ms'),
          pageNumber: row.readNullable<int>('page_number'),
        ),
    };
  }

  /// Las citas de [itemIds] buscando los mejores chunks: para las consultas que
  /// no se resuelven en una pasada, porque tienen otros filtros o piden otro
  /// orden.
  Future<Map<String, SearchCitation>> _citationsByRanking(
    String searchText,
    Iterable<String> itemIds,
  ) async {
    final ids = itemIds.toSet().toList();
    final terms = searchTerms(searchText);
    if (ids.isEmpty || terms.isEmpty) return const {};

    // Se resuelve igual que la búsqueda: ordenando por relevancia, o en una
    // ventana de los chunks más recientes si la palabra está en casi todo.
    final plan = await _sqlFor(
      LibraryQuery(searchText: searchText),
    ).then((sql) => sql.plan);
    final match = buildSearchQuery(searchText);

    const columns =
        'c.item_id AS item_id, c.id AS chunk_id, '
        'c.char_start AS char_start, c.char_end AS char_end, '
        'c.start_ms AS start_ms, c.end_ms AS end_ms, '
        'c.page_number AS page_number, c.content AS content';

    // UNA pasada por los MEJORES chunks, quedándose con el primero de cada
    // elemento pedido. La versión anterior le preguntaba al índice por cada
    // chunk de esos elementos y tardaba lo que tardan las coincidencias por
    // cada uno: dos segundos con una palabra frecuente. Y los mejores chunks
    // son entre los que la búsqueda eligió a esos elementos, así que el suyo
    // está ahí: ver [topChunksFor].
    final wanted = ids.toSet();
    final rows = plan.windowed
        ? await _db
              .customSelect(
                'SELECT $columns FROM ( '
                'SELECT chunk_search.rowid AS rid FROM chunk_search '
                'WHERE chunk_search MATCH ? '
                'ORDER BY chunk_search.rowid DESC LIMIT ?) w '
                'JOIN chunks c ON c.row_key = w.rid '
                'ORDER BY w.rid DESC',
                variables: [
                  Variable.withString(match),
                  Variable.withInt(kSearchWindowChunks),
                ],
              )
              .get()
        : await _db
              .customSelect(
                'SELECT $columns FROM ( '
                'SELECT chunk_search.rowid AS rid, chunk_search.rank AS s '
                'FROM chunk_search WHERE chunk_search MATCH ? '
                'ORDER BY chunk_search.rank LIMIT ?) top '
                'JOIN chunks c ON c.row_key = top.rid '
                'ORDER BY top.s',
                variables: [
                  Variable.withString(match),
                  Variable.withInt(topChunksFor(ids.length)),
                ],
              )
              .get();

    final citations = <String, SearchCitation>{};
    for (final row in rows) {
      final itemId = row.read<String>('item_id');
      // Vienen del mejor al peor: el primero de cada elemento es el suyo.
      if (!wanted.contains(itemId) || citations.containsKey(itemId)) continue;
      citations[itemId] = SearchCitation(
        itemId: itemId,
        chunkId: row.read<String>('chunk_id'),
        snippet: buildSnippet(row.read<String>('content'), [
          for (final t in terms) t.term,
        ]),
        charStart: row.read<int>('char_start'),
        charEnd: row.read<int>('char_end'),
        startMs: row.readNullable<int>('start_ms'),
        endMs: row.readNullable<int>('end_ms'),
        pageNumber: row.readNullable<int>('page_number'),
      );
    }
    return citations;
  }

  @override
  Future<Either<Failure, Unit>> delete(String id) async {
    try {
      // El archivo original se busca ANTES de borrar la fila: después ya no
      // habría forma de saber cuál era, y quedaría ocupando espacio para
      // siempre. Las cascadas del esquema limpian la base, pero el disco no
      // tiene cascadas.
      final filePath = await _originalFilePathOf(id);

      // Las formas, vínculos, tarjetas, subrayados, chunks y la fuente o nota
      // se van solos por las cascadas del esquema (ver `PRAGMA foreign_keys` en
      // AppDatabase): todo cuelga de la fila de `item`.
      await (_db.delete(
        _db.knowledgeEntries,
      )..where((e) => e.id.equals(id))).go();

      if (filePath != null) await _deleteFileQuietly(filePath, id);

      return right(unit);
      // Ver `_unexpected`: un TypeError es Error, no Exception.
      // ignore: avoid_catches_without_on_clauses
    } catch (e, stackTrace) {
      return left(_unexpected(e, stackTrace, 'LibraryRepositoryImpl.delete'));
    }
  }

  @override
  Future<Either<Failure, Unit>> deleteMany(List<String> ids) async {
    try {
      // Las filas se borran todas dentro de la misma transacción —o quedan
      // todas o no queda ninguna—; los archivos, después y fuera de ella: el
      // disco no es transaccional, y que uno se resista a borrarse no
      // debería deshacer el borrado de los demás que sí funcionaron.
      //
      // `_originalFilePathOf` se pregunta por cada id ANTES de borrar esa
      // fila, dentro del mismo recorrido: si dos de los [ids] comparten
      // fuente —el mismo PDF capturado dos veces—, la pregunta para el
      // segundo ya ve borrada la fila del primero, así que el archivo se
      // borra una sola vez, no cero ni dos.
      final filesToDelete = <(String id, String path)>[];
      await _db.transaction(() async {
        for (final id in ids) {
          final filePath = await _originalFilePathOf(id);
          if (filePath != null) filesToDelete.add((id, filePath));
          // La fila se borra DENTRO del recorrido: la pregunta por el archivo
          // del elemento siguiente se hace sobre ella, y con esta fila todavía
          // ahí ninguno de los dos se animaría a borrarlo.
          await (_db.delete(
            _db.knowledgeEntries,
          )..where((e) => e.id.equals(id))).go();
        }
      });

      for (final (id, path) in filesToDelete) {
        await _deleteFileQuietly(path, id);
      }

      return right(unit);
      // Ver `_unexpected`: un TypeError es Error, no Exception.
      // ignore: avoid_catches_without_on_clauses
    } catch (e, stackTrace) {
      return left(
        _unexpected(e, stackTrace, 'LibraryRepositoryImpl.deleteMany'),
      );
    }
  }

  /// La ruta del archivo original de un elemento, si tenía uno.
  ///
  /// El mismo archivo puede estar en varios elementos —el mismo PDF capturado
  /// dos veces— así que solo se borra cuando nadie más lo referencia. Borrarlo
  /// sin mirar dejaría al otro elemento apuntando a un archivo que ya no está.
  Future<String?> _originalFilePathOf(String id) async {
    final source = await (_db.select(
      _db.knowledgeSources,
    )..where((s) => s.itemId.equals(id))).getSingleOrNull();

    final path = source?.originalBlobPath;
    if (path == null) return null;

    final others =
        await (_db.select(_db.knowledgeSources)..where(
              (s) => s.originalBlobPath.equals(path) & s.itemId.isNotValue(id),
            ))
            .get();

    return others.isEmpty ? path : null;
  }

  @override
  Future<Either<Failure, Unit>> assignSpace({
    required String itemId,
    required String? spaceId,
  }) async {
    try {
      await (_db.update(_db.knowledgeEntries)
            ..where((e) => e.id.equals(itemId)))
          .write(KnowledgeEntriesCompanion(spaceId: Value(spaceId)));
      return right(unit);
      // Ver `_unexpected`: un TypeError es Error, no Exception.
      // ignore: avoid_catches_without_on_clauses
    } catch (e, stackTrace) {
      return left(
        _unexpected(e, stackTrace, 'LibraryRepositoryImpl.assignSpace'),
      );
    }
  }

  @override
  Future<Either<Failure, Unit>> assignSpaceMany({
    required List<String> itemIds,
    required String? spaceId,
  }) async {
    try {
      // Un único `UPDATE ... WHERE id IN (...)`, no [itemIds] llamadas
      // sueltas a [assignSpace]: la misma columna para todos a la vez.
      await (_db.update(_db.knowledgeEntries)..where((e) => e.id.isIn(itemIds)))
          .write(KnowledgeEntriesCompanion(spaceId: Value(spaceId)));
      return right(unit);
      // Ver `_unexpected`: un TypeError es Error, no Exception.
      // ignore: avoid_catches_without_on_clauses
    } catch (e, stackTrace) {
      return left(
        _unexpected(e, stackTrace, 'LibraryRepositoryImpl.assignSpaceMany'),
      );
    }
  }

  /// Borra el archivo sin dejar que un fallo del disco frustre el borrado.
  ///
  /// El usuario pidió eliminar algo y la fila ya no está: devolver un error
  /// porque el archivo se resistió sería mentirle —el elemento sí se borró— y
  /// dejarlo intentándolo otra vez sin resultado. Se registra y sigue.
  Future<void> _deleteFileQuietly(String path, String id) async {
    try {
      await _files.delete(path);
      // Catch-all deliberado: el disco puede fallar de muchas formas —permisos,
      // volumen desmontado, un `Error` del sistema de archivos que no es
      // `Exception`— y ninguna de ellas debe volver atrás un borrado que el
      // usuario ya pidió y que en la base ya ocurrió.
      // ignore: avoid_catches_without_on_clauses
    } catch (e, stackTrace) {
      _telemetry.recordError(
        e,
        stackTrace,
        hint: 'LibraryRepositoryImpl.delete: quedó el archivo de $id',
      );
    }
  }

  // ---------------------------------------------------------------------
  // Escritura
  // ---------------------------------------------------------------------

  /// Deja las formas guardadas igual a las del elemento.
  ///
  /// Actualiza las que siguen estando y borra **solo** las que desaparecieron.
  /// La alternativa obvia —borrar todas y reinsertarlas— sería más corta y
  /// destruiría datos del usuario: los subrayados cuelgan de la rendition con
  /// borrado en cascada, así que rehacerlas todas se llevaría puesto cada
  /// subrayado y cada nota al margen de un elemento, cada vez que se guarda.
  Future<void> _syncRenditions(KnowledgeItem item) async {
    final keptIds = item.renditions.map((r) => r.renditionId).toList();

    await (_db.delete(
      _db.renditions,
    )..where((r) => r.itemId.equals(item.id) & r.id.isNotIn(keptIds))).go();

    for (final rendition in item.renditions) {
      await _db
          .into(_db.renditions)
          .insertOnConflictUpdate(_companionOf(rendition, item.id));
    }
  }

  RenditionsCompanion _companionOf(Rendition rendition, String itemId) {
    return switch (rendition) {
      TextRendition(
        :final id,
        :final kind,
        :final content,
        :final isPrimary,
        :final createdAt,
      ) =>
        RenditionsCompanion.insert(
          id: id,
          itemId: itemId,
          kind: kind,
          isPrimary: isPrimary,
          createdAt: createdAt,
          content: Value(content),
        ),
      FileRendition(
        :final id,
        :final kind,
        :final relativePath,
        :final isPrimary,
        :final createdAt,
      ) =>
        RenditionsCompanion.insert(
          id: id,
          itemId: itemId,
          kind: kind,
          isPrimary: isPrimary,
          createdAt: createdAt,
          relativePath: Value(relativePath),
        ),
    };
  }

  /// Deja las etiquetas del elemento igual a las de la entidad.
  ///
  /// Una etiqueta ES un valor de la categoría Tema: no hay otra tabla. Acá
  /// se sincroniza por DIFERENCIA y no rehaciendo la relación entera, porque
  /// una asignación tiene datos propios —su `origin`: `suggestedAccepted`,
  /// `inherited`—, y borrarla para volver a insertarla la degradaría a
  /// `manual`. Solo se borra lo que la entidad ya no tiene y solo se agrega
  /// lo que le falta.
  ///
  /// Una etiqueta que todavía no existe como valor —una que se armó en
  /// memoria— se crea acá, con su mismo id. Un valor que ya existe no se
  /// toca: renombrarlo es asunto de `renameTag`, no de guardar un elemento.
  ///
  /// Cualquier propiedad de Tema que llegue en `item.properties` se trata
  /// como etiqueta: una entidad bien armada no la trae —`_assemble` separa
  /// las dos cosas—, pero perderla en silencio sería peor que reinterpretarla.
  Future<void> _syncTags(KnowledgeItem item, String temaId) async {
    final desired = <String, ItemPropertyOrigin>{
      for (final property in item.properties)
        if (property.definitionId == temaId) property.valueId: property.origin,
      for (final tag in item.tags) tag.id: ItemPropertyOrigin.manual,
    };

    for (final tag in item.tags) {
      await _ensureTemaValue(
        id: tag.id,
        temaId: temaId,
        label: tag.name,
        createdAt: tag.createdAt,
      );
    }
    for (final property in item.properties) {
      if (property.definitionId != temaId) continue;
      await _ensureTemaValue(
        id: property.valueId,
        temaId: temaId,
        label: property.value,
        createdAt: property.createdAt,
      );
    }

    final current =
        (await (_db.select(_db.itemPropertyValues).join([
                  innerJoin(
                    _db.propertyValues,
                    _db.propertyValues.id.equalsExp(
                      _db.itemPropertyValues.propertyValueId,
                    ),
                  ),
                ])..where(
                  _db.itemPropertyValues.itemId.equals(item.id) &
                      _db.propertyValues.definitionId.equals(temaId),
                ))
                .get())
            .map((row) => row.readTable(_db.itemPropertyValues).propertyValueId)
            .toSet();

    final stale = current.difference(desired.keys.toSet());
    if (stale.isNotEmpty) {
      await (_db.delete(_db.itemPropertyValues)..where(
            (it) => it.itemId.equals(item.id) & it.propertyValueId.isIn(stale),
          ))
          .go();
    }

    for (final entry in desired.entries) {
      if (current.contains(entry.key)) continue;
      await _db
          .into(_db.itemPropertyValues)
          .insert(
            ItemPropertyValuesCompanion.insert(
              itemId: item.id,
              propertyValueId: entry.key,
              origin: Value(entry.value),
            ),
          );
    }
  }

  /// Crea el valor de Tema de una etiqueta armada en memoria, si todavía no
  /// existe. Un valor que ya está no se toca.
  ///
  /// `insert` a secas, sin ignorar conflictos: si el texto choca con otro
  /// valor de Tema, que falle con el motivo real es mejor que dejar una
  /// asignación apuntando a un valor que nunca se creó.
  Future<void> _ensureTemaValue({
    required String id,
    required String temaId,
    required String label,
    required DateTime createdAt,
  }) async {
    final exists =
        await (_db.select(
          _db.propertyValues,
        )..where((v) => v.id.equals(id))).getSingleOrNull() !=
        null;
    if (exists) return;

    await _db
        .into(_db.propertyValues)
        .insert(
          PropertyValuesCompanion.insert(
            id: id,
            definitionId: temaId,
            value: label,
            createdAt: createdAt,
          ),
        );
  }

  /// Deja los valores de propiedad del elemento igual a los de la entidad,
  /// SIN contar los de Tema —esos son las etiquetas, ver [_syncTags]—: se
  /// rehace la relación entera de lo que no es Tema, y de paso se hace
  /// upsert de cada valor —por si llegó de un lugar que todavía no lo había
  /// persistido— sin tocar la categoría a la que pertenece.
  Future<void> _syncProperties(KnowledgeItem item, String temaId) async {
    final others = item.properties.where((p) => p.definitionId != temaId);

    for (final property in others) {
      await _db
          .into(_db.propertyValues)
          .insertOnConflictUpdate(
            PropertyValuesCompanion.insert(
              id: property.valueId,
              definitionId: property.definitionId,
              value: property.value,
              createdAt: property.createdAt,
            ),
          );
    }

    await (_db.delete(_db.itemPropertyValues)..where(
          (it) =>
              it.itemId.equals(item.id) &
              it.propertyValueId.isNotInQuery(
                _db.selectOnly(_db.propertyValues)
                  ..addColumns([_db.propertyValues.id])
                  ..where(_db.propertyValues.definitionId.equals(temaId)),
              ),
        ))
        .go();

    for (final property in others) {
      await _db
          .into(_db.itemPropertyValues)
          .insert(
            ItemPropertyValuesCompanion.insert(
              itemId: item.id,
              propertyValueId: property.valueId,
              origin: Value(property.origin),
            ),
          );
    }
  }

  /// Escribe el elemento: la fila de `item` y, según sea, su `source` o su
  /// `note`. Desde F10 es lo ÚNICO que se escribe del elemento en sí —antes
  /// había además una copia en `items`/`sources`, de la que este método era el
  /// espejo—.
  ///
  /// `title`/`subtitle`/`notes`/`spaceId`/`updatedAt` y los campos estructurales
  /// de `source` se sobreescriben siempre: son un reflejo directo de [item].
  /// `state` —y, para una nota, `noteKind`/`maturity`, y `contentHash` de una
  /// fuente— se preservan si ya existían: los escribe otra cosa (la Bandeja,
  /// `createRelation`, el chunking), nunca este método.
  Future<void> _upsertEntry(KnowledgeItem item) async {
    final existingEntry = await (_db.select(
      _db.knowledgeEntries,
    )..where((e) => e.id.equals(item.id))).getSingleOrNull();

    final state = nextMirrorState(
      current: existingEntry?.state,
      processingState: item.processingState,
    );
    final kind = itemKindFor(item.source.kind);

    await _db
        .into(_db.knowledgeEntries)
        .insertOnConflictUpdate(
          KnowledgeEntriesCompanion.insert(
            id: item.id,
            title: item.title,
            subtitle: Value(item.subtitle),
            notes: Value(item.notes),
            spaceId: Value(item.spaceId),
            kind: kind,
            state: state,
            createdAt: item.createdAt,
            updatedAt: item.updatedAt,
            deviceId: kMirrorDeviceIdPlaceholder,
          ),
        );

    if (kind == ItemKind.note) {
      await _db
          .into(_db.knowledgeNotes)
          .insert(
            KnowledgeNotesCompanion.insert(
              itemId: item.id,
              noteKind: NoteKind.living,
              maturity: NoteMaturity.seed,
            ),
            mode: InsertMode.insertOrIgnore,
          );
      return;
    }

    final existingSource = await (_db.select(
      _db.knowledgeSources,
    )..where((s) => s.itemId.equals(item.id))).getSingleOrNull();

    await _db
        .into(_db.knowledgeSources)
        .insertOnConflictUpdate(
          KnowledgeSourcesCompanion.insert(
            itemId: item.id,
            sourceType: item.source.kind,
            originUrl: Value(item.source.url),
            authorName: Value(item.source.authorName),
            authorUrl: Value(item.source.authorUrl),
            publishedAt: Value(item.source.publishedAt),
            capturedAt: item.source.capturedAt,
            originalBlobPath: Value(item.source.originalFilePath),
            contentHash: existingSource?.contentHash ?? '',
            processingStatus: sourceProcessingStatusFor(item.processingState),
          ),
        );
  }

  // ---------------------------------------------------------------------
  // Lectura
  // ---------------------------------------------------------------------

  Future<List<KnowledgeItem>> _list(LibraryQuery query) async =>
      _itemsInOrder(await _matchingIds(query));

  /// Los elementos de [ids], armados, en ESE orden.
  Future<List<KnowledgeItem>> _itemsInOrder(List<String> ids) async {
    if (ids.isEmpty) return [];

    final rows = await (_db.select(
      _db.knowledgeEntries,
    )..where((e) => e.id.isIn(ids))).get();

    final assembled = await _assemble(rows);

    // `WHERE id IN (...)` no conserva el orden de la lista, así que se
    // reordena según los identificadores que ya venían ordenados. Importa
    // sobre todo con orden por relevancia, donde el criterio vive en FTS5 y
    // no se puede reproducir con un ORDER BY sobre `items`.
    final byId = {for (final item in assembled) item.id: item};
    return ids.map((id) => byId[id]).whereType<KnowledgeItem>().toList();
  }

  /// Resuelve qué elementos cumplen la consulta, y en qué orden.
  ///
  /// Devuelve solo identificadores porque el trabajo pesado —traer
  /// transcripciones enteras y armar los agregados— no debe hacerse sobre
  /// filas que después se van a descartar por un filtro o por la paginación.
  ///
  /// El filtrado, el orden —también el de relevancia— y la página los
  /// resuelve la base en una sola consulta: ver [LibraryQuerySql].
  Future<List<String>> _matchingIds(LibraryQuery query) async {
    final sql = await _sqlFor(query);
    if (sql.matchesNothing) return [];

    final ids = sql.ids();
    final rows = await _db
        .customSelect(ids.sql, variables: ids.variables)
        .get();
    return [for (final row in rows) row.read<String>('id')];
  }

  /// El SQL de [query], decidiendo antes cómo se resuelve su texto: ordenado
  /// por relevancia, o en una ventana de los chunks más recientes si la palabra
  /// está en tantos que ordenarla no distingue nada —ver [kRankedHitsCap]—.
  Future<LibraryQuerySql> _sqlFor(LibraryQuery query) async {
    if (!query.hasSearchText) return LibraryQuerySql(query);
    final match = buildSearchQuery(query.searchText!);
    if (match.isEmpty) {
      return LibraryQuerySql(query, plan: TextSearchPlan(match: match));
    }
    final terms = await estimateTermHits(_db, query.searchText!);
    final rarest = terms.isEmpty
        ? 0
        : terms.map((t) => t.hits).reduce((a, b) => a < b ? a : b);
    final windowed = rarest > _rankedHitsCap;
    return LibraryQuerySql(
      query,
      plan: TextSearchPlan(
        match: match,
        windowed: windowed,
        termMatches: terms.length < 2
            ? const []
            : [
                for (final t in terms)
                  if (t.hits <= _rankedHitsCap) t.match,
              ],
      ),
    );
  }

  Future<int> _countMatching(LibraryQuery query) async {
    final sql = await _sqlFor(query);
    if (sql.matchesNothing) return 0;

    final count = sql.count();
    final row = await _db
        .customSelect(count.sql, variables: count.variables)
        .getSingle();
    return row.read<int>('n');
  }

  /// Convierte filas planas en agregados completos.
  ///
  /// Hace tres consultas en total, y no tres por elemento: pedir las formas y
  /// las etiquetas dentro de un bucle sobre los elementos daría el problema
  /// clásico —una lista de cincuenta elementos disparando ciento cincuenta
  /// consultas— que no se nota en una prueba con tres filas y arruina la
  /// pantalla principal con una biblioteca de verdad.
  Future<List<KnowledgeItem>> _assemble(
    List<KnowledgeEntryRow> itemRows,
  ) async {
    if (itemRows.isEmpty) return [];

    final itemIds = itemRows.map((i) => i.id).toList();

    final sourceRows = await (_db.select(
      _db.knowledgeSources,
    )..where((s) => s.itemId.isIn(itemIds))).get();
    final sourcesById = {for (final s in sourceRows) s.itemId: s};

    final renditionRows = await (_db.select(
      _db.renditions,
    )..where((r) => r.itemId.isIn(itemIds))).get();
    final renditionsByItem = <String, List<Rendition>>{};
    for (final row in renditionRows) {
      (renditionsByItem[row.itemId] ??= []).add(_toRendition(row));
    }

    final propertyRows = await (_db.select(_db.itemPropertyValues).join([
      innerJoin(
        _db.propertyValues,
        _db.propertyValues.id.equalsExp(_db.itemPropertyValues.propertyValueId),
      ),
      innerJoin(
        _db.propertyDefinitions,
        _db.propertyDefinitions.id.equalsExp(_db.propertyValues.definitionId),
      ),
    ])..where(_db.itemPropertyValues.itemId.isIn(itemIds))).get();
    final propertiesByItem = <String, List<ItemProperty>>{};
    final tagsByItem = <String, List<Tag>>{};
    for (final row in propertyRows) {
      final assignmentRow = row.readTable(_db.itemPropertyValues);
      final valueRow = row.readTable(_db.propertyValues);
      final definitionRow = row.readTable(_db.propertyDefinitions);
      // Los valores de Tema son las etiquetas: la entidad los separa de
      // las demás propiedades, así que ninguno aparece dos veces.
      if (isTemaDefinitionRow(definitionRow)) {
        (tagsByItem[assignmentRow.itemId] ??= []).add(
          Tag(
            id: valueRow.id,
            name: valueRow.value,
            createdAt: valueRow.createdAt,
          ),
        );
        continue;
      }
      (propertiesByItem[assignmentRow.itemId] ??= []).add(
        ItemProperty(
          definitionId: definitionRow.id,
          definitionName: definitionRow.name,
          valueId: valueRow.id,
          value: valueRow.value,
          createdAt: valueRow.createdAt,
          origin: assignmentRow.origin,
        ),
      );
    }

    return itemRows.map((row) {
      final source = sourcesById[row.id];
      return KnowledgeItem(
        id: row.id,
        title: row.title,
        subtitle: row.subtitle,
        notes: row.notes,
        source: sourceFor(row, source),
        processingState: processingStateFor(source?.processingStatus),
        createdAt: row.createdAt,
        updatedAt: row.updatedAt,
        renditions: renditionsByItem[row.id] ?? const [],
        tags: tagsByItem[row.id] ?? const [],
        properties: propertiesByItem[row.id] ?? const [],
        spaceId: row.spaceId,
      );
    }).toList();
  }

  /// De qué columna esté llena depende cuál de las dos variantes se
  /// construye. La base garantiza con un CHECK que siempre haya exactamente
  /// una, así que el `else` no es un caso posible — pero si alguna vez lo
  /// fuera, fallar acá es mejor que devolver en silencio una forma vacía que
  /// después aparezca como contenido en blanco.
  Rendition _toRendition(RenditionRow row) {
    final content = row.content;
    if (content != null) {
      return Rendition.text(
        id: row.id,
        itemId: row.itemId,
        kind: row.kind,
        content: content,
        isPrimary: row.isPrimary,
        createdAt: row.createdAt,
      );
    }

    return Rendition.file(
      id: row.id,
      itemId: row.itemId,
      kind: row.kind,
      relativePath: row.relativePath!,
      isPrimary: row.isPrimary,
      createdAt: row.createdAt,
    );
  }

  /// Catch-all deliberado, igual que en el resto de la app: un `TypeError`
  /// —por ejemplo, una columna con un valor que no corresponde a ningún
  /// miembro del enum— es un `Error`, no un `Exception`, y atrapar solo
  /// `Exception` lo dejaría escapar dejando a quien llamó esperando una
  /// respuesta que nunca llega. Siempre es un defecto, así que se reporta.
  Failure _unexpected(Object e, StackTrace stackTrace, String hint) {
    _telemetry.recordError(e, stackTrace, hint: hint);
    return Failure.unexpected(message: e.toString());
  }
}
