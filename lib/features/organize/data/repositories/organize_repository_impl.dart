import 'dart:math' as math;

import 'package:drift/drift.dart';
import 'package:fpdart/fpdart.dart';
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/database/knowledge_entry_writer.dart';
import 'package:sinapsis/core/database/property_value_merge.dart';
import 'package:sinapsis/core/database/tema_category.dart';
import 'package:sinapsis/core/database/vocabulary_lookup.dart';
import 'package:sinapsis/core/database/watching_query.dart';
import 'package:sinapsis/core/domain/entities/highlight.dart';
import 'package:sinapsis/core/domain/entities/historical_date.dart';
import 'package:sinapsis/core/domain/entities/item_property_origin.dart';
import 'package:sinapsis/core/domain/entities/item_relation.dart';
import 'package:sinapsis/core/domain/entities/neighborhood.dart';
import 'package:sinapsis/core/domain/entities/note_kind.dart';
import 'package:sinapsis/core/domain/entities/property_definition.dart';
import 'package:sinapsis/core/domain/entities/property_value.dart';
import 'package:sinapsis/core/domain/entities/property_value_type.dart';
import 'package:sinapsis/core/domain/entities/relation_edge.dart';
import 'package:sinapsis/core/domain/entities/relation_kind.dart';
import 'package:sinapsis/core/domain/entities/source_kind.dart';
import 'package:sinapsis/core/domain/entities/space.dart';
import 'package:sinapsis/core/domain/entities/tag.dart';
import 'package:sinapsis/core/error/failures.dart';
import 'package:sinapsis/core/telemetry/telemetry_service.dart';
import 'package:sinapsis/core/util/clock.dart';
import 'package:sinapsis/core/util/id_generator.dart';
import 'package:sinapsis/features/organize/domain/repositories/organize_repository.dart';

class OrganizeRepositoryImpl implements OrganizeRepository {
  const OrganizeRepositoryImpl({
    required AppDatabase database,
    required TelemetryService telemetry,
    required IdGenerator ids,
    required Clock clock,
  }) : _db = database,
       _telemetry = telemetry,
       _ids = ids,
       _clock = clock;

  final AppDatabase _db;
  final TelemetryService _telemetry;
  final IdGenerator _ids;
  final Clock _clock;

  /// Quien escribe el subtipo de una nota: ver [KnowledgeEntryWriter].
  KnowledgeEntryWriter get _writer => KnowledgeEntryWriter(_db, clock: _clock);

  // ---------------------------------------------------------------------
  // Etiquetas
  // ---------------------------------------------------------------------
  //
  // Desde F8, una etiqueta ES un valor de la categoría Tema: no hay otra
  // fuente de verdad. La API de etiquetas —lo que usa `TagEditor`— se
  // conserva tal cual, reimplementada encima de las propiedades: `Tag.id` es
  // el id del valor, y por eso una etiqueta creada acá aparece al filtrar
  // por la propiedad Tema y al revés.

  @override
  Stream<List<Tag>> watchAllTags() {
    return watchQuery(
      db: _db,
      // Solo los valores: el id de Tema no cambia nunca —es de sistema, no
      // se renombra ni se borra—, y observar `propertyDefinitions` solo
      // traería avisos de más, como el de la siembra al crear la base.
      tables: [_db.propertyValues],
      read: () async {
        final temaId = await temaDefinitionId(_db);
        final rows =
            await (_db.select(_db.propertyValues)
                  ..where((v) => v.definitionId.equals(temaId))
                  ..orderBy([(v) => OrderingTerm(expression: v.value)]))
                .get();
        return rows.map(_toTag).toList();
      },
      telemetry: _telemetry,
      hint: 'OrganizeRepositoryImpl.watchAllTags',
    );
  }

  @override
  Future<Either<Failure, Tag>> getOrCreateTag(String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      return left(
        const Failure.validation(message: 'El nombre no puede quedar vacío.'),
      );
    }

