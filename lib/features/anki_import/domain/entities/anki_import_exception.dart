/// Por qué no se pudo leer un `.apkg`.
enum AnkiImportFailure {
  /// El archivo no existe o está vacío.
  emptyFile,

  /// No es un `.zip`, o no tiene la forma de un paquete de Anki.
  notAnApkg,

  /// Es un paquete de Anki, pero la colección de adentro está dañada o le
  /// faltan tablas.
  corrupt,

  /// Solo trae la colección del formato nuevo de Anki (`collection.anki21b`,
  /// comprimida con zstd), que Sinapsis no puede abrir.
  newFormatOnly,

  /// El paquete es de una versión de Anki que cambió el formato por dentro y
  /// no se sabe leer.
  unsupportedSchema,

  /// El disco falló al leer: sin espacio para el archivo de trabajo, o el
  /// archivo se movió mientras se leía.
  unreadable,
}

/// Lo que lanza el lector de `.apkg` cuando no puede: siempre esto, nunca una
/// excepción cruda del zip o de SQLite. [message] está en español y listo
/// para mostrar.
class AnkiImportException implements Exception {
  const AnkiImportException(this.failure, this.message, {this.cause});

  final AnkiImportFailure failure;
  final String message;

  /// Lo que falló por debajo (la excepción original), para el registro de
  /// diagnóstico; no se muestra.
  final Object? cause;

  @override
  String toString() => 'AnkiImportException(${failure.name}): $message';
}
