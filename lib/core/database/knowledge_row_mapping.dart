import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/domain/entities/person_name.dart';
import 'package:sinapsis/core/domain/entities/reference_data.dart';
import 'package:sinapsis/core/domain/entities/source.dart';
import 'package:sinapsis/core/domain/entities/source_kind.dart';

/// De las filas del modelo nuevo (`item`/`source`) a las entidades del
/// dominio: el único lugar que decide cómo se lee una procedencia, para que
/// quien la necesite —la Biblioteca al armar un elemento, la fusión de
/// duplicados al guardar de dónde vino el que se descarta— no repita la regla.

/// La procedencia de un elemento: la de su fila de `source` o, si es una nota,
/// la de una nota escrita a mano —que no tiene fila, ni URL, ni autor—.
///
/// Su id es el del propio elemento: hay una fuente por elemento. Antes de F10
/// la fuente tenía identidad propia y podía compartirla con otros elementos;
/// nada la usaba como tal.
Source sourceFor(KnowledgeEntryRow item, KnowledgeSourceRow? source) {
  if (source == null) {
    return Source(
      id: item.id,
      kind: SourceKind.manualNote,
      capturedAt: item.createdAt,
    );
  }
  return Source(
    id: item.id,
    kind: source.sourceType,
    capturedAt: source.capturedAt,
    url: source.originUrl,
    authorName: source.authorName,
    authorUrl: source.authorUrl,
    publishedAt: source.publishedAt,
    originalFilePath: source.originalBlobPath,
    language: source.language,
    onlyFile: source.onlyFile,
  );
}

/// El nombre de la persona que representa un valor del vocabulario de autores
/// (F15).
///
/// Un valor cuyo nombre nadie partió todavía —uno que ya estaba en una
/// categoría «Autor» que alguien había creado a mano— se cita ENTERO, tal como
/// está escrito, como si fuera el apellido de una sola palabra: no se adivina
/// dónde termina el apellido, y un nombre mal partido en una bibliografía es
/// peor que uno sin invertir.
PersonName personNameFor(PropertyValueRow value) => personNameFromColumns(
  label: value.value,
  family: value.nameFamily,
  given: value.nameGiven,
  suffix: value.nameSuffix,
  isInstitution: value.isInstitution,
);

/// Lo mismo que [personNameFor] desde las columnas sueltas: es lo que usa la
/// fusión de bóvedas, que lee la copia con SQL y no con filas tipadas.
PersonName personNameFromColumns({
  required String label,
  required String? family,
  required String? given,
  required String? suffix,
  required bool? isInstitution,
}) {
  if (family == null) return PersonName(family: label);
  return PersonName(
    family: family,
    given: given ?? '',
    suffix: suffix ?? '',
    isInstitution: isInstitution ?? false,
  );
}

/// Los datos bibliográficos de una fuente a partir de su fila de
/// `source_reference` —`null` si solo tiene personas— y sus [contributors], ya
/// leídos y en orden.
ReferenceData referenceFor(
  SourceReferenceRow? row,
  List<Contributor> contributors,
) => ReferenceData(
  type: row?.referenceType,
  contributors: contributors,
  containerTitle: row?.containerTitle,
  publisher: row?.publisher,
  publisherPlace: row?.publisherPlace,
  edition: row?.edition,
  volume: row?.volume,
  issue: row?.issue,
  pages: row?.pages,
  isbn: row?.isbn,
  issn: row?.issn,
  doi: row?.doi,
  accessedAt: row?.accessedAt,
  citationKey: row?.citationKey,
  publicationPrecision: row?.publicationPrecision,
);
