import 'package:sinapsis/core/domain/entities/knowledge_item.dart';
import 'package:sinapsis/core/usecase/usecase.dart';
import 'package:sinapsis/features/export/data/services/zip_package_downloader.dart';
import 'package:sinapsis/features/export/domain/entities/notebooklm_export_result.dart';
import 'package:sinapsis/features/export/domain/notebooklm/notebooklm_package_builder.dart';
import 'package:sinapsis/features/export/domain/services/directory_chooser.dart';
import 'package:sinapsis/features/export/domain/services/directory_writer.dart';
import 'package:sinapsis/features/export/domain/usecases/export_notebooklm_package_web_usecase.dart';

/// El caso de uso del paquete de NotebookLM en la web: no hay carpeta que
/// elegir, así que se entrega como un único `.zip` para descargar.
///
/// Recibe [directoryChooser] y [directoryWriter] solo para que la firma
/// coincida con la versión nativa —quien arma el proveedor no tiene que
/// saber cuál de las dos implementaciones va a usar—; acá no se usan para
/// nada.
UseCase<NotebookLmExportResult, List<KnowledgeItem>>
createExportNotebookLmPackageUseCase({
  required NotebookLmPackageBuilder builder,
  required DirectoryChooser directoryChooser,
  required DirectoryWriter directoryWriter,
}) {
  return ExportNotebookLmPackageWebUseCase(
    downloader: const ZipPackageDownloader(),
    builder: builder,
  );
}
