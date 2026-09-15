import 'package:sinapsis/core/domain/entities/relation_kind.dart';

final _suggestionLine = RegExp(
  r'^SUGERENCIA:\s*(\d+)\s*\|\s*(\w+)\s*\|\s*(.+)$',
  caseSensitive: false,
);

/// Una línea de sugerencia ya interpretada, todavía apuntando al índice de
/// la lista de candidatos que se le mandó al modelo — no a un `itemId`
/// directamente: es `GemmaChatModel` quien sabe a qué candidato corresponde
/// cada número, no este parser.
typedef ParsedSuggestionLine = ({
  int candidateIndex,
  RelationKind kind,
  String reason,
});

/// Interpreta la respuesta cruda del modelo como una lista de sugerencias.
///
/// Función pura, aparte de quien habla con el modelo — mismo criterio que
/// `parseFlashcardDrafts`: lo único que puede fallar acá es el formato de un
/// texto, y eso se prueba sin ningún modelo de lenguaje corriendo de
/// verdad. El formato pedido es una línea por sugerencia,
/// `SUGERENCIA: <número> | <clave> | <motivo>`, y una línea que no matchea
/// se ignora en silencio en vez de hacer fallar el lote entero por una sola
/// que el modelo escribió distinto.
List<ParsedSuggestionLine> parseRelationSuggestions(String rawResponse) {
  final results = <ParsedSuggestionLine>[];

  for (final rawLine in rawResponse.split('\n')) {
    final line = rawLine.trim();
    if (line.isEmpty) continue;

    final match = _suggestionLine.firstMatch(line);
    if (match == null) continue;

    final index = int.tryParse(match.group(1)!);
    final kind = _kindFor(match.group(2)!);
    final reason = match.group(3)!.trim();
    if (index == null || kind == null || reason.isEmpty) continue;

    // Los números que manda el modelo son 1-based —la posición que vio en
    // la lista que se le mandó—, y el índice que usa quien llama a este
    // parser es 0-based.
    results.add((candidateIndex: index - 1, kind: kind, reason: reason));
  }

  return results;
}

RelationKind? _kindFor(String token) => switch (token.toLowerCase()) {
  'relacionado' => RelationKind.relatedTo,
  'continua' => RelationKind.continues,
  'contradice' => RelationKind.contradicts,
  'cita' => RelationKind.cites,
  'resume' => RelationKind.summarizes,
  _ => null,
};
