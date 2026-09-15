import 'package:sinapsis/core/domain/entities/relation_kind.dart';

/// Un candidato a vincular con el elemento semilla: lo mínimo que necesita
/// el modelo para juzgar si están relacionados, sin mandarle el elemento
/// entero.
class RelationCandidate {
  const RelationCandidate({
    required this.itemId,
    required this.title,
    required this.excerpt,
  });

  final String itemId;
  final String title;
  final String excerpt;
}

/// Un vínculo que el modelo cree que existe, todavía sin guardar.
///
/// Mismo criterio que `FlashcardDraft`: quien la pidió revisa, descarta o
/// confirma antes de que exista de verdad. Una sugerencia mala se ignora con
/// un toque; un vínculo guardado por error hay que borrarlo a mano.
class RelationSuggestion {
  const RelationSuggestion({
    required this.itemId,
    required this.kind,
    required this.reason,
  });

  final String itemId;
  final RelationKind kind;
  final String reason;
}

/// Propone vínculos entre un elemento semilla y una lista de candidatos,
/// usando el mismo modelo de lenguaje del chat.
///
/// Nunca guarda nada por su cuenta: solo sugiere, con la misma asimetría que
/// justifica ese mismo diseño en `FlashcardGenerator` — descartar una mala
/// sugerencia cuesta un toque, deshacer un vínculo guardado por error cuesta
/// encontrarlo y borrarlo a mano.
// ignore: one_member_abstracts
abstract interface class RelationSuggestionService {
  /// Hasta un vínculo por cada [candidates] que el modelo considere
  /// relacionado con el elemento semilla. Lista vacía si no encontró
  /// ninguno — no es un error, es una sugerencia que no sirvió.
  Future<List<RelationSuggestion>> suggestRelations({
    required String seedTitle,
    required String seedExcerpt,
    required List<RelationCandidate> candidates,
  });
}
