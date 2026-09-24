import 'package:fpdart/fpdart.dart';
import 'package:sinapsis/core/domain/entities/contributor_role.dart';
import 'package:sinapsis/core/domain/entities/duplicate_match_kind.dart';
import 'package:sinapsis/core/domain/entities/imported_reference.dart';
import 'package:sinapsis/core/domain/entities/knowledge_item.dart';
import 'package:sinapsis/core/domain/entities/processing_state.dart';
import 'package:sinapsis/core/domain/entities/source.dart';
import 'package:sinapsis/core/domain/entities/source_kind.dart';
import 'package:sinapsis/core/domain/services/vocabulary_normalizer.dart';
import 'package:sinapsis/core/error/failures.dart';
import 'package:sinapsis/core/util/clock.dart';
import 'package:sinapsis/core/util/id_generator.dart';
import 'package:sinapsis/features/library/domain/repositories/library_repository.dart';
import 'package:sinapsis/features/reference/domain/entities/reference_fuzzy_index.dart';
import 'package:sinapsis/features/reference/domain/entities/reference_identity_index.dart';
import 'package:sinapsis/features/reference/domain/repositories/reference_repository.dart';
import 'package:sinapsis/features/reference/domain/services/reference_import_merge.dart';
import 'package:sinapsis/features/suggestions/domain/repositories/suggestion_repository.dart';

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
    this.possibleDuplicates = 0,
  });

  final String itemId;
  final ImportedReferenceOutcome outcome;

  /// Cuántas propuestas de posible duplicado se mandaron a la pantalla de
  /// F7 al crear esta entrada —D9: nunca fusiona sola—. Siempre 0 cuando
  /// [outcome] no es [ImportedReferenceOutcome.created]: la coincidencia
  /// difusa solo se mira si nada coincidió por identidad exacta.
  final int possibleDuplicates;
}

/// Crea o completa UNA fuente a partir de una entrada leída de un `.bib` o
/// un `.ris` (F15, D9): con un índice de identidad ya armado —qué
/// DOI/ISBN/URL tiene cada fuente de la bóveda—, sin una consulta por
/// entrada. Sin identidad exacta, propone —nunca fusiona sola— los
/// candidatos que encuentre en el índice de coincidencia difusa, a la
/// pantalla de duplicados de F7.
///
/// Lo que hace con muchas entradas a la vez —el informe de creadas,
/// actualizadas y saltadas, los adjuntos— es de un caso de uso aparte, que
/// llama a este una vez por entrada.
class ImportReferenceEntryUseCase {
  ImportReferenceEntryUseCase({
    required LibraryRepository library,
    required ReferenceRepository reference,
    required SuggestionRepository suggestions,
    required IdGenerator ids,
    required Clock clock,
  }) : _library = library,
       _reference = reference,
       _suggestions = suggestions,
       _ids = ids,
       _clock = clock;

  final LibraryRepository _library;
  final ReferenceRepository _reference;
  final SuggestionRepository _suggestions;
  final IdGenerator _ids;
  final Clock _clock;

  Future<Either<Failure, ImportReferenceEntryResult>> call(
    ImportedReference entry,
    ReferenceIdentityIndex index,
    ReferenceFuzzyIndex fuzzyIndex, {
    bool prioritizeIncoming = false,
  }) {
    final existingId = index.find(
      doi: entry.reference.doi,
      isbn: entry.reference.isbn,
      url: entry.url,
    );
    return existingId == null
        ? _create(entry, fuzzyIndex)
        : _update(
            existingId,
            entry,
            fuzzyIndex,
            prioritizeIncoming: prioritizeIncoming,
          );
  }

