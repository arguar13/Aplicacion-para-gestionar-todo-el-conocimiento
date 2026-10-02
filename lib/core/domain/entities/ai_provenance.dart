import 'package:meta/meta.dart';

/// De qué pasada de la IA sale algo que se crea (F27), y qué tan segura
/// estaba.
///
/// Es lo que separa crear algo a mano de que la IA lo aplique sola: quien crea
/// un vínculo, una tarjeta o una propiedad sin esto la crea como de la persona;
/// con esto queda marcada como de la IA, con su pasada, y se puede deshacer de
/// un saque con todo lo demás de esa pasada.
@immutable
class AiProvenance {
  const AiProvenance({required this.runId, this.confidence});

  /// La pasada (`AiRunRepository.startRun`) que la crea.
  final String runId;

  /// De 0 a 1, si la IA lo sabe. Solo se guarda en los vínculos: es lo que
  /// decide, más adelante, qué se aplica solo y qué va a «Para revisar».
  final double? confidence;

  @override
  bool operator ==(Object other) =>
      other is AiProvenance &&
      other.runId == runId &&
      other.confidence == confidence;

  @override
  int get hashCode => Object.hash(runId, confidence);
}
