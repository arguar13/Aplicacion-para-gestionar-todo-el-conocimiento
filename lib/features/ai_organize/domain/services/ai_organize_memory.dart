/// Lo poco que la cola de la IA recuerda fuera de la base (F27).
///
/// Lo pendiente NO está acá: se deduce de la base, de las pasadas
/// (`AiOrganizeBacklog`). Esto es solo lo que la base no sabe decir.
abstract interface class AiOrganizeMemory {
  /// Desde cuándo la IA organiza sola en este dispositivo: la primera vez que
  /// se pregunta, ahora. Lo creado antes es la biblioteca que ya existía —se
  /// recorre solo con el teléfono cargando (decisión C)—; lo creado después
  /// es nuevo y se organiza apenas está listo.
  Future<DateTime> epoch();

  /// Cuántos caracteres tenía la nota [itemId] la última vez que la IA la
  /// organizó; `null` si nunca o si no se sabe.
  int? noteLengthSeen(String itemId);

  /// Recuerda que la IA organizó la nota [itemId] cuando tenía [length]
  /// caracteres: lo que decide si después cambió tanto como para volver a
  /// organizarla.
  Future<void> rememberNoteLength(String itemId, int length);
}
