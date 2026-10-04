import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/core/logging/logger_provider.dart';
import 'package:sinapsis/core/network/model_download_providers.dart';
import 'package:sinapsis/features/chat/presentation/providers/chat_providers.dart';
import 'package:sinapsis/features/chat/presentation/providers/hugging_face_token_notifier.dart';
import 'package:sinapsis/features/relations/presentation/providers/relations_providers.dart';
import 'package:sinapsis/features/transform/presentation/providers/model_download_notifier.dart';
import 'package:sinapsis/features/transform/presentation/providers/transform_providers.dart';

/// Al abrir la app (F29): las descargas de los modelos que siguieron con la
/// app cerrada —las baja el gestor del sistema— vuelven a verse en su
/// pantalla, con su avance o con cómo terminaron, y lo que esperaba el
/// modelo se entera cuando queda listo. No pide ninguna descarga nueva: si
/// no había una en curso, no hace nada.
///
/// Una por modelo, cada una por su cuenta: que no se pueda mirar una no
/// impide engancharse a las otras.
///
/// [read] es el `read` de quien llama: el de la app (`WidgetRef`) o el de
/// una prueba (`ProviderContainer`).
Future<void> resumeModelDownloads(
  T Function<T>(ProviderListenable<T> provider) read,
) async {
  // Bajadas dentro de la app —el escritorio, sin gestor del sistema—, las
  // descargas mueren con ella: al abrirla no hay ninguna a qué engancharse.
  if (!read(modelFileTransferProvider).continuesWithAppClosed) return;

  final chat = read(chatModelManagerProvider);
  final embedding = read(embeddingModelManagerProvider);
  final whisper = read(whisperModelManagerProvider);

  Future<void> resume(
    String model,
    ModelDownloadNotifier notifier,
    Future<bool> Function() isDownloading,
    Stream<double> Function() download,
  ) async {
    try {
      await notifier.resume(isDownloading: isDownloading, download: download);
    } on Object catch (e, stackTrace) {
      // Sin poder mirarla, la pantalla ofrece "Descargar", y tocarlo se
      // engancha igual a la que sigue: no es motivo para frenar el arranque.
      read(
        appLoggerProvider,
      ).warning('No se pudo retomar la descarga de $model', e, stackTrace);
    }
  }

  await Future.wait([
    resume(
      'el modelo de lenguaje',
      read(chatModelDownloadProvider.notifier),
      chat.isDownloading,
      () => chat.download(
        huggingFaceToken: read(huggingFaceTokenNotifierProvider),
      ),
    ),
    resume(
      'el modelo de relaciones',
      read(embeddingModelDownloadProvider.notifier),
      embedding.isDownloading,
      () => embedding.download(
        huggingFaceToken: read(huggingFaceTokenNotifierProvider),
      ),
    ),
    resume(
      'el modelo de transcripción',
      read(transcriptionModelDownloadProvider.notifier),
      whisper.isDownloading,
      whisper.download,
    ),
  ]);
}
