import 'package:drift/drift.dart';
import 'package:fpdart/fpdart.dart';
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/database/knowledge_row_mapping.dart';
import 'package:sinapsis/core/database/knowledge_source_chunking.dart';
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
        _db.knowledgeEntries,
      )..where((i) => i.id.equals(discardItemId))).getSingleOrNull();
      final keepItem = await (_db.select(
        _db.knowledgeEntries,
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

      // Una nota no tiene fila de fuente: su procedencia es la de una nota
      // escrita a mano, sin URL ni autor.
      final discardSource = sourceFor(
        discardItem,
        await (_db.select(
          _db.knowledgeSources,
        )..where((s) => s.itemId.equals(discardItemId))).getSingleOrNull(),
      );

      await _db.transaction(() async {
        await _reassignRelations(keepItemId, discardItemId);
        await _reassignInlineLinks(keepItemId, discardItemId);
        await _reassignProperties(keepItemId, discardItemId);
        await _reassignFlashcards(keepItemId, discardItemId);
        await _reassignRenditions(keepItemId, discardItemId);
        await _refreshChunks(keepItemId);

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

  /// Los `[[ ]]` registrados (`inline_link`) siguen al elemento: sin esto, un
  /// enlace hacia el descartado quedaría roto al borrarlo —la clave foránea lo
  /// suelta— aunque su contenido ahora vive en el que queda, y los enlaces que
  /// escribía el descartado se irían con él aunque su texto pasa al que queda.
  ///
  ///  * Los que apuntaban al descartado apuntan al que queda.
  ///  * Los que el descartado escribía pasan a ser del que queda. Si el que
  ///    queda ya tenía ese destino, no se duplica: se conserva el suyo, salvo
  ///    que estuviera roto y el otro no.
  ///  * Una nota no se enlaza a sí misma: los que quedarían así, porque los
  ///    dos duplicados se apuntaban entre sí, se borran.
  Future<void> _reassignInlineLinks(String keepId, String discardId) async {
    await (_db.update(_db.inlineLinks)
          ..where((l) => l.toItemId.equals(discardId)))
        .write(InlineLinksCompanion(toItemId: Value(keepId)));

    final keepLinks = {
      for (final link in await (_db.select(
        _db.inlineLinks,
      )..where((l) => l.fromItemId.equals(keepId))).get())
        link.normalizedTitle: link,
    };
    final discardLinks = await (_db.select(
      _db.inlineLinks,
    )..where((l) => l.fromItemId.equals(discardId))).get();

    for (final link in discardLinks) {
      final keepLink = keepLinks[link.normalizedTitle];
      if (keepLink == null) {
        await (_db.update(_db.inlineLinks)..where((l) => l.id.equals(link.id)))
            .write(InlineLinksCompanion(fromItemId: Value(keepId)));
        continue;
      }
      if (keepLink.toItemId == null && link.toItemId != null) {
        await (_db.update(_db.inlineLinks)
              ..where((l) => l.id.equals(keepLink.id)))
            .write(InlineLinksCompanion(toItemId: Value(link.toItemId)));
      }
      await (_db.delete(
        _db.inlineLinks,
      )..where((l) => l.id.equals(link.id))).go();
    }

    await (_db.delete(_db.inlineLinks)..where(
          (l) => l.fromItemId.equals(keepId) & l.toItemId.equals(keepId),
        ))
        .go();
  }

  /// Los valores de propiedad del descartado pasan al que queda; uno que
  /// el que queda ya tiene no se duplica.
  ///
  /// Las etiquetas viajan por acá: desde F8 son valores de la categoría
  /// Tema, sin tabla propia. Se compara por VALOR, no por categoría —todas
  /// las etiquetas están bajo Tema, y compararlas por categoría dejaría una
  /// sola.
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

  /// Los chunks del que queda, al día con el texto con el que se queda.
  ///
  /// Reasignar las formas puede cambiar cuál es la principal —la más completa
  /// gana—, y los chunks describen la principal: sin esto, buscar una palabra
  /// del descartado ya no encontraría nada, porque sus chunks se van con él y
  /// los del que queda siguen siendo los del texto de antes, con posiciones que
  /// ya no corresponden a ningún texto. `save()` los mantiene; la fusión
  /// escribe formas sin pasar por `save()`.
  ///
  /// Si la principal no cambió, no toca nada: el hash del texto lo dice. Sin
  /// páginas: el texto que queda puede venir de la otra fuente, y numerarlo
  /// como si fuera el del PDF de este elemento correría los números —mejor
  /// ninguno que uno equivocado—.
  Future<void> _refreshChunks(String keepId) async {
    await chunkAndPersistSource(
      _db,
      itemId: keepId,
      ids: _ids,
      reportedBy: 'f10_merge',
    );
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
