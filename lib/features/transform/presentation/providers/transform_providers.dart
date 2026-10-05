import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sinapsis/core/database/database_provider.dart';
import 'package:sinapsis/core/database/reference_reader.dart';
import 'package:sinapsis/core/domain/entities/processing_failure_reason.dart';
import 'package:sinapsis/core/logging/logger_provider.dart';
import 'package:sinapsis/core/network/model_download_providers.dart';
import 'package:sinapsis/core/network/network_providers.dart';
import 'package:sinapsis/core/storage/storage_providers.dart';
import 'package:sinapsis/core/telemetry/telemetry_provider.dart';
import 'package:sinapsis/core/util/util_providers.dart';
import 'package:sinapsis/features/attachments/data/services/attachment_processor.dart';
import 'package:sinapsis/features/attachments/domain/services/attachment_work.dart';
import 'package:sinapsis/features/attachments/presentation/providers/attachment_cap.dart';
import 'package:sinapsis/features/attachments/presentation/providers/attachment_providers.dart';
import 'package:sinapsis/features/duplicates/presentation/providers/duplicate_providers.dart';
import 'package:sinapsis/features/library/presentation/providers/library_providers.dart';
import 'package:sinapsis/features/reference/presentation/providers/reference_providers.dart';
import 'package:sinapsis/features/transform/data/archive/html_page_archiver.dart';
import 'package:sinapsis/features/transform/data/clients/dio_resource_fetcher.dart';
import 'package:sinapsis/features/transform/data/clients/dio_web_page_client.dart';
import 'package:sinapsis/features/transform/data/clients/html_social_post_client.dart';
import 'package:sinapsis/features/transform/data/clients/reader_mode_article_extractor.dart';
import 'package:sinapsis/features/transform/data/clients/youtube_explode_client.dart';
import 'package:sinapsis/features/transform/data/documents/docx_parser.dart';
import 'package:sinapsis/features/transform/data/documents/epub_parser.dart';
import 'package:sinapsis/features/transform/data/documents/pdf_parser.dart';
import 'package:sinapsis/features/transform/data/documents/plain_text_parser.dart';
import 'package:sinapsis/features/transform/data/repositories/processing_state_repository_impl.dart';
import 'package:sinapsis/features/transform/data/repositories/text_anchor_relocator_impl.dart';
import 'package:sinapsis/features/transform/data/services/method_channel_long_work_platform.dart';
import 'package:sinapsis/features/transform/data/transformers/audio_transcript_transformer.dart';
import 'package:sinapsis/features/transform/data/transformers/document_transformer.dart';
import 'package:sinapsis/features/transform/data/transformers/image_transformer.dart';
import 'package:sinapsis/features/transform/data/transformers/social_post_transformer.dart';
import 'package:sinapsis/features/transform/data/transformers/web_article_transformer.dart';
import 'package:sinapsis/features/transform/data/transformers/youtube_transcript_transformer.dart';
import 'package:sinapsis/features/transform/domain/archive/page_archiver.dart';
import 'package:sinapsis/features/transform/domain/clients/resource_fetcher.dart';
import 'package:sinapsis/features/transform/domain/clients/social_post_client.dart';
import 'package:sinapsis/features/transform/domain/clients/web_page_client.dart';
import 'package:sinapsis/features/transform/domain/clients/youtube_client.dart';
import 'package:sinapsis/features/transform/domain/documents/document_parser.dart';
import 'package:sinapsis/features/transform/domain/repositories/processing_state_repository.dart';
import 'package:sinapsis/features/transform/domain/services/audio_transcriber.dart';
import 'package:sinapsis/features/transform/domain/services/image_text_extractor.dart';
import 'package:sinapsis/features/transform/domain/services/long_work_keeper.dart';
import 'package:sinapsis/features/transform/domain/services/whisper_model_manager.dart';
import 'package:sinapsis/features/transform/domain/transformers/transformer_registry.dart';
import 'package:sinapsis/features/transform/domain/usecases/download_youtube_audio_usecase.dart';
import 'package:sinapsis/features/transform/domain/usecases/process_item_usecase.dart';
import 'package:sinapsis/features/transform/presentation/providers/model_download_notifier.dart';
import 'package:sinapsis/features/transform/presentation/providers/platform_audio_transcriber.dart';
import 'package:sinapsis/features/transform/presentation/providers/platform_image_text_extractor.dart';
import 'package:sinapsis/features/transform/presentation/providers/platform_whisper_model_manager.dart';

final youTubeClientProvider = Provider<YouTubeClient>((ref) {
  return const YoutubeExplodeClient();
});

final webPageClientProvider = Provider<WebPageClient>((ref) {
  return DioWebPageClient(
    ref.watch(dioProvider),
    logger: ref.watch(appLoggerProvider),
  );
});

final articleExtractorProvider = Provider<ArticleExtractor>((ref) {
  return const ReaderModeArticleExtractor();
});

final resourceFetcherProvider = Provider<ResourceFetcher>((ref) {
  return DioResourceFetcher(ref.watch(resourceFetchDioProvider));
});

