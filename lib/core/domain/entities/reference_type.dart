/// Qué clase de obra es lo que se cita: lo que decide cómo se arma su cita.
///
/// Es un dato de la OBRA, no de cómo llegó a la bóveda: un mismo libro puede
/// estar guardado como un PDF (`SourceKind.document`) o como una referencia
/// sin texto (`SourceKind.reference`), y en los dos casos se cita como un
/// libro. Por eso no reemplaza a `SourceKind`, que dice de dónde vino.
///
/// Son los ocho tipos del encargo más [other]. Los que un archivo `.bib` o
/// `.ris` trae y no caben en ninguno —una patente, un programa— no se
/// adivinan: se reportan y se saltan.
enum ReferenceType {
  /// Un libro entero.
  book,

  /// Un capítulo o una parte de un libro, con su título propio y el del libro
  /// en el contenedor.
  chapter,

  /// Un artículo de una revista, de un diario o de unas actas.
  article,

  /// Una tesis o una disertación.
  thesis,

  /// Un documento de archivo, una carta, un decreto: lo que se estudia y no
  /// lo que se lee sobre ello.
  primarySource,

  /// Un documental o un video.
  documentary,

  /// Una página o un sitio web.
  website,

  /// Una publicación en una red social o en un foro.
  onlinePublication,

  /// Lo que no es ninguno de los anteriores: se cita con una plantilla
  /// genérica que marca lo que falta.
  other,
}
