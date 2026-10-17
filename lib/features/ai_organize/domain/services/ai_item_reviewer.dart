import 'package:sinapsis/core/domain/entities/knowledge_item.dart';
import 'package:sinapsis/features/ai_organize/domain/services/ai_organize_step.dart';

/// Revisa lo que hizo la IA en un elemento, con el modelo elegido ahora (F33,
/// «Revisar con otro modelo»), y deja lo que propone corregir o sacar en
/// «Revisión». Nunca cambia nada: eso pasa si la persona acepta.
///
/// Lo usa la cola de revisión (`AiReviewQueue`), dentro de una pasada de
/// revisión (`AiRunScope.review`).
// ignore: one_member_abstracts
abstract interface class AiItemReviewer {
  /// Revisa [item] dentro de la pasada [runId] del modelo [model]. Con
  /// [exceptMadeBy], deja afuera lo que hizo ese modelo: al revisar toda la
  /// biblioteca, un modelo no revisa lo suyo. Devuelve cuántas correcciones
  /// dejó (`forReview`).
  ///
  /// Puede lanzar, como un paso de la IA: el modelo es de terceros.
  Future<AiStepReport> review(
    KnowledgeItem item, {
    required String runId,
    String? model,
    String? exceptMadeBy,
  });
}

/// Varios revisores de un elemento, uno detrás del otro: las tarjetas y lo
/// demás (F33). Para la cola son uno solo; lo que proponen se suma.
class AiItemReviewers implements AiItemReviewer {
  const AiItemReviewers(this._reviewers);

  final List<AiItemReviewer> _reviewers;

  @override
  Future<AiStepReport> review(
    KnowledgeItem item, {
    required String runId,
    String? model,
    String? exceptMadeBy,
  }) async {
    var applied = 0;
    var forReview = 0;
    for (final reviewer in _reviewers) {
      final report = await reviewer.review(
        item,
        runId: runId,
        model: model,
        exceptMadeBy: exceptMadeBy,
      );
      applied += report.applied;
      forReview += report.forReview;
    }
    return AiStepReport(applied: applied, forReview: forReview);
  }
}
