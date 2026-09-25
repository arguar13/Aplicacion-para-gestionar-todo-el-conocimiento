import 'package:sinapsis/features/flashcards/domain/entities/topic_error_summary.dart';

/// A qué tema del Atlas concentró los errores una sesión de quiz (F20,
/// commit 8): "de dónde salió la pregunta que se falló", no "de dónde salió
/// cada opción" —el tema de una pregunta es el de `Flashcard.itemId`, mismo
/// criterio que ya usa la exportación a Anki para armar subdecks—.
// ignore: one_member_abstracts
abstract interface class QuizSessionSummaryService {
  /// [missedItemIds] es el `itemId` de cada pregunta fallada, uno por
  /// pregunta —repetido si varias preguntas falladas salieron del mismo
  /// elemento—. Agrupado por tema, de más a menos errores; un elemento sin
  /// ningún tema asignado no aporta a ningún grupo. Vacío si
  /// [missedItemIds] está vacío.
  Future<List<TopicErrorSummary>> summarize(List<String> missedItemIds);
}
