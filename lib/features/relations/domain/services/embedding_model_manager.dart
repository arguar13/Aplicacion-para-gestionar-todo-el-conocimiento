/// Trae y guarda el modelo de embeddings que preselecciona candidatos por
/// similitud para el motor de relaciones, sin que nadie más sepa de dónde
/// sale ni dónde queda.
///
/// Mismo criterio que `ChatModelManager`/`WhisperModelManager` (decisión
/// 8): el modelo pesa varios cientos de MB y no viene con la app, así que
/// hace falta bajarlo aparte, una sola vez, con el permiso explícito de
/// quien usa la app.
///
/// Interfaz PARALELA a `ChatModelManager`, no una extensión: `flutter_gemma`
/// gestiona el embedder y el modelo de chat como dos "modelos activos"
/// totalmente independientes (`hasActiveEmbedder()`/`getActiveEmbedder()`
/// contra `hasActiveModel()`/`getActiveModel()`), y la descarga de un
/// embedder necesita DOS archivos —modelo y tokenizador, cada uno con su
/// propia URL— mientras `ChatModelManager.download()` asume uno solo. Ver
/// la decisión sobre F5 en docs/arquitectura.md.
abstract interface class EmbeddingModelManager {
  /// Si el modelo ya está descargado y activo, listo para generar
  /// embeddings.
  Future<bool> isReady();

  /// Cuánto pesa la descarga completa, en bytes, si se puede saber de
  /// antemano. `null` si no se pudo consultar.
  Future<int?> downloadSizeInBytes();

  /// Descarga el modelo —y su tokenizador— y lo deja activo.
  ///
  /// [huggingFaceToken] es necesario: el repositorio en Hugging Face está
  /// protegido, mismo gate que el modelo de chat. El stream emite el
  /// progreso combinado de 0.0 a 1.0 y se cierra solo al terminar. Un
  /// error en el medio llega como un error del stream, sin dejar el
  /// modelo a medio instalar.
  Stream<double> download({String? huggingFaceToken});

  /// Si hay una descarga del modelo en curso a la que engancharse: con el
  /// gestor de descargas del sistema, también una que siguió con la app
  /// cerrada (F29). Al abrir la app, la descarga se sigue mostrando en vez
  /// de ofrecer bajarlo de nuevo.
  Future<bool> isDownloading();

  /// Corta la descarga en curso, si hay una, y borra lo bajado.
  Future<void> cancelDownload();
}

/// Por qué falló una descarga, en términos que la pantalla pueda mostrar
/// sin conocer nada de `flutter_gemma` ni de HTTP — mismo criterio que
/// `ChatModelDownloadError`.
sealed class EmbeddingModelDownloadError {
  const EmbeddingModelDownloadError();
}

/// El repositorio pide autenticarse (401/403): falta un token de Hugging
/// Face, o el que se guardó no tiene acceso a este modelo en particular.
class EmbeddingModelNeedsAuthentication extends EmbeddingModelDownloadError {
  const EmbeddingModelNeedsAuthentication();
}

/// Cualquier otra falla —de verdad de conexión, del servidor, o algo que
/// esta app no supo clasificar—.
///
/// Sin mensaje propio a propósito: el texto que sabe explicarlo bien vive
/// en la pantalla (`l10n`), no en la capa de datos. [technicalDetail] es
/// solo para telemetría, nunca para mostrarse.
class EmbeddingModelDownloadFailed extends EmbeddingModelDownloadError {
  const EmbeddingModelDownloadFailed([this.technicalDetail]);
  final String? technicalDetail;
}
