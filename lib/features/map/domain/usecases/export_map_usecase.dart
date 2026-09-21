import 'dart:typed_data';

import 'package:fpdart/fpdart.dart';
import 'package:sinapsis/core/error/failures.dart';
import 'package:sinapsis/core/usecase/usecase.dart';
import 'package:sinapsis/features/export/domain/services/file_saver.dart';

/// Guarda el mapa ya dibujado —una imagen PNG o un dibujo SVG— donde el usuario
/// quiera (F14, D7).
///
/// Como en `ExportAtlasUseCase`, no distingue «se canceló el diálogo» de «se
/// guardó»: en la web esa diferencia ni siquiera existe —ver [FileSaver]—.
class ExportMapUseCase implements UseCase<Unit, ExportMapParams> {
  const ExportMapUseCase({required FileSaver saver}) : _saver = saver;

  final FileSaver _saver;

  @override
  Future<Either<Failure, Unit>> call(ExportMapParams params) async {
    try {
      await _saver.saveFile(fileName: params.fileName, bytes: params.bytes);
      return right(unit);
      // El diálogo de guardado puede fallar por motivos que no tienen un tipo
      // propio, igual que en `ExportAtlasUseCase`.
      // ignore: avoid_catches_without_on_clauses
    } catch (e) {
      return left(Failure.exportFailed(message: '$e'));
    }
  }
}

/// El mapa a guardar: el archivo entero y el nombre que se sugiere.
final class ExportMapParams {
  const ExportMapParams({required this.fileName, required this.bytes});

  final String fileName;
  final Uint8List bytes;
}
