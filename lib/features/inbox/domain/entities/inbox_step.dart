import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:sinapsis/features/processed/domain/entities/process_outcome.dart';

part 'inbox_step.freezed.dart';

/// Qué se hizo con una fuente en la Bandeja.
enum InboxStepKind {
  discarded,

  /// Se trió con la hoja «¿Qué va a Procesado?» (F41): su documento procesado
  /// guarda lo elegido —el texto, el resumen, la síntesis, las notas
  /// extraídas, los fragmentos cortados— y queda triada.
  triaged,

  /// «Pasar todo sin modificar» (F41): su documento procesado guarda el texto
  /// original entero, y queda triada.
  passedUnchanged,

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
/// texto que recuperar al deshacer. Lo que sí se deshace es lo que triar armó
/// en «Procesado» ([processUndo]).
@freezed
sealed class InboxStep with _$InboxStep {
  const factory InboxStep({
    required String itemId,
    required String title,
    required InboxStepKind kind,

    /// Con [InboxStepKind.linked], el vínculo que deshacer.
    LinkedNote? linkedNote,

    /// Con [InboxStepKind.triaged] o [InboxStepKind.passedUnchanged], cómo
    /// dejar el documento procesado como estaba (F41): si nació al triar, se
    /// va; si ya existía, vuelve a lo que tenía.
    ProcessUndo? processUndo,
  }) = _InboxStep;
}
