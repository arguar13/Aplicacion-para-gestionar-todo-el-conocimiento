import 'package:meta/meta.dart';

/// El nombre de una persona o de una institución, con el apellido y el nombre
/// separados: lo que hace falta para citarlo.
///
/// Las normas no citan igual «Gabriel García Márquez» en la bibliografía
/// («García Márquez, G.») que en una nota («Gabriel García Márquez»), y eso
/// no se puede hacer con un texto entero. Por eso el nombre se guarda
/// partido, y por eso esta clase no adivina: quien la arma dice cuál es el
/// apellido.
///
/// El apellido lleva adentro su partícula («de la Vega», «van Gogh», «von
/// Ranke»): se ordena y se muestra junto con ella. Separarla es distinguir
/// entre normas que la sueltan al invertir el nombre y las que no, y para
/// una bibliografía en español o en inglés no vale la complicación.
@immutable
class PersonName {
  /// Una persona con su [family] y su [given], y su [suffix] si lo tiene
  /// («Jr.»).
  const PersonName({
    required this.family,
    this.given = '',
    this.suffix = '',
    this.isInstitution = false,
  });

  /// Una institución o un nombre que no se parte: «Organización Mundial de la
  /// Salud», «Real Academia Española», o el nombre de un canal.
  const PersonName.institution(String name)
    : family = name,
      given = '',
      suffix = '',
      isInstitution = true;

  /// El apellido, con su partícula. En una institución, su nombre entero.
  final String family;

  /// El nombre de pila. Vacío en una institución y en un nombre de una sola
  /// palabra («Tucídides», «Platón»).
  final String given;

  /// «Jr.», «III»… Casi siempre vacío.
  final String suffix;

  /// Si es una institución: no se invierte ni se abrevia.
  final bool isInstitution;

  /// Si no tiene ni apellido ni nombre.
  bool get isEmpty => family.trim().isEmpty && given.trim().isEmpty;

  /// La etiqueta con que el vocabulario controlado guarda a esta persona:
  /// «Apellido, Nombre». Es lo que se compara para saber si dos autores son
  /// el mismo, así que es la forma canónica y no la de una norma.
  String get label {
    if (isInstitution) return family;
    final base = [family, given].where((part) => part.isNotEmpty).join(', ');
    return suffix.isEmpty ? base : '$base $suffix';
  }

  /// El nombre como se lee en una nota: «Nombre Apellido».
  String get displayName {
    if (isInstitution) return family;
    final base = [given, family].where((part) => part.isNotEmpty).join(' ');
    return suffix.isEmpty ? base : '$base $suffix';
  }

  /// Las iniciales del nombre de pila: «G. J.» para «Gabriel José», «J.-P.»
  /// para «Jean-Paul», «J. R. R.» para «J.R.R.». Vacío en una institución o
  /// si no hay nombre de pila.
  String get initials {
    if (isInstitution || given.trim().isEmpty) return '';
    final words = <String>[];
    for (final word in given.trim().split(RegExp(r'\s+'))) {
      final hyphenated = <String>[];
      for (final part in word.split('-')) {
        final letters = <String>[];
        for (final piece in part.split('.')) {
          final initial = _firstLetter(piece);
          if (initial != null) letters.add('${initial.toUpperCase()}.');
        }
        if (letters.isNotEmpty) hyphenated.add(letters.join(' '));
      }
      if (hyphenated.isNotEmpty) words.add(hyphenated.join('-'));
    }
    return words.join(' ');
  }

  /// Una copia con lo que se cambie.
  PersonName copyWith({
    String? family,
    String? given,
    String? suffix,
    bool? isInstitution,
  }) => PersonName(
    family: family ?? this.family,
    given: given ?? this.given,
    suffix: suffix ?? this.suffix,
    isInstitution: isInstitution ?? this.isInstitution,
  );

  @override
  bool operator ==(Object other) =>
      other is PersonName &&
      other.family == family &&
      other.given == given &&
      other.suffix == suffix &&
      other.isInstitution == isInstitution;

  @override
  int get hashCode => Object.hash(family, given, suffix, isInstitution);

  @override
  String toString() =>
      'PersonName($label${isInstitution ? ', institución' : ''})';
}

/// La primera letra de [text], sin contar lo que no es una letra —comillas,
/// paréntesis, llaves—; `null` si no hay ninguna.
String? _firstLetter(String text) {
  for (final rune in text.runes) {
    final char = String.fromCharCode(rune);
    if (char.toLowerCase() != char.toUpperCase()) return char;
  }
  return null;
}
