import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/domain/services/vocabulary_normalizer.dart';

/// El valor de [definitionId] al que [text] se refiere: por su label o, si
/// ninguno coincide, por uno de sus alias. Sin distinguir mayúsculas ni
/// acentos (`normalizeVocabularyLabel`).
///
/// Se compara en Dart y no con `lower()` en SQL: el `lower()` y el
/// `COLLATE NOCASE` de SQLite solo conocen ASCII —"Álgebra" y "álgebra" no
/// coinciden por ahí— y no hay forma de plegar acentos sin una función
/// propia. Leer los valores de UNA categoría es barato; la consulta con
/// `lower()` tampoco podía usar el índice y recorría esos mismos valores.
///
/// Un label gana siempre sobre un alias. [excludingValueId] deja afuera a un
/// valor de la búsqueda POR LABEL —al renombrar, un valor no choca consigo
/// mismo—; los alias no se excluyen: uno propio también bloquea el nombre.
///
/// Lo comparten el repositorio de organización —asignar, resolver y
/// renombrar— y el de Vocabulario —renombrar y agregar alias—: los dos tienen
/// que decidir igual qué es "el mismo texto".
Future<PropertyValueRow?> findValueByLabelOrAlias(
  AppDatabase db,
  String definitionId,
  String text, {
  String? excludingValueId,
}) async {
  final wanted = normalizeVocabularyLabel(text);
  if (wanted.isEmpty) return null;
  final typed = text.trim();

  final values = await (db.select(
    db.propertyValues,
  )..where((v) => v.definitionId.equals(definitionId))).get();
  final byLabel = _closestMatch<PropertyValueRow>(
    values.where(
      (v) =>
          v.id != excludingValueId &&
          normalizeVocabularyLabel(v.value) == wanted,
    ),
    typed: typed,
    labelOf: (v) => v.value,
    createdAtOf: (v) => v.createdAt,
    idOf: (v) => v.id,
  );
  if (byLabel != null) return byLabel;

  final aliases = await (db.select(
    db.propertyAliases,
  )..where((a) => a.definitionId.equals(definitionId))).get();
  final alias = _closestMatch<PropertyAliasRow>(
    aliases.where((a) => normalizeVocabularyLabel(a.alias) == wanted),
    typed: typed,
    labelOf: (a) => a.alias,
    createdAtOf: (a) => a.createdAt,
    idOf: (a) => a.id,
  );
  if (alias == null) return null;

  return (db.select(
    db.propertyValues,
  )..where((v) => v.id.equals(alias.propertyValueId))).getSingleOrNull();
}

/// De varios [candidates] que normalizan igual a lo que se escribió, el que
/// se elige: el que se escribió idéntico, después el que solo difiere en
/// mayúsculas, y si no el más antiguo (con el id de desempate).
///
/// Que haya más de uno es posible en bases de antes de F8: el índice único de
/// SQLite solo ve mayúsculas ASCII, así que "Roma" y "Róma" convivían. Sin un
/// criterio fijo, cuál de los dos gana dependería del orden en que la base
/// los devuelva.
T? _closestMatch<T>(
  Iterable<T> candidates, {
  required String typed,
  required String Function(T) labelOf,
  required DateTime Function(T) createdAtOf,
  required String Function(T) idOf,
}) {
  int rank(T candidate) {
    final label = labelOf(candidate);
    if (label == typed) return 0;
    if (label.toLowerCase() == typed.toLowerCase()) return 1;
    return 2;
  }

  int compare(T a, T b) {
    final byRank = rank(a).compareTo(rank(b));
    if (byRank != 0) return byRank;
    final byAge = createdAtOf(a).compareTo(createdAtOf(b));
    if (byAge != 0) return byAge;
    return idOf(a).compareTo(idOf(b));
  }

  T? best;
  for (final candidate in candidates) {
    if (best == null || compare(candidate, best) < 0) best = candidate;
  }
  return best;
}
