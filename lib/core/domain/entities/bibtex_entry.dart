import 'package:meta/meta.dart';
import 'package:sinapsis/core/domain/entities/publication_date.dart';
import 'package:sinapsis/core/domain/entities/reference_data.dart';

/// Una obra leída de, o lista para escribir en, un archivo `.bib` (F15,
/// commit 13): el título y el enlace, aparte de [reference] por la misma
/// razón que en `ExtractedMetadata` —son del elemento, no de la referencia—.
///
/// No lleva identidad de la bóveda (ni `itemId` ni `sourceId`): vincular una
/// entrada con una fuente que ya existe, o crear una nueva, es del comando 15
/// («importar y exportar desde la app»). Esto es solo la lectura y la
/// escritura del formato, sin decidir qué hacer con el resultado.
@immutable
class BibtexEntry {
  const BibtexEntry({
    this.title,
    this.url,
    this.publishedAt,
    this.publicationPrecision,
    this.reference = const ReferenceData(),
  });

  /// El título de la obra.
  final String? title;

  /// El enlace, si lo trae —el campo `url` de BibTeX, o `howpublished`
  /// cuando parece un enlace—.
  final String? url;

  /// Cuándo se publicó, con [publicationPrecision]. Igual que en
  /// `ExtractedMetadata`: es `Source.publishedAt`, no un dato de
  /// [ReferenceData].
  final DateTime? publishedAt;
  final PublicationPrecision? publicationPrecision;

  /// El resto de los datos bibliográficos: tipo, contenedor, editorial,
  /// identificadores, la clave de cita y las personas de la obra.
  final ReferenceData reference;

  @override
  bool operator ==(Object other) =>
      other is BibtexEntry &&
      other.title == title &&
      other.url == url &&
      other.publishedAt == publishedAt &&
      other.publicationPrecision == publicationPrecision &&
      other.reference == reference;

  @override
  int get hashCode =>
      Object.hash(title, url, publishedAt, publicationPrecision, reference);

  @override
  String toString() =>
      'BibtexEntry(title: $title, key: ${reference.citationKey}, '
      'reference: $reference)';
}
