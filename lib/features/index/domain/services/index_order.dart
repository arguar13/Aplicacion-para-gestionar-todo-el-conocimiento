import 'package:sinapsis/core/util/word_folding.dart';

/// La clave con que se ordena un nombre del Índice de la A a la Z (F46): sin
/// mayúsculas ni acentos, como lo lee una persona —«Ágora» va con la A, no
/// después de «Zama», que es lo que haría `COLLATE NOCASE` de SQLite, que
/// solo entiende ASCII—. Lo que no es letra ni número queda tal cual, en
/// minúscula: un espacio sigue separando palabras.
///
/// La ñ es una letra propia, después de la n, como en el diccionario:
/// «Ñandú» va después de «nilo» y antes de «oasis». Su clave es una n seguida
/// de `~`, que va después de toda letra sin acento.
String indexSortKey(String name) {
  final key = StringBuffer();
  for (final unit in name.trim().runes) {
    final char = String.fromCharCode(unit).toLowerCase();
    key.write(char == 'ñ' ? 'n~' : foldWordChar(unit) ?? char);
  }
  return key.toString();
}

/// Compara dos nombres por [indexSortKey]; si son iguales así, por cómo están
/// escritos, para que el orden no dependa de cómo llegaron.
int compareIndexNames(String a, String b) {
  final byKey = indexSortKey(a).compareTo(indexSortKey(b));
  return byKey != 0 ? byKey : a.compareTo(b);
}
