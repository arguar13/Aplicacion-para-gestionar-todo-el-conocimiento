import 'dart:convert';

import 'package:fpdart/fpdart.dart';
import 'package:sinapsis/core/error/failures.dart';
import 'package:sinapsis/core/usecase/usecase.dart';
import 'package:sinapsis/features/export/domain/services/file_saver.dart';

/// Guarda el Atlas ya armado como un archivo Markdown, donde el usuario
/// quiera (F13).
///
/// Como en `ExportItemUseCase`, no distingue «se canceló el diálogo» de «se
/// guardó»: en la web esa diferencia ni siquiera existe —ver [FileSaver]—.
class ExportAtlasUseCase implements UseCase<Unit, ExportAtlasParams> {
  const ExportAtlasUseCase({required FileSaver saver}) : _saver = saver;

  final FileSaver _saver;

  @override
  Future<Either<Failure, Unit>> call(ExportAtlasParams params) async {
    try {
      await _saver.saveFile(
        fileName: params.fileName,
        bytes: utf8.encode(params.markdown),
      );
      return right(unit);
      // El diálogo de guardado puede fallar por motivos que no tienen un tipo
      // propio, igual que en `ExportItemUseCase`.
      // ignore: avoid_catches_without_on_clauses
    } catch (e) {
      return left(Failure.exportFailed(message: '$e'));
    }
  }
}

/// El Atlas a guardar: el documento y el nombre que se sugiere.
final class ExportAtlasParams {
  const ExportAtlasParams({required this.fileName, required this.markdown});

  final String fileName;
  final String markdown;
}
