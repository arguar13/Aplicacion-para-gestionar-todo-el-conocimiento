import 'package:meta/meta.dart';
import 'package:sinapsis/core/domain/entities/publication_date.dart';
import 'package:sinapsis/core/domain/entities/reference_data.dart';

/// Una obra leída de, o lista para escribir en, un archivo bibliográfico
/// —`.bib` (F15, commit 13) o `.ris` (commit 14)—: el título y el enlace,
/// aparte de [reference] por la misma razón que en `ExtractedMetadata` —son
/// del elemento, no de la referencia—.
///
/// Un nombre por formato (`BibtexEntry`, `RisEntry`) hubiera sido dos copias
/// idénticas de la misma forma: lo que trae un `.bib` y lo que trae un `.ris`
/// es el mismo puñado de datos, solo que uno lo escribe con llaves y el otro
/// con etiquetas de dos letras.
///
/// No lleva identidad de la bóveda (ni `itemId` ni `sourceId`): vincular una
/// entrada con una fuente que ya existe, o crear una nueva, es del comando 15
/// («importar y exportar desde la app»). Esto es solo la lectura y la
/// escritura del formato, sin decidir qué hacer con el resultado.
@immutable
class ImportedReference {
  const ImportedReference({
    this.title,
    this.url,
    this.publishedAt,
    this.publicationPrecision,
    this.reference = const ReferenceData(),
  });

  /// El título de la obra.
  final String? title;

  /// El enlace, si lo trae.
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
      other is ImportedReference &&
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
      'ImportedReference(title: $title, key: ${reference.citationKey}, '
      'reference: $reference)';
}
