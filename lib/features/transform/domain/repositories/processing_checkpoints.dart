import 'package:sinapsis/core/domain/entities/processing_checkpoint_kind.dart';

/// El avance guardado de un trabajo largo sobre un elemento (F21): lo que
/// necesita un transformador para seguir desde donde quedó —la página 212
/// de 400, el tramo 30 de 48— en vez de empezar de nuevo cada vez que la app
/// se cierra.
///
/// Se borra solo cuando el elemento termina de procesarse bien: hasta
/// entonces, cada intento lo retoma.
abstract interface class ProcessingCheckpoints {
  /// Las partes ya hechas de [kind] para [itemId]: posición → contenido.
  Future<Map<int, String>> load(String itemId, ProcessingCheckpointKind kind);

  /// Guarda que la parte [position] ya está hecha, con su [content].
  ///
  /// Guardar una parte nueva es prueba de avance: el elemento deja de
  /// contar como "se interrumpió sin avanzar", y cerrar la app varias veces
  /// en un libro largo no lo da por fallido.
  Future<void> save(
    String itemId,
    ProcessingCheckpointKind kind, {
    required int position,
    required String content,
  });
}
