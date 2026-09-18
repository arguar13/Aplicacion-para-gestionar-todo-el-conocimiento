import 'package:drift/drift.dart';
import 'package:fpdart/fpdart.dart';
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/error/failures.dart';
import 'package:sinapsis/core/telemetry/telemetry_service.dart';
import 'package:sinapsis/core/util/clock.dart';
import 'package:sinapsis/core/util/id_generator.dart';
import 'package:sinapsis/features/duplicates/domain/usecases/merge_duplicate_items_usecase.dart';
import 'package:sinapsis/features/library/domain/repositories/library_repository.dart';

/// [MergeDuplicateItemsUseCase] contra `AppDatabase` directo —igual que
/// `OrganizeRepositoryImpl.mergePropertyValues` (F2), el precedente de
/// cómo reasignar referencias tolerando conflictos antes de borrar lo
/// descartado, aplicado acá a un elemento entero en vez de a un solo
/// valor de propiedad.
class MergeDuplicateItemsUseCaseImpl implements MergeDuplicateItemsUseCase {
  const MergeDuplicateItemsUseCaseImpl({
    required AppDatabase database,
    required LibraryRepository library,
    required IdGenerator ids,
    required Clock clock,
    required TelemetryService telemetry,
  }) : _db = database,
       _library = library,
       _ids = ids,
       _clock = clock,
       _telemetry = telemetry;

  final AppDatabase _db;
  final LibraryRepository _library;
  final IdGenerator _ids;
  final Clock _clock;
  final TelemetryService _telemetry;

  @override
  Future<Either<Failure, Unit>> call({
    required String keepItemId,
    required String discardItemId,
  }) async {
    if (keepItemId == discardItemId) {
      return left(
        const Failure.validation(
          message: 'Un elemento no se puede fusionar consigo mismo.',
        ),
      );
    }

    try {
      final discardItem = await (_db.select(
        _db.items,
      )..where((i) => i.id.equals(discardItemId))).getSingleOrNull();
      final keepItem = await (_db.select(
        _db.items,
      )..where((i) => i.id.equals(keepItemId))).getSingleOrNull();
      if (discardItem == null || keepItem == null) {
        return left(
          const Failure.unexpected(
            message:
                'Uno de los dos elementos ya no existe; puede que se haya '
                'borrado.',
          ),
        );
      }

      final discardSource = await (_db.select(
        _db.sources,
      )..where((s) => s.id.equals(discardItem.sourceId))).getSingle();

      await _db.transaction(() async {
        await _reassignRelations(keepItemId, discardItemId);
        await _reassignTags(keepItemId, discardItemId);
        await _reassignProperties(keepItemId, discardItemId);
        await _reassignFlashcards(keepItemId, discardItemId);
        await _reassignRenditions(keepItemId, discardItemId);

        await _db
            .into(_db.mergedProvenances)
            .insert(
              MergedProvenancesCompanion.insert(
                id: _ids.next(),
                itemId: keepItemId,
                sourceKind: discardSource.kind,
                url: Value(discardSource.url),
                authorName: Value(discardSource.authorName),
                authorUrl: Value(discardSource.authorUrl),
                publishedAt: Value(discardSource.publishedAt),
                capturedAt: discardSource.capturedAt,
                mergedAt: _clock(),
              ),
            );
      });

      final deleted = await _library.delete(discardItemId);
      final deleteFailure = deleted.getLeft().toNullable();
      if (deleteFailure != null) return left(deleteFailure);

      return right(unit);
      // Ver `_unexpected` más abajo: un TypeError es Error, no Exception.
      // ignore: avoid_catches_without_on_clauses
    } catch (e, stackTrace) {
      return left(_unexpected(e, stackTrace));
    }
  }

  /// Los vínculos del descartado pasan al que queda. Uno *entre* los dos
  /// duplicados se borra sin más: reasignarlo lo convertiría en una
  /// auto-relación, que el `CHECK` de la tabla prohíbe. Uno que el que
  /// queda ya tiene, con el mismo otro extremo y el mismo tipo, también
  /// se borra en vez de reasignarse: el `UNIQUE` de la tabla lo
  /// impediría igual, y no hace falta conservarlo dos veces.
  Future<void> _reassignRelations(String keepId, String discardId) async {
    final relations =
        await (_db.select(_db.relations)..where(
              (r) =>
                  r.fromItemId.equals(discardId) | r.toItemId.equals(discardId),
            ))
            .get();

    for (final relation in relations) {
      final isFrom = relation.fromItemId == discardId;
      final otherId = isFrom ? relation.toItemId : relation.fromItemId;

      if (otherId == keepId) {
        await (_db.delete(
          _db.relations,
        )..where((r) => r.id.equals(relation.id))).go();
        continue;
      }

      final newFromId = isFrom ? keepId : relation.fromItemId;
      final newToId = isFrom ? relation.toItemId : keepId;
      final alreadyExists =
          await (_db.select(_db.relations)..where(
                (r) =>
                    r.fromItemId.equals(newFromId) &
                    r.toItemId.equals(newToId) &
                    r.kind.equalsValue(relation.kind),
              ))
              .getSingleOrNull();

      if (alreadyExists != null) {
        await (_db.delete(
          _db.relations,
        )..where((r) => r.id.equals(relation.id))).go();
      } else {
        await (_db.update(
          _db.relations,
        )..where((r) => r.id.equals(relation.id))).write(
          isFrom
              ? RelationsCompanion(fromItemId: Value(keepId))
              : RelationsCompanion(toItemId: Value(keepId)),
        );
      }
    }
  }

