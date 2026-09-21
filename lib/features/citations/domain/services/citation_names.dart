import 'package:sinapsis/core/domain/entities/contributor_role.dart';
import 'package:sinapsis/core/domain/entities/person_name.dart';
import 'package:sinapsis/core/domain/entities/reference_data.dart';
import 'package:sinapsis/core/domain/entities/reference_type.dart';
import 'package:sinapsis/core/domain/services/vocabulary_normalizer.dart';
import 'package:sinapsis/features/citations/domain/entities/citation_source.dart';
import 'package:sinapsis/features/citations/domain/services/citation_terms.dart';

/// Quién figura en el lugar de autor de una cita (F15), y con qué rol: lo que
/// todos los estilos necesitan antes de darle su forma.
class LeadPeople {
  const LeadPeople(this.names, this.role);

  /// Las personas, en su orden.
  final List<PersonName> names;

  /// El rol con que figuran: las autoras no llevan marca; una obra que se cita
  /// por sus editoras o por su director sí —«(Ed.)», «(Director)»—.
  final ContributorRole role;

  bool get isEmpty => names.isEmpty;
}

/// Quién va en el lugar de autor de [source] según la clase de obra.
///
/// - Un documental se cita por su director; el resto, por sus autores.
/// - Si no hay autores pero sí editores —un libro compilado—, van ellos.
/// - Si no hay ninguna persona cargada pero la fuente trae un autor tal como se
///   capturó —un canal de YouTube, una cuenta—, se cita ENTERO, sin invertirlo
///   ni abreviarlo: no se adivina cómo se parte «Kurzgesagt – In a Nutshell».
/// - Si no hay nada, la lista queda vacía y la cita marca el hueco.
LeadPeople leadPeopleOf(CitationSource source) {
  final reference = source.reference;
  final directors = reference.byRole(ContributorRole.director);
  final authors = reference.byRole(ContributorRole.author);
  final editors = reference.byRole(ContributorRole.editor);

  List<PersonName> namesOf(List<Contributor> people) => [
    for (final c in people) c.name,
  ];

  if (source.type == ReferenceType.documentary && directors.isNotEmpty) {
    return LeadPeople(namesOf(directors), ContributorRole.director);
  }
  if (authors.isNotEmpty) {
    return LeadPeople(namesOf(authors), ContributorRole.author);
  }
  if (source.type != ReferenceType.chapter && editors.isNotEmpty) {
    return LeadPeople(namesOf(editors), ContributorRole.editor);
  }
  final literal = source.authorName?.trim();
  if (literal != null && literal.isNotEmpty) {
    return LeadPeople([
      PersonName.institution(literal),
    ], ContributorRole.author);
  }
  return const LeadPeople([], ContributorRole.author);
}

/// «García Márquez, G. J.»: el apellido y las iniciales, como los pide APA. Una
/// institución o un nombre sin partir —solo apellido— va entero.
String surnameInitials(PersonName name) {
  final initials = name.initials;
  if (initials.isEmpty) return name.family;
  final base = '${name.family}, $initials';
  return name.suffix.isEmpty ? base : '$base, ${name.suffix}';
}

/// «G. J. García Márquez»: las iniciales y el apellido, para quien va después
/// de «En» —los editores de un libro—.
String initialsSurname(PersonName name) {
  final initials = name.initials;
  if (initials.isEmpty) return name.family;
  final base = '$initials ${name.family}';
  return name.suffix.isEmpty ? base : '$base, ${name.suffix}';
}

