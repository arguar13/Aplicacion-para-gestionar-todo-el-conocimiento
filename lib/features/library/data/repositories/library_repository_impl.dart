import 'dart:async';

import 'package:drift/drift.dart';
import 'package:fpdart/fpdart.dart';
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/database/search_index.dart';
import 'package:sinapsis/core/domain/entities/knowledge_item.dart';
import 'package:sinapsis/core/domain/entities/rendition.dart';
import 'package:sinapsis/core/domain/entities/source.dart';
import 'package:sinapsis/core/domain/entities/tag.dart';
import 'package:sinapsis/core/error/failures.dart';
import 'package:sinapsis/core/telemetry/telemetry_service.dart';
import 'package:sinapsis/features/library/domain/entities/library_query.dart';
import 'package:sinapsis/features/library/domain/repositories/library_repository.dart';

class LibraryRepositoryImpl implements LibraryRepository {
  const LibraryRepositoryImpl({
    required AppDatabase database,
    required TelemetryService telemetry,
  }) : _db = database,
       _telemetry = telemetry;

  final AppDatabase _db;
  final TelemetryService _telemetry;

  @override
  Future<Either<Failure, KnowledgeItem>> save(KnowledgeItem item) async {
    try {
      await _db.transaction(() async {
        await _upsertSource(item.source);
        await _upsertItem(item);
        await _syncRenditions(item);
        await _syncTags(item);
      });
      return right(item);
      // Ver `_unexpected`: un TypeError es Error, no Exception.
      // ignore: avoid_catches_without_on_clauses
    } catch (e, stackTrace) {
      return left(_unexpected(e, stackTrace, 'LibraryRepositoryImpl.save'));
    }
  }

