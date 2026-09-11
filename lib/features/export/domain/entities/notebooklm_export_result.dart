import 'package:freezed_annotation/freezed_annotation.dart';

part 'notebooklm_export_result.freezed.dart';

/// Cómo terminó de armar el paquete para NotebookLM.
///
/// No es un fallo de dominio: cancelar el selector de carpeta es la
/// respuesta más común de un selector, no un error — igual que en la
/// captura de archivos.
@freezed
sealed class NotebookLmExportResult with _$NotebookLmExportResult {
  const factory NotebookLmExportResult.cancelled() = NotebookLmExportCancelled;

  const factory NotebookLmExportResult.completed({
    required String directoryPath,
    required int fileCount,
  }) = NotebookLmExportCompleted;
}
