import 'dart:convert';

import 'package:sinapsis/core/domain/entities/contributor_role.dart';
import 'package:sinapsis/core/domain/entities/person_name.dart';
import 'package:sinapsis/core/domain/entities/publication_date.dart';
import 'package:sinapsis/core/domain/entities/reference_data.dart';
import 'package:sinapsis/core/domain/entities/reference_type.dart';

/// La referencia de una fuente como texto (F15): lo que se guarda de una
/// versión que un conflicto de fusión no dejó en vivo, para poder ponerla de
/// nuevo.
///
/// Es un JSON de UNA línea, con la versión del formato y solo lo que tiene un
/// valor, en un orden fijo: la misma referencia da siempre el mismo texto.
/// Lleva a las personas **por su nombre** —apellido, nombre, sufijo,
/// institución y rol— y no por el identificador del vocabulario: ese cambia de
/// una bóveda a otra, y al ponerla de nuevo la persona se busca por su nombre
/// (`PersonVocabulary`), como al importar.
///
/// [decodeReference] es lo inverso, y tolerante: lo que no entiende lo ignora
/// en vez de rechazar todo el texto —una versión guardada por una app más
/// nueva no debe quedar inservible—.
String encodeReference(ReferenceData data) => jsonEncode(referenceToJson(data));

/// Ver [encodeReference].
Map<String, Object?> referenceToJson(ReferenceData data) => {
  'v': _version,
  if (data.type != null) 'type': data.type!.name,
  if (data.contributors.isNotEmpty)
    'people': [for (final c in data.contributors) _personToJson(c)],
  if (data.containerTitle != null) 'container': data.containerTitle,
  if (data.publisher != null) 'publisher': data.publisher,
  if (data.publisherPlace != null) 'place': data.publisherPlace,
  if (data.edition != null) 'edition': data.edition,
  if (data.volume != null) 'volume': data.volume,
  if (data.issue != null) 'issue': data.issue,
  if (data.pages != null) 'pages': data.pages,
  if (data.isbn != null) 'isbn': data.isbn,
  if (data.issn != null) 'issn': data.issn,
  if (data.doi != null) 'doi': data.doi,
  // Segundos desde 1970, como guarda la base las fechas.
  if (data.accessedAt != null)
    'accessed': data.accessedAt!.millisecondsSinceEpoch ~/ 1000,
  if (data.citationKey != null) 'key': data.citationKey,
  if (data.publicationPrecision != null)
    'precision': data.publicationPrecision!.name,
};

/// La referencia que dice [text], o `null` si no es un JSON de un objeto.
ReferenceData? decodeReference(String text) {
  final Object? json;
  try {
    json = jsonDecode(text);
  } on FormatException {
    return null;
  }
  return json is Map<String, Object?> ? referenceFromJson(json) : null;
}

/// Ver [decodeReference].
ReferenceData referenceFromJson(Map<String, Object?> json) {
  final people = json['people'];
  final accessed = json['accessed'];
  return ReferenceData(
    type: _named(ReferenceType.values, json['type']),
    contributors: [
      if (people is List<Object?>)
        for (final person in people)
          if (person is Map<String, Object?>)
            if (_personFromJson(person) case final contributor?) contributor,
    ],
    containerTitle: _text(json['container']),
    publisher: _text(json['publisher']),
    publisherPlace: _text(json['place']),
    edition: _text(json['edition']),
    volume: _text(json['volume']),
    issue: _text(json['issue']),
    pages: _text(json['pages']),
    isbn: _text(json['isbn']),
    issn: _text(json['issn']),
    doi: _text(json['doi']),
    accessedAt: accessed is int
        ? DateTime.fromMillisecondsSinceEpoch(accessed * 1000)
        : null,
    citationKey: _text(json['key']),
    publicationPrecision: _named(
      PublicationPrecision.values,
      json['precision'],
    ),
  );
}

const _version = 1;

Map<String, Object?> _personToJson(Contributor contributor) {
  final name = contributor.name;
  return {
    'role': contributor.role.name,
    'family': name.family,
    if (name.given.isNotEmpty) 'given': name.given,
    if (name.suffix.isNotEmpty) 'suffix': name.suffix,
    if (name.isInstitution) 'institution': true,
  };
}

/// Una persona de un JSON, o `null` si no tiene ni apellido.
Contributor? _personFromJson(Map<String, Object?> json) {
  final family = _text(json['family']);
  if (family == null) return null;
  return Contributor(
    name: PersonName(
      family: family,
      given: _text(json['given']) ?? '',
      suffix: _text(json['suffix']) ?? '',
      isInstitution: json['institution'] == true,
    ),
    role:
        _named(ContributorRole.values, json['role']) ?? ContributorRole.author,
  );
}

String? _text(Object? value) =>
    value is String && value.isNotEmpty ? value : null;

T? _named<T extends Enum>(List<T> values, Object? name) =>
    name is String ? values.asNameMap()[name] : null;
