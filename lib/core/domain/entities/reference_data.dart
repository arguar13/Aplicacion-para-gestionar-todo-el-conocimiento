import 'package:meta/meta.dart';
import 'package:sinapsis/core/domain/entities/contributor_role.dart';
import 'package:sinapsis/core/domain/entities/person_name.dart';
import 'package:sinapsis/core/domain/entities/publication_date.dart';
import 'package:sinapsis/core/domain/entities/reference_type.dart';

/// Una persona en una obra: quién es y qué hizo. El orden de la lista de
/// [ReferenceData.contributors] es el orden en que las normas los nombran.
@immutable
class Contributor {
  const Contributor({
    required this.name,
    this.role = ContributorRole.author,
    this.personId,
  });

  /// Quién es.
  final PersonName name;

  /// Qué hizo en esta obra.
  final ContributorRole role;

  /// El valor del vocabulario que la representa, si ya está guardada: dos
  /// obras del mismo autor comparten esta identidad y no dos textos parecidos.
  /// `null` mientras la persona es solo un nombre que todavía nadie guardó.
  final String? personId;

  Contributor copyWith({
    PersonName? name,
    ContributorRole? role,
    String? personId,
  }) => Contributor(
    name: name ?? this.name,
    role: role ?? this.role,
    personId: personId ?? this.personId,
  );

  @override
  bool operator ==(Object other) =>
      other is Contributor &&
      other.name == name &&
      other.role == role &&
      other.personId == personId;

  @override
  int get hashCode => Object.hash(name, role, personId);

  @override
  String toString() => 'Contributor(${role.name}: ${name.label})';
}

/// Los datos bibliográficos de una fuente, aparte de los que ya tiene
/// (título, enlace, fecha de publicación y autor tal como se capturó).
///
/// Nada es obligatorio: una fuente sin nada de esto se cita con lo que hay y
/// marca lo que falta. Los identificadores se guardan ya normalizados —ver
/// `normalizeDoi`, `normalizeIsbn` y `normalizeIssn`—, así que dos referencias
/// al mismo libro tienen el mismo texto.
///
/// El año no está acá: es `Source.publishedAt` con la precisión de
/// [publicationPrecision], y quien cita los junta con
/// `PublicationDate.fromStored`. Guardarlo dos veces sería tener dos verdades.
@immutable
class ReferenceData {
  const ReferenceData({
    this.type,
    this.contributors = const [],
    this.containerTitle,
    this.publisher,
    this.publisherPlace,
    this.edition,
    this.volume,
    this.issue,
    this.pages,
    this.isbn,
    this.issn,
    this.doi,
    this.accessedAt,
    this.citationKey,
    this.publicationPrecision,
  });

  /// Qué clase de obra es. `null` si nadie lo dijo: la cita lo marca como un
  /// hueco en vez de suponerlo.
  final ReferenceType? type;

  /// Las personas de la obra, en el orden en que se nombran.
  final List<Contributor> contributors;

  /// El libro en el que sale un capítulo, la revista en la que sale un
  /// artículo, el sitio en el que sale una página.
  final String? containerTitle;

  /// La editorial. En una tesis, la universidad; en una fuente primaria, el
  /// archivo.
  final String? publisher;

  /// La ciudad de la editorial.
  final String? publisherPlace;

  /// «2.ª ed.», «Rev.».
  final String? edition;

  /// El volumen o el tomo.
  final String? volume;

  /// El número de la revista.
  final String? issue;

  /// Las páginas: «45-67». Texto y no dos números, porque hay artículos con
  /// «e1234», «S12-S15» o «xii».
  final String? pages;

  /// El ISBN, en ISBN-13 y sin guiones.
  final String? isbn;

  /// El ISSN, con su guion: «1234-5678».
  final String? issn;

  /// El DOI, en minúsculas y sin prefijo: «10.1000/xyz123».
  final String? doi;

  /// Cuándo se consultó. Para una página web, cuando no se cargó, se toma la
  /// fecha en que se capturó.
  final DateTime? accessedAt;

  /// La clave con que un archivo `.bib` llamaba a esta obra («garcia1967»):
  /// se conserva para que exportar de vuelta no cambie las claves que alguien
  /// ya usa en su texto.
  final String? citationKey;

  /// Con qué exactitud se sabe la fecha de publicación de la fuente.
  final PublicationPrecision? publicationPrecision;

  /// Las personas que cumplieron [role], en su orden.
  List<Contributor> byRole(ContributorRole role) => [
    for (final contributor in contributors)
      if (contributor.role == role) contributor,
  ];

  /// Si no tiene ningún dato: no hay nada que guardar.
  bool get isEmpty =>
      type == null &&
      contributors.isEmpty &&
      containerTitle == null &&
      publisher == null &&
      publisherPlace == null &&
      edition == null &&
      volume == null &&
      issue == null &&
      pages == null &&
      isbn == null &&
      issn == null &&
      doi == null &&
      accessedAt == null &&
      citationKey == null &&
      publicationPrecision == null;

  /// Una copia con lo que se cambie. Para BORRAR un dato hay que armar la
  /// referencia de nuevo: un `null` acá significa «dejalo como estaba».
  ReferenceData copyWith({
    ReferenceType? type,
    List<Contributor>? contributors,
    String? containerTitle,
    String? publisher,
    String? publisherPlace,
    String? edition,
    String? volume,
    String? issue,
    String? pages,
    String? isbn,
    String? issn,
    String? doi,
    DateTime? accessedAt,
    String? citationKey,
    PublicationPrecision? publicationPrecision,
  }) => ReferenceData(
    type: type ?? this.type,
    contributors: contributors ?? this.contributors,
    containerTitle: containerTitle ?? this.containerTitle,
    publisher: publisher ?? this.publisher,
    publisherPlace: publisherPlace ?? this.publisherPlace,
    edition: edition ?? this.edition,
    volume: volume ?? this.volume,
    issue: issue ?? this.issue,
    pages: pages ?? this.pages,
    isbn: isbn ?? this.isbn,
    issn: issn ?? this.issn,
    doi: doi ?? this.doi,
    accessedAt: accessedAt ?? this.accessedAt,
    citationKey: citationKey ?? this.citationKey,
    publicationPrecision: publicationPrecision ?? this.publicationPrecision,
  );

  @override
  bool operator ==(Object other) =>
      other is ReferenceData &&
      other.type == type &&
      _sameList(other.contributors, contributors) &&
      other.containerTitle == containerTitle &&
      other.publisher == publisher &&
      other.publisherPlace == publisherPlace &&
      other.edition == edition &&
      other.volume == volume &&
      other.issue == issue &&
      other.pages == pages &&
      other.isbn == isbn &&
      other.issn == issn &&
      other.doi == doi &&
      other.accessedAt == accessedAt &&
      other.citationKey == citationKey &&
      other.publicationPrecision == publicationPrecision;

  @override
  int get hashCode => Object.hash(
    type,
    Object.hashAll(contributors),
    containerTitle,
    publisher,
    publisherPlace,
    edition,
    volume,
    issue,
    pages,
    isbn,
    issn,
    doi,
    accessedAt,
    citationKey,
    publicationPrecision,
  );

  @override
  String toString() =>
      'ReferenceData(${type?.name ?? 'sin tipo'}, '
      '${contributors.length} personas)';
}

bool _sameList(List<Contributor> a, List<Contributor> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
