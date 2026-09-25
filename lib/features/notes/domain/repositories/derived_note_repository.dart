import 'package:sinapsis/features/notes/domain/entities/derived_note_mark.dart';

/// La procedencia de una nota generada (F16, D3): quién la escribió, y si
/// el usuario ya la hizo suya editándola.
abstract interface class DerivedNoteRepository {
  /// La marca de [itemId], emitiendo de nuevo cada vez que cambia. `null`
  /// si no es una nota generada —la inmensa mayoría—.
  Stream<DerivedNoteMark?> watchMark(String itemId);

  /// Marca que el usuario ya tocó el contenido de la nota generada
  /// [itemId]. No hace nada si no es una nota generada o ya estaba
  /// marcada.
  Future<void> markEdited(String itemId);
}
