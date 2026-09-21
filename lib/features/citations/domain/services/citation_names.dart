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
/// [joiner] es lo que va antes del último: «y», «&» o «and».
String joinList(
  List<String> items,
  CitationTerms terms, {
  required String joiner,
}) {
  if (items.isEmpty) return '';
  if (items.length == 1) return items.single;
  final head = items.sublist(0, items.length - 1).join(', ');
  final comma = terms.serialComma ? ',' : '';
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
