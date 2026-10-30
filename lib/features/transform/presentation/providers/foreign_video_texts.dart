import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/core/database/database_provider.dart';
import 'package:sinapsis/core/logging/logger_provider.dart';
import 'package:sinapsis/core/telemetry/telemetry_provider.dart';
import 'package:sinapsis/features/library/presentation/providers/library_providers.dart';
import 'package:sinapsis/features/processed/presentation/providers/processed_text_refresh.dart';
import 'package:sinapsis/features/transform/data/repositories/video_text_repository_impl.dart';
import 'package:sinapsis/features/transform/domain/entities/stored_video_text.dart';
import 'package:sinapsis/features/transform/domain/repositories/video_text_repository.dart';
import 'package:sinapsis/features/transform/presentation/providers/processing_queue.dart';

final videoTextRepositoryProvider = Provider<VideoTextRepository>(
  (ref) => VideoTextRepositoryImpl(
    database: ref.watch(appDatabaseProvider),
    telemetry: ref.watch(telemetryServiceProvider),
  ),
);

/// Los videos de la Bandeja con el texto en otro idioma que el que se habla
/// (F45, paso 4), en el orden de la Bandeja.
final pendingForeignVideoTextsProvider =
    StreamProvider.autoDispose<List<ForeignVideoText>>(
      (ref) =>
          ref.watch(videoTextRepositoryProvider).watchPending().map(_foreignOf),
    );

/// Los documentos de Procesado que salieron de un video y tienen su texto en
/// otro idioma que el que se habla (F45, paso 4).
final processedForeignVideoTextsProvider =
    StreamProvider.autoDispose<List<ForeignVideoText>>(
      (ref) => ref
          .watch(videoTextRepositoryProvider)
          .watchProcessed()
          .map(_foreignOf),
    );

List<ForeignVideoText> _foreignOf(List<StoredVideoText> videos) => [
  for (final video in videos)
    if (foreignVideoTextOf(video) case final foreign?) foreign,
];

/// El video `sourceId` de la Bandeja, si su texto está en otro idioma.
final pendingForeignVideoTextProvider = Provider.autoDispose
    .family<ForeignVideoText?, String>(
      (ref, sourceId) => ref
          .watch(pendingForeignVideoTextsProvider)
          .valueOrNull
          ?.where((foreign) => foreign.sourceId == sourceId)
          .firstOrNull,
    );

/// El documento `documentId` de Procesado, si su texto está en otro idioma.
final processedForeignVideoTextProvider = Provider.autoDispose
    .family<ForeignVideoText?, String>(
      (ref, documentId) => ref
          .watch(processedForeignVideoTextsProvider)
          .valueOrNull
          ?.where((foreign) => foreign.video.documentId == documentId)
          .firstOrNull,
    );

/// Vuelve a extraer el texto de [videos] (F45, paso 4), y devuelve a cuántos
/// se les pidió. Los que ya se están extrayendo se saltan.
///
/// - **La fuente**, en la cola de siempre (`ProcessingQueueNotifier.
///   reextract`), con el idioma guardado corregido antes: si es el del texto
///   equivocado —lo puso una versión anterior al guardar la pista que
///   bajó—, se borra, y el video se transcribe en el que se habla
///   ([languageToReextract]).
/// - **Desde Procesado**, además, el texto nuevo va al documento cuando
///   llega ([ProcessedTextRefresh]); y si la fuente ya lo tiene en su idioma
///   —se volvió a extraer desde la Bandeja o la Biblioteca—, se trae ahora,
///   sin volver a extraer.
Future<int> reextractForeignVideos(
  Ref ref,
  Iterable<ForeignVideoText> videos,
) async {
  final library = ref.read(libraryRepositoryProvider);
  final queue = ref.read(processingQueueProvider.notifier);
  final refresh = ref.read(processedTextRefreshProvider);
  var asked = 0;
  for (final foreign in videos) {
    if (foreign.video.reextracting) continue;
    final processed = foreign.video.documentId != null;
    if (processed && foreign.sourceFits) {
      if (await refresh.updateNow(foreign.sourceId)) asked++;
      continue;
    }
    final language = languageToReextract(foreign);
    if (language != foreign.video.language) {
      final found = await library.findById(foreign.sourceId);
      final current = found.getRight().toNullable();
      if (current != null) {
        final saved = await library.save(
          current.copyWith(source: current.source.copyWith(language: language)),
        );
        if (saved.getLeft().toNullable() case final failure?) {
          ref
              .read(appLoggerProvider)
              .warning(
                'No se pudo corregir el idioma de ${foreign.sourceId}: '
                '$failure',
              );
        }
      }
    }
    if (processed) await refresh.request(foreign.sourceId);
    await queue.reextract(foreign.sourceId);
    asked++;
  }
  return asked;
}

/// [reextractForeignVideos] con lo que da un `WidgetRef`: el de los botones.
final reextractForeignVideosProvider =
    Provider<Future<int> Function(Iterable<ForeignVideoText> videos)>(
      (ref) =>
          (videos) => reextractForeignVideos(ref, videos),
    );
