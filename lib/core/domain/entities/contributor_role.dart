/// Qué hizo una persona en una obra.
///
/// El encargo pide autores y traductor; se suman el editor —un capítulo se
/// cita «En A. B. (Ed.)»— y el director —un documental no tiene autor—, que
/// sin ellos no se pueden citar.
enum ContributorRole {
  /// Escribió la obra. Es el rol por defecto.
  author,

  /// La reunió o la dirigió como libro: el editor del volumen en el que sale
  /// un capítulo.
  editor,

  /// La tradujo.
  translator,

  /// La dirigió: un documental, una película.
  director,
}
