/// Por qué no se pudo procesar un elemento.
///
/// Se guarda con la fuente (`source.processing_error`, por su nombre) para
/// que la interfaz pueda decir la causa real y ofrecer lo que la resuelve
/// —descargar un modelo, reintentar con conexión— en vez de un "no se pudo"
/// genérico y un reintento que va a fallar igual.
enum ProcessingFailureReason {
  /// La app se cerró a mitad de procesarlo demasiadas veces seguidas. Se deja
  /// de reintentar solo para que algo que la hace caer no entre en un bucle.
  interrupted,

  /// Tardó demasiado, o dejó de avanzar.
  timedOut,

  /// Hace falta el modelo de transcripción y todavía no se descargó.
  transcriptionModelMissing,

  /// El video o la publicación ya no está, es privado o es de pago.
  unavailable,

  /// La página se trajo, pero no tenía un artículo que extraer.
  noArticle,

  /// El documento está dañado, cifrado o en una versión que no se puede leer.
  unreadableDocument,

  /// El archivo original ya no está en el almacenamiento de la app.
  missingOriginalFile,

  /// Sin conexión, o el servidor no respondió.
  network,

  /// Cualquier otra cosa.
  unknown;

  /// El motivo guardado con [name], o [unknown] si no se reconoce —uno que
  /// escribió una versión más nueva de la app, por ejemplo—.
  static ProcessingFailureReason? fromStored(String? name) {
    if (name == null) return null;
    return values.where((reason) => reason.name == name).firstOrNull ?? unknown;
  }
}
