import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/features/export/data/exporters/markdown_exporter.dart';
import 'package:sinapsis/features/export/data/exporters/pdf_exporter.dart';
import 'package:sinapsis/features/export/data/exporters/plain_text_exporter.dart';
import 'package:sinapsis/features/export/data/services/local_directory_writer.dart';
import 'package:sinapsis/features/export/data/services/system_directory_chooser.dart';
import 'package:sinapsis/features/export/data/services/system_file_saver.dart';
import 'package:sinapsis/features/export/domain/exporters/exporter_registry.dart';
import 'package:sinapsis/features/export/domain/notebooklm/notebooklm_package_builder.dart';
import 'package:sinapsis/features/export/domain/services/directory_chooser.dart';
import 'package:sinapsis/features/export/domain/services/directory_writer.dart';
import 'package:sinapsis/features/export/domain/services/file_saver.dart';
import 'package:sinapsis/features/export/domain/usecases/export_item_usecase.dart';
import 'package:sinapsis/features/export/domain/usecases/export_notebooklm_package_usecase.dart';

const _markdownExporter = MarkdownExporter();

final exporterRegistryProvider = Provider<ExporterRegistry>((ref) {
  return const ExporterRegistry([
    _markdownExporter,
    PlainTextExporter(),
    PdfExporter(),
  ]);
});

final directoryChooserProvider = Provider<DirectoryChooser>((ref) {
  return const SystemDirectoryChooser();
});

final directoryWriterProvider = Provider<DirectoryWriter>((ref) {
  return const LocalDirectoryWriter();
});

final notebookLmPackageBuilderProvider = Provider<NotebookLmPackageBuilder>((
  ref,
) {
  // Markdown y no otro formato: es el que lee NotebookLM como fuente, y el
  // que trae la cabecera de procedencia — ver la clase.
  return const NotebookLmPackageBuilder(exporter: _markdownExporter);
});

final exportNotebookLmPackageUseCaseProvider =
    Provider<ExportNotebookLmPackageUseCase>((ref) {
      return ExportNotebookLmPackageUseCase(
        chooser: ref.watch(directoryChooserProvider),
        writer: ref.watch(directoryWriterProvider),
        builder: ref.watch(notebookLmPackageBuilderProvider),
      );
    });

final fileSaverProvider = Provider<FileSaver>((ref) {
  return const SystemFileSaver();
});

final exportItemUseCaseProvider = Provider<ExportItemUseCase>((ref) {
  return ExportItemUseCase(
    registry: ref.watch(exporterRegistryProvider),
    saver: ref.watch(fileSaverProvider),
  );
});
