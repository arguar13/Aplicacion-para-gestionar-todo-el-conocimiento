import 'package:fpdart/fpdart.dart';
import 'package:sinapsis/core/domain/entities/knowledge_item.dart';
import 'package:sinapsis/core/error/failures.dart';
import 'package:sinapsis/core/usecase/usecase.dart';
import 'package:sinapsis/features/export/domain/entities/notebooklm_export_result.dart';
import 'package:sinapsis/features/export/domain/notebooklm/notebooklm_package_builder.dart';
import 'package:sinapsis/features/export/domain/services/package_downloader.dart';

/// La versión web de `ExportNotebookLmPackageUseCase`.
///
/// En la web no hay selector de carpeta que preguntar antes —`file_picker`
/// no implementa `getDirectoryPath()` ahí, y llamarlo revienta con
/// `UnimplementedError`—, así que no hay nada que cancelar: se arma el
/// paquete directo y se entrega como un único `.zip` para descargar. Ver la
/// decisión 11 en docs/arquitectura.md.
class ExportNotebookLmPackageWebUseCase
    implements UseCase<NotebookLmExportResult, List<KnowledgeItem>> {
  const ExportNotebookLmPackageWebUseCase({
    required PackageDownloader downloader,
    required NotebookLmPackageBuilder builder,
  }) : _downloader = downloader,
       _builder = builder;

  final PackageDownloader _downloader;
  final NotebookLmPackageBuilder _builder;

  @override
  Future<Either<Failure, NotebookLmExportResult>> call(
    List<KnowledgeItem> params,
  ) async {
    if (params.isEmpty) {
      return left(
        const Failure.validation(message: 'No hay elementos para exportar.'),
      );
    }

    try {
      final files = await _builder.build(params);
      final zipName = await _downloader.downloadAsZip(
        files,
        zipFileName: 'notebooklm.zip',
      );

      return right(
        NotebookLmExportResult.completed(
          directoryPath: zipName,
          fileCount: files.length,
        ),
      );
      // El .zip se arma en memoria y se entrega vía una URL de blob: no hay
      // un tipo propio para lo que pueda fallar ahí, así que se atrapa
      // parejo con la versión nativa.
      // ignore: avoid_catches_without_on_clauses
    } catch (e) {
      return left(Failure.exportFailed(message: '$e'));
    }
  }
}