final socialPostClientProvider = Provider<SocialPostClient>((ref) {
  return HtmlSocialPostClient(ref.watch(webPageClientProvider));
});

final pageArchiverProvider = Provider<PageArchiver>((ref) {
  return HtmlPageArchiver(fetcher: ref.watch(resourceFetcherProvider));
});

final imageTextExtractorProvider = Provider<ImageTextExtractor>((ref) {
  return createImageTextExtractor(files: ref.watch(fileStoreProvider));
});

/// Deliberadamente NO autoDispose: si se descarta al cerrar la pantalla de
/// descarga, una descarga en curso perdería su avance —o directamente su
/// `StreamController`— apenas alguien navegara para atrás.
final whisperModelManagerProvider = Provider<WhisperModelManager>((ref) {
  final storage = ref.watch(modelStorageProvider);
  return createWhisperModelManager(
    dio: ref.watch(modelDownloadDioProvider),
    transfer: ref.watch(modelFileTransferProvider),
    rootDirectory: storage.root,
    earlierRoots: storage.earlierRoots,
  );
});

/// Lo que mantiene viva la app mientras baja un modelo: nada si lo baja el
/// gestor del sistema —baja en su propio proceso, con su notificación, y
/// sigue con la app cerrada (F29)—; el servicio en primer plano si lo baja
/// la app.
LongWorkKeeper Function()? modelDownloadKeeper(Ref ref) =>
    ref.read(modelFileTransferProvider).continuesWithAppClosed
    ? null
    : () => ref
          .read(longWorkCoordinatorProvider)
          .keeperFor(LongWorkOwner.modelDownload);

/// La descarga del modelo de transcripción, viva aparte de su pantalla (ver
/// [ModelDownloadNotifier]). NO autoDispose: tiene que seguir aunque nadie
/// la mire.
final transcriptionModelDownloadProvider =
    StateNotifierProvider<ModelDownloadNotifier, ModelDownloadState>(
      (ref) => ModelDownloadNotifier(
        keeper: modelDownloadKeeper(ref),
        detail: LongWorkDetail.transcriptionModel,
        // Lo que falló porque faltaba este modelo vuelve a quedar en espera,
        // y la cola —que sigue a la base— lo retoma sola: nadie tiene que ir
        // audio por audio a tocar "Reintentar" (F21). Aunque la descarga
        // termine con la pantalla cerrada.
        onFinished: () => unawaited(
          ref
              .read(processingStateRepositoryProvider)
              .requeueFailedWith(
                ProcessingFailureReason.transcriptionModelMissing,
              )
              .catchError((Object _) => 0),
        ),
      ),
    );

final audioTranscriberProvider = Provider<AudioTranscriber>((ref) {
  return createAudioTranscriber(
    model: ref.watch(whisperModelManagerProvider),
    files: ref.watch(fileStoreProvider),
    temporaryDirectory: getTemporaryDirectory,
  );
});

/// El orden no importa tanto como en los adaptadores —cada transformador
/// mira el tipo de fuente y solo uno acepta cada elemento— pero se mantiene
/// la misma convención: lo específico antes que lo general.
final transformerRegistryProvider = Provider<TransformerRegistry>((ref) {
  final ids = ref.watch(idGeneratorProvider);
  final clock = ref.watch(clockProvider);
  final db = ref.watch(appDatabaseProvider);

  return TransformerRegistry([
    YouTubeTranscriptTransformer(
      client: ref.watch(youTubeClientProvider),
      ids: ids,
      clock: clock,
      transcriber: ref.watch(audioTranscriberProvider),
      temporaryDirectory: getTemporaryDirectory,
      checkpoints: ref.watch(processingStateRepositoryProvider),
      files: ref.watch(fileStoreProvider),
    ),
    SocialPostTransformer(
      client: ref.watch(socialPostClientProvider),
      fetcher: ref.watch(resourceFetcherProvider),
      files: ref.watch(fileStoreProvider),
      ids: ids,
      clock: clock,
      logger: ref.watch(appLoggerProvider),
      transcriber: ref.watch(audioTranscriberProvider),
      checkpoints: ref.watch(processingStateRepositoryProvider),
      // Sin quien baje (la web), no se anota nada.
      attachments: ref.watch(linkedFileFetcherProvider) == null
          ? null
          : ref.watch(attachmentRepositoryProvider),
    ),
    WebArticleTransformer(
      client: ref.watch(webPageClientProvider),
      extractor: ref.watch(articleExtractorProvider),
      archiver: ref.watch(pageArchiverProvider),
      files: ref.watch(fileStoreProvider),
      ids: ids,
      clock: clock,
      logger: ref.watch(appLoggerProvider),
      fileFetcher: ref.watch(linkedFileFetcherProvider),
      attachments: ref.watch(attachmentRepositoryProvider),
      maxBytesPerItem: () => ref.read(attachmentCapProvider),
    ),
    DocumentTransformer(
      parsers: ref.watch(documentParsersProvider),
      files: ref.watch(fileStoreProvider),
      ids: ids,
      clock: clock,
      hasConfirmedReference: (itemId) async =>
          !(await ReferenceReader(db).read(itemId)).isEmpty,
      checkpoints: ref.watch(processingStateRepositoryProvider),
    ),
    ImageTransformer(
      extractor: ref.watch(imageTextExtractorProvider),
      files: ref.watch(fileStoreProvider),
      ids: ids,
      clock: clock,
    ),
    AudioTranscriptTransformer(
      transcriber: ref.watch(audioTranscriberProvider),
      files: ref.watch(fileStoreProvider),
      ids: ids,
      clock: clock,
      checkpoints: ref.watch(processingStateRepositoryProvider),
    ),
  ]);
});

