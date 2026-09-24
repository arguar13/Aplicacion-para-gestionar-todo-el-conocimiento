import 'package:fpdart/fpdart.dart';
import 'package:sinapsis/core/domain/entities/imported_reference.dart';
import 'package:sinapsis/core/domain/entities/knowledge_item.dart';
import 'package:sinapsis/core/domain/entities/processing_state.dart';
import 'package:sinapsis/core/domain/entities/source.dart';
import 'package:sinapsis/core/domain/entities/source_kind.dart';
import 'package:sinapsis/core/error/failures.dart';
import 'package:sinapsis/core/util/clock.dart';
import 'package:sinapsis/core/util/id_generator.dart';
import 'package:sinapsis/features/library/domain/repositories/library_repository.dart';
import 'package:sinapsis/features/reference/domain/entities/reference_identity_index.dart';
import 'package:sinapsis/features/reference/domain/repositories/reference_repository.dart';
import 'package:sinapsis/features/reference/domain/services/reference_import_merge.dart';

/// Qué pasó con UNA entrada al importarla (F15, D9).
enum ImportedReferenceOutcome {
  /// No había nada con ese DOI, ISBN ni enlace: se creó una fuente nueva,
  /// `SourceKind.reference`.
  created,

  /// Ya había una fuente con esa identidad, y algo de lo que traía la
  /// entrada le faltaba: se completó.
  updated,

  /// Ya había una fuente con esa identidad, y ya tenía todo lo que traía la
  /// entrada: no se tocó nada, y la importación sigue siendo idempotente.
  unchanged,
}

/// El resultado de importar una entrada.
class ImportReferenceEntryResult {
  const ImportReferenceEntryResult({
    required this.itemId,
    required this.outcome,
  });

  final String itemId;
  final ImportedReferenceOutcome outcome;
}

/// Crea o completa UNA fuente a partir de una entrada leída de un `.bib` o
/// un `.ris` (F15, D9): con un índice de identidad ya armado —qué
/// DOI/ISBN/URL tiene cada fuente de la bóveda—, sin una consulta por
/// entrada.
///
/// Lo que hace con muchas entradas a la vez —el informe de creadas,
/// actualizadas y saltadas, la coincidencia difusa que propone en vez de
/// crear, los adjuntos— es de un caso de uso aparte, que llama a este una
/// vez por entrada.
class ImportReferenceEntryUseCase {
  ImportReferenceEntryUseCase({
    required LibraryRepository library,
    required ReferenceRepository reference,
    required IdGenerator ids,
    required Clock clock,
  }) : _library = library,
       _reference = reference,
       _ids = ids,
       _clock = clock;

  final LibraryRepository _library;
  final ReferenceRepository _reference;
  final IdGenerator _ids;
  final Clock _clock;

  Future<Either<Failure, ImportReferenceEntryResult>> call(
    ImportedReference entry,
    ReferenceIdentityIndex index, {
    bool prioritizeIncoming = false,
  }) {
    final existingId = index.find(
      doi: entry.reference.doi,
      isbn: entry.reference.isbn,
      url: entry.url,
    );
    return existingId == null
        ? _create(entry)
        : _update(existingId, entry, prioritizeIncoming: prioritizeIncoming);
  }

  Future<Either<Failure, ImportReferenceEntryResult>> _create(
    ImportedReference entry,
  ) async {
    final now = _clock();
    final itemId = _ids.next();
    final title = entry.title?.trim();

    final item = KnowledgeItem(
      id: itemId,
      title: (title == null || title.isEmpty) ? 'Sin título' : title,
      source: Source(
        id: _ids.next(),
        kind: SourceKind.reference,
        capturedAt: now,
        url: entry.url,
        publishedAt: entry.publishedAt,
      ),
      processingState: ProcessingState.ready,
      createdAt: now,
      updatedAt: now,
    );

    final saved = await _library.save(item);
    final failure = saved.getLeft().toNullable();
    if (failure != null) return left(failure);

    await _reference.saveReference(
      itemId,
      entry.reference.copyWith(
        publicationPrecision: entry.publicationPrecision,
      ),
    );
    return right(
      ImportReferenceEntryResult(
        itemId: itemId,
        outcome: ImportedReferenceOutcome.created,
      ),
    );
  }

  Future<Either<Failure, ImportReferenceEntryResult>> _update(
    String itemId,
    ImportedReference entry, {
    required bool prioritizeIncoming,
  }) async {
    final found = await _library.findById(itemId);
    final failure = found.getLeft().toNullable();
    if (failure != null) return left(failure);

    final currentItem = found.getRight().toNullable();
    // El índice se armó al empezar la importación; si el elemento se borró
    // justo después (otra pestaña, otro dispositivo), se trata como si no
    // hubiera coincidido con nada, en vez de fallar la entrada entera.
    if (currentItem == null) return _create(entry);

    final currentReference = await _reference.read(itemId);
    final incomingReference = entry.reference.copyWith(
      publicationPrecision: entry.publicationPrecision,
    );
    final mergedReference = mergeReferenceOnImport(
      currentReference,
      incomingReference,
      prioritizeIncoming: prioritizeIncoming,
    );

    final currentDate = currentItem.source.publishedAt;
    final incomingDate = entry.publishedAt;
    final resolvedDate = prioritizeIncoming
        ? (incomingDate ?? currentDate)
        : (currentDate ?? incomingDate);

    final referenceChanged = mergedReference != currentReference;
    if (referenceChanged) {
      await _reference.saveReference(itemId, mergedReference);
    }
    final dateChanged = resolvedDate != currentDate;
    if (dateChanged) {
      await _reference.savePublishedAt(itemId, resolvedDate);
    }

    return right(
      ImportReferenceEntryResult(
        itemId: itemId,
        outcome: (referenceChanged || dateChanged)
            ? ImportedReferenceOutcome.updated
            : ImportedReferenceOutcome.unchanged,
      ),
    );
  }
}