  @override
  Future<Either<Failure, KnowledgeItem?>> findById(String id) async {
    try {
      final rows = await (_db.select(
        _db.items,
      )..where((i) => i.id.equals(id))).get();

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
      // entraron en la página actual.
      final ids = await _matchingIds(query.copyWith(limit: null, offset: 0));
      return right(ids.length);
      // Ver `_unexpected`: un TypeError es Error, no Exception.
      // ignore: avoid_catches_without_on_clauses
    } catch (e, stackTrace) {
      return left(_unexpected(e, stackTrace, 'LibraryRepositoryImpl.count'));
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
  Stream<T> _watching<T>(Future<T> Function() read, {required String hint}) {
    late final StreamController<T> controller;
    StreamSubscription<void>? changes;
    var isReading = false;
    var changedWhileReading = false;

    Future<void> refresh() async {
      if (isReading) {
        changedWhileReading = true;
        return;
      }

      isReading = true;
      try {
        do {
          changedWhileReading = false;
          final value = await read();
          if (!controller.isClosed) controller.add(value);
        } while (changedWhileReading);
        // Catch-all deliberado, igual que en el resto del archivo.
        // ignore: avoid_catches_without_on_clauses
      } catch (e, stackTrace) {
        // Un fallo al recomponer viaja por el stream en vez de quedar en una
        // excepción sin dueño: quien observa tiene que poder mostrar el
        // error, no quedarse esperando una emisión que no va a llegar.
        _telemetry.recordError(e, stackTrace, hint: hint);
        if (!controller.isClosed) controller.addError(e, stackTrace);
      } finally {
        isReading = false;
      }
    }

    controller = StreamController<T>(
      onListen: () {
        changes = _db
            .tableUpdates(
              TableUpdateQuery.onAllTables([
                _db.items,
                _db.sources,
                _db.renditions,
                _db.tags,
                _db.itemTags,
              ]),
            )
            .listen((_) => unawaited(refresh()));

        // El primer valor sale sin esperar a que cambie nada: quien se
        // suscribe quiere ver lo que hay ahora.
        unawaited(refresh());
      },
      onCancel: () async {
        await changes?.cancel();
      },
    );

    return controller.stream;
  }

  @override
  Stream<KnowledgeItem?> watchById(String id) {
    return _watching(() async {
      final rows = await (_db.select(
        _db.items,
      )..where((i) => i.id.equals(id))).get();

      if (rows.isEmpty) return null;
      return (await _assemble(rows)).single;
    }, hint: 'LibraryRepositoryImpl.watchById');
  }

  @override
  Future<Either<Failure, Unit>> delete(String id) async {
    try {
      // Las formas, etiquetas, vínculos y subrayados se van solos por las
      // cascadas del esquema (ver `PRAGMA foreign_keys` en AppDatabase).
      await (_db.delete(_db.items)..where((i) => i.id.equals(id))).go();
      return right(unit);
      // Ver `_unexpected`: un TypeError es Error, no Exception.
      // ignore: avoid_catches_without_on_clauses
    } catch (e, stackTrace) {
      return left(_unexpected(e, stackTrace, 'LibraryRepositoryImpl.delete'));
    }
  }

  // ---------------------------------------------------------------------
  // Escritura
  // ---------------------------------------------------------------------

  Future<void> _upsertSource(Source source) {
    return _db
        .into(_db.sources)
        .insertOnConflictUpdate(
          SourcesCompanion.insert(
            id: source.id,
            kind: source.kind,
            capturedAt: source.capturedAt,
            url: Value(source.url),
            authorName: Value(source.authorName),
            authorUrl: Value(source.authorUrl),
            publishedAt: Value(source.publishedAt),
            originalFilePath: Value(source.originalFilePath),
          ),
        );
  }

  Future<void> _upsertItem(KnowledgeItem item) {
    return _db
        .into(_db.items)
        .insertOnConflictUpdate(
          ItemsCompanion.insert(
            id: item.id,
            title: item.title,
            sourceId: item.source.id,
            processingState: item.processingState,
            createdAt: item.createdAt,
            updatedAt: item.updatedAt,
            subtitle: Value(item.subtitle),
            notes: Value(item.notes),
          ),
        );
  }

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
  /// Acá sí se puede rehacer la relación entera sin perder nada: la tabla de
  /// unión no tiene datos propios más allá del vínculo, y nada cuelga de
  /// ella. Las etiquetas en sí no se tocan — dejan de estar asociadas a este
  /// elemento, pero siguen existiendo para los demás.
  Future<void> _syncTags(KnowledgeItem item) async {
    for (final tag in item.tags) {
      await _db
          .into(_db.tags)
          .insertOnConflictUpdate(
            TagsCompanion.insert(
              id: tag.id,
              name: tag.name,
              createdAt: tag.createdAt,
            ),
          );
    }

    await (_db.delete(
      _db.itemTags,
    )..where((it) => it.itemId.equals(item.id))).go();

    for (final tag in item.tags) {
      await _db
          .into(_db.itemTags)
          .insert(ItemTagsCompanion.insert(itemId: item.id, tagId: tag.id));
    }
  }

  // ---------------------------------------------------------------------
  // Lectura
  // ---------------------------------------------------------------------

  Future<List<KnowledgeItem>> _list(LibraryQuery query) async {
    final ids = await _matchingIds(query);
    if (ids.isEmpty) return [];

    final rows = await (_db.select(
      _db.items,
    )..where((i) => i.id.isIn(ids))).get();

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
  Future<List<String>> _matchingIds(LibraryQuery query) async {
    // La búsqueda de texto se resuelve aparte, en la tabla FTS5, y entra al
    // resto de la consulta como un filtro más por identificador. Unirlas en
    // un solo SELECT obligaría a SQL crudo para todo; así cada mitad usa la
    // herramienta que le corresponde.
    Set<String>? textMatches;
    List<String>? relevanceOrder;

    if (query.hasSearchText) {
      relevanceOrder = await _searchIds(query.searchText!);
      textMatches = relevanceOrder.toSet();
      if (textMatches.isEmpty) return [];
    }

    final select = _db.select(_db.items).join([
      innerJoin(_db.sources, _db.sources.id.equalsExp(_db.items.sourceId)),
    ]);

    if (textMatches != null) {
      select.where(_db.items.id.isIn(textMatches));
    }
    if (query.sourceKinds.isNotEmpty) {
      select.where(_db.sources.kind.isIn(query.sourceKinds.map((k) => k.name)));
    }
    if (query.processingStates.isNotEmpty) {
      select.where(
        _db.items.processingState.isIn(
          query.processingStates.map((s) => s.name),
        ),
      );
    }
    if (query.tagIds.isNotEmpty) {
      // Subconsulta en vez de un join: con un join, un elemento que tiene
      // tres de las etiquetas buscadas aparecería tres veces en el
      // resultado.
      select.where(
        _db.items.id.isInQuery(
          _db.selectOnly(_db.itemTags)
            ..addColumns([_db.itemTags.itemId])
            ..where(_db.itemTags.tagId.isIn(query.tagIds)),
        ),
      );
    }

    // Con orden por relevancia, el criterio ya lo puso FTS5 y no hay ORDER BY
    // que lo reproduzca: se ordena en Dart según la posición que traía cada
    // identificador. Sin texto buscado, la relevancia no significa nada y se
    // cae en el orden por fecha de captura.
    final useRelevance =
        query.sortBy == LibrarySort.relevance && relevanceOrder != null;

    if (!useRelevance) {
      select.orderBy([_orderingFor(query)]);
    }

    if (query.limit != null && !useRelevance) {
      select.limit(query.limit!, offset: query.offset);
    }

    final rows = await select.get();
    var ids = rows.map((r) => r.readTable(_db.items).id).toList();

    if (useRelevance) {
      final rank = {
        for (var i = 0; i < relevanceOrder.length; i++) relevanceOrder[i]: i,
      };
      ids.sort((a, b) => (rank[a] ?? 1 << 30).compareTo(rank[b] ?? 1 << 30));
      if (query.limit != null) {
        ids = ids.skip(query.offset).take(query.limit!).toList();
      }
    }

    return ids;
  }

  OrderingTerm _orderingFor(LibraryQuery query) {
    final mode = query.descending ? OrderingMode.desc : OrderingMode.asc;

    return switch (query.sortBy) {
      LibrarySort.capturedAt => OrderingTerm(
        expression: _db.sources.capturedAt,
        mode: mode,
      ),
      LibrarySort.publishedAt => OrderingTerm(
        expression: _db.sources.publishedAt,
        mode: mode,
      ),
      LibrarySort.updatedAt => OrderingTerm(
        expression: _db.items.updatedAt,
        mode: mode,
      ),
      LibrarySort.title => OrderingTerm(
        expression: _db.items.title,
        mode: mode,
      ),
      // Sin texto buscado no hay relevancia que medir; se usa el orden por
      // defecto en vez de fallar o devolver cualquier cosa.
      LibrarySort.relevance => OrderingTerm(
        expression: _db.sources.capturedAt,
        mode: mode,
      ),
    };
  }

  /// Los identificadores que coinciden con el texto, ordenados por relevancia.
  Future<List<String>> _searchIds(String rawInput) async {
    final query = buildSearchQuery(rawInput);
    if (query.isEmpty) return [];

    final rows = await _db
        .customSelect(
          'SELECT item_id FROM item_search WHERE item_search MATCH ? '
          'ORDER BY rank',
          variables: [Variable.withString(query)],
        )
        .get();

    return rows.map((r) => r.data['item_id']! as String).toList();
  }

  /// Convierte filas planas en agregados completos.
  ///
  /// Hace tres consultas en total, y no tres por elemento: pedir las formas y
  /// las etiquetas dentro de un bucle sobre los elementos daría el problema
  /// clásico —una lista de cincuenta elementos disparando ciento cincuenta
  /// consultas— que no se nota en una prueba con tres filas y arruina la
  /// pantalla principal con una biblioteca de verdad.
  Future<List<KnowledgeItem>> _assemble(List<ItemRow> itemRows) async {
    if (itemRows.isEmpty) return [];

    final itemIds = itemRows.map((i) => i.id).toList();
    final sourceIds = itemRows.map((i) => i.sourceId).toSet().toList();

    final sourceRows = await (_db.select(
      _db.sources,
    )..where((s) => s.id.isIn(sourceIds))).get();
    final sourcesById = {for (final s in sourceRows) s.id: _toSource(s)};

    final renditionRows = await (_db.select(
      _db.renditions,
    )..where((r) => r.itemId.isIn(itemIds))).get();
    final renditionsByItem = <String, List<Rendition>>{};
    for (final row in renditionRows) {
      (renditionsByItem[row.itemId] ??= []).add(_toRendition(row));
    }

    final tagRows = await (_db.select(_db.itemTags).join([
      innerJoin(_db.tags, _db.tags.id.equalsExp(_db.itemTags.tagId)),
    ])..where(_db.itemTags.itemId.isIn(itemIds))).get();
    final tagsByItem = <String, List<Tag>>{};
    for (final row in tagRows) {
      final itemId = row.readTable(_db.itemTags).itemId;
      (tagsByItem[itemId] ??= []).add(_toTag(row.readTable(_db.tags)));
    }

    return itemRows.map((row) {
      return KnowledgeItem(
        id: row.id,
        title: row.title,
        subtitle: row.subtitle,
        notes: row.notes,
        source: sourcesById[row.sourceId]!,
        processingState: row.processingState,
        createdAt: row.createdAt,
        updatedAt: row.updatedAt,
        renditions: renditionsByItem[row.id] ?? const [],
        tags: tagsByItem[row.id] ?? const [],
      );
    }).toList();
  }

  Source _toSource(SourceRow row) => Source(
    id: row.id,
    kind: row.kind,
    capturedAt: row.capturedAt,
    url: row.url,
    authorName: row.authorName,
    authorUrl: row.authorUrl,
    publishedAt: row.publishedAt,
    originalFilePath: row.originalFilePath,
  );

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

  Tag _toTag(TagRow row) =>
      Tag(id: row.id, name: row.name, createdAt: row.createdAt);

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
