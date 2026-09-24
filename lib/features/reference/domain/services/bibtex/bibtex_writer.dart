import 'package:sinapsis/core/domain/entities/bibtex_entry.dart';
import 'package:sinapsis/core/domain/entities/contributor_role.dart';
import 'package:sinapsis/core/domain/entities/publication_date.dart';
import 'package:sinapsis/core/domain/entities/reference_data.dart';
import 'package:sinapsis/core/domain/entities/reference_type.dart';

/// Escribe una lista de [BibtexEntry] como un archivo `.bib` (F15, commit
/// 13), con una clave única por entrada: la que ya traía —para no romper el
/// `\cite{...}` de nadie— o, si no tenía, apellido (o la primera palabra del
/// título) más el año, con una letra de más si dos entradas coinciden.
///
/// Escribe los acentos como UTF-8 directo, que es lo que ya hacen los
/// gestores modernos (BibLaTeX, Zotero, JabRef): el analizador propio los
/// deja pasar sin tocar, así que no hace falta ida y vuelta por los escapes
/// de LaTeX para que el propio archivo se lea igual que se escribió —esos
/// escapes solo hacen falta para LEER lo que otro programa, más viejo,
/// escribió—.
///
/// Cada entrada suma dos campos propios, `sinapsis-type` y
/// `sinapsis-undated`, que cualquier otro lector de BibTeX ignora sin
/// problema: sin ellos, un documental, una fuente primaria o una
/// publicación en red se leerían de vuelta como «otro» —`@misc` no los
/// distingue—, y una obra sin fecha se leería como una fecha desconocida.
String writeBibtex(List<BibtexEntry> entries) {
  final used = <String>{};
  final buffer = StringBuffer();
  for (final entry in entries) {
    final key = _uniqueKey(entry, used);
    used.add(key);
    buffer
      ..write(_writeEntry(entry, key))
      ..writeln();
  }
  return buffer.toString();
}

const _bibtexType = {
  ReferenceType.article: 'article',
  ReferenceType.book: 'book',
  ReferenceType.chapter: 'incollection',
  ReferenceType.thesis: 'phdthesis',
  ReferenceType.website: 'online',
  ReferenceType.primarySource: 'misc',
  ReferenceType.documentary: 'misc',
  ReferenceType.onlinePublication: 'misc',
  ReferenceType.other: 'misc',
};

String _writeEntry(BibtexEntry entry, String key) {
  final type = _bibtexType[entry.reference.type] ?? 'misc';
  final fields = <String, String>{};

  void put(String name, String? value) {
    if (value != null && value.trim().isNotEmpty) fields[name] = value.trim();
  }

  put('title', entry.title);

  final authors = entry.reference.byRole(ContributorRole.author);
  if (authors.isNotEmpty) put('author', _joinNames(authors));
  final editors = entry.reference.byRole(ContributorRole.editor);
  if (editors.isNotEmpty) put('editor', _joinNames(editors));

  final containerField = entry.reference.type == ReferenceType.article
      ? 'journal'
      : 'booktitle';
  put(containerField, entry.reference.containerTitle);
  put('publisher', entry.reference.publisher);
  put('address', entry.reference.publisherPlace);
  put('edition', entry.reference.edition);
  put('volume', entry.reference.volume);
  put('number', entry.reference.issue);
  put('pages', entry.reference.pages);
  put('isbn', entry.reference.isbn);
  put('issn', entry.reference.issn);
  put('doi', entry.reference.doi);
  put('url', entry.url);
  if (entry.reference.accessedAt != null) {
    put('urldate', _isoDate(entry.reference.accessedAt!));
  }

  switch (entry.publicationPrecision) {
    case PublicationPrecision.undated:
      put('sinapsis-undated', 'true');
    case PublicationPrecision.year:
      if (entry.publishedAt != null) {
        put('year', '${entry.publishedAt!.year}');
      }
    case PublicationPrecision.month:
      if (entry.publishedAt != null) {
        put('date', _isoDate(entry.publishedAt!, month: true));
      }
    case PublicationPrecision.day:
      if (entry.publishedAt != null) {
        put('date', _isoDate(entry.publishedAt!));
      }
    case null:
      break;
  }

  // Siempre, aun sin tipo («none»): así se distingue de `ReferenceType.other`
  // al releer, y un documental/fuente primaria/publicación en red no se
  // confunde con cualquier otro `@misc`.
  fields['sinapsis-type'] = entry.reference.type?.name ?? 'none';

  final buffer = StringBuffer('@$type{$key,\n');
  final names = fields.keys.toList();
  for (var i = 0; i < names.length; i++) {
    final isLast = i == names.length - 1;
    buffer.writeln(
      '  ${names[i]} = {${_escapeForWrite(fields[names[i]]!)}}'
      '${isLast ? '' : ','}',
    );
  }
  buffer.writeln('}');
  return buffer.toString();
}

/// «Apellido, Nombre» por persona, unidas con ` and `: la forma que
/// `parseNameList` reconoce sin ambigüedad al releer. Una institución va
/// entre llaves —«{Organización Mundial de la Salud}»— para que no se
/// interprete «Organización» como apellido.
String _joinNames(List<Contributor> contributors) => contributors
    .map((c) => c.name.isInstitution ? '{${c.name.family}}' : c.name.label)
    .join(' and ');

String _isoDate(DateTime date, {bool month = false}) {
  final year = date.year.toString().padLeft(4, '0');
  final m = date.month.toString().padLeft(2, '0');
  if (month) return '$year-$m';
  return '$year-$m-${date.day.toString().padLeft(2, '0')}';
}

/// Solo escapa la barra invertida: un valor propio nunca necesita nada más,
/// y un `{`/`}` balanceado dentro de un campo es BibTeX válido tal cual.
String _escapeForWrite(String value) => value.replaceAll(r'\', r'\\');

String _uniqueKey(BibtexEntry entry, Set<String> used) {
  final base = _baseKey(entry);
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

String _baseKey(BibtexEntry entry) {
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

/// Solo letras y números ASCII, en minúsculas: una clave BibTeX con acentos
/// rompe en la mayoría de los motores de LaTeX.
String _asciiSlug(String raw) {
  var result = raw;
  for (var i = 0; i < _withAccents.length; i++) {
    result = result.replaceAll(_withAccents[i], _withoutAccents[i]);
  }
  final ascii = result.replaceAll(RegExp('[^a-zA-Z0-9]'), '').toLowerCase();
  return ascii.isEmpty ? 'sinapsis' : ascii;
}

/// La misma limpieza que [_asciiSlug], pero sin forzar minúsculas: una clave
/// que la persona ya eligió («GarciaMarquez1967») se conserva tal como la
/// escribió, solo sin lo que rompería un motor de LaTeX.
String _asciiSlugKeepCase(String raw) {
  var result = raw;
  for (var i = 0; i < _withAccents.length; i++) {
    result = result.replaceAll(_withAccents[i], _withoutAccents[i]);
  }
  final ascii = result.replaceAll(RegExp('[^a-zA-Z0-9]'), '');
  return ascii.isEmpty ? 'sinapsis' : ascii;
}