/// Los lectores de documentos, en el orden en que se les pregunta.
///
/// El orden no importa: cada uno declara qué formato sabe leer y ninguno se
/// pisa con otro. Se mantiene la lista igual para que agregar uno nuevo sea
/// una línea.
final documentParsersProvider = Provider<List<DocumentParser>>((ref) {
  return [
    PdfParser(
      ocrExtractor: ref.watch(imageTextExtractorProvider),
      ocrFileStore: ref.watch(fileStoreProvider),
    ),
    DocxParser(logger: ref.watch(appLoggerProvider)),
    EpubParser(logger: ref.watch(appLoggerProvider)),
    const PlainTextParser(),
  ];
});

/// El servicio en primer plano que mantiene viva la app mientras hay trabajo
/// largo (F21, decisión C), compartido por sus dueños (F27): en Android, el
/// de verdad; en el resto, nada. Uno solo para toda la sesión: junta lo que
/// piden el procesamiento, las descargas y la IA.
///
/// Lo que lo devuelve después de que Android lo cortó —`appResumed`— lo
/// llama la app al volver al frente (ver `App`).
final longWorkCoordinatorProvider = Provider<LongWorkCoordinator>((ref) {
  final coordinator = LongWorkCoordinator(
    platform: kIsWeb || defaultTargetPlatform != TargetPlatform.android
        ? const NoLongWorkPlatform()
        : MethodChannelLongWorkPlatform(logger: ref.watch(appLoggerProvider)),
  );
  ref.onDispose(coordinator.dispose);
  return coordinator;
});

/// Lo que pide la cola de procesamiento para mantener viva la app.
final longWorkKeeperProvider = Provider<LongWorkKeeper>(
  (ref) => ref
      .watch(longWorkCoordinatorProvider)
      .keeperFor(LongWorkOwner.processing),
);

final processingStateRepositoryProvider = Provider<ProcessingStateRepository>((
  ref,
) {
  return ProcessingStateRepositoryImpl(ref.watch(appDatabaseProvider));
});

final downloadYouTubeAudioUseCaseProvider =
    Provider<DownloadYouTubeAudioUseCase>((ref) {
      return DownloadYouTubeAudioUseCase(
        client: ref.watch(youTubeClientProvider),
        files: ref.watch(fileStoreProvider),
        repository: ref.watch(libraryRepositoryProvider),
        clock: ref.watch(clockProvider),
      );
    });

/// Por qué falló un elemento —`null` si no falló—, siguiendo a la base: lo
/// que muestra el detalle en vez de un "no se pudo" genérico.
final processingFailureProvider = StreamProvider.autoDispose
    .family<ProcessingFailureReason?, String>(
      (ref, itemId) =>
          ref.watch(processingStateRepositoryProvider).watchFailure(itemId),
    );

final processItemUseCaseProvider = Provider<ProcessItemUseCase>((ref) {
  return ProcessItemUseCase(
    registry: ref.watch(transformerRegistryProvider),
    repository: ref.watch(libraryRepositoryProvider),
    processingStates: ref.watch(processingStateRepositoryProvider),
    logger: ref.watch(appLoggerProvider),
    telemetry: ref.watch(telemetryServiceProvider),
    clock: ref.watch(clockProvider),
    duplicateSuggestionGenerator: ref.watch(
      duplicateSuggestionGeneratorProvider,
    ),
    metadataSuggestionGenerator: ref.watch(metadataSuggestionGeneratorProvider),
    anchorRelocator: TextAnchorRelocatorImpl(ref.watch(appDatabaseProvider)),
    attachmentWork: ref.watch(attachmentWorkProvider),
  );
});

/// El trabajo del «Contenido» de los elementos (F30): bajar lo que ofrece
/// cada página y sacarle el texto a cada archivo.
final attachmentWorkProvider = Provider<AttachmentWork>(
  (ref) => AttachmentProcessor(
    attachments: ref.watch(attachmentRepositoryProvider),
    fetcher: ref.watch(linkedFileFetcherProvider),
    maxBytesPerItem: () => ref.read(attachmentCapProvider),
    logger: ref.watch(appLoggerProvider),
    archives: ref.watch(archiveExpanderProvider),
    files: ref.watch(fileStoreProvider),
    parsers: ref.watch(documentParsersProvider),
    transcriber: ref.watch(audioTranscriberProvider),
    imageText: ref.watch(imageTextExtractorProvider),
  ),
);
