final _propertyLine = RegExp(
  r'^PROPIEDAD:\s*(.+?)\s*\|\s*(.+)$',
  caseSensitive: false,
);

/// Una línea de sugerencia ya interpretada: la categoría, con la
/// capitalización CANÓNICA de `knownCategories` —no la que haya escrito el
/// modelo—, y el valor propuesto.
typedef ParsedPropertyLine = ({String category, String value});

/// Interpreta la respuesta cruda del modelo como una lista de propiedades.
///
/// Función pura, aparte de quien habla con el modelo — mismo criterio que
/// `parseRelationSuggestions`. A diferencia de ese parser, este SÍ valida
/// contra [knownCategories]: el modelo solo puede proponer un valor bajo una
/// categoría existente, nunca inventar una nueva (ver decisión D2 de F4) —
/// una línea cuya categoría no matchee ninguna conocida, sin distinguir
/// mayúsculas, se descarta en silencio.
List<ParsedPropertyLine> parsePropertySuggestions(
  String rawResponse, {
  required List<String> knownCategories,
}) {
  final results = <ParsedPropertyLine>[];

  for (final rawLine in rawResponse.split('\n')) {
    final line = rawLine.trim();
    if (line.isEmpty) continue;

    final match = _propertyLine.firstMatch(line);
    if (match == null) continue;

    final category = match.group(1)!.trim();
    final value = match.group(2)!.trim();
    if (value.isEmpty) continue;

    String? canonical;
    for (final known in knownCategories) {
      if (known.toLowerCase() == category.toLowerCase()) {
        canonical = known;
        break;
      }
    }
    if (canonical == null) continue;

    results.add((category: canonical, value: value));
  }

  return results;
}
