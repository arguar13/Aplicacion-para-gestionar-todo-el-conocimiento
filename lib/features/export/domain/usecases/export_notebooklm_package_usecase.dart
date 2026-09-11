import 'package:fpdart/fpdart.dart';
import 'package:sinapsis/core/domain/entities/knowledge_item.dart';
import 'package:sinapsis/core/error/failures.dart';
import 'package:sinapsis/core/usecase/usecase.dart';
import 'package:sinapsis/features/export/domain/entities/notebooklm_export_result.dart';
import 'package:sinapsis/features/export/domain/notebooklm/notebooklm_package_builder.dart';
import 'package:sinapsis/features/export/domain/services/directory_chooser.dart';
import 'package:sinapsis/features/export/domain/services/directory_writer.dart';

/// Arma el paquete para NotebookLM de los elementos elegidos y lo guarda
/// donde el usuario diga.
///
/// Pide la carpeta primero y arma los archivos después: así, cancelar el
/// selector no cuesta el trabajo de exportar nada que después no se va a
/// guardar en ningún lado.
class ExportNotebookLmPackageUseCase
    implements UseCase<NotebookLmExportResult, List<KnowledgeItem>> {
  const ExportNotebookLmPackageUseCase({
    required DirectoryChooser chooser,
    required DirectoryWriter writer,
    required NotebookLmPackageBuilder builder,
  }) : _chooser = chooser,
       _writer = writer,
       _builder = builder;

  final DirectoryChooser _chooser;
  final DirectoryWriter _writer;
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

    final directoryPath = await _chooser.pickDirectory();
    if (directoryPath == null) {
      return right(const NotebookLmExportResult.cancelled());
    }

    try {
      final files = await _builder.build(params);
      for (final entry in files.entries) {
        await _writer.writeFile(
          directoryPath: directoryPath,
          fileName: entry.key,
          bytes: entry.value,
        );
      }

      return right(
        NotebookLmExportResult.completed(
          directoryPath: directoryPath,
          fileCount: files.length,
        ),
      );
      // La carpeta la eligió el usuario, no la app: puede fallar por
      // permisos, por quedarse sin espacio o porque un disco externo se
      // desconectó a mitad de la escritura, y ninguno de esos casos tiene
      // un tipo propio en dart:io.
      // ignore: avoid_catches_without_on_clauses
    } catch (e) {
      return left(Failure.exportFailed(message: '$e'));
    }
  }
}