  Future<Either<Failure, ImportReferenceEntryResult>> _create(
    ImportedReference entry,
    ReferenceFuzzyIndex fuzzyIndex,
  ) async {
    final now = _clock();
    final itemId = _ids.next();
    final title = entry.title?.trim();
    final resolvedTitle = (title == null || title.isEmpty)
        ? 'Sin título'
        : title;

    final item = KnowledgeItem(
      id: itemId,
      title: resolvedTitle,
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

    final possibleDuplicates = await _proposeFuzzyDuplicates(
      newItemId: itemId,
      newItemTitle: resolvedTitle,
      entry: entry,
      fuzzyIndex: fuzzyIndex,
    );

    return right(
      ImportReferenceEntryResult(
        itemId: itemId,
        outcome: ImportedReferenceOutcome.created,
        possibleDuplicates: possibleDuplicates,
      ),
    );
  }

  /// Los candidatos difusos (D9) se proponen DESPUÉS de crear, entre dos
  /// elementos que ya existen —el mismo camino que cualquier otro duplicado
  /// de la app—, en vez de inventar una forma nueva de proponer algo que
  /// todavía no es un elemento.
  Future<int> _proposeFuzzyDuplicates({
    required String newItemId,
    required String newItemTitle,
    required ImportedReference entry,
    required ReferenceFuzzyIndex fuzzyIndex,
  }) async {
    // Sin título propio, comparar contra el resto de lo que tampoco tiene
    // título sería puro ruido: todo compartiría la misma clave «sin título».
    final ownTitle = entry.title?.trim();
    if (ownTitle == null || ownTitle.isEmpty) return 0;

    final year = entry.publishedAt?.year;
    final authorFamily = _firstAuthorFamily(entry);
    final candidates = fuzzyIndex.find(
      title: newItemTitle,
      year: year,
      authorFamily: authorFamily,
    );

    for (final candidate in candidates) {
      await _suggestions.createDuplicateSuggestion(
        targetItemId: candidate.itemId,
        duplicateItemId: newItemId,
        duplicateItemTitle: newItemTitle,
        matchKind: DuplicateMatchKind.bibliographic,
        confidence: _fuzzyConfidence(candidate, year, authorFamily),
      );
    }
    return candidates.length;
  }

  Future<Either<Failure, ImportReferenceEntryResult>> _update(
    String itemId,
    ImportedReference entry,
    ReferenceFuzzyIndex fuzzyIndex, {
    required bool prioritizeIncoming,
  }) async {
    final found = await _library.findById(itemId);
    final failure = found.getLeft().toNullable();
    if (failure != null) return left(failure);

    final currentItem = found.getRight().toNullable();
    // El índice se armó al empezar la importación; si el elemento se borró
    // justo después (otra pestaña, otro dispositivo), se trata como si no
    // hubiera coincidido con nada, en vez de fallar la entrada entera.
    if (currentItem == null) return _create(entry, fuzzyIndex);

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

/// El apellido del primer autor de [entry], ya normalizado —mismo criterio
/// que `ReferenceFuzzyMatchRepositoryImpl`—, o `null` si no tiene ninguno.
String? _firstAuthorFamily(ImportedReference entry) {
  for (final contributor in entry.reference.contributors) {
    if (contributor.role != ContributorRole.author) continue;
    final family = contributor.name.family.trim();
    if (family.isNotEmpty) return normalizeVocabularyLabel(family);
  }
  return null;
}

/// Qué tan seguro está el candidato: máxima cuando el año Y el autor
/// coinciden de verdad (no solo «ninguno de los dos lo tenía»), intermedia
/// cuando solo uno de los dos aporta certeza, y la mínima cuando la
/// coincidencia es solo por el título.
double _fuzzyConfidence(
  ReferenceFuzzyCandidate candidate,
  int? year,
  String? authorFamily,
) {
  final yearMatched =
      year != null && candidate.year != null && candidate.year == year;
  final authorMatched =
      authorFamily != null &&
      candidate.firstAuthorFamily != null &&
      candidate.firstAuthorFamily == authorFamily;

  if (yearMatched && authorMatched) return 1;
  if (yearMatched || authorMatched) return 0.75;
  return 0.5;
}
