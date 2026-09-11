import 'package:drift/drift.dart';
import 'package:fpdart/fpdart.dart';
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/database/watching_query.dart';
import 'package:sinapsis/core/domain/entities/highlight.dart';
import 'package:sinapsis/core/domain/entities/item_relation.dart';
import 'package:sinapsis/core/domain/entities/relation_kind.dart';
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
  // Utilidades
  // ---------------------------------------------------------------------

  Tag _toTag(TagRow row) =>
      Tag(id: row.id, name: row.name, createdAt: row.createdAt);

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
