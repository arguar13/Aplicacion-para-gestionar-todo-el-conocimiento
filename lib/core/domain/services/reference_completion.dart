import 'package:meta/meta.dart';
import 'package:sinapsis/core/domain/entities/extracted_metadata.dart';
import 'package:sinapsis/core/domain/entities/reference_data.dart';

/// Cómo queda una referencia después de completarla con lo que se leyó de
/// su archivo o su página: los datos y la fecha de publicación.
@immutable
class CompletedReference {
  const CompletedReference({required this.reference, this.publishedAt});

  final ReferenceData reference;

  /// `Source.publishedAt`: va aparte de [reference], como en
  /// [ExtractedMetadata].
  final DateTime? publishedAt;
}

/// Completa **solo lo vacío** de una referencia —[current], con su fecha
/// [publishedAt]— con lo que trae [found], dato por dato (F27). La regla es
/// una sola para la IA que completa sola (`AiFieldLedger`) y para la persona
/// que acepta los datos en «Para revisar»: si cada uno tuviera la suya, lo
/// que uno respeta el otro lo borraría.
///
/// - Lo que la referencia ya tiene manda, aunque [found] traiga otra cosa:
///   nunca se pisa lo que la persona escribió. Un texto en blanco cuenta como
///   vacío.
/// - Las personas van enteras o no van: mezclar dos elencos daría uno que
///   nadie propuso.
/// - Lo que una lectura no trae —cuándo se consultó, la clave de cita— queda
///   tal cual.
/// - La fecha, con su exactitud, solo si nadie dijo nada de ella: «sin fecha»
///   (`undated`) también es algo que la persona escribió.
CompletedReference completeEmptyReference({
  required ReferenceData current,
  required DateTime? publishedAt,
  required ExtractedMetadata found,
}) {
  final filled = _fillEmpty(current, found.reference);
  final dateFilled =
      publishedAt == null &&
      current.publicationPrecision == null &&
      found.publishedAt != null;
  if (!dateFilled) {
    return CompletedReference(reference: filled, publishedAt: publishedAt);
  }
  return CompletedReference(
    // `copyWith` alcanza: la exactitud de antes era nula.
    reference: filled.copyWith(
      publicationPrecision: found.publicationPrecision,
    ),
    publishedAt: found.publishedAt,
  );
}

ReferenceData _fillEmpty(ReferenceData current, ReferenceData found) =>
    ReferenceData(
      type: current.type ?? found.type,
      contributors: current.contributors.isEmpty
          ? found.contributors
          : current.contributors,
      containerTitle: _blank(current.containerTitle)
          ? found.containerTitle
          : current.containerTitle,
      publisher: _blank(current.publisher)
          ? found.publisher
          : current.publisher,
      publisherPlace: _blank(current.publisherPlace)
          ? found.publisherPlace
          : current.publisherPlace,
      edition: _blank(current.edition) ? found.edition : current.edition,
      volume: _blank(current.volume) ? found.volume : current.volume,
      issue: _blank(current.issue) ? found.issue : current.issue,
      pages: _blank(current.pages) ? found.pages : current.pages,
      isbn: _blank(current.isbn) ? found.isbn : current.isbn,
      issn: _blank(current.issn) ? found.issn : current.issn,
      doi: _blank(current.doi) ? found.doi : current.doi,
      accessedAt: current.accessedAt,
      citationKey: current.citationKey,
      publicationPrecision: current.publicationPrecision,
    );

bool _blank(String? text) => text == null || text.trim().isEmpty;
