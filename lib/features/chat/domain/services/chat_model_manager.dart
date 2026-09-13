/// Trae y guarda el modelo de lenguaje que redacta las respuestas del chat,
/// sin que nadie más sepa de dónde sale ni dónde queda.
///
/// Mismo criterio que `WhisperModelManager` (Fase 7, decisión 8): el modelo
/// pesa cientos de megas a varios gigas y no viene con la app, así que hace
/// falta bajarlo aparte, una sola vez, con el permiso explícito de quien usa
/// la app — nunca junto con la app, y nunca en silencio.
abstract interface class ChatModelManager {
  /// Si el modelo ya está descargado y activo, listo para responder.
  Future<bool> isReady();

  /// Cuánto pesa la descarga completa, en bytes, si se puede saber de
  /// antemano. `null` si no se pudo consultar.
  Future<int?> downloadSizeInBytes();

  /// Descarga el modelo y lo deja activo para responder.
  ///
  /// El stream emite el progreso de 0.0 a 1.0 a medida que avanza, y se
  /// cierra solo al terminar. Un error en el medio llega como un error del
  /// stream, sin dejar el modelo a medio instalar.
  Stream<double> download();
}
