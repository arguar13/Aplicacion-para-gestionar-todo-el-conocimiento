import 'package:freezed_annotation/freezed_annotation.dart';

part 'inbox_step.freezed.dart';

/// Qué se hizo con una fuente en la Bandeja.
enum InboxStepKind {
  discarded,
  triaged,

  /// Se abrió para extraerle notas: queda triada.
  extracted,

  /// Se vinculó a una nota viva: queda triada.
  linked,

  /// Se revisaron sus sugerencias: queda triada.
  reviewed,
}

/// La nota viva a la que se vinculó una fuente, y si se creó para eso.
@freezed
sealed class LinkedNote with _$LinkedNote {
  const factory LinkedNote({
    required String id,
    required String title,

    /// Si la nota nació en esta misma acción —desde el selector, porque no
    /// había ninguna o se pidió una nueva—. Deshacer la manda a la papelera;
    /// una que ya existía no se toca.
    required bool created,
  }) = _LinkedNote;
}

/// Una decisión tomada en la Bandeja, con lo que hace falta para revertirla
/// (F28): el historial de «Deshacer» es una pila de estos.
///
/// Deshacer la devuelve a la Bandeja (`InboxRepository.returnToInbox`), al
/// estado de espera que le corresponde **ahora** —`captured` si su texto
/// todavía se está sacando, `processed` si ya terminó—, no al que tenía al
/// decidir: una fuente descartada mientras se transcribía pudo terminar de
/// transcribirse antes de que se deshiciera (F41).
///
/// Triar nunca suelta nada de la fuente (F41, decisión G): no hay archivo ni
/// texto que recuperar al deshacer.
@freezed
sealed class InboxStep with _$InboxStep {
  const factory InboxStep({
    required String itemId,
    required String title,
    required InboxStepKind kind,

    /// Con [InboxStepKind.linked], el vínculo que deshacer.
    LinkedNote? linkedNote,
  }) = _InboxStep;
}
