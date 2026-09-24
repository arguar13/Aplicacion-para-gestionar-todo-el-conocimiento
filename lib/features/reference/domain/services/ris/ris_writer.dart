import 'package:sinapsis/core/domain/entities/contributor_role.dart';
import 'package:sinapsis/core/domain/entities/imported_reference.dart';
import 'package:sinapsis/core/domain/entities/publication_date.dart';
import 'package:sinapsis/core/domain/entities/reference_data.dart';
import 'package:sinapsis/core/domain/entities/reference_type.dart';

/// Escribe una lista de [ImportedReference] como un archivo `.ris` (F15,
/// commit 14), con las mismas garantías que el exportador de BibTeX: una
/// clave única por entrada —acá en el campo `ID`, que RIS define
/// justamente para esto, «puede limitarse a 20 caracteres alfanuméricos»—.
///
/// `SN` es el mismo campo para ISBN e ISSN en RIS: si una obra tuviera los
/// dos —caso raro—, se prioriza el ISBN. `SP`/`EP` son página de inicio y de
/// fin por separado, así que una página suelta («e1234») se escribe solo en
/// `SP`. Dos campos propios, `G1`/`G2` —sin conflicto con ninguno de los ya
/// definidos por el formato—, cumplen el mismo papel que `sinapsis-type`/
/// `sinapsis-undated` en BibTeX.
String writeRis(List<ImportedReference> entries) {
  final used = <String>{};
  final buffer = StringBuffer();
  for (final entry in entries) {
    final id = _uniqueId(entry, used);
    used.add(id);
    buffer.write(_writeEntry(entry, id));
  }
  return buffer.toString();
}

const _risType = {
  ReferenceType.article: 'JOUR',
  ReferenceType.book: 'BOOK',
  ReferenceType.chapter: 'CHAP',
  ReferenceType.thesis: 'THES',
  ReferenceType.website: 'WEB',
  ReferenceType.primarySource: 'GEN',
  ReferenceType.documentary: 'GEN',
  ReferenceType.onlinePublication: 'GEN',
  ReferenceType.other: 'GEN',
};

String _writeEntry(ImportedReference entry, String id) {
  final type = _risType[entry.reference.type] ?? 'GEN';
  final buffer = StringBuffer()..writeln('TY  - $type');

  void put(String tag, String? value) {
    if (value != null && value.trim().isNotEmpty) {
      buffer.writeln('$tag  - ${value.trim()}');
    }
  }

  put('ID', id);
  put('TI', entry.title);
  for (final author in entry.reference.byRole(ContributorRole.author)) {
    put('AU', _writeName(author));
  }
  for (final editor in entry.reference.byRole(ContributorRole.editor)) {
    put('A2', _writeName(editor));
  }
  put('T2', entry.reference.containerTitle);
  put('PB', entry.reference.publisher);
  put('CY', entry.reference.publisherPlace);
  put('ET', entry.reference.edition);
  put('VL', entry.reference.volume);
  put('IS', entry.reference.issue);

  final pages = entry.reference.pages;
  if (pages != null && pages.trim().isNotEmpty) {
    final dash = pages.indexOf('-');
    if (dash > 0) {
      put('SP', pages.substring(0, dash));
      put('EP', pages.substring(dash + 1));
    } else {
      put('SP', pages);
    }
  }

  put('SN', entry.reference.isbn ?? entry.reference.issn);
  put('DO', entry.reference.doi);
  put('UR', entry.url);
  if (entry.reference.accessedAt != null) {
    put('DA', _slashDate(entry.reference.accessedAt!));
  }

  switch (entry.publicationPrecision) {
    case PublicationPrecision.undated:
      put('G2', 'true');
    case PublicationPrecision.year:
      if (entry.publishedAt != null) {
        put('PY', '${entry.publishedAt!.year}///');
      }
    case PublicationPrecision.month:
      if (entry.publishedAt != null) {
        final date = entry.publishedAt!;
        put('PY', '${date.year}/${_pad(date.month)}//');
      }
    case PublicationPrecision.day:
      if (entry.publishedAt != null) {
        put('PY', _slashDate(entry.publishedAt!));
      }
    case null:
      break;
  }

  buffer
    ..writeln('G1  - ${entry.reference.type?.name ?? 'none'}')
    ..writeln('ER  - ')
    ..writeln();
  return buffer.toString();
}

/// «Apellido, Nombre», o solo el nombre con una coma al final si es una
/// institución: la convención de EndNote para un autor corporativo.
String _writeName(Contributor contributor) => contributor.name.isInstitution
    ? '${contributor.name.family},'
    : contributor.name.label;

String _slashDate(DateTime date) =>
    '${date.year}/${_pad(date.month)}/${_pad(date.day)}/';

String _pad(int n) => n.toString().padLeft(2, '0');

String _uniqueId(ImportedReference entry, Set<String> used) {
  final base = _baseId(entry);
  if (!used.contains(base)) return base;

  for (var i = 0; i < 26; i++) {
    final candidate = '$base${String.fromCharCode(97 + i)}';
    if (!used.contains(candidate)) return candidate;
  }
  var n = 2;
  while (used.contains('$base$n')) {
    n++;
  }
  return '$base$n';
}

String _baseId(ImportedReference entry) {
  final existing = entry.reference.citationKey?.trim();
  if (existing != null && existing.isNotEmpty) {
    return _asciiSlugKeepCase(existing);
  }

  final authors = entry.reference.byRole(ContributorRole.author);
  final familyWord = authors.isEmpty
      ? null
      : authors.first.name.family.split(RegExp(r'\s+')).firstOrNull;
  final titleWord = entry.title?.split(RegExp(r'\s+')).firstOrNull;
  final base = _asciiSlug(familyWord ?? titleWord ?? 'sinapsis');
  final year = entry.publishedAt?.year;
  return year == null ? base : '$base$year';
}

const _withAccents = 'áéíóúñÁÉÍÓÚÑüÜàèìòùÀÈÌÒÙâêîôûÂÊÎÔÛäëïöÄËÏÖçÇ';
const _withoutAccents = 'aeiounAEIOUNuUaeiouAEIOUaeiouAEIOUaeioAEIOcC';

String _asciiSlug(String raw) {
  var result = raw;
  for (var i = 0; i < _withAccents.length; i++) {
    result = result.replaceAll(_withAccents[i], _withoutAccents[i]);
  }
  final ascii = result.replaceAll(RegExp('[^a-zA-Z0-9]'), '').toLowerCase();
  return ascii.isEmpty ? 'sinapsis' : ascii;
}

String _asciiSlugKeepCase(String raw) {
  var result = raw;
  for (var i = 0; i < _withAccents.length; i++) {
    result = result.replaceAll(_withAccents[i], _withoutAccents[i]);
  }
  final ascii = result.replaceAll(RegExp('[^a-zA-Z0-9]'), '');
  return ascii.isEmpty ? 'sinapsis' : ascii;
}
