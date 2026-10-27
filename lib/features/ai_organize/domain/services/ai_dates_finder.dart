import 'package:sinapsis/core/domain/entities/knowledge_item.dart';
import 'package:sinapsis/features/ai_organize/domain/services/ai_organize_step.dart';

/// Buscar **solo** los hechos fechados de un elemento para la línea de tiempo
/// (F40): lo que piden «Organizar con IA» de la línea de tiempo y «Buscar
/// fechas con IA» del detalle, sin vínculos, tarjetas, temas ni etiquetas.
///
/// Lo implementa el mismo paso de fechas de la IA que organiza sola
/// (`AutoDatesStep`): los hechos son los mismos —por partes, con su cita, sin
/// repetir—; cambia quién los pide. La cola lo encuentra entre sus pasos.
abstract interface class AiDatesFinder {
  /// Si el texto de [item] tiene alguna fecha escrita que valga la pena
  /// preguntarle al modelo. Es una lectura local y sin IA: la cola la mira
  /// antes de abrir la pasada, para que un elemento sin ninguna no deje una
  /// pasada vacía —pedirle fechas a toda la biblioteca son miles de
  /// elementos—.
  Future<bool> mentionsDates(KnowledgeItem item);

  /// Los hechos fechados de [item] dentro de la pasada [runId]. Cuenta en el
  /// informe cuántos puso (`AiStepReport.applied`).
  ///
  /// Si el modelo deja de contestar a mitad —sin cuota, sin conexión—, lanza;
  /// llamado otra vez con la misma pasada, sigue desde donde quedó.
  Future<AiStepReport> findDates(KnowledgeItem item, {required String runId});
}
