import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/core/network/model_download_providers.dart';
import 'package:sinapsis/features/chat/presentation/providers/chat_providers.dart';
import 'package:sinapsis/features/chat/presentation/providers/hugging_face_token_notifier.dart';
import 'package:sinapsis/features/relations/presentation/providers/relations_providers.dart';
import 'package:sinapsis/features/transform/presentation/providers/transform_providers.dart';

/// Al abrir la app (F29): las descargas de los modelos que siguieron con la
/// app cerrada —las baja el gestor del sistema— vuelven a verse en su
/// pantalla, con su avance o con cómo terminaron, y lo que esperaba el
/// modelo se entera cuando queda listo. No pide ninguna descarga nueva: si
/// no había una en curso, no hace nada.
///
/// Una por modelo, cada una por su cuenta: que no se pueda mirar una no
/// impide engancharse a las otras, y el error de esa se lanza al final.
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

  // `Future.wait` espera a las tres aunque una falle, y después lanza el
  // primer error: no mirar una no deja sin engancharse a las otras, y el
  // fallo llega a quien llama —en la app, a la telemetría— en vez de
  // perderse.
  await Future.wait([
    read(chatModelDownloadProvider.notifier).resume(
      isDownloading: chat.isDownloading,
      download: () => chat.download(
        huggingFaceToken: read(huggingFaceTokenNotifierProvider),
      ),
    ),
    read(embeddingModelDownloadProvider.notifier).resume(
      isDownloading: embedding.isDownloading,
      download: () => embedding.download(
        huggingFaceToken: read(huggingFaceTokenNotifierProvider),
      ),
    ),
    read(
      transcriptionModelDownloadProvider.notifier,
    ).resume(isDownloading: whisper.isDownloading, download: whisper.download),
  ]);
}
