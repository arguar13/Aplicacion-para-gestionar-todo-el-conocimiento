import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:sinapsis/core/domain/entities/note_maturity.dart';

part 'grown_note.freezed.dart';

/// Una nota que creció en la ventana mirada: con bloques o relaciones nuevas.
///
/// Es el punto de entrada de la sesión de consolidación: se abre cada una, se
/// reescribe como texto continuo y se marca madura.
@freezed
sealed class GrownNote with _$GrownNote {
  const factory GrownNote({
    required String itemId,
    required String title,
    required NoteMaturity maturity,

    /// Bloques con texto que se agregaron en la ventana.
    required int newBlocks,

    /// Relaciones que se crearon en la ventana, en cualquiera de los dos
    /// sentidos.
    required int newRelations,
  }) = _GrownNote;

  const GrownNote._();

  /// Cuánto creció, para ordenar: lo que más creció, primero.
  int get growth => newBlocks + newRelations;
}