  /// Las etiquetas del descartado pasan al que queda; una que el que
  /// queda ya tiene puesta no se duplica.
  Future<void> _reassignTags(String keepId, String discardId) async {
    final tags = await (_db.select(
      _db.itemTags,
    )..where((t) => t.itemId.equals(discardId))).get();

    for (final tag in tags) {
      final alreadyHas =
          await (_db.select(_db.itemTags)..where(
                (t) => t.itemId.equals(keepId) & t.tagId.equals(tag.tagId),
              ))
              .getSingleOrNull();

      if (alreadyHas != null) {
        await (_db.delete(_db.itemTags)..where(
              (t) => t.itemId.equals(discardId) & t.tagId.equals(tag.tagId),
            ))
            .go();
      } else {
        await (_db.update(_db.itemTags)..where(
              (t) => t.itemId.equals(discardId) & t.tagId.equals(tag.tagId),
            ))
            .write(ItemTagsCompanion(itemId: Value(keepId)));
      }
    }
  }

  /// Los valores de propiedad del descartado pasan al que queda; uno que
  /// el que queda ya tiene bajo la misma categoría no se duplica — mismo
  /// criterio que `_reassignTags`.
  Future<void> _reassignProperties(String keepId, String discardId) async {
    final properties = await (_db.select(
      _db.itemPropertyValues,
    )..where((p) => p.itemId.equals(discardId))).get();

    for (final property in properties) {
      final alreadyHas =
          await (_db.select(_db.itemPropertyValues)..where(
                (p) =>
                    p.itemId.equals(keepId) &
                    p.propertyValueId.equals(property.propertyValueId),
              ))
              .getSingleOrNull();

      if (alreadyHas != null) {
        await (_db.delete(_db.itemPropertyValues)..where(
              (p) =>
                  p.itemId.equals(discardId) &
                  p.propertyValueId.equals(property.propertyValueId),
            ))
            .go();
      } else {
        await (_db.update(_db.itemPropertyValues)..where(
              (p) =>
                  p.itemId.equals(discardId) &
                  p.propertyValueId.equals(property.propertyValueId),
            ))
            .write(ItemPropertyValuesCompanion(itemId: Value(keepId)));
      }
    }
  }

  /// Las tarjetas del descartado pasan al que queda — sin conflicto
  /// posible: cada una es su propia fila, con su propio `id`.
  Future<void> _reassignFlashcards(String keepId, String discardId) async {
    await (_db.update(_db.flashcards)..where((f) => f.itemId.equals(discardId)))
        .write(FlashcardsCompanion(itemId: Value(keepId)));
  }

  /// TODAS las renditions del descartado pasan al que queda —incluidos
  /// sus resaltados, que cuelgan de la rendition y no del elemento, así
  /// que vienen solos—: ninguna rendition de texto se borra (D5). Entre
  /// todas las de texto que termina teniendo el que queda, la más
  /// completa —más caracteres— queda como principal; el resto, no.
  Future<void> _reassignRenditions(String keepId, String discardId) async {
    await (_db.update(_db.renditions)..where((r) => r.itemId.equals(discardId)))
        .write(RenditionsCompanion(itemId: Value(keepId)));

    final textRenditions = await (_db.select(
      _db.renditions,
    )..where((r) => r.itemId.equals(keepId) & r.content.isNotNull())).get();
    if (textRenditions.isEmpty) return;

    final longest = textRenditions.reduce(
      (a, b) => b.content!.length > a.content!.length ? b : a,
    );

    for (final rendition in textRenditions) {
      final shouldBePrimary = rendition.id == longest.id;
      if (rendition.isPrimary != shouldBePrimary) {
        await (_db.update(_db.renditions)
              ..where((r) => r.id.equals(rendition.id)))
            .write(RenditionsCompanion(isPrimary: Value(shouldBePrimary)));
      }
    }
  }

  Failure _unexpected(Object e, StackTrace stackTrace) {
    _telemetry.recordError(
      e,
      stackTrace,
      hint: 'MergeDuplicateItemsUseCaseImpl.call',
    );
    return Failure.unexpected(message: e.toString());
  }
}
