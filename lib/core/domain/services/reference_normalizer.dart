import 'package:sinapsis/core/domain/entities/reference_data.dart';
import 'package:sinapsis/core/domain/services/bibliographic_identifiers.dart';

/// La referencia tal como se guarda (F15): lo que llega de un formulario o de
/// un archivo `.bib`, ya limpio.
///
/// - Un texto se recorta, y uno vacío es «no dijeron nada»: `null`.
/// - Un DOI, un ISBN o un ISSN se guardan **normalizados** —minúsculas y sin
///   prefijo, ISBN-13 sin guiones, ISSN con su guion—, y uno que no vale
///   (dígito de control equivocado, no tiene la forma) **no se guarda**: un
///   identificador mal escrito es peor que ninguno, porque dos referencias
///   distintas se creerían la misma. Quien quiera avisar de eso —el
///   formulario, el informe de una importación— compara lo que entró con lo
///   que salió.
/// - Las personas sin nombre ni identidad se descartan, y una persona que
///   figura dos veces con el mismo rol queda una vez, en el lugar de la
///   primera.
///
/// Es una función pura y no una decisión del escritor para que el formulario
/// y el importador puedan mostrar exactamente lo que se va a guardar.
ReferenceData normalizeReference(ReferenceData reference) {
  final seen = <String>{};
  final contributors = <Contributor>[];
  for (final contributor in reference.contributors) {
    final name = contributor.name.copyWith(
      family: contributor.name.family.trim(),
      given: contributor.name.given.trim(),
      suffix: contributor.name.suffix.trim(),
    );
    final id = contributor.personId;
    // Sin nombre y sin persona guardada no hay a quién citar.
    if (name.isEmpty && id == null) continue;
    final who = id ?? name.label.toLowerCase();
    if (!seen.add('${contributor.role.name}|$who')) continue;
    contributors.add(
      Contributor(name: name, role: contributor.role, personId: id),
    );
  }

  return ReferenceData(
    type: reference.type,
    contributors: contributors,
    containerTitle: _text(reference.containerTitle),
    publisher: _text(reference.publisher),
    publisherPlace: _text(reference.publisherPlace),
    edition: _text(reference.edition),
    volume: _text(reference.volume),
    issue: _text(reference.issue),
    pages: _text(reference.pages),
    isbn: _identifier(reference.isbn, normalizeIsbn),
    issn: _identifier(reference.issn, normalizeIssn),
    doi: _identifier(reference.doi, normalizeDoi),
    accessedAt: reference.accessedAt,
    citationKey: _text(reference.citationKey),
    publicationPrecision: reference.publicationPrecision,
  );
}

/// [value] recortado, o `null` si no queda nada.
String? _text(String? value) {
  final trimmed = value?.trim();
  return trimmed == null || trimmed.isEmpty ? null : trimmed;
}

/// [value] pasado por [normalize], o `null` si estaba vacío o no vale.
String? _identifier(String? value, String? Function(String) normalize) {
  final text = _text(value);
  return text == null ? null : normalize(text);
}
