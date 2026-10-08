import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:sinapsis/core/domain/entities/item_state.dart';

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
@freezed
sealed class InboxStep with _$InboxStep {
  const factory InboxStep({
    required String itemId,
    required String title,
    required InboxStepKind kind,

    /// El estado en que estaba antes: deshacer lo devuelve a ese, no a uno
    /// supuesto.
    required ItemState previousState,

    /// Con [InboxStepKind.linked], el vínculo que deshacer.
    LinkedNote? linkedNote,

    /// Lo que se soltó del elemento al triarlo —su archivo o su texto, en la
    /// papelera del contenido— (F30, decisión 68): deshacer lo recupera.
    @Default(<String>[]) List<String> trashedContentIds,
  }) = _InboxStep;
}
