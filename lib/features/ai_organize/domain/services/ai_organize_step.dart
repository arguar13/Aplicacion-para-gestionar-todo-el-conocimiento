import 'package:flutter/foundation.dart';
import 'package:fpdart/fpdart.dart';
import 'package:sinapsis/core/domain/entities/knowledge_item.dart';
import 'package:sinapsis/core/error/failures.dart';
import 'package:sinapsis/features/ai_organize/domain/entities/ai_organize_settings.dart';

/// Una de las cosas que hace la IA sobre un elemento (F27): vincularlo, sus
/// tarjetas, sus temas y propiedades, su espacio, los datos de su referencia.
///
/// La cola de la IA los corre de a uno, dentro de una pasada
/// (`AiRunRepository.startRun`), y solo los que tienen prendido su
/// interruptor ([toggle]).
abstract interface class AiOrganizeStep {
  /// El interruptor de Ajustes › IA que lo prende y lo apaga.
  AiOrganizeToggle get toggle;

  /// Hace su parte sobre [item]. Todo lo que crea lleva la pasada [runId],
  /// para que se pueda deshacer.
  ///
  /// Puede lanzar —el modelo de lenguaje es de terceros, la base puede
  /// fallar—: la cola registra el error y sigue con el paso siguiente. Lo que
  /// el paso ya había creado queda, con su pasada.
  Future<AiStepReport> organize(KnowledgeItem item, {required String runId});
}

/// Lo que hizo un paso: cuánto aplicó solo y cuánto dejó en «Para revisar»
/// porque no estaba segura (decisión B).
@immutable
class AiStepReport {
  const AiStepReport({this.applied = 0, this.forReview = 0});

  static const nothing = AiStepReport();

  final int applied;
  final int forReview;

  @override
  bool operator ==(Object other) =>
      other is AiStepReport &&
      other.applied == applied &&
      other.forReview == forReview;

  @override
  int get hashCode => Object.hash(applied, forReview);

  @override
  String toString() => 'AiStepReport(applied: $applied, review: $forReview)';
}

/// Un repositorio contestó con un fallo en medio de un paso de la IA.
class AiStepFailure implements Exception {
  const AiStepFailure(this.what, this.failure);

  /// Qué se estaba haciendo.
  final String what;
  final Failure failure;

  @override
  String toString() => 'AiStepFailure($what): $failure';
}

/// Para los pasos de la IA: el valor, o [AiStepFailure] si fue un fallo. Un
/// paso que no puede leer lo que necesita no tiene cómo seguir bien, y la
/// cola registra lo que lanza.
extension AiStepEither<T> on Either<Failure, T> {
  T orThrowStep(String what) =>
      match((failure) => throw AiStepFailure(what, failure), (value) => value);
}
