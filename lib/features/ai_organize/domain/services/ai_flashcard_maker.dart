import 'package:sinapsis/core/domain/entities/knowledge_item.dart';
import 'package:sinapsis/features/ai_organize/domain/services/ai_organize_step.dart';
import 'package:sinapsis/features/flashcards/domain/services/flashcard_style.dart';

/// Hacer **solo** las tarjetas de repaso de un elemento (F30): lo que pide
/// «Para cada documento» en la hoja de «Tarjetas didácticas» de Repasar (F43,
/// M18; antes, el ✨ de la barra) y «Llenar con IA» de un cuaderno, sin
/// vínculos, temas ni etiquetas.
///
/// Lo implementa el mismo paso de tarjetas de la IA que organiza sola
/// (`AutoFlashcardsStep`): las tarjetas son las mismas —por partes, con su
/// pasaje, lo dudoso a «Para revisar»—; cambia quién las pide. La cola lo
/// encuentra entre sus pasos.
// ignore: one_member_abstracts
abstract interface class AiFlashcardMaker {
  /// Las tarjetas de [item] dentro de la pasada [runId]. Sin
  /// [anotherBatch], completa lo que le falta para su cantidad
  /// (`flashcardTargetFor`): uno que ya tiene las suyas no suma ninguna. Con
  /// [anotherBatch], hace otra tanda entera aunque ya tenga —la persona pidió
  /// «también los que ya tienen»—, sin repetir ninguna pregunta.
  ///
  /// [style] es lo elegido en la hoja: el idioma, la dificultad, el tema y
  /// cuántas (F43, M18). [FlashcardStyle.plain], lo de siempre.
  Future<AiStepReport> makeFlashcards(
    KnowledgeItem item, {
    required String runId,
    bool anotherBatch = false,
    FlashcardStyle style = FlashcardStyle.plain,
  });
}
