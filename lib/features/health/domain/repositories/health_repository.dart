import 'package:sinapsis/core/domain/entities/note_kind.dart';
import 'package:sinapsis/features/health/domain/entities/grown_note.dart';
import 'package:sinapsis/features/health/domain/entities/note_composition.dart';

/// Las consultas del panel de salud de la bóveda: cuánto hay por hacer en cada
/// frente de mantenimiento, sin recorrer el contenido de nada más de lo
/// necesario.
///
/// Todas son reactivas: el panel se actualiza solo cuando algo cambia.
///
/// Lo que ya tenía dueño no se repite acá: cuántos pendientes hay en la
/// Bandeja lo dice `InboxRepository`, los candidatos de vocabulario a fusionar
/// salen del motor de F8 y las sugerencias pendientes de
/// `SuggestionRepository`. Una sola definición de "pendiente" por frente.
abstract interface class HealthRepository {
  /// De qué está hecha la bóveda de notas, por subtipo y por madurez.
  Stream<NoteComposition> watchNoteComposition();

  /// Cuántas contradicciones faltan por revisar: vínculos `contradicts` sin la
  /// marca de revisado.
  Stream<int> watchUnreviewedContradictionCount();

  /// Cuántos títulos distintos hay escritos entre `[[ ]]` sin ninguna nota que
  /// los reciba. Es lo que cuenta la vista de enlaces rotos: un título, aunque
  /// lo escriban varias notas.
  Stream<int> watchBrokenLinkCount();

  /// Las notas de los subtipos [kinds] que crecieron desde [since] —con
  /// bloques con texto o relaciones nuevas—, las que más crecieron primero.
  ///
  /// Por defecto, solo las vivas: una nota atómica no crece —es una idea sola,
  /// y otra idea es otra nota— y una nota mapa es solo estructura. Las que
  /// nacen en la ventana, en cambio, sí aparecen: nacer es tener bloques
  /// nuevos.
  Stream<List<GrownNote>> watchGrownNotes({
    required DateTime since,
    Set<NoteKind> kinds = const {NoteKind.living},
  });
}
