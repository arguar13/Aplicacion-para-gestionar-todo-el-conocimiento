import 'package:drift/drift.dart';
import 'package:sinapsis/core/database/tables/knowledge_entries.dart';
import 'package:sinapsis/core/database/tables/properties.dart';
import 'package:sinapsis/core/domain/entities/contributor_role.dart';
import 'package:sinapsis/core/domain/entities/publication_date.dart';
import 'package:sinapsis/core/domain/entities/reference_type.dart';

/// Los datos bibliográficos de una fuente (F15): editorial, volumen, DOI…
///
/// Es una tabla aparte, 1:1 con la fuente, y no columnas de `source`, por dos
/// motivos. Uno: cada campo versionado de `source` está enumerado en la
/// fusión, el escritor y la lectura; quince columnas más serían quince campos
/// de linaje con su regla de conflicto, y con esta tabla la referencia entera
/// cuenta como UN campo (`reference`). Dos: las listas no cargan nada nuevo, y
/// el detalle la pide por su clave.
///
/// El año NO está acá: es `source.published_at`, con la exactitud que dice
/// [publicationPrecision]. Guardarlo dos veces sería tener dos verdades.
///
/// Los identificadores se guardan normalizados —el DOI en minúsculas y sin
/// prefijo, el ISBN en ISBN-13 sin guiones, el ISSN con su guion—, así dos
/// referencias al mismo libro tienen el mismo texto y se encuentran por índice.
/// No son `UNIQUE` a propósito: dos dispositivos pueden haber cargado la misma
/// obra por separado, y una fusión no puede fallar por eso; la identidad la
/// decide quien importa, y la coincidencia difusa la propone la pantalla de
/// duplicados.
///
/// Solo una fuente tiene referencia: lo hace cumplir un trigger
/// (`reference_triggers.dart`).
@DataClassName('SourceReferenceRow')
@TableIndex(name: 'idx_source_reference_doi', columns: {#doi})
@TableIndex(name: 'idx_source_reference_isbn', columns: {#isbn})
class SourceReferences extends Table {
  @override
  String get tableName => 'source_reference';

  TextColumn get itemId =>
      text().references(KnowledgeEntries, #id, onDelete: KeyAction.cascade)();

  /// Qué clase de obra es. `null` si nadie lo dijo: la cita lo marca como un
  /// hueco en vez de suponerlo.
  TextColumn get referenceType => textEnum<ReferenceType>().nullable()();

  /// El libro que contiene un capítulo, la revista que contiene un artículo,
  /// el sitio que contiene una página.
  TextColumn get containerTitle => text().nullable()();
  TextColumn get publisher => text().nullable()();
  TextColumn get publisherPlace => text().nullable()();
  TextColumn get edition => text().nullable()();
  TextColumn get volume => text().nullable()();
  TextColumn get issue => text().nullable()();

  /// Texto y no dos números: hay artículos con «e1234», «S12-S15» o «xii».
  TextColumn get pages => text().nullable()();
  TextColumn get isbn => text().nullable()();
  TextColumn get issn => text().nullable()();
  TextColumn get doi => text().nullable()();

  /// Cuándo se consultó. Para una fuente web que no la trae se toma la fecha
  /// de captura al citar, sin guardarla acá.
  DateTimeColumn get accessedAt => dateTime().nullable()();

  /// La clave con que un `.bib` llamaba a la obra: se conserva para que
  /// exportar de vuelta no cambie las claves que alguien ya usa en su texto.
  TextColumn get citationKey => text().nullable()();

  /// Con qué exactitud se sabe `source.published_at`: año, mes, día o «sin
  /// fecha». `null` en una fuente que nunca dijo nada de eso.
  TextColumn get publicationPrecision =>
      textEnum<PublicationPrecision>().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {itemId};
}

/// Las personas de una obra, con su rol y su orden (F15).
///
/// Cada persona es un valor de la categoría de sistema «Autor» del
/// vocabulario, así renombrarla, fusionarla con otra escrita distinto y ver
/// «las obras de este autor» funcionan como con cualquier valor. Lo que un
/// valor no tiene —el orden en que se nombran y qué hizo cada uno (autor,
/// traductor, editor, director)— es lo que esta tabla agrega.
///
/// La asignación `item_property_values` de cada persona la mantiene espejada el
/// escritor, para que los conteos, el explorador y la línea de tiempo no
/// tengan que saber de esta tabla. La fuente de verdad de quién es y en qué
/// orden es esta.
///
/// Que el valor sea de una categoría de tipo persona, y que el elemento sea una
/// fuente, lo hacen cumplir los triggers de `reference_triggers.dart`.
///
/// Si la persona se borra del vocabulario, deja de figurar en sus obras: es lo
/// que le pasa a cualquier valor con lo que tenía asignado.
@DataClassName('SourceContributorRow')
@TableIndex(name: 'idx_source_contributor_person', columns: {#propertyValueId})
class SourceContributors extends Table {
  @override
  String get tableName => 'source_contributor';

  TextColumn get itemId =>
      text().references(KnowledgeEntries, #id, onDelete: KeyAction.cascade)();

  TextColumn get propertyValueId =>
      text().references(PropertyValues, #id, onDelete: KeyAction.cascade)();

  TextColumn get role => textEnum<ContributorRole>()();

  /// El lugar entre las personas de la obra, desde 0. Es de TODAS, no por rol:
  /// dos personas en el mismo lugar serían un orden ambiguo, y la restricción
  /// de abajo lo impide.
  IntColumn get position => integer()();

  @override
  Set<Column<Object>> get primaryKey => {itemId, propertyValueId, role};

  @override
  List<String> get customConstraints => ['UNIQUE (item_id, position)'];
}
