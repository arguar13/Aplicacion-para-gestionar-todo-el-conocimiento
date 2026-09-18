import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_gemma/flutter_gemma.dart' hide EmbeddingModel;
import 'package:flutter_gemma/rag/embedding_models.dart' show EmbeddingModel;
import 'package:sinapsis/features/chat/data/services/http_gemma_model_downloader.dart';
import 'package:sinapsis/features/relations/domain/services/embedding_model_manager.dart'
    as domain;

/// El único modelo de embeddings que la app baja — sin selector de
/// variantes como el chat (ver la decisión sobre F5, D9): nadie interactúa
/// directo con "el embedder", solo se beneficia de que exista. 8-bit en vez
/// de fp32 (300MB) porque corre automáticamente en cada captura nueva, no
/// es una acción puntual que se pide una vez.
const _model = EmbeddingModel.embeddingGemma300M8bit;

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
  const GemmaEmbeddingModelManager({required this.downloader});

  final HttpGemmaModelDownloader downloader;

  @override
  Future<bool> isReady() async => FlutterGemma.hasActiveEmbedder();

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
        url: _model.url,
        fileName: _model.filename,
        token: token,
      );
      await for (final value in modelProgress) {
        if (!controller.isClosed) controller.add(value * 0.9);
      }

      final tokenizerProgress = downloader.download(
        url: _model.tokenizerUrl,
        fileName: _model.tokenizerFilename,
        token: token,
      );
      await for (final value in tokenizerProgress) {
        if (!controller.isClosed) controller.add(0.9 + value * 0.1);
      }

      final modelFile = await downloader.targetFile(_model.filename);
      final tokenizerFile = await downloader.targetFile(
        _model.tokenizerFilename,
      );
      await FlutterGemma.installEmbedder()
          .modelFromFile(modelFile.path)
          .tokenizerFromFile(tokenizerFile.path)
          .install();

      if (!controller.isClosed) await controller.close();
      // Catch-all deliberado, mismo motivo que `GemmaChatModelManager`: la
      // descarga y la instalación pueden fallar cada una por su cuenta, y
      // las dos tienen que llegar como el mismo tipo de error.
      // ignore: avoid_catches_without_on_clauses
    } catch (e, stackTrace) {
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
