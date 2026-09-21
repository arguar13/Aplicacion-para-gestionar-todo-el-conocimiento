import 'package:sinapsis/core/domain/entities/contributor_role.dart';
import 'package:sinapsis/core/domain/entities/publication_date.dart';
import 'package:sinapsis/core/domain/entities/reference_data.dart';
import 'package:sinapsis/core/domain/entities/reference_type.dart';
import 'package:sinapsis/features/reference/domain/services/reference_draft.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// Cómo se nombran, para quien los mira, los tipos de obra, los roles y la
/// exactitud de una fecha (F15). Vive en un solo lugar por lo mismo que
/// `SourceKindPresentation`: el formulario, los conflictos de fusión y la
/// bibliografía los nombran igual.
extension ReferenceTypePresentation on ReferenceType {
  String label(AppLocalizations l10n) => switch (this) {
    ReferenceType.book => l10n.referenceTypeBook,
    ReferenceType.chapter => l10n.referenceTypeChapter,
    ReferenceType.article => l10n.referenceTypeArticle,
    ReferenceType.thesis => l10n.referenceTypeThesis,
    ReferenceType.primarySource => l10n.referenceTypePrimarySource,
    ReferenceType.documentary => l10n.referenceTypeDocumentary,
    ReferenceType.website => l10n.referenceTypeWebsite,
    ReferenceType.onlinePublication => l10n.referenceTypeOnlinePublication,
    ReferenceType.other => l10n.referenceTypeOther,
  };
}

extension PublicationPrecisionPresentation on PublicationPrecision {
  String label(AppLocalizations l10n) => switch (this) {
    PublicationPrecision.year => l10n.referencePrecisionYear,
    PublicationPrecision.month => l10n.referencePrecisionMonth,
    PublicationPrecision.day => l10n.referencePrecisionDay,
    PublicationPrecision.undated => l10n.referencePrecisionUndated,
  };
}

extension ContributorRolePresentation on ContributorRole {
  /// El rol de UNA persona: «Autor», «Traductor».
  String label(AppLocalizations l10n) => switch (this) {
    ContributorRole.author => l10n.contributorRoleAuthor,
    ContributorRole.translator => l10n.contributorRoleTranslator,
    ContributorRole.editor => l10n.contributorRoleEditor,
    ContributorRole.director => l10n.contributorRoleDirector,
  };

  /// El nombre de la lista de personas con este rol: «Autores», «Traductores».
  String listLabel(AppLocalizations l10n) => switch (this) {
    ContributorRole.author => l10n.referenceFieldAuthors,
    ContributorRole.translator => l10n.referenceFieldTranslators,
    ContributorRole.editor => l10n.referenceFieldEditors,
    ContributorRole.director => l10n.referenceFieldDirectors,
  };
}

extension ReferenceFieldPresentation on ReferenceField {
  /// Cómo se llama este dato para una obra de [type]: el contenedor de un
  /// capítulo es un libro y el de un artículo, una revista; la editorial de una
  /// tesis es una universidad.
  String label(AppLocalizations l10n, ReferenceType? type) => switch (this) {
    ReferenceField.container => switch (type) {
      ReferenceType.chapter => l10n.referenceContainerBook,
      ReferenceType.article => l10n.referenceContainerJournal,
      ReferenceType.website ||
      ReferenceType.onlinePublication => l10n.referenceContainerSite,
      _ => l10n.referenceFieldContainer,
    },
    ReferenceField.publisher => switch (type) {
      ReferenceType.thesis => l10n.referencePublisherUniversity,
      ReferenceType.primarySource => l10n.referencePublisherArchive,
      ReferenceType.documentary => l10n.referencePublisherProducer,
      _ => l10n.referenceFieldPublisher,
    },
    ReferenceField.place => l10n.referenceFieldPlace,
    ReferenceField.edition => l10n.referenceFieldEdition,
    ReferenceField.volume => l10n.referenceFieldVolume,
    ReferenceField.issue => l10n.referenceFieldIssue,
    ReferenceField.pages => l10n.referenceFieldPages,
    ReferenceField.isbn => l10n.referenceFieldIsbn,
    ReferenceField.issn => l10n.referenceFieldIssn,
    ReferenceField.doi => l10n.referenceFieldDoi,
    ReferenceField.accessed => l10n.referenceFieldAccessed,
    ReferenceField.citationKey => l10n.referenceFieldCitationKey,
  };
}

/// La fecha de publicación como se muestra: «2020», «2020-03», «2020-03-15» o
/// «Sin fecha». `null` si nadie la cargó.
String? publicationDateText(AppLocalizations l10n, PublicationDate date) {
  if (date.isUndated) return l10n.referencePrecisionUndated;
  final year = date.year;
  if (year == null) return null;
  final month = date.month;
  if (month == null) return '$year';
  final mm = month.toString().padLeft(2, '0');
  final day = date.day;
  if (day == null) return '$year-$mm';
  return '$year-$mm-${day.toString().padLeft(2, '0')}';
}

/// Los datos de [reference] uno por línea, «Etiqueta: valor», solo los que
/// tienen algo: lo que un conflicto de fusión muestra de cada versión para que
/// se pueda elegir. Vacío si no tiene ningún dato.
///
/// Más adelante, con los estilos de cita, se mostrará la cita ya armada; esto
/// es lo que se ve hasta que una obra tiene título y estilo con que citarla.
String describeReference(AppLocalizations l10n, ReferenceData reference) {
  final lines = <String>[];
  void add(String label, String? value) {
    if (value != null && value.isNotEmpty) lines.add('$label: $value');
  }

  add(l10n.referenceFieldType, reference.type?.label(l10n));
  for (final role in ContributorRole.values) {
    final people = reference.byRole(role);
    if (people.isEmpty) continue;
    add(role.listLabel(l10n), people.map((c) => c.name.label).join('; '));
  }
  add(l10n.referenceFieldContainer, reference.containerTitle);
  add(l10n.referenceFieldPublisher, reference.publisher);
  add(l10n.referenceFieldPlace, reference.publisherPlace);
  add(l10n.referenceFieldEdition, reference.edition);
  add(l10n.referenceFieldVolume, reference.volume);
  add(l10n.referenceFieldIssue, reference.issue);
  add(l10n.referenceFieldPages, reference.pages);
  add(l10n.referenceFieldIsbn, reference.isbn);
  add(l10n.referenceFieldIssn, reference.issn);
  add(l10n.referenceFieldDoi, reference.doi);
  final accessed = reference.accessedAt;
  add(
    l10n.referenceFieldAccessed,
    accessed == null
        ? null
        : '${accessed.year}-${accessed.month.toString().padLeft(2, '0')}-'
              '${accessed.day.toString().padLeft(2, '0')}',
  );
  add(l10n.referenceFieldCitationKey, reference.citationKey);
  add(
    l10n.referenceFieldDateExactness,
    reference.publicationPrecision?.label(l10n),
  );
  return lines.join('\n');
}
