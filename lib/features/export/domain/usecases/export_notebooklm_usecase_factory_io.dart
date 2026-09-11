import 'package:sinapsis/core/domain/entities/knowledge_item.dart';
import 'package:sinapsis/core/usecase/usecase.dart';
import 'package:sinapsis/features/export/domain/entities/notebooklm_export_result.dart';
import 'package:sinapsis/features/export/domain/notebooklm/notebooklm_package_builder.dart';
import 'package:sinapsis/features/export/domain/services/directory_chooser.dart';
import 'package:sinapsis/features/export/domain/services/directory_writer.dart';
import 'package:sinapsis/features/export/domain/usecases/export_notebooklm_package_usecase.dart';

/// El caso de uso del paquete de NotebookLM fuera de la web: pide una
/// carpeta y escribe los archivos ahí.
UseCase<NotebookLmExportResult, List<KnowledgeItem>>
createExportNotebookLmPackageUseCase({
  required NotebookLmPackageBuilder builder,
  required DirectoryChooser directoryChooser,
  required DirectoryWriter directoryWriter,
}) {
  return ExportNotebookLmPackageUseCase(
    chooser: directoryChooser,
    writer: directoryWriter,
    builder: builder,
  );
}