    try {
      final temaId = await temaDefinitionId(_db);
      // Por label o por alias, sin distinguir mayúsculas ni acentos:
      // escribir "filosofia" en un elemento que ya tiene "Filosofía" tiene
      // que terminar en la misma etiqueta, no en dos que compiten por
      // agrupar lo mismo.
      final existing = await _findValueByLabelOrAlias(temaId, trimmed);
      if (existing != null) return right(_toTag(existing));

      final tag = Tag(id: _ids.next(), name: trimmed, createdAt: _clock());
      await _db
          .into(_db.propertyValues)
          .insert(
            PropertyValuesCompanion.insert(
              id: tag.id,
              definitionId: temaId,
              value: tag.name,
              createdAt: tag.createdAt,
            ),
          );

      return right(tag);
      // Ver `_unexpected`: un TypeError es Error, no Exception.
      // ignore: avoid_catches_without_on_clauses
    } catch (e, stackTrace) {
      return left(
        _unexpected(e, stackTrace, 'OrganizeRepositoryImpl.getOrCreateTag'),
      );
    }
  }

  @override
  Future<Either<Failure, Tag>> renameTag({
    required String id,
    required String name,
  }) async {
    final Either<Failure, PropertyValueRow> renamed;
    try {
      renamed = await _renameValue(
        id: id,
        label: name,
        onlyInDefinition: await temaDefinitionId(_db),
        blankMessage: 'El nombre no puede quedar vacío.',
        missingMessage: 'La etiqueta ya no existe; puede que se haya borrado.',
        clashMessage: (label) => 'Ya existe una etiqueta "$label".',
        hint: 'OrganizeRepositoryImpl.renameTag',
      );
      // Ver `_unexpected`: un TypeError es Error, no Exception.
      // ignore: avoid_catches_without_on_clauses
    } catch (e, stackTrace) {
      return left(
        _unexpected(e, stackTrace, 'OrganizeRepositoryImpl.renameTag'),
      );
    }
    return renamed.map(_toTag);
  }

  @override
  Future<Either<Failure, Unit>> deleteTag(String id) async {
    try {
      final temaId = await temaDefinitionId(_db);
      // Borrar el valor se lleva sus asignaciones y sus alias en cascada:
      // el elemento que la tenía simplemente deja de tenerla. Solo si es de
      // Tema: por esta API no se borra un valor de otra categoría.
      await (_db.delete(
        _db.propertyValues,
      )..where((v) => v.id.equals(id) & v.definitionId.equals(temaId))).go();
      return right(unit);
      // Ver `_unexpected`: un TypeError es Error, no Exception.
      // ignore: avoid_catches_without_on_clauses
    } catch (e, stackTrace) {
      return left(
        _unexpected(e, stackTrace, 'OrganizeRepositoryImpl.deleteTag'),
      );
    }
  }

  // ---------------------------------------------------------------------
  // Relaciones
  // ---------------------------------------------------------------------

  @override
  Future<Either<Failure, Unit>> createRelation({
    required String fromItemId,
    required String toItemId,
    required RelationKind kind,
    String? note,
    int? sourceCharStart,
    int? sourceCharEnd,
  }) async {
    if (fromItemId == toItemId) {
      return left(
        const Failure.validation(
          message: 'Un elemento no puede vincularse consigo mismo.',
        ),
      );
    }

    if ((sourceCharStart == null) != (sourceCharEnd == null)) {
      return left(
        const Failure.validation(
          message: 'El rango de la fuente necesita su inicio y su fin.',
        ),
      );
    }
    if (sourceCharStart != null &&
        (kind != RelationKind.extractedFrom ||
            sourceCharStart < 0 ||
            sourceCharEnd! <= sourceCharStart)) {
      return left(
        const Failure.validation(
          message:
              'El rango de la fuente solo va en una extracción, y tiene que '
              'ir de 0 en adelante con el fin después del inicio.',
        ),
      );
    }

    try {
      final duplicate =
          await (_db.select(_db.relations)..where(
                (r) =>
                    r.fromItemId.equals(fromItemId) &
                    r.toItemId.equals(toItemId) &
                    r.kind.equalsValue(kind),
              ))
              .getSingleOrNull();

      if (duplicate != null) {
        return left(
          const Failure.validation(message: 'Ese vínculo ya existe.'),
        );
      }

      await _db
          .into(_db.relations)
          .insert(
            RelationsCompanion.insert(
              id: _ids.next(),
              fromItemId: fromItemId,
              toItemId: toItemId,
              kind: kind,
              note: Value(_nonEmpty(note)),
              sourceCharStart: Value(sourceCharStart),
              sourceCharEnd: Value(sourceCharEnd),
              createdAt: _clock(),
            ),
          );

      if (kind == RelationKind.extractedFrom) {
        // `fromItemId` es siempre la nota nueva en este tipo de vínculo
        // —así lo usa `HighlightableText._extractSelection`—, así que
        // esto corrige `noteKind` tanto ahí como en la Bandeja de
        // entrada (F3). Que la nota no exista no es un error —el escritor
        // devuelve `false` y no hace nada—: no debería pasar.
        await _writer.setNoteKind(fromItemId, NoteKind.atomic);

        // Herencia (F4): la nota nueva hereda las propiedades de la
        // fuente de la que se extrajo — extraer 8 fragmentos de un
        // video no puede costar 8 clasificaciones manuales. `origin:
        // inherited`, y `insertOrIgnore` en vez de
        // `insertOnConflictUpdate`: si la nota ya tenía esa propiedad
        // puesta a mano, el insert que choca con la clave compuesta no
        // hace nada, y el `origin: manual` original se conserva —
        // pisarlo downgradearía en silencio una decisión real del
        // usuario en cada extracción.
        final sourceProperties = await (_db.select(
          _db.itemPropertyValues,
        )..where((p) => p.itemId.equals(toItemId))).get();

        for (final property in sourceProperties) {
          await _db
              .into(_db.itemPropertyValues)
              .insert(
                ItemPropertyValuesCompanion.insert(
                  itemId: fromItemId,
                  propertyValueId: property.propertyValueId,
                  origin: const Value(ItemPropertyOrigin.inherited),
                ),
                mode: InsertMode.insertOrIgnore,
              );
        }
      }

      return right(unit);
      // Ver `_unexpected`: un TypeError es Error, no Exception.
      // ignore: avoid_catches_without_on_clauses
    } catch (e, stackTrace) {
      return left(
        _unexpected(e, stackTrace, 'OrganizeRepositoryImpl.createRelation'),
      );
    }
  }

  @override
  Future<Either<Failure, Unit>> deleteRelation(String id) async {
    try {
      await (_db.delete(_db.relations)..where((r) => r.id.equals(id))).go();
      return right(unit);
      // Ver `_unexpected`: un TypeError es Error, no Exception.
      // ignore: avoid_catches_without_on_clauses
    } catch (e, stackTrace) {
      return left(
        _unexpected(e, stackTrace, 'OrganizeRepositoryImpl.deleteRelation'),
      );
    }
  }

  @override
  Future<Either<Failure, Unit>> setRelationReviewed({
    required String relationId,
    required bool reviewed,
  }) async {
    try {
      final updated =
          await (_db.update(
            _db.relations,
          )..where((r) => r.id.equals(relationId))).writeReturning(
            RelationsCompanion(reviewedAt: Value(reviewed ? _clock() : null)),
          );

      if (updated.isEmpty) {
        return left(
          const Failure.unexpected(
            message: 'El vínculo ya no existe; puede que se haya borrado.',
          ),
        );
      }

      return right(unit);
      // Ver `_unexpected`: un TypeError es Error, no Exception.
      // ignore: avoid_catches_without_on_clauses
    } catch (e, stackTrace) {
      return left(
        _unexpected(
          e,
          stackTrace,
          'OrganizeRepositoryImpl.setRelationReviewed',
        ),
      );
    }
  }

  @override
  Stream<List<ItemRelation>> watchRelationsForItem(String itemId) {
    return watchQuery(
      db: _db,
      tables: [_db.relations, _db.knowledgeEntries, _db.knowledgeSources],
      read: () async {
        final outgoing = await _relationsQuery(
          itemId: itemId,
          direction: RelationDirection.outgoing,
        );
        final incoming = await _relationsQuery(
          itemId: itemId,
          direction: RelationDirection.incoming,
        );

        final all = [...outgoing, ...incoming]
          ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
        return all;
      },
      telemetry: _telemetry,
      hint: 'OrganizeRepositoryImpl.watchRelationsForItem',
    );
  }

  /// Una de las dos direcciones del vínculo.
  ///
  /// El "otro" elemento es siempre `toItemId` mirando hacia afuera
  /// (`outgoing`) y siempre `fromItemId` mirando hacia adentro (`incoming`).
  /// Son dos consultas y no una con un `OR` porque el join necesita saber de
  /// entrada cuál columna trae al otro elemento — con un `OR` habría que
  /// resolverlo fila por fila en Dart, que es exactamente lo que el motor de
  /// la base hace mejor.
  Future<List<ItemRelation>> _relationsQuery({
    required String itemId,
    required RelationDirection direction,
  }) async {
    final ownColumn = direction == RelationDirection.outgoing
        ? _db.relations.fromItemId
        : _db.relations.toItemId;
    final otherColumn = direction == RelationDirection.outgoing
        ? _db.relations.toItemId
        : _db.relations.fromItemId;

    final query = _db.select(_db.relations).join([
      innerJoin(
        _db.knowledgeEntries,
        _db.knowledgeEntries.id.equalsExp(otherColumn),
      ),
      // Una nota no tiene fila de fuente: por eso `LEFT`.
      leftOuterJoin(
        _db.knowledgeSources,
        _db.knowledgeSources.itemId.equalsExp(_db.knowledgeEntries.id),
      ),
    ])..where(ownColumn.equals(itemId));

    final rows = await query.get();

    return rows.map((row) {
      final relation = row.readTable(_db.relations);
      final otherItem = row.readTable(_db.knowledgeEntries);
      final otherSource = row.readTableOrNull(_db.knowledgeSources);

      return ItemRelation(
        relationId: relation.id,
        direction: direction,
        kind: relation.kind,
        createdAt: relation.createdAt,
        note: relation.note,
        otherItemId: otherItem.id,
        otherItemTitle: otherItem.title,
        otherItemSourceKind: otherSource?.sourceType ?? SourceKind.manualNote,
        sourceCharStart: relation.sourceCharStart,
        sourceCharEnd: relation.sourceCharEnd,
      );
    }).toList();
  }

  @override
  Stream<List<RelationEdge>> watchAllRelations() {
    return watchQuery(
      db: _db,
      tables: [_db.relations],
      read: () async {
        final rows = await _db.select(_db.relations).get();
        return rows
            .map(
              (row) => RelationEdge(
                id: row.id,
                fromItemId: row.fromItemId,
                toItemId: row.toItemId,
                kind: row.kind,
                reviewedAt: row.reviewedAt,
              ),
            )
            .toList();
      },
      telemetry: _telemetry,
      hint: 'OrganizeRepositoryImpl.watchAllRelations',
    );
  }

  @override
  Stream<Neighborhood> watchNeighborhood({
    required String seedItemId,
    required int maxNodes,
    int? degree = 1,
  }) {
    return watchQuery(
      db: _db,
      tables: [_db.relations],
      read: () => _readNeighborhood(seedItemId, maxNodes, degree),
      telemetry: _telemetry,
      hint: 'OrganizeRepositoryImpl.watchNeighborhood',
    );
  }

  /// Cuántos ids entran en una sola consulta: por debajo del tope de
  /// parámetros que SQLite acepta, con margen para la consulta que los usa
  /// dos veces.
  static const _idsPerQuery = 400;

  Future<Neighborhood> _readNeighborhood(
    String seedItemId,
    int maxNodes,
    int? degree,
  ) async {
    final visited = <String>{seedItemId};
    var frontier = <String>{seedItemId};
    var hop = 0;
    var omitted = 0;

    while (frontier.isNotEmpty && (degree == null || hop < degree)) {
      // Los que se alcanzan desde la frontera y todavía no se vieron, cada uno
      // con la fecha de su vínculo más reciente: es el criterio para elegir
      // cuáles entran si el tope no alcanza para todos.
      final fresh = <String, DateTime>{};
      for (final row in await _linksOf(frontier)) {
        for (final id in [row.fromItemId, row.toItemId]) {
          if (visited.contains(id)) continue;
          final seen = fresh[id];
          if (seen == null || row.createdAt.isAfter(seen)) {
            fresh[id] = row.createdAt;
          }
        }
      }
      if (fresh.isEmpty) break;

      final room = maxNodes - visited.length;
      final chosen = fresh.keys.toList()
        ..sort((a, b) => fresh[b]!.compareTo(fresh[a]!));
      if (chosen.length > room) {
        omitted = chosen.length - math.max(room, 0);
        chosen.removeRange(math.max(room, 0), chosen.length);
      }
      visited.addAll(chosen);
      frontier = chosen.toSet();
      hop++;
      // Con el tope alcanzado no se sigue: lo que haya más allá no entraría.
      if (omitted > 0) break;
    }

    if (visited.length == 1 && omitted == 0) return Neighborhood.empty;

    final edges = <RelationEdge>[];
    final ids = visited.toList();
    // Los vínculos entre los nodos elegidos. Con más de un lote, un vínculo
    // puede caer entre dos lotes distintos: se busca por el extremo de origen
    // en cada lote y se filtra el destino en Dart.
    for (var start = 0; start < ids.length; start += _idsPerQuery) {
      final batch = ids.skip(start).take(_idsPerQuery).toList();
      final rows = await (_db.select(
        _db.relations,
      )..where((r) => r.fromItemId.isIn(batch))).get();
      for (final row in rows) {
        if (!visited.contains(row.toItemId)) continue;
        edges.add(
          RelationEdge(
            id: row.id,
            fromItemId: row.fromItemId,
            toItemId: row.toItemId,
            kind: row.kind,
            reviewedAt: row.reviewedAt,
          ),
        );
      }
    }

    return Neighborhood(nodeIds: visited, edges: edges, omitted: omitted);
  }

  /// Los vínculos que tocan a alguno de [ids], en cualquiera de los dos
  /// sentidos.
  Future<List<RelationRow>> _linksOf(Set<String> ids) async {
    final list = ids.toList();
    final rows = <RelationRow>[];
    for (var start = 0; start < list.length; start += _idsPerQuery) {
      final batch = list.skip(start).take(_idsPerQuery).toList();
      rows.addAll(
        await (_db.select(_db.relations)
              ..where((r) => r.fromItemId.isIn(batch) | r.toItemId.isIn(batch)))
            .get(),
      );
    }
    return rows;
  }

  // ---------------------------------------------------------------------
  // Resaltados
  // ---------------------------------------------------------------------

  @override
  Future<Either<Failure, Highlight>> createHighlight({
    required String renditionId,
    required int startOffset,
    required int endOffset,
    required String excerpt,
    String? note,
  }) async {
    if (startOffset < 0 || endOffset <= startOffset) {
      return left(
        const Failure.validation(message: 'La selección no es válida.'),
      );
    }

    try {
      final id = _ids.next();
      final createdAt = _clock();

      await _db
          .into(_db.highlights)
          .insert(
            HighlightsCompanion.insert(
              id: id,
              renditionId: renditionId,
              startOffset: startOffset,
              endOffset: endOffset,
              excerpt: excerpt,
              note: Value(_nonEmpty(note)),
              createdAt: createdAt,
            ),
          );

      return right(
        Highlight(
          id: id,
          renditionId: renditionId,
          startOffset: startOffset,
          endOffset: endOffset,
          excerpt: excerpt,
          createdAt: createdAt,
          note: _nonEmpty(note),
        ),
      );
      // Ver `_unexpected`: un TypeError es Error, no Exception.
      // ignore: avoid_catches_without_on_clauses
    } catch (e, stackTrace) {
      return left(
        _unexpected(e, stackTrace, 'OrganizeRepositoryImpl.createHighlight'),
      );
    }
  }

  @override
  Future<Either<Failure, Highlight>> updateHighlightNote({
    required String id,
    required String? note,
  }) async {
    try {
      final updated =
          await (_db.update(
            _db.highlights,
          )..where((h) => h.id.equals(id))).writeReturning(
            HighlightsCompanion(note: Value(_nonEmpty(note))),
          );

      final row = updated.singleOrNull;
      if (row == null) {
        return left(
          const Failure.unexpected(
            message: 'El resaltado ya no existe; puede que se haya borrado.',
          ),
        );
      }

      return right(_toHighlight(row));
      // Ver `_unexpected`: un TypeError es Error, no Exception.
      // ignore: avoid_catches_without_on_clauses
    } catch (e, stackTrace) {
      return left(
        _unexpected(
          e,
          stackTrace,
          'OrganizeRepositoryImpl.updateHighlightNote',
        ),
      );
    }
  }

  @override
  Future<Either<Failure, Unit>> deleteHighlight(String id) async {
    try {
      await (_db.delete(_db.highlights)..where((h) => h.id.equals(id))).go();
      return right(unit);
      // Ver `_unexpected`: un TypeError es Error, no Exception.
      // ignore: avoid_catches_without_on_clauses
    } catch (e, stackTrace) {
      return left(
        _unexpected(e, stackTrace, 'OrganizeRepositoryImpl.deleteHighlight'),
      );
    }
  }

  @override
  Stream<List<Highlight>> watchHighlightsForRendition(String renditionId) {
    return watchQuery(
      db: _db,
      tables: [_db.highlights],
      read: () async {
        final rows =
            await (_db.select(_db.highlights)
                  ..where((h) => h.renditionId.equals(renditionId))
                  ..orderBy([(h) => OrderingTerm(expression: h.startOffset)]))
                .get();
        return rows.map(_toHighlight).toList();
      },
      telemetry: _telemetry,
      hint: 'OrganizeRepositoryImpl.watchHighlightsForRendition',
    );
  }

  // ---------------------------------------------------------------------
  // Espacios
  // ---------------------------------------------------------------------

  @override
  Stream<List<Space>> watchAllSpaces() {
    return watchQuery(
      db: _db,
      tables: [_db.spaces],
      read: () async {
        final rows = await (_db.select(
          _db.spaces,
        )..orderBy([(s) => OrderingTerm(expression: s.name)])).get();
        return rows.map(_toSpace).toList();
      },
      telemetry: _telemetry,
      hint: 'OrganizeRepositoryImpl.watchAllSpaces',
    );
  }

  @override
  Future<Either<Failure, Space>> createSpace(String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      return left(
        const Failure.validation(message: 'El nombre no puede quedar vacío.'),
      );
    }

    try {
      final clash =
          await (_db.select(_db.spaces)
                ..where((s) => s.name.lower().equals(trimmed.toLowerCase())))
              .getSingleOrNull();
      if (clash != null) {
        return left(
          Failure.validation(message: 'Ya existe un espacio "$trimmed".'),
        );
      }

      final space = Space(id: _ids.next(), name: trimmed, createdAt: _clock());
      await _db
          .into(_db.spaces)
          .insert(
            SpacesCompanion.insert(
              id: space.id,
              name: space.name,
              createdAt: space.createdAt,
            ),
          );

      return right(space);
      // Ver `_unexpected`: un TypeError es Error, no Exception.
      // ignore: avoid_catches_without_on_clauses
    } catch (e, stackTrace) {
      return left(
        _unexpected(e, stackTrace, 'OrganizeRepositoryImpl.createSpace'),
      );
    }
  }

  @override
  Future<Either<Failure, Space>> renameSpace({
    required String id,
    required String name,
  }) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      return left(
        const Failure.validation(message: 'El nombre no puede quedar vacío.'),
      );
    }

    try {
      final clash =
          await (_db.select(_db.spaces)..where(
                (s) =>
                    s.name.lower().equals(trimmed.toLowerCase()) &
                    s.id.equals(id).not(),
              ))
              .getSingleOrNull();
      if (clash != null) {
        return left(
          Failure.validation(message: 'Ya existe un espacio "$trimmed".'),
        );
      }

      final updated =
          await (_db.update(_db.spaces)..where((s) => s.id.equals(id)))
              .writeReturning(SpacesCompanion(name: Value(trimmed)));

      final row = updated.singleOrNull;
      if (row == null) {
        return left(
          const Failure.unexpected(
            message: 'El espacio ya no existe; puede que se haya borrado.',
          ),
        );
      }

      return right(_toSpace(row));
      // Ver `_unexpected`: un TypeError es Error, no Exception.
      // ignore: avoid_catches_without_on_clauses
    } catch (e, stackTrace) {
      return left(
        _unexpected(e, stackTrace, 'OrganizeRepositoryImpl.renameSpace'),
      );
    }
  }

  @override
  Future<Either<Failure, Unit>> deleteSpace(String id) async {
    try {
      await (_db.delete(_db.spaces)..where((s) => s.id.equals(id))).go();
      return right(unit);
      // Ver `_unexpected`: un TypeError es Error, no Exception.
      // ignore: avoid_catches_without_on_clauses
    } catch (e, stackTrace) {
      return left(
        _unexpected(e, stackTrace, 'OrganizeRepositoryImpl.deleteSpace'),
      );
    }
  }

  // ---------------------------------------------------------------------
  // Propiedades
  // ---------------------------------------------------------------------

  @override
  Stream<List<PropertyDefinition>> watchAllPropertyDefinitions() {
    return watchQuery(
      db: _db,
      tables: [_db.propertyDefinitions],
      read: () async {
        final rows = await (_db.select(
          _db.propertyDefinitions,
        )..orderBy([(d) => OrderingTerm(expression: d.name)])).get();
        return rows.map(_toPropertyDefinition).toList();
      },
      telemetry: _telemetry,
      hint: 'OrganizeRepositoryImpl.watchAllPropertyDefinitions',
    );
  }

  @override
  Future<Either<Failure, PropertyDefinition>> getOrCreatePropertyDefinition(
    String name, {
    PropertyValueType type = PropertyValueType.text,
  }) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      return left(
        const Failure.validation(message: 'El nombre no puede quedar vacío.'),
      );
    }

    try {
      final existing =
          await (_db.select(_db.propertyDefinitions)
                ..where((d) => d.name.lower().equals(trimmed.toLowerCase())))
              .getSingleOrNull();
      if (existing != null) return right(_toPropertyDefinition(existing));

      final definition = PropertyDefinition(
        id: _ids.next(),
        name: trimmed,
        createdAt: _clock(),
        type: type,
      );
      await _db
          .into(_db.propertyDefinitions)
          .insert(
            PropertyDefinitionsCompanion.insert(
              id: definition.id,
              name: definition.name,
              createdAt: definition.createdAt,
              type: Value(definition.type),
            ),
          );

      return right(definition);
      // Ver `_unexpected`: un TypeError es Error, no Exception.
      // ignore: avoid_catches_without_on_clauses
    } catch (e, stackTrace) {
      return left(
        _unexpected(
          e,
          stackTrace,
          'OrganizeRepositoryImpl.getOrCreatePropertyDefinition',
        ),
      );
    }
  }

  @override
  Future<Either<Failure, Unit>> deletePropertyDefinition(String id) async {
    try {
      final existing = await (_db.select(
        _db.propertyDefinitions,
      )..where((d) => d.id.equals(id))).getSingleOrNull();
      if (existing != null && existing.isSystem) {
        return left(
          const Failure.validation(
            message: 'Esta categoría la crea la app: no se puede borrar.',
          ),
        );
      }

      await (_db.delete(
        _db.propertyDefinitions,
      )..where((d) => d.id.equals(id))).go();
      return right(unit);
      // Ver `_unexpected`: un TypeError es Error, no Exception.
      // ignore: avoid_catches_without_on_clauses
    } catch (e, stackTrace) {
      return left(
        _unexpected(
          e,
          stackTrace,
          'OrganizeRepositoryImpl.deletePropertyDefinition',
        ),
      );
    }
  }

  @override
  Stream<List<PropertyValue>> watchPropertyValues(String definitionId) {
    return watchQuery(
      db: _db,
      tables: [_db.propertyValues],
      read: () async {
        final rows =
            await (_db.select(_db.propertyValues)
                  ..where((v) => v.definitionId.equals(definitionId))
                  ..orderBy([(v) => OrderingTerm(expression: v.value)]))
                .get();
        return rows.map(_toPropertyValue).toList();
      },
      telemetry: _telemetry,
      hint: 'OrganizeRepositoryImpl.watchPropertyValues',
    );
  }

  @override
  Future<Either<Failure, Unit>> assignProperty({
    required String itemId,
    required String definitionId,
    required String value,
    ItemPropertyOrigin origin = ItemPropertyOrigin.manual,
  }) async {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      return left(
        const Failure.validation(message: 'El valor no puede quedar vacío.'),
      );
    }

    try {
      // Por label o por alias, sin distinguir acentos: escribir
      // "Constantinopla" —alias de "Bizancio"— asigna "Bizancio" en vez de
      // crear un valor duplicado.
      final existing = await _findValueByLabelOrAlias(definitionId, trimmed);

      final propertyValueId = existing?.id ?? _ids.next();
      if (existing == null) {
        await _db
            .into(_db.propertyValues)
            .insert(
              PropertyValuesCompanion.insert(
                id: propertyValueId,
                definitionId: definitionId,
                value: trimmed,
                createdAt: _clock(),
              ),
            );
      }

      await _db
          .into(_db.itemPropertyValues)
          .insertOnConflictUpdate(
            ItemPropertyValuesCompanion.insert(
              itemId: itemId,
              propertyValueId: propertyValueId,
              origin: Value(origin),
            ),
          );

      return right(unit);
      // Ver `_unexpected`: un TypeError es Error, no Exception.
      // ignore: avoid_catches_without_on_clauses
    } catch (e, stackTrace) {
      return left(
        _unexpected(e, stackTrace, 'OrganizeRepositoryImpl.assignProperty'),
      );
    }
  }

  @override
  Future<Either<Failure, Unit>> removeItemProperty({
    required String itemId,
    required String propertyValueId,
  }) async {
    try {
      await (_db.delete(_db.itemPropertyValues)..where(
            (it) =>
                it.itemId.equals(itemId) &
                it.propertyValueId.equals(propertyValueId),
          ))
          .go();
      return right(unit);
      // Ver `_unexpected`: un TypeError es Error, no Exception.
      // ignore: avoid_catches_without_on_clauses
    } catch (e, stackTrace) {
      return left(
        _unexpected(e, stackTrace, 'OrganizeRepositoryImpl.removeItemProperty'),
      );
    }
  }

  @override
  Future<Either<Failure, PropertyValue>> renamePropertyValue({
    required String id,
    required String label,
  }) async {
    final Either<Failure, PropertyValueRow> renamed;
    try {
      renamed = await _renameValue(
        id: id,
        label: label,
        blankMessage: 'El valor no puede quedar vacío.',
        missingMessage: 'El valor ya no existe; puede que se haya borrado.',
        clashMessage: (label) => 'Ya existe un valor "$label".',
        hint: 'OrganizeRepositoryImpl.renamePropertyValue',
      );
      // Ver `_unexpected`: un TypeError es Error, no Exception.
      // ignore: avoid_catches_without_on_clauses
    } catch (e, stackTrace) {
      return left(
        _unexpected(
          e,
          stackTrace,
          'OrganizeRepositoryImpl.renamePropertyValue',
        ),
      );
    }
    return renamed.map(_toPropertyValue);
  }

  @override
  Future<Either<Failure, PropertyValue?>> resolvePropertyValue({
    required String definitionId,
    required String text,
  }) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return right(null);

    try {
      final found = await _findValueByLabelOrAlias(definitionId, trimmed);
      return right(found == null ? null : _toPropertyValue(found));
      // Ver `_unexpected`: un TypeError es Error, no Exception.
      // ignore: avoid_catches_without_on_clauses
    } catch (e, stackTrace) {
      return left(
        _unexpected(
          e,
          stackTrace,
          'OrganizeRepositoryImpl.resolvePropertyValue',
        ),
      );
    }
  }

  @override
  Future<Either<Failure, Unit>> mergePropertyValues({
    required String keepId,
    required String discardId,
  }) async {
    if (keepId == discardId) {
      return left(
        const Failure.validation(
          message: 'Un valor no se puede fusionar consigo mismo.',
        ),
      );
    }

    try {
      final keep = await (_db.select(
        _db.propertyValues,
      )..where((v) => v.id.equals(keepId))).getSingleOrNull();
      final discard = await (_db.select(
        _db.propertyValues,
      )..where((v) => v.id.equals(discardId))).getSingleOrNull();
      if (keep == null || discard == null) {
        return left(
          const Failure.unexpected(
            message:
                'Uno de los dos valores ya no existe; puede que se haya '
                'borrado.',
          ),
        );
      }
      if (keep.definitionId != discard.definitionId) {
        return left(
          const Failure.validation(
            message: 'No se puede fusionar valores de categorías distintas.',
          ),
        );
      }

      // Los cinco pasos de la fusión viven a nivel de base: los comparte con
      // la reconciliación de etiquetas de la migración.
      await _db.transaction(
        () => mergePropertyValueRows(
          _db,
          keep: keep,
          discard: discard,
          ids: _ids,
          clock: _clock,
        ),
      );

      return right(unit);
      // Ver `_unexpected`: un TypeError es Error, no Exception.
      // ignore: avoid_catches_without_on_clauses
    } catch (e, stackTrace) {
      return left(
        _unexpected(
          e,
          stackTrace,
          'OrganizeRepositoryImpl.mergePropertyValues',
        ),
      );
    }
  }

  @override
  Future<Either<Failure, PropertyValue>> getOrCreateHistoricalPropertyValue({
    required String definitionId,
    required HistoricalDate date,
  }) async {
    try {
      final definition = await (_db.select(
        _db.propertyDefinitions,
      )..where((d) => d.id.equals(definitionId))).getSingleOrNull();
      if (definition == null) {
        return left(
          const Failure.validation(message: 'La categoría no existe.'),
        );
      }
      if (definition.type != PropertyValueType.date) {
        return left(
          const Failure.validation(
            message: 'Esta categoría no es de tipo fecha.',
          ),
        );
      }

      final label = date.label;
      final existing =
          await (_db.select(_db.propertyValues)..where(
                (v) =>
                    v.definitionId.equals(definitionId) &
                    v.value.lower().equals(label.toLowerCase()),
              ))
              .getSingleOrNull();
      if (existing != null) return right(_toPropertyValue(existing));

      final rangeStart = date.rangeStart;
      final rangeEnd = date.rangeEnd;
      final id = _ids.next();
      final createdAt = _clock();
      await _db
          .into(_db.propertyValues)
          .insert(
            PropertyValuesCompanion.insert(
              id: id,
              definitionId: definitionId,
              value: label,
              createdAt: createdAt,
              dateFromYear: Value(rangeStart.year),
              dateFromMonth: Value(rangeStart.month),
              dateFromDay: Value(rangeStart.day),
              dateToYear: Value(rangeEnd.year),
              dateToMonth: Value(rangeEnd.month),
              dateToDay: Value(rangeEnd.day),
              datePrecision: Value(date.precision),
              dateIsCirca: Value(date.isCirca),
            ),
          );

      return right(
        PropertyValue(
          id: id,
          definitionId: definitionId,
          value: label,
          createdAt: createdAt,
          historicalDate: date,
        ),
      );
      // Ver `_unexpected`: un TypeError es Error, no Exception.
      // ignore: avoid_catches_without_on_clauses
    } catch (e, stackTrace) {
      return left(
        _unexpected(
          e,
          stackTrace,
          'OrganizeRepositoryImpl.getOrCreateHistoricalPropertyValue',
        ),
      );
    }
  }

  // ---------------------------------------------------------------------
  // Utilidades
  // ---------------------------------------------------------------------

  /// Ver `findValueByLabelOrAlias`: la comparten este repositorio y el de
  /// Vocabulario, y los dos tienen que decidir igual qué es "el mismo texto".
  Future<PropertyValueRow?> _findValueByLabelOrAlias(
    String definitionId,
    String text, {
    String? excludingValueId,
  }) => findValueByLabelOrAlias(
    _db,
    definitionId,
    text,
    excludingValueId: excludingValueId,
  );

  /// El renombrado que comparten etiquetas y valores: lo único que cambia
  /// entre los dos son los mensajes y, para una etiqueta, que el valor tiene
  /// que ser de Tema ([onlyInDefinition]).
  ///
  /// Sin distinguir mayúsculas ni acentos, y solo dentro de la misma
  /// categoría: "Roma" bajo "Región" y "Roma" bajo "Ciudad natal" no
  /// compiten entre sí, mismo criterio que el UNIQUE de PropertyAlias. El
  /// propio valor queda afuera de la comparación de labels —cambiar "Roma"
  /// por "Róma" es corregir su grafía, no chocar consigo mismo—, pero no de
  /// la de alias: uno suyo también bloquea el nombre.
  ///
  /// Puede lanzar: quien llama lo convierte en `Failure`.
  Future<Either<Failure, PropertyValueRow>> _renameValue({
    required String id,
    required String label,
    required String blankMessage,
    required String missingMessage,
    required String Function(String label) clashMessage,
    required String hint,
    String? onlyInDefinition,
  }) async {
    final trimmed = label.trim();
    if (trimmed.isEmpty) {
      return left(Failure.validation(message: blankMessage));
    }

    final current = await (_db.select(
      _db.propertyValues,
    )..where((v) => v.id.equals(id))).getSingleOrNull();
    if (current == null ||
        (onlyInDefinition != null &&
            current.definitionId != onlyInDefinition)) {
      return left(Failure.unexpected(message: missingMessage));
    }

    final clash = await _findValueByLabelOrAlias(
      current.definitionId,
      trimmed,
      excludingValueId: id,
    );
    if (clash != null) {
      return left(Failure.validation(message: clashMessage(trimmed)));
    }

    final updated =
        await (_db.update(_db.propertyValues)..where((v) => v.id.equals(id)))
            .writeReturning(PropertyValuesCompanion(value: Value(trimmed)));
    return right(updated.single);
  }

  Tag _toTag(PropertyValueRow row) =>
      Tag(id: row.id, name: row.value, createdAt: row.createdAt);

  Space _toSpace(SpaceRow row) =>
      Space(id: row.id, name: row.name, createdAt: row.createdAt);

  PropertyDefinition _toPropertyDefinition(PropertyDefinitionRow row) =>
      PropertyDefinition(
        id: row.id,
        name: row.name,
        createdAt: row.createdAt,
        type: row.type,
        isSystem: row.isSystem,
      );

  PropertyValue _toPropertyValue(PropertyValueRow row) => PropertyValue(
    id: row.id,
    definitionId: row.definitionId,
    value: row.value,
    createdAt: row.createdAt,
    numberValue: row.numberValue,
    historicalDate: _toHistoricalDate(row),
  );

  /// `null` salvo que la fila venga de una categoría de tipo fecha —ahí
  /// viaja siempre `datePrecision`, así que su presencia es la señal de
  /// que hay una fecha que reconstruir—.
  HistoricalDate? _toHistoricalDate(PropertyValueRow row) {
    final precision = row.datePrecision;
    if (precision == null) return null;

    return HistoricalDate.fromStored(
      astronomicalYear: row.dateFromYear!,
      precision: precision,
      month: row.dateFromMonth,
      day: row.dateFromDay,
      isCirca: row.dateIsCirca,
    );
  }

  Highlight _toHighlight(HighlightRow row) => Highlight(
    id: row.id,
    renditionId: row.renditionId,
    startOffset: row.startOffset,
    endOffset: row.endOffset,
    excerpt: row.excerpt,
    createdAt: row.createdAt,
    note: row.note,
  );

  /// Una nota en blanco cuenta como ausente: un campo de texto vacío no es lo
  /// mismo que "sin nota" en la interfaz, pero para guardar es exactamente lo
  /// mismo, y guardar `''` dejaría una nota fantasma que se ve vacía pero
  /// está "puesta".
  String? _nonEmpty(String? value) {
    final trimmed = value?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }

  /// Catch-all deliberado, igual que en el resto de los repositorios: un
  /// `TypeError` es `Error`, no `Exception`, y atrapar solo `Exception` lo
  /// dejaría escapar dejando a quien llamó esperando una respuesta que nunca
  /// llega.
  Failure _unexpected(Object e, StackTrace stackTrace, String hint) {
    _telemetry.recordError(e, stackTrace, hint: hint);
    return Failure.unexpected(message: e.toString());
  }
}
