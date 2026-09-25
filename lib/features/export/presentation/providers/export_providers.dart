import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/core/database/database_provider.dart';
import 'package:sinapsis/core/domain/entities/knowledge_item.dart';
import 'package:sinapsis/core/usecase/usecase.dart';
import 'package:sinapsis/features/citations/data/repositories/bibliography_repository_impl.dart';
import 'package:sinapsis/features/citations/domain/repositories/bibliography_repository.dart';
import 'package:sinapsis/features/citations/presentation/fragment_citation.dart';
import 'package:sinapsis/features/citations/presentation/providers/citation_preferences.dart';
import 'package:sinapsis/features/export/data/exporters/bibtex_exporter.dart';
import 'package:sinapsis/features/export/data/exporters/docx_exporter.dart';
import 'package:sinapsis/features/export/data/exporters/markdown_exporter.dart';
import 'package:sinapsis/features/export/data/exporters/pdf_exporter.dart';
import 'package:sinapsis/features/export/data/exporters/plain_text_exporter.dart';
import 'package:sinapsis/features/export/data/services/anki_package_builder.dart';
import 'package:sinapsis/features/export/data/services/anki_topic_resolver_impl.dart';
import 'package:sinapsis/features/export/data/services/directory_services.dart';
import 'package:sinapsis/features/export/data/services/system_file_saver.dart';
import 'package:sinapsis/features/export/domain/entities/notebooklm_export_result.dart';
import 'package:sinapsis/features/export/domain/exporters/exporter_registry.dart';
import 'package:sinapsis/features/export/domain/notebooklm/notebooklm_package_builder.dart';
import 'package:sinapsis/features/export/domain/services/anki_deck_builder.dart';
import 'package:sinapsis/features/export/domain/services/anki_topic_resolver.dart';
import 'package:sinapsis/features/export/domain/services/directory_chooser.dart';
import 'package:sinapsis/features/export/domain/services/directory_writer.dart';
import 'package:sinapsis/features/export/domain/services/file_saver.dart';
import 'package:sinapsis/features/export/domain/usecases/export_flashcards_to_anki_usecase.dart';
import 'package:sinapsis/features/export/domain/usecases/export_item_usecase.dart';
import 'package:sinapsis/features/export/domain/usecases/export_notebooklm_usecase_factory.dart';
import 'package:sinapsis/features/flashcards/presentation/providers/flashcard_providers.dart';

const _markdownExporter = MarkdownExporter();

final exporterRegistryProvider = Provider<ExporterRegistry>((ref) {
  return const ExporterRegistry([
    _markdownExporter,
    PlainTextExporter(),
    PdfExporter(),
    BibtexExporter(),
    DocxExporter(),
  ]);
});

// `createDefaultDirectoryChooser`/`createDefaultDirectoryWriter` eligen en
// tiempo de compilación entre el Storage Access Framework (Android, donde
// el almacenamiento con ámbito lo exige) y `dart:io` sencillo (el resto de
// las plataformas de escritorio) — ver directory_services_io.dart. La
// elección vive ahí y no acá porque este archivo también lo importa la web,
// donde `Platform.isAndroid` no tiene nada real que contestar.
final directoryChooserProvider = Provider<DirectoryChooser>((ref) {
  return createDefaultDirectoryChooser();
});

final directoryWriterProvider = Provider<DirectoryWriter>((ref) {
  return createDefaultDirectoryWriter();
});

final notebookLmPackageBuilderProvider = Provider<NotebookLmPackageBuilder>((
  ref,
) {
  // Markdown y no otro formato: es el que lee NotebookLM como fuente, y el
  // que trae la cabecera de procedencia — ver la clase.
  return const NotebookLmPackageBuilder(exporter: _markdownExporter);
});

/// En la web no hay carpeta que elegir —ver la decisión 11 en
/// docs/arquitectura.md—, así que `createExportNotebookLmPackageUseCase()`
/// elige en tiempo de compilación entre pedir una carpeta y escribir ahí, o
/// entregar todo junto como un `.zip` para descargar.
final exportNotebookLmPackageUseCaseProvider =
    Provider<UseCase<NotebookLmExportResult, List<KnowledgeItem>>>((ref) {
      return createExportNotebookLmPackageUseCase(
        directoryChooser: ref.watch(directoryChooserProvider),
        directoryWriter: ref.watch(directoryWriterProvider),
        builder: ref.watch(notebookLmPackageBuilderProvider),
      );
    });

final fileSaverProvider = Provider<FileSaver>((ref) {
  return const SystemFileSaver();
});

/// De dónde sale una bibliografía (F15): un espacio, una rama del Atlas, lo
/// que cita una nota, o una selección — ver `BibliographyRepository`.
final bibliographyRepositoryProvider = Provider<BibliographyRepository>((ref) {
  return BibliographyRepositoryImpl(ref.watch(appDatabaseProvider));
});

final exportItemUseCaseProvider = Provider<ExportItemUseCase>((ref) {
  return ExportItemUseCase(
    registry: ref.watch(exporterRegistryProvider),
    saver: ref.watch(fileSaverProvider),
    bibliography: ref.watch(bibliographyRepositoryProvider),
    citationStyle: ref.watch(defaultCitationStyleProvider),
    citationLanguage: ref.watch(defaultCitationLanguageProvider),
  );
});

final ankiDeckBuilderProvider = Provider<AnkiDeckBuilder>((ref) {
  return const AnkiPackageBuilder();
});

final ankiTopicResolverProvider = Provider<AnkiTopicResolver>((ref) {
  return AnkiTopicResolverImpl(database: ref.watch(appDatabaseProvider));
});

final exportFlashcardsToAnkiUseCaseProvider =
    Provider<ExportFlashcardsToAnkiUseCase>((ref) {
      return ExportFlashcardsToAnkiUseCase(
        flashcards: ref.watch(flashcardRepositoryProvider),
        topics: ref.watch(ankiTopicResolverProvider),
        bibliography: ref.watch(bibliographyRepositoryProvider),
        locator: ref.watch(fragmentLocatorResolverProvider),
        citationStyle: ref.watch(defaultCitationStyleProvider),
        citationLanguage: ref.watch(defaultCitationLanguageProvider),
        builder: ref.watch(ankiDeckBuilderProvider),
        saver: ref.watch(fileSaverProvider),
      );
    });
