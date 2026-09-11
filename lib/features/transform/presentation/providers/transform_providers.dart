import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/core/logging/logger_provider.dart';
import 'package:sinapsis/core/network/network_providers.dart';
import 'package:sinapsis/core/storage/storage_providers.dart';
import 'package:sinapsis/core/telemetry/telemetry_provider.dart';
import 'package:sinapsis/core/util/util_providers.dart';
import 'package:sinapsis/features/library/presentation/providers/library_providers.dart';
import 'package:sinapsis/features/transform/data/clients/dio_web_page_client.dart';
import 'package:sinapsis/features/transform/data/clients/reader_mode_article_extractor.dart';
import 'package:sinapsis/features/transform/data/clients/youtube_explode_client.dart';
import 'package:sinapsis/features/transform/data/documents/docx_parser.dart';
import 'package:sinapsis/features/transform/data/documents/epub_parser.dart';
import 'package:sinapsis/features/transform/data/documents/pdf_parser.dart';
import 'package:sinapsis/features/transform/data/documents/plain_text_parser.dart';
import 'package:sinapsis/features/transform/data/transformers/document_transformer.dart';
import 'package:sinapsis/features/transform/data/transformers/web_article_transformer.dart';
import 'package:sinapsis/features/transform/data/transformers/youtube_transcript_transformer.dart';
import 'package:sinapsis/features/transform/domain/clients/web_page_client.dart';
import 'package:sinapsis/features/transform/domain/clients/youtube_client.dart';
import 'package:sinapsis/features/transform/domain/documents/document_parser.dart';
import 'package:sinapsis/features/transform/domain/transformers/transformer_registry.dart';
import 'package:sinapsis/features/transform/domain/usecases/process_item_usecase.dart';

final youTubeClientProvider = Provider<YouTubeClient>((ref) {
  return const YoutubeExplodeClient();
});

final webPageClientProvider = Provider<WebPageClient>((ref) {
  return DioWebPageClient(ref.watch(dioProvider));
});

final articleExtractorProvider = Provider<ArticleExtractor>((ref) {
  return const ReaderModeArticleExtractor();
});

/// El orden no importa tanto como en los adaptadores —cada transformador
/// mira el tipo de fuente y solo uno acepta cada elemento— pero se mantiene
/// la misma convención: lo específico antes que lo general.
final transformerRegistryProvider = Provider<TransformerRegistry>((ref) {
  final ids = ref.watch(idGeneratorProvider);
  final clock = ref.watch(clockProvider);

  return TransformerRegistry([
    YouTubeTranscriptTransformer(
      client: ref.watch(youTubeClientProvider),
      ids: ids,
      clock: clock,
    ),
    WebArticleTransformer(
      client: ref.watch(webPageClientProvider),
      extractor: ref.watch(articleExtractorProvider),
      ids: ids,
      clock: clock,
    ),
    DocumentTransformer(
      parsers: ref.watch(documentParsersProvider),
      files: ref.watch(fileStoreProvider),
      ids: ids,
      clock: clock,
    ),
  ]);
});

/// Los lectores de documentos, en el orden en que se les pregunta.
///
/// El orden no importa: cada uno declara qué formato sabe leer y ninguno se
/// pisa con otro. Se mantiene la lista igual para que agregar uno nuevo sea
/// una línea.
final documentParsersProvider = Provider<List<DocumentParser>>((ref) {
  return const [PdfParser(), DocxParser(), EpubParser(), PlainTextParser()];
});

final processItemUseCaseProvider = Provider<ProcessItemUseCase>((ref) {
  return ProcessItemUseCase(
    registry: ref.watch(transformerRegistryProvider),
    repository: ref.watch(libraryRepositoryProvider),
    logger: ref.watch(appLoggerProvider),
    telemetry: ref.watch(telemetryServiceProvider),
    clock: ref.watch(clockProvider),
  );
});
