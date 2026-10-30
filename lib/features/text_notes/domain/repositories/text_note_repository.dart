import 'package:fpdart/fpdart.dart';
import 'package:sinapsis/core/domain/entities/highlight_color.dart';
import 'package:sinapsis/core/error/failures.dart';
import 'package:sinapsis/features/text_notes/domain/entities/text_note.dart';
import 'package:sinapsis/features/text_notes/domain/entities/text_note_target.dart';

/// Las notas en el texto (F45, mejora 19, decisión I): ponerlas, editarlas,
/// cambiarles el color, borrarlas con «Deshacer» y listarlas en el orden del
/// texto.
///
/// Cada texto, por su clave ([TextNoteTarget]): lo de la Biblioteca no aparece
/// en Procesado ni al revés. Las notas de los resaltados de antes (F38) se leen
/// con las del original de la Biblioteca, por esta misma interfaz, y sus
/// cambios van al resaltado.
///
/// Nada de esto toca nunca el documento: ni su texto, ni su archivo, ni sus
/// marcas. Borrar una nota borra la nota; la de un resaltado le saca la nota
/// y el resaltado queda (decisión E).
abstract interface class TextNoteRepository {
  /// Las notas de [target], en el orden del texto (`compareInTextOrder`), al
  /// día. Las del original de la Biblioteca traen también las de sus
  /// resaltados de antes.
  Stream<List<TextNote>> watchNotes(TextNoteTarget target);

  /// Cuántas notas tiene [target], al día: lo que dice «Notas (N)». Cuenta
  /// lo mismo que [watchNotes] sin traer ninguna.
  Stream<int> watchCount(TextNoteTarget target);

  /// Pone una nota en `[start, end)` del texto de [target], sobre [excerpt]
  /// —ese tramo, tal como se ve—. Falla si el tramo no es válido o si la nota
  /// está en blanco.
  Future<Either<Failure, TextNote>> create({
    required TextNoteTarget target,
    required int start,
    required int end,
    required String excerpt,
    required String note,
    required HighlightColor color,
  });

  /// Cambia lo que dice [note]. Una nota no queda en blanco: para sacarla, se
  /// borra.
  Future<Either<Failure, TextNote>> edit(TextNote note, String text);

  /// Cambia el color de [note].
  Future<Either<Failure, TextNote>> recolor(
    TextNote note,
    HighlightColor color,
  );

  /// Borra [note] y la devuelve tal como estaba, para «Deshacer» con
  /// [restore]. La de un resaltado de antes le saca la nota; el resaltado
  /// queda.
  Future<Either<Failure, TextNote>> delete(TextNote note);

  /// Vuelve a poner [note] tal como estaba antes de [delete]: el mismo id, el
  /// mismo lugar, las mismas fechas. Falla si su texto ya no está —la fuente,
  /// el documento o la creación se borraron de verdad— o si el resaltado de
  /// una nota de antes ya no existe.
  Future<Either<Failure, Unit>> restore(TextNote note);
}
