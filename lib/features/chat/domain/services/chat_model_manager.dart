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
  /// [huggingFaceToken] es necesario para Gemma: el repositorio en Hugging
  /// Face está protegido (hay que aceptar la licencia de Google con una
  /// cuenta gratuita), así que una descarga anónima siempre falla con 401,
  /// sin importar la conexión de quien la pide. Ver
  /// [ChatModelNeedsAuthentication].
  ///
  /// El stream emite el progreso de 0.0 a 1.0 a medida que avanza, y se
  /// cierra solo al terminar. Un error en el medio llega como un error del
  /// stream, sin dejar el modelo a medio instalar.
  Stream<double> download({String? huggingFaceToken});

  /// Si hay una descarga del modelo en curso a la que engancharse: con el
  /// gestor de descargas del sistema, también una que siguió con la app
  /// cerrada (F29). Al abrir la app, la descarga se sigue mostrando en vez
  /// de ofrecer bajarlo de nuevo.
  Future<bool> isDownloading();

  /// Corta la descarga en curso, si hay una, y borra lo bajado.
  Future<void> cancelDownload();
}

/// Por qué falló una descarga, en términos que la pantalla pueda mostrar sin
/// conocer nada de `flutter_gemma` ni de HTTP — esa traducción es trabajo de
/// la implementación de [ChatModelManager], no de quien mira este tipo.
sealed class ChatModelDownloadError {
  const ChatModelDownloadError();
}

/// El repositorio pide autenticarse (401/403): falta un token de Hugging
/// Face, o el que se guardó no tiene acceso a este modelo en particular.
class ChatModelNeedsAuthentication extends ChatModelDownloadError {
  const ChatModelNeedsAuthentication();
}

/// Cualquier otra falla —de verdad de conexión, del servidor, o algo que
/// esta app no supo clasificar—.
///
/// Sin mensaje propio a propósito: el texto que sabe explicarlo bien vive
/// en la pantalla (`l10n`), no en la capa de datos. [technicalDetail] es
/// solo para telemetría, nunca para mostrarse.
class ChatModelDownloadFailed extends ChatModelDownloadError {
  const ChatModelDownloadFailed([this.technicalDetail]);

  final String? technicalDetail;
}
