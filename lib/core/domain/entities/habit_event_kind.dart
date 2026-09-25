/// Una de las dos acciones de D6 (F17, racha) que no dejan ningún rastro
/// propio en ningún otro lado —a diferencia de repasar una tarjeta
/// (`review_log`) o editar una nota viva (`field_version`), que ya lo
/// hacen—: hace falta guardarlas aparte para saber en qué día pasaron.
enum HabitEventKind {
  /// Aceptar o descartar una sugerencia de la Bandeja. `reject()` nunca
  /// escribe nada más; `accept()` solo a veces —según el tipo de
  /// sugerencia— toca un campo con versión, así que no alcanza con mirar
  /// `field_version`.
  triage,

  /// Fusionar, renombrar o mover un valor del vocabulario.
  /// `VocabularyOperation` —lo que cada una de esas operaciones
  /// devuelve— vive en memoria a propósito, para poder deshacerse; no
  /// deja ninguna fila que diga cuándo pasó.
  vocabulary,
}
