import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/core/domain/entities/knowledge_item.dart';
import 'package:sinapsis/core/domain/entities/processing_failure_reason.dart';
import 'package:sinapsis/core/domain/entities/source_kind.dart';
import 'package:sinapsis/features/transform/domain/entities/cancellation_signal.dart';
import 'package:sinapsis/features/transform/domain/usecases/download_youtube_audio_usecase.dart';
import 'package:sinapsis/features/transform/domain/usecases/processing_failure_classifier.dart';
import 'package:sinapsis/features/transform/presentation/providers/transform_providers.dart';

/// Si a [item] le falta el audio para escucharlo en la app: un video de
/// YouTube sin archivo propio todavía (F24). En la web no hay dónde
/// guardarlo como archivo.
bool needsYouTubeAudio(KnowledgeItem item) =>
    !kIsWeb &&
    item.source.kind == SourceKind.youtube &&
    item.source.originalFilePath == null &&
    item.source.url != null;

/// En qué va la descarga del audio de un video de YouTube.
sealed class YouTubeAudioDownloadState {
  const YouTubeAudioDownloadState();
}

/// Sin descarga en curso.
class AudioDownloadIdle extends YouTubeAudioDownloadState {
  const AudioDownloadIdle();
}

/// Bajando: [fraction] de 0 a 1, o `null` si YouTube no informó el total.
class AudioDownloading extends YouTubeAudioDownloadState {
  const AudioDownloading(this.fraction);

  final double? fraction;
}

/// No se pudo, por [reason].
class AudioDownloadFailed extends YouTubeAudioDownloadState {
  const AudioDownloadFailed(this.reason);

  final ProcessingFailureReason reason;
}

/// La descarga del audio de un video de YouTube. Desde F24 se hace sola
/// —apenas el video queda listo, o al abrirlo si todavía no la tiene—, sin
/// que nadie la pida; antes era a pedido (F21, decisión B).
///
/// Vive aparte de la pantalla: salir del detalle no corta la descarga, y
/// volver muestra cuánto va.
class YouTubeAudioDownloadNotifier
    extends StateNotifier<YouTubeAudioDownloadState> {
  YouTubeAudioDownloadNotifier({
    required this.itemId,
    required DownloadYouTubeAudioUseCase Function() download,
  }) : _download = download,
       super(const AudioDownloadIdle());

  final String itemId;
  final DownloadYouTubeAudioUseCase Function() _download;
  CancellationSignal? _cancellation;

  /// Empieza a bajar. Si ya está bajando, no hace nada.
  Future<void> start() async {
    if (state is AudioDownloading) return;

    final cancellation = CancellationSignal();
    _cancellation = cancellation;
    state = const AudioDownloading(null);

    try {
      await _download()(
        itemId,
        cancellation: cancellation,
        onProgress: (received, total) {
          if (!mounted || cancellation.isCancelled) return;
          state = AudioDownloading(
            total == null || total <= 0 ? null : received / total,
          );
        },
      );
      if (mounted) state = const AudioDownloadIdle();
    } on ProcessingCancelledException {
      if (mounted) state = const AudioDownloadIdle();
      // Cualquier otro fallo se muestra con su motivo, como un procesamiento
      // fallido: sin conexión, video no disponible...
      // ignore: avoid_catches_without_on_clauses
    } catch (error) {
      if (mounted) {
        state = AudioDownloadFailed(processingFailureReasonFor(error));
      }
    } finally {
      if (identical(_cancellation, cancellation)) _cancellation = null;
    }
  }

  /// Corta la descarga en curso: no queda ningún archivo a medias.
  void cancel() => _cancellation?.cancel();

  @override
  void dispose() {
    _cancellation?.cancel();
    super.dispose();
  }
}

/// Deliberadamente NO autoDispose: la descarga sigue aunque se salga del
/// detalle.
final youTubeAudioDownloadProvider =
    StateNotifierProvider.family<
      YouTubeAudioDownloadNotifier,
      YouTubeAudioDownloadState,
      String
    >(
      (ref, itemId) => YouTubeAudioDownloadNotifier(
        itemId: itemId,
        download: () => ref.read(downloadYouTubeAudioUseCaseProvider),
      ),
    );
