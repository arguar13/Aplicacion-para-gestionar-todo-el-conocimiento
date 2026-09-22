import 'package:meta/meta.dart';
import 'package:sinapsis/core/domain/entities/publication_date.dart';
import 'package:sinapsis/core/domain/entities/reference_data.dart';
import 'package:sinapsis/core/domain/entities/reference_type.dart';

/// Lo que un extractor —del PDF, de la página o de YouTube— pudo leer de una
/// fuente (F15, D12): el título, cuándo se publicó y el resto de los datos
/// bibliográficos, con sus personas, en la misma forma en que se guardan.
///
/// Nada es obligatorio: cada extractor llena lo que encontró y deja el resto
/// en `null`. [isEmpty] dice si no encontró nada, y entonces no hay
/// sugerencia que generar: nunca se escribe sin mirar, y tampoco se ofrece
/// mirar la nada.
@immutable
class ExtractedMetadata {
  const ExtractedMetadata({
    this.title,
    this.publishedAt,
    this.publicationPrecision,
    this.reference = const ReferenceData(),
  });

  /// El título de la obra, si el extractor lo trae. No es un dato de
  /// [ReferenceData]: es el título del elemento, que vive aparte.
  final String? title;

  /// Cuándo se publicó, con [publicationPrecision]. Aparte de [reference] por
  /// la misma razón que en `ReferenceData`: es `Source.publishedAt`, no un
  /// dato de la referencia.
  final DateTime? publishedAt;
  final PublicationPrecision? publicationPrecision;

  /// El resto de los datos bibliográficos: contenedor, editorial,
  /// identificadores y las personas de la obra.
  final ReferenceData reference;

  /// Si no se encontró nada de nada.
  bool get isEmpty =>
      (title == null || title!.trim().isEmpty) &&
      publishedAt == null &&
      reference.isEmpty;

  @override
  bool operator ==(Object other) =>
      other is ExtractedMetadata &&
      other.title == title &&
      other.publishedAt == publishedAt &&
      other.publicationPrecision == publicationPrecision &&
      other.reference == reference;

  @override
  int get hashCode =>
      Object.hash(title, publishedAt, publicationPrecision, reference);

  @override
  String toString() =>
      'ExtractedMetadata(title: $title, publishedAt: $publishedAt, '
      'reference: $reference)';
}

/// Junta varios [ExtractedMetadata] en uno, dato por dato: el primero de
/// [byPriority] que trae cada uno gana. Las personas no se mezclan entre
/// fuentes —la primera lista no vacía se queda entera—, porque unir la mitad
/// de una lista con la mitad de otra daría un elenco que ninguna de las dos
/// propuso.
ExtractedMetadata mergeExtractedMetadata(List<ExtractedMetadata> byPriority) {
  String? title;
  DateTime? publishedAt;
  PublicationPrecision? precision;
  var contributors = const <Contributor>[];
  String? containerTitle;
  String? publisher;
  String? publisherPlace;
  String? volume;
  String? issue;
  String? pages;
  String? isbn;
  String? issn;
  String? doi;
  ReferenceType? type;

  for (final source in byPriority) {
    title ??= source.title;
    if (publishedAt == null && source.publishedAt != null) {
      publishedAt = source.publishedAt;
      precision = source.publicationPrecision;
    }
    final ref = source.reference;
    if (contributors.isEmpty && ref.contributors.isNotEmpty) {
      contributors = ref.contributors;
    }
    type ??= ref.type;
    containerTitle ??= ref.containerTitle;
    publisher ??= ref.publisher;
    publisherPlace ??= ref.publisherPlace;
    volume ??= ref.volume;
    issue ??= ref.issue;
    pages ??= ref.pages;
    isbn ??= ref.isbn;
    issn ??= ref.issn;
    doi ??= ref.doi;
  }

  return ExtractedMetadata(
    title: title,
    publishedAt: publishedAt,
    publicationPrecision: precision,
    reference: ReferenceData(
      type: type,
      contributors: contributors,
      containerTitle: containerTitle,
      publisher: publisher,
      publisherPlace: publisherPlace,
      volume: volume,
      issue: issue,
      pages: pages,
      isbn: isbn,
      issn: issn,
      doi: doi,
    ),
  );
}
