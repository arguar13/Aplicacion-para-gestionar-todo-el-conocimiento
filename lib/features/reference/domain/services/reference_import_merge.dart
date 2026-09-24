import 'package:sinapsis/core/domain/entities/reference_data.dart';

/// Junta la referencia que ya estaba guardada con la que trae un `.bib` o un
/// `.ris` al reimportar (F15, D9): lo que [current] ya tenía gana siempre
/// —«reimportar completa lo vacío, no pisa lo que el usuario tocó»—, campo
/// por campo, salvo que [prioritizeIncoming] invierta el orden («priorizar
/// el archivo»).
///
/// El tipo y la lista de personas se tratan como UN dato cada uno, no campo
/// por campo ni persona por persona: la lista entera de quien va primero
/// gana solo si está vacía la del otro. Fusionar autor por autor mezclaría
/// dos elencos que nadie propuso así —ver la misma decisión en
/// `mergeExtractedMetadata`, que este código no reusa porque a esa función
/// le faltan `edition`, `accessedAt`, `citationKey` y `publicationPrecision`
/// —campos que un `.bib`/`.ris` sí trae, y que escribirla directamente
/// borraría—.
ReferenceData mergeReferenceOnImport(
  ReferenceData current,
  ReferenceData incoming, {
  bool prioritizeIncoming = false,
}) {
  final first = prioritizeIncoming ? incoming : current;
  final second = prioritizeIncoming ? current : incoming;

  return ReferenceData(
    type: first.type ?? second.type,
    contributors: first.contributors.isNotEmpty
        ? first.contributors
        : second.contributors,
    containerTitle: first.containerTitle ?? second.containerTitle,
    publisher: first.publisher ?? second.publisher,
    publisherPlace: first.publisherPlace ?? second.publisherPlace,
    edition: first.edition ?? second.edition,
    volume: first.volume ?? second.volume,
    issue: first.issue ?? second.issue,
    pages: first.pages ?? second.pages,
    isbn: first.isbn ?? second.isbn,
    issn: first.issn ?? second.issn,
    doi: first.doi ?? second.doi,
    accessedAt: first.accessedAt ?? second.accessedAt,
    citationKey: first.citationKey ?? second.citationKey,
    publicationPrecision:
        first.publicationPrecision ?? second.publicationPrecision,
  );
}
