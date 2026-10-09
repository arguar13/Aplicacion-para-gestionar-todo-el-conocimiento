import 'package:fpdart/fpdart.dart';
import 'package:sinapsis/core/domain/entities/knowledge_item.dart';
import 'package:sinapsis/core/domain/entities/processing_state.dart';
import 'package:sinapsis/core/domain/entities/rendition.dart';
import 'package:sinapsis/core/domain/entities/rendition_kind.dart';
import 'package:sinapsis/core/domain/entities/source.dart';
import 'package:sinapsis/core/domain/entities/source_kind.dart';
import 'package:sinapsis/core/domain/entities/tag.dart';
import 'package:sinapsis/core/error/failures.dart';
import 'package:sinapsis/core/util/clock.dart';
import 'package:sinapsis/core/util/id_generator.dart';
import 'package:sinapsis/features/anki_import/domain/entities/anki_import_plan.dart';
import 'package:sinapsis/features/anki_import/domain/entities/anki_imported_package.dart';
import 'package:sinapsis/features/anki_import/domain/repositories/anki_import_repository.dart';
import 'package:sinapsis/features/anki_import/domain/services/anki_import_planner.dart';
import 'package:sinapsis/features/flashcards/domain/services/study_day.dart';
import 'package:sinapsis/features/library/domain/repositories/library_repository.dart';
import 'package:sinapsis/features/organize/domain/repositories/organize_repository.dart';

/// Trae un paquete de Anki ya leído (`AnkiPackageReader`) a la bóveda (F31,
/// decisión 73): primero se muestra qué trae ([preview]) y después se escribe
/// ([import]).
///
/// **Atómica.** Los elementos que reciben las tarjetas, sus etiquetas y las
/// tarjetas van en UNA transacción (`LibraryRepository.runInTransaction`): si
/// algo falla, no queda nada a medias.
///
/// **Sin duplicar.** Cada tarjeta, cada hermandad y cada elemento tienen un
/// `id` que sale del `guid` de la nota de Anki (ver `anki_import_ids.dart`):
/// traer otra vez el mismo `.apkg` encuentra lo que ya está y solo suma lo que
/// falte. Lo que la persona repasó entre una y otra importación no se toca. Un
/// elemento que está en la papelera se saca de ella: pidieron traer sus
/// tarjetas.
class ImportAnkiPackageUseCase {
  ImportAnkiPackageUseCase({
    required AnkiImportRepository repository,
    required LibraryRepository library,
    required OrganizeRepository organize,
    required IdGenerator ids,
    required Clock clock,
    StudyDay studyDay = const StudyDay(),
  }) : _repository = repository,
       _library = library,
       _organize = organize,
       _ids = ids,
       _clock = clock,
       _studyDay = studyDay;

  final AnkiImportRepository _repository;
  final LibraryRepository _library;
  final OrganizeRepository _organize;
  final IdGenerator _ids;
  final Clock _clock;
  final StudyDay _studyDay;

  /// Cuántas tarjetas se escriben por tanda: entre una y otra se avisa del
  /// avance, y la pantalla puede dibujar.
  static const _batch = 500;

  /// De qué está hecho [package], y cuánto de eso ya está en la bóveda.
  Future<AnkiImportPreview> preview(AnkiImportedPackage package) async {
    final already = await _repository.alreadyImported(package.cards.toList());
    return AnkiImportPreview.of(package, alreadyImported: already.length);
  }

  /// Escribe [package] según [destination]. [onProgress] dice cuántas tarjetas
  /// van de cuántas.
  Future<Either<Failure, AnkiImportReport>> import(
    AnkiImportedPackage package, {
    required AnkiImportDestination destination,
    void Function(int done, int total)? onProgress,
  }) async {
    try {
      final already = await _repository.alreadyImported(package.cards.toList());
      final now = _clock();
      final plan = planAnkiImport(
        package,
        destination: destination,
        alreadyImported: already,
        now: now,
        studyDay: _studyDay,
      );
      if (plan.items.isEmpty) {
        return right(
          AnkiImportReport(
            cardsImported: 0,
            itemsCreated: 0,
            alreadyImported: plan.alreadyImported,
            unusable: plan.unusable,
          ),
        );
      }

      final total = plan.cardCount;
      var done = 0;
      var itemsCreated = 0;
      var imported = 0;
      onProgress?.call(0, total);

      await _library.runInTransaction<void>(() async {
        final existing = await _repository.existingItems([
          for (final item in plan.items) item.id,
        ]);
        for (final item in plan.items) {
          final trashed = existing[item.id];
          if (trashed == null) {
            await _createItem(item, now);
            itemsCreated++;
          } else if (trashed) {
            final restored = await _library.restore(item.id);
            final failure = restored.getLeft().toNullable();
            if (failure != null) throw _ImportFailed(failure);
          }

          for (var start = 0; start < item.cards.length; start += _batch) {
            final end = start + _batch > item.cards.length
                ? item.cards.length
                : start + _batch;
            imported += await _repository.insertCards(
              item.cards.sublist(start, end),
            );
            done += end - start;
            onProgress?.call(done, total);
          }
        }
      });

      return right(
        AnkiImportReport(
          cardsImported: imported,
          itemsCreated: itemsCreated,
          alreadyImported: plan.alreadyImported,
          unusable: plan.unusable,
        ),
      );
    } on _ImportFailed catch (failed) {
      return left(failed.failure);
      // Cualquier otra cosa que falle por debajo (el disco, la base) deshace
      // la transacción entera y se informa; un TypeError es Error, no
      // Exception.
      // ignore: avoid_catches_without_on_clauses
    } catch (e) {
      return left(Failure.unexpected(message: e.toString()));
    }
  }

  /// Crea el elemento que recibe las tarjetas: una nota con el nombre del mazo,
  /// y sus etiquetas.
  Future<void> _createItem(AnkiPlannedItem planned, DateTime now) async {
    final tags = <Tag>[];
    for (final name in planned.tags) {
      final tag = await _organize.getOrCreateTag(name);
      final failure = tag.getLeft().toNullable();
      if (failure != null) throw _ImportFailed(failure);
      final found = tag.getRight().toNullable()!;
      if (tags.every((t) => t.id != found.id)) tags.add(found);
    }

    final item = KnowledgeItem(
      id: planned.id,
      title: planned.title,
      source: Source(
        id: _ids.next(),
        kind: SourceKind.manualNote,
        capturedAt: now,
      ),
      processingState: ProcessingState.ready,
      createdAt: now,
      updatedAt: now,
      tags: tags,
      renditions: [
        Rendition.text(
          id: _ids.next(),
          itemId: planned.id,
          kind: RenditionKind.plainText,
          content: planned.description,
          isPrimary: true,
          createdAt: now,
        ),
      ],
    );
    final saved = await _library.save(item);
    final failure = saved.getLeft().toNullable();
    if (failure != null) throw _ImportFailed(failure);
  }
}

/// Una falla con tipo propio que sale de la transacción para deshacerla toda.
class _ImportFailed implements Exception {
  const _ImportFailed(this.failure);

  final Failure failure;
}
