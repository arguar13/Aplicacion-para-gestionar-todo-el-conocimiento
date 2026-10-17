import 'dart:convert';

import 'package:sinapsis/core/domain/entities/ai_changed_field.dart';
import 'package:sinapsis/core/domain/entities/publication_date.dart';
import 'package:sinapsis/core/domain/entities/reference_data.dart';

// Lo que la IA completa en un elemento (F27), como lo recuerda su pasada en
// `ai_field_changes`: cómo se lee hoy cada dato para compararlo con lo que
// puso, y cómo se vacía o se cambia. Lo usan quien deshace la pasada
// (`AiFieldLedger`) y quien corrige lo que puso (F33,
// `correction_suggestions.dart`): los dos tienen que leerlo igual.

/// [reference] con [field] vacío —o, en la fecha, con [precision]—. Hace
/// falta armarla de nuevo: en `copyWith`, un `null` es «dejalo como estaba».
///
/// [field] es un dato de la referencia (`AiChangedField.isReference`).
ReferenceData referenceWithout(
  ReferenceData reference,
  AiChangedField field, {
  PublicationPrecision? precision,
}) {
  String? keep(AiChangedField f, String? value) => field == f ? null : value;
  return ReferenceData(
    type: field == AiChangedField.referenceType ? null : reference.type,
    contributors: field == AiChangedField.contributors
        ? const []
        : reference.contributors,
    containerTitle: keep(
      AiChangedField.containerTitle,
      reference.containerTitle,
    ),
    publisher: keep(AiChangedField.publisher, reference.publisher),
    publisherPlace: keep(
      AiChangedField.publisherPlace,
      reference.publisherPlace,
    ),
    edition: keep(AiChangedField.edition, reference.edition),
    volume: keep(AiChangedField.volume, reference.volume),
    issue: keep(AiChangedField.issue, reference.issue),
    pages: keep(AiChangedField.pages, reference.pages),
    isbn: keep(AiChangedField.isbn, reference.isbn),
    issn: keep(AiChangedField.issn, reference.issn),
    doi: keep(AiChangedField.doi, reference.doi),
    accessedAt: reference.accessedAt,
    citationKey: reference.citationKey,
    publicationPrecision: field == AiChangedField.publishedAt
        ? precision
        : reference.publicationPrecision,
  );
}

/// El valor de [field] como texto, para compararlo con lo que puso la IA
/// (`ai_field_changes.after_value`):
/// `null` si está vacío. Las personas, por su identidad en el vocabulario y
/// su rol, en orden —renombrar a una persona no la cambia—; la fecha, en
/// segundos y con su exactitud, que van juntas.
String? aiFieldValue(
  AiChangedField field,
  ReferenceData reference,
  DateTime? publishedAt, {
  String? spaceId,
}) {
  String? text(String? value) =>
      value == null || value.trim().isEmpty ? null : value;
  return switch (field) {
    // Una nota mapa no es un valor que se compare: se mira si sigue viva y
    // sin editar (`_mapNoteOf`), antes de llegar acá.
    AiChangedField.mapNote => throw StateError(
      'La nota mapa de una pasada no se codifica como un dato.',
    ),
    AiChangedField.space => spaceId,
    AiChangedField.referenceType => reference.type?.name,
    AiChangedField.contributors =>
      reference.contributors.isEmpty
          ? null
          : jsonEncode([
              for (final c in reference.contributors)
                [c.role.name, c.personId ?? c.name.label],
            ]),
    AiChangedField.containerTitle => text(reference.containerTitle),
    AiChangedField.publisher => text(reference.publisher),
    AiChangedField.publisherPlace => text(reference.publisherPlace),
    AiChangedField.edition => text(reference.edition),
    AiChangedField.volume => text(reference.volume),
    AiChangedField.issue => text(reference.issue),
    AiChangedField.pages => text(reference.pages),
    AiChangedField.isbn => text(reference.isbn),
    AiChangedField.issn => text(reference.issn),
    AiChangedField.doi => text(reference.doi),
    AiChangedField.publishedAt =>
      publishedAt == null && reference.publicationPrecision == null
          ? null
          : '${_seconds(publishedAt)}'
                '|${reference.publicationPrecision?.name ?? ''}',
  };
}

/// [at] en segundos, como lo guarda drift; vacío si no hay.
String _seconds(DateTime? at) =>
    at == null ? '' : '${at.millisecondsSinceEpoch ~/ 1000}';

/// [reference] con el dato de texto [field] en [value] —vacío si es `null`—.
/// Solo los de texto (`AiChangedField.isReferenceText`): el resto tiene su
/// propio editor.
ReferenceData referenceWithText(
  ReferenceData reference,
  AiChangedField field,
  String? value,
) {
  assert(field.isReferenceText, '$field no es un dato de texto');
  final cleared = referenceWithout(reference, field);
  if (value == null) return cleared;
  return switch (field) {
    AiChangedField.containerTitle => cleared.copyWith(containerTitle: value),
    AiChangedField.publisher => cleared.copyWith(publisher: value),
    AiChangedField.publisherPlace => cleared.copyWith(publisherPlace: value),
    AiChangedField.edition => cleared.copyWith(edition: value),
    AiChangedField.volume => cleared.copyWith(volume: value),
    AiChangedField.issue => cleared.copyWith(issue: value),
    AiChangedField.pages => cleared.copyWith(pages: value),
    AiChangedField.isbn => cleared.copyWith(isbn: value),
    AiChangedField.issn => cleared.copyWith(issn: value),
    AiChangedField.doi => cleared.copyWith(doi: value),
    _ => cleared,
  };
}
