// El doble lanza lo que el test le dé, y el tipo tiene que ser `Object`
// porque `Exception` y `Error` no comparten más supertipo que ese.
// ignore_for_file: only_throw_errors

import 'package:sinapsis/features/graph/domain/services/relation_suggestion_service.dart';

/// Un servicio de sugerencias de mentira, para las pruebas de pantalla que
/// no están probando `flutter_gemma` en sí.
class FakeRelationSuggestionService implements RelationSuggestionService {
  FakeRelationSuggestionService({this.suggestions = const [], this.error});

  /// Lo que "sugiere" [suggestRelations]. Mutable a propósito.
  List<RelationSuggestion> suggestions;

  /// Si está, se lanza en vez de sugerir.
  Object? error;

  /// Cada pedido que se hizo, en orden — el título semilla y cuántos
  /// candidatos se le mandaron —, para comprobar en las pruebas qué se le
  /// pidió al modelo.
  final requests = <({String seedTitle, int candidateCount})>[];

  /// Qué candidatos llegaron en cada pedido, en el mismo orden que
  /// [requests]: para comprobar qué se dejó afuera antes de preguntar.
  final candidateIdsSent = <List<String>>[];

  @override
  Future<List<RelationSuggestion>> suggestRelations({
    required String seedTitle,
    required String seedExcerpt,
    required List<RelationCandidate> candidates,
  }) async {
    requests.add((seedTitle: seedTitle, candidateCount: candidates.length));
    candidateIdsSent.add([for (final c in candidates) c.itemId]);
    final err = error;
    if (err != null) throw err;
    return suggestions;
  }
}