/// Junta [items] con la conjunción de [terms]: «A», «A y B», «A, B y C» —con
/// coma antes de «&» en inglés—.
///
/// [joiner] es lo que va antes del último: «y», «&» o «and». Con [commaForPair]
/// en falso, dos nombres no llevan la coma del inglés —«A and B»—, como en
/// IEEE; APA la escribe también con dos.
String joinList(
  List<String> items,
  CitationTerms terms, {
  required String joiner,
  bool commaForPair = true,
}) {
  if (items.isEmpty) return '';
  if (items.length == 1) return items.single;
  final head = items.sublist(0, items.length - 1).join(', ');
  final comma = terms.serialComma && (items.length > 2 || commaForPair)
      ? ','
      : '';
  final and = conjunctionBefore(joiner, items.last);
  return '$head$comma $and ${items.last}';
}

/// La conjunción [joiner] que va antes de [next]. En español «y» se vuelve «e»
/// delante de un nombre que empieza con el sonido «i» —«García e Iglesias»,
/// «Paz e Hidalgo»—, y sigue siendo «y» si la «i» suena a consonante
/// —«Hierro»— o si [next] empieza con una inicial —«y I. Iglesias»—. Cualquier
/// otra conjunción
/// —«&», «and»— se deja.
String conjunctionBefore(String joiner, String next) {
  if (joiner != 'y') return joiner;
  final word = normalizeVocabularyLabel(next)
      .split(RegExp(r'[^\p{L}]+', unicode: true))
      .firstWhere((token) => token.isNotEmpty, orElse: () => '');
  if (word.length < 2) return joiner;
  return RegExp('^h?i(?![aeou])').hasMatch(word) ? 'e' : joiner;
}

/// Los apellidos como van dentro del texto: uno, dos unidos con [joiner] o,
/// con tres o más, el primero con «et al.». Una institución va entera.
String inTextSurnames(
  List<PersonName> names,
  CitationTerms terms, {
  required String joiner,
}) {
  if (names.length == 1) return names.single.family;
  if (names.length == 2) {
    final and = conjunctionBefore(joiner, names.last.family);
    return '${names.first.family} $and ${names.last.family}';
  }
  return '${names.first.family} ${terms.etAl}';
}

/// La edición como la escribe una cita: «2.ª ed.», «2nd ed.». Un número solo
/// se vuelve ordinal; un texto que ya dice «ed.» se deja. `null` si no hay.
String? editionText(String? raw, CitationTerms terms) {
  final text = raw?.trim();
  if (text == null || text.isEmpty) return null;
  final number = int.tryParse(text);
  if (number != null) return '${terms.ordinal(number)} ${terms.editionAbbr}';
  if (RegExp(
    r'\bed(\.|ición|ition)?(\W|$)',
    caseSensitive: false,
  ).hasMatch(text)) {
    return text;
  }
  return '$text ${terms.editionAbbr}';
}

/// «pp. 345–359» o «p. 12», o `null` si no hay páginas.
String? pagesWithTerm(String? pages, CitationTerms terms) {
  if (pages == null) return null;
  final range = pageRange(pages);
  return '${isPageSpan(pages) ? terms.pages : terms.page} $range';
}

/// El pasaje citado: «p. 12», «pp. 12–14» o «0:14:35» —un instante no lleva
/// abreviatura—.
String locatorWithTerm(CitationLocator locator, CitationTerms terms) {
  if (locator.isTime) return locator.text;
  return pagesWithTerm(locator.text, terms)!;
}

/// [text] con la primera letra en mayúscula.
String capitalized(String text) =>
    text.isEmpty ? text : '${text[0].toUpperCase()}${text.substring(1)}';

/// Las páginas como las escribe una cita: el guion entre dos números pasa a
/// raya —«45-67» es «45–67»—. Lo que no tiene esa forma —«e1234», «S12-S15
/// (suplemento)»— se deja como está.
String pageRange(String pages) {
  final match = RegExp(r'^\s*([\w.]+)\s*-\s*([\w.]+)\s*$').firstMatch(pages);
  if (match == null) return pages.trim();
  return '${match[1]}–${match[2]}';
}

/// Si [pages] son varias: un rango o una lista.
bool isPageSpan(String pages) =>
    pages.contains('-') || pages.contains('–') || pages.contains(',');
