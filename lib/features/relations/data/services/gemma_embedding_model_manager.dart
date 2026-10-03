import 'dart:async';

import 'package:dio/dio.dart';
import 'package:sinapsis/features/chat/data/services/gemma_runtime.dart';
import 'package:sinapsis/features/chat/data/services/http_gemma_model_downloader.dart';
import 'package:sinapsis/features/relations/domain/services/embedding_model_manager.dart'
    as domain;

/// El único modelo de embeddings que la app baja —sin selector de
/// variantes como el chat (ver la decisión sobre F5, D9): nadie interactúa
/// directo con "el embedder", solo se beneficia de que exista—.
///
/// De `litert-community/embeddinggemma-300m`, el repositorio cuya licencia
/// la pantalla pide aceptar y el mismo que usa el ejemplo oficial de
/// `flutter_gemma`. Antes salía de `EmbeddingModel.embeddingGemma300M8bit`
/// del paquete, que apunta a `google/embeddinggemma-300m-8bit`: ese
/// repositorio no existe para nadie —responde 401 hasta a la consulta
/// pública de su ficha (medido el 2026-10-03)—, así que la descarga fallaba
/// siempre con "comprobá tu conexión", aceptara quien aceptara la licencia
/// del otro.
///
/// La exportación de precisión mixta para textos de hasta 1024 piezas (183
/// MB): un tramo de nota tiene hasta 2000 caracteres
/// (`kNoteEmbeddingPieceChars`, unas 500 piezas) y uno de transcripción, 75
/// segundos de habla (unas 300), así que la de 512 quedaba justa y la de
/// 2048 pesa más sin hacer falta.
const _modelUrl =
    'https://huggingface.co/litert-community/embeddinggemma-300m/resolve/'
    'main/embeddinggemma-300M_seq1024_mixed-precision.tflite';
const _modelFilename = 'embeddinggemma-300M_seq1024_mixed-precision.tflite';
const _tokenizerUrl =
    'https://huggingface.co/litert-community/embeddinggemma-300m/resolve/'
    'main/sentencepiece.model';
const _tokenizerFilename = 'embeddinggemma-sentencepiece.model';

/// Lo que pesa cada archivo según Hugging Face
/// (`/api/models/litert-community/embeddinggemma-300m/tree/main`, consultado
/// el 2026-10-03): para reconocer lo que se bajó antes de que la descarga
/// dejara su marca de terminada (ver `HttpGemmaModelDownloader.isComplete`).
const _modelPublishedBytes = 183329528;
const _tokenizerPublishedBytes = 4683319;

/// [domain.EmbeddingModelManager] sobre `flutter_gemma`, con la descarga
/// bajada a mano vía [HttpGemmaModelDownloader] —reusado tal cual del
/// feature `chat`, sin nada específico del modelo de chat— por el mismo
/// motivo que `GemmaChatModelManager`: la descarga que hace `flutter_gemma`
/// por dentro no retoma bien un corte a medias.
///
/// Un embedder necesita DOS archivos —modelo y tokenizador—, así que el
/// progreso reportado es el combinado de ambas descargas: 0-90% el modelo
/// (el más pesado con diferencia), 90-100% el tokenizador.
class GemmaEmbeddingModelManager implements domain.EmbeddingModelManager {
  GemmaEmbeddingModelManager({
    required this.downloader,
    GemmaRuntime runtime = const FlutterGemmaRuntime(),
  }) : _runtime = runtime;

  final HttpGemmaModelDownloader downloader;
  final GemmaRuntime _runtime;

  /// La comprobación en curso: ver `GemmaChatModelManager`.
  Future<bool>? _checking;

  /// Si el modelo está en el dispositivo, listo para calcular vectores; si
  /// sus dos archivos están enteros pero `flutter_gemma` no lo tiene activo,
  /// lo registra en el acto.
  ///
  /// Mismo motivo que `GemmaChatModelManager.isReady`: `flutter_gemma`
  /// 1.8.3 no recuerda entre sesiones un modelo instalado desde un archivo
  /// fuera de la raíz de sus documentos.
  @override
  Future<bool> isReady() =>
      _checking ??= _ensureReady().whenComplete(() => _checking = null);

  Future<bool> _ensureReady() async {
    if (_runtime.hasActiveEmbedder) return true;
    final complete =
        await downloader.isComplete(
          _modelFilename,
          publishedBytes: _modelPublishedBytes,
        ) &&
        await downloader.isComplete(
          _tokenizerFilename,
          publishedBytes: _tokenizerPublishedBytes,
        );
    if (!complete) return false;
    await _install();
    return _runtime.hasActiveEmbedder;
  }

  Future<void> _install() async {
    final modelFile = await downloader.targetFile(_modelFilename);
    final tokenizerFile = await downloader.targetFile(_tokenizerFilename);
    await _runtime.installEmbedderFiles(
      modelPath: modelFile.path,
      tokenizerPath: tokenizerFile.path,
    );
  }

  @override
  Future<int?> downloadSizeInBytes() async {
    // Mismo criterio que `GemmaChatModelManager`: el tamaño aproximado que
    // ve quien elige descargar está en el texto de la pantalla, no acá.
    return null;
  }

  @override
  Stream<double> download({String? huggingFaceToken}) {
    final controller = StreamController<double>();
    unawaited(_runDownload(controller, huggingFaceToken));
    return controller.stream;
  }

  Future<void> _runDownload(
    StreamController<double> controller,
    String? token,
  ) async {
    try {
      final modelProgress = downloader.download(
        url: _modelUrl,
        fileName: _modelFilename,
        token: token,
        publishedBytes: _modelPublishedBytes,
      );
      await for (final value in modelProgress) {
        if (!controller.isClosed) controller.add(value * 0.9);
      }

      final tokenizerProgress = downloader.download(
        url: _tokenizerUrl,
        fileName: _tokenizerFilename,
        token: token,
        publishedBytes: _tokenizerPublishedBytes,
      );
      await for (final value in tokenizerProgress) {
        if (!controller.isClosed) controller.add(0.9 + value * 0.1);
      }

      await _install();
      if (!controller.isClosed) await controller.close();
    } on Object catch (e, stackTrace) {
      // Mismo criterio que `GemmaChatModelManager`: la descarga y la
      // instalación pueden fallar cada una por su cuenta, y las dos tienen
      // que llegar como el mismo tipo de error.
      if (!controller.isClosed) {
        controller.addError(_toDomainError(e), stackTrace);
      }
      if (!controller.isClosed) await controller.close();
    }
  }

  /// Traduce lo que salga mal —bajando cualquiera de los dos archivos o
  /// instalándolos— a algo que la pantalla pueda mostrar sin necesitar
  /// saber nada de HTTP ni de `flutter_gemma`. Mismo criterio que
  /// `GemmaChatModelManager._toDomainError`.
  domain.EmbeddingModelDownloadError _toDomainError(Object e) {
    if (e is DioException) {
      final status = e.response?.statusCode;
      if (status == 401 || status == 403) {
        return const domain.EmbeddingModelNeedsAuthentication();
      }
    }
    return domain.EmbeddingModelDownloadFailed(e.toString());
  }
}
