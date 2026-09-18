import 'package:drift/drift.dart';
import 'package:fpdart/fpdart.dart';
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/database/watching_query.dart';
import 'package:sinapsis/core/domain/entities/date_precision.dart';
import 'package:sinapsis/core/domain/entities/highlight.dart';
import 'package:sinapsis/core/domain/entities/historical_date.dart';
import 'package:sinapsis/core/domain/entities/item_relation.dart';
import 'package:sinapsis/core/domain/entities/note_kind.dart';
import 'package:sinapsis/core/domain/entities/property_definition.dart';
import 'package:sinapsis/core/domain/entities/property_value.dart';
import 'package:sinapsis/core/domain/entities/property_value_type.dart';
import 'package:sinapsis/core/domain/entities/relation_edge.dart';
import 'package:sinapsis/core/domain/entities/relation_kind.dart';
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

  // ---------------------------------------------------------------------
  // Etiquetas
  // ---------------------------------------------------------------------

  @override
  Stream<List<Tag>> watchAllTags() {
    return watchQuery(
      db: _db,
      tables: [_db.tags],
      read: () async {
        final rows = await (_db.select(
          _db.tags,
        )..orderBy([(t) => OrderingTerm(expression: t.name)])).get();
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
      final existing =
          await (_db.select(_db.tags)
                ..where((t) => t.name.lower().equals(trimmed.toLowerCase())))
              .getSingleOrNull();

      if (existing != null) return right(_toTag(existing));

      final tag = Tag(id: _ids.next(), name: trimmed, createdAt: _clock());
      await _db
          .into(_db.tags)
          .insert(
            TagsCompanion.insert(
              id: tag.id,
              name: tag.name,
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
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      return left(
        const Failure.validation(message: 'El nombre no puede quedar vacío.'),
      );
    }

    try {
      // Sin distinguir mayúsculas, igual que la restricción de la base:
      // "Filosofía" y "filosofía" tienen que seguir siendo la misma
      // etiqueta. Se comprueba acá para poder explicar qué pasó — la
      // restricción de la base solo daría una excepción cruda.
      final clash =
          await (_db.select(_db.tags)..where(
                (t) =>
                    t.name.lower().equals(trimmed.toLowerCase()) &
                    t.id.equals(id).not(),
              ))
              .getSingleOrNull();

      if (clash != null) {
        return left(
          Failure.validation(message: 'Ya existe una etiqueta "$trimmed".'),
        );
      }

      final updated =
          await (_db.update(_db.tags)..where((t) => t.id.equals(id)))
              .writeReturning(TagsCompanion(name: Value(trimmed)));

      final row = updated.singleOrNull;
      if (row == null) {
        // Se borró entre que se abrió el diálogo de renombrar y se confirmó.
        return left(
          const Failure.unexpected(
            message: 'La etiqueta ya no existe; puede que se haya borrado.',
          ),
        );
      }

      return right(_toTag(row));
      // Ver `_unexpected`: un TypeError es Error, no Exception.
      // ignore: avoid_catches_without_on_clauses
    } catch (e, stackTrace) {
      return left(
        _unexpected(e, stackTrace, 'OrganizeRepositoryImpl.renameTag'),
      );
    }
  }

  @override
  Future<Either<Failure, Unit>> deleteTag(String id) async {
    try {
      await (_db.delete(_db.tags)..where((t) => t.id.equals(id))).go();
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
  }) async {
    if (fromItemId == toItemId) {
      return left(
        const Failure.validation(
          message: 'Un elemento no puede vincularse consigo mismo.',
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
              createdAt: _clock(),
            ),
          );

      if (kind == RelationKind.extractedFrom) {
        // `fromItemId` es siempre la nota nueva en este tipo de vínculo
        // —así lo usa `HighlightableText._extractSelection`—, así que
        // esto corrige `noteKind` tanto ahí como en la futura Bandeja de
        // entrada (F3). Un UPDATE que no afecta ninguna fila no es un
        // error: no debería pasar, pero el espejo de esa nota podría no
        // existir todavía.
        await (_db.update(
          _db.knowledgeNotes,
        )..where((n) => n.itemId.equals(fromItemId))).write(
          const KnowledgeNotesCompanion(noteKind: Value(NoteKind.atomic)),
        );
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
  Stream<List<ItemRelation>> watchRelationsForItem(String itemId) {
    return watchQuery(
      db: _db,
      tables: [_db.relations, _db.items, _db.sources],
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
      innerJoin(_db.items, _db.items.id.equalsExp(otherColumn)),
      innerJoin(_db.sources, _db.sources.id.equalsExp(_db.items.sourceId)),
    ])..where(ownColumn.equals(itemId));

    final rows = await query.get();

    return rows.map((row) {
      final relation = row.readTable(_db.relations);
      final otherItem = row.readTable(_db.items);
      final otherSource = row.readTable(_db.sources);

      return ItemRelation(
        relationId: relation.id,
        direction: direction,
        kind: relation.kind,
        createdAt: relation.createdAt,
        note: relation.note,
        otherItemId: otherItem.id,
        otherItemTitle: otherItem.title,
        otherItemSourceKind: otherSource.kind,
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
              ),
            )
            .toList();
      },
      telemetry: _telemetry,
      hint: 'OrganizeRepositoryImpl.watchAllRelations',
    );
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
  }) async {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      return left(
        const Failure.validation(message: 'El valor no puede quedar vacío.'),
      );
    }

    try {
      final existing =
          await (_db.select(_db.propertyValues)..where(
                (v) =>
                    v.definitionId.equals(definitionId) &
                    v.value.lower().equals(trimmed.toLowerCase()),
              ))
              .getSingleOrNull();

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
    final trimmed = label.trim();
    if (trimmed.isEmpty) {
      return left(
        const Failure.validation(message: 'El valor no puede quedar vacío.'),
      );
    }

    try {
      final current = await (_db.select(
        _db.propertyValues,
      )..where((v) => v.id.equals(id))).getSingleOrNull();
      if (current == null) {
        return left(
          const Failure.unexpected(
            message: 'El valor ya no existe; puede que se haya borrado.',
          ),
        );
      }

      // Sin distinguir mayúsculas, y solo dentro de la misma categoría:
      // "Roma" bajo "Región" y "Roma" bajo "Ciudad natal" no compiten
      // entre sí, mismo criterio que el UNIQUE de PropertyAlias.
      final valueClash =
          await (_db.select(_db.propertyValues)..where(
                (v) =>
                    v.definitionId.equals(current.definitionId) &
                    v.value.lower().equals(trimmed.toLowerCase()) &
                    v.id.equals(id).not(),
              ))
              .getSingleOrNull();
      if (valueClash != null) {
        return left(
          Failure.validation(message: 'Ya existe un valor "$trimmed".'),
        );
      }

      final aliasClash =
          await (_db.select(_db.propertyAliases)..where(
                (a) =>
                    a.definitionId.equals(current.definitionId) &
                    a.alias.lower().equals(trimmed.toLowerCase()),
              ))
              .getSingleOrNull();
      if (aliasClash != null) {
        return left(
          Failure.validation(message: 'Ya existe un valor "$trimmed".'),
        );
      }

      final updated =
          await (_db.update(_db.propertyValues)..where((v) => v.id.equals(id)))
              .writeReturning(PropertyValuesCompanion(value: Value(trimmed)));

      return right(_toPropertyValue(updated.single));
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
  }

  @override
  Future<Either<Failure, PropertyValue?>> resolvePropertyValue({
    required String definitionId,
    required String text,
  }) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return right(null);

    try {
      final byLabel =
          await (_db.select(_db.propertyValues)..where(
                (v) =>
                    v.definitionId.equals(definitionId) &
                    v.value.lower().equals(trimmed.toLowerCase()),
              ))
              .getSingleOrNull();
      if (byLabel != null) return right(_toPropertyValue(byLabel));

      final alias =
          await (_db.select(_db.propertyAliases)..where(
                (a) =>
                    a.definitionId.equals(definitionId) &
                    a.alias.lower().equals(trimmed.toLowerCase()),
              ))
              .getSingleOrNull();
      if (alias == null) return right(null);

      final byAlias = await (_db.select(
        _db.propertyValues,
      )..where((v) => v.id.equals(alias.propertyValueId))).getSingleOrNull();

      return right(byAlias == null ? null : _toPropertyValue(byAlias));
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

      await _db.transaction(() async {
        // 1. Si un item ya tenía asignadas ambas, la fila de discardId
        // sobra: borrarla antes de reapuntar el resto, para no chocar
        // con la clave primaria compuesta de ItemPropertyValues en el
        // paso 2.
        final assignments = await (_db.select(
          _db.itemPropertyValues,
        )..where((t) => t.propertyValueId.equals(discardId))).get();
        for (final assignment in assignments) {
          final alreadyHasKeep =
              await (_db.select(_db.itemPropertyValues)..where(
                    (t) =>
                        t.itemId.equals(assignment.itemId) &
                        t.propertyValueId.equals(keepId),
                  ))
                  .getSingleOrNull();
          if (alreadyHasKeep != null) {
            await (_db.delete(_db.itemPropertyValues)..where(
                  (t) =>
                      t.itemId.equals(assignment.itemId) &
                      t.propertyValueId.equals(discardId),
                ))
                .go();
          }
        }

        // 2. El resto de las asignaciones de discardId pasan a keepId.
        await (_db.update(_db.itemPropertyValues)
              ..where((t) => t.propertyValueId.equals(discardId)))
            .write(ItemPropertyValuesCompanion(propertyValueId: Value(keepId)));

        // 3. Los alias que ya apuntaban a discardId pasan a keepId
        // —ANTES de borrar discardId: su FK es ON DELETE CASCADE, y
        // borrarlo primero se los llevaría con él—.
        await (_db.update(_db.propertyAliases)
              ..where((a) => a.propertyValueId.equals(discardId)))
            .write(PropertyAliasesCompanion(propertyValueId: Value(keepId)));

        // 4. El label de discardId queda como alias nuevo de keepId,
        // salvo que ese texto ya sea un alias de otra cosa en la misma
        // categoría —de otro valor, o de keepId mismo—: se tolera sin
        // fallar la fusión entera por un solo alias que no se pudo
        // sumar.
        final aliasClash =
            await (_db.select(_db.propertyAliases)..where(
                  (a) =>
                      a.definitionId.equals(keep.definitionId) &
                      a.alias.lower().equals(discard.value.toLowerCase()),
                ))
                .getSingleOrNull();
        if (aliasClash == null) {
          await _db
              .into(_db.propertyAliases)
              .insert(
                PropertyAliasesCompanion.insert(
                  id: _ids.next(),
                  propertyValueId: keepId,
                  definitionId: keep.definitionId,
                  alias: discard.value,
                  createdAt: _clock(),
                ),
              );
        }

        // 5. discardId ya no tiene nada que solo él tuviera: se borra.
        await (_db.delete(
          _db.propertyValues,
        )..where((v) => v.id.equals(discardId))).go();
      });

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

  Tag _toTag(TagRow row) =>
      Tag(id: row.id, name: row.name, createdAt: row.createdAt);

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
  /// que hay una fecha que reconstruir—. `month`/`day` solo importan
  /// para las precisiones que los usan: para el resto son `null` en el
  /// [HistoricalDate] original, aunque `dateFromMonth`/`dateFromDay`
  /// guarden 1 (el primer día del rango) para toda otra precisión.
  HistoricalDate? _toHistoricalDate(PropertyValueRow row) {
    final precision = row.datePrecision;
    if (precision == null) return null;

    final usesMonth =
        precision == DatePrecision.day || precision == DatePrecision.month;
    return HistoricalDate.fromAstronomicalYear(
      row.dateFromYear!,
      precision: precision,
      month: usesMonth ? row.dateFromMonth : null,
      day: precision == DatePrecision.day ? row.dateFromDay : null,
      isCirca: row.dateIsCirca ?? false,
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
