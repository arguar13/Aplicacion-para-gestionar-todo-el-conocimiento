import 'package:sinapsis/core/domain/entities/ai_certainty.dart';
import 'package:sinapsis/core/domain/entities/relation_kind.dart';

final _suggestionLine = RegExp(
  r'^SUGERENCIA:\s*(\d+)\s*\|\s*(\w+)\s*\|\s*(.+)$',
  caseSensitive: false,
);

/// La certeza al principio del motivo (F27): `alta | motivo`.
final _certaintyPrefix = RegExp(r'^(\w+)\s*\|\s*(.+)$');

/// Una línea de sugerencia ya interpretada, todavía apuntando al índice de
/// la lista de candidatos que se le mandó al modelo — no a un `itemId`
/// directamente: es `GemmaChatModel` quien sabe a qué candidato corresponde
/// cada número, no este parser.
///
/// `certainty` es lo que el modelo dijo de su propia certeza (F27), `null` si
/// no lo dijo —el formato de antes, que se sigue aceptando—.
typedef ParsedSuggestionLine = ({
  int candidateIndex,
  RelationKind kind,
  String reason,
  AiCertainty? certainty,
});

/// Interpreta la respuesta cruda del modelo como una lista de sugerencias.
///
/// Función pura, aparte de quien habla con el modelo — mismo criterio que
/// `parseFlashcardDrafts`: lo único que puede fallar acá es el formato de un
/// texto, y eso se prueba sin ningún modelo de lenguaje corriendo de
/// verdad. El formato pedido es una línea por sugerencia,
/// `SUGERENCIA: <número> | <clave> | <certeza> | <motivo>` —la certeza, desde
/// F27; sin ella también se lee—, y una línea que no matchea
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
    var reason = match.group(3)!.trim();
    AiCertainty? certainty;
    // Solo cuenta como certeza si la primera palabra es una de las tres: un
    // motivo que casualmente tiene una barra sigue siendo un motivo entero.
    final prefixed = _certaintyPrefix.firstMatch(reason);
    if (prefixed != null) {
      certainty = AiCertainty.parse(prefixed.group(1)!);
      if (certainty != null) reason = prefixed.group(2)!.trim();
    }
    if (index == null || kind == null || reason.isEmpty) continue;

    // Los números que manda el modelo son 1-based —la posición que vio en
    // la lista que se le mandó—, y el índice que usa quien llama a este
    // parser es 0-based.
    results.add((
      candidateIndex: index - 1,
      kind: kind,
      reason: reason,
      certainty: certainty,
    ));
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
