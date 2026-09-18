/// En qué punto del trabajo intelectual está un elemento: si ya se decidió
/// qué hacer con él, y qué tanto se hizo.
///
/// No es lo mismo que [ProcessingState] —ese es del pipeline técnico
/// (¿ya se descargó, transcribió o extrajo el texto?)—: acá el eje es la
/// decisión humana sobre algo que ya terminó de procesarse. Un elemento
/// puede estar `ProcessingState.ready` y a la vez `ItemState.captured`,
/// recién llegado, sin que nadie lo haya mirado todavía.
enum ItemState {
  /// Recién entró. Nadie decidió todavía si vale la pena trabajarlo.
  captured,

  /// El pipeline técnico ya terminó con él —está listo para que el
  /// usuario lo triage—, sin que eso implique ninguna decisión tomada.
  processed,

  /// El usuario ya lo miró y decidió que vale la pena: puede pasar directo
  /// a [discarded], o quedar acá esperando a que se trabaje del todo.
  triaged,

  /// Ya se extrajeron sus notas atómicas y se vinculó a las notas vivas
  /// que correspondía. El trabajo intelectual sobre esta fuente terminó.
  distilled,

  /// El usuario decidió que no vale la pena. No se borra: sigue existiendo,
  /// solo deja de aparecer en la bandeja de entrada.
  discarded,
}
