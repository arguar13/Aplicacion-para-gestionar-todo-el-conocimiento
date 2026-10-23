import 'dart:typed_data';

import 'package:fpdart/fpdart.dart';
import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;
import 'package:sinapsis/core/domain/entities/highlight.dart';
import 'package:sinapsis/core/domain/entities/knowledge_item.dart';
import 'package:sinapsis/core/storage/file_store.dart';
import 'package:sinapsis/features/export/domain/entities/marked_document_format.dart';
import 'package:sinapsis/features/export/domain/entities/marked_document_options.dart';
import 'package:sinapsis/features/export/domain/services/document_marks_builder.dart';
import 'package:sinapsis/features/export/domain/services/file_saver.dart';
import 'package:sinapsis/features/export/domain/services/marked_document_writer.dart';
import 'package:sinapsis/features/study/domain/entities/document_study.dart';

/// Por qué no se pudo descargar el documento marcado.
enum MarkedDownloadError {
  /// No se eligió nada que marcar.
  nothingSelected,

  /// Lo elegido no tiene ningún tramo: sin resumen, sin palabras clave…
  nothingToMark,

  /// El original ya no está guardado, o no se pudo leer.
  originalMissing,

  /// El original no es de un formato que se sepa marcar, o todavía no hay
  /// quien lo escriba.
  unsupportedFormat,

  /// El escritor del formato no pudo marcar este archivo: uno dañado, uno con
  /// una estructura que no esperaba.
  writeFailed,

  /// El selector del sistema se cayó al guardar.
  saveFailed,
}

@immutable
final class MarkedDownloadFailure {
  const MarkedDownloadFailure(this.error, [this.detail]);

  final MarkedDownloadError error;

  /// Lo que dijo la excepción, para el diagnóstico y no para la pantalla.
  final String? detail;

  @override
  String toString() => 'MarkedDownloadFailure($error, $detail)';
}

/// Lo que dejó una descarga que llegó hasta el selector del sistema.
@immutable
final class MarkedDownloadDone {
  const MarkedDownloadDone({required this.fileName, this.path});

  /// El nombre con el que se ofreció guardar.
  final String fileName;

  /// Dónde quedó. `null` no es un error: o se canceló el selector, o es la
  /// web, donde el navegador descarga solo y no hay ruta que contar —ver
  /// [FileSaver]—. Quien muestra el resultado sabe en cuál de las dos está.
  final String? path;
}

@immutable
final class DownloadMarkedDocumentParams {
  const DownloadMarkedDocumentParams({
    required this.item,
    required this.content,
    required this.study,
    required this.highlights,
    required this.options,
  });

  /// El elemento: de él salen el título y el archivo original.
  final KnowledgeItem item;

  /// El texto extraído al que apuntan todas las posiciones.
  final String content;

  /// Lo estudiado de [content] (F36).
  final DocumentStudy study;

  /// Los subrayados de la persona sobre [content].
  final List<Highlight> highlights;
  final MarkedDocumentOptions options;
}

/// Descarga el original con lo elegido marcado, en su mismo formato (F38).
///
/// Lee el archivo original, reconoce su formato por los bytes, arma los tramos
/// —ver [buildDocumentMarks]—, se los da al escritor de ese formato y deja
/// guardar el resultado como «título — lo elegido.extensión».
///
/// Como en `ExportItemUseCase`, cancelar el selector no es un error: el
/// resultado trae `path == null`.
class DownloadMarkedDocumentUseCase {
  const DownloadMarkedDocumentUseCase({
    required FileStore files,
    required Map<MarkedDocumentFormat, MarkedDocumentWriter> writers,
    required FileSaver saver,
    required DocumentMarkColors colors,
  }) : _files = files,
       _writers = writers,
       _saver = saver,
       _colors = colors;

  final FileStore _files;
  final Map<MarkedDocumentFormat, MarkedDocumentWriter> _writers;
  final FileSaver _saver;
  final DocumentMarkColors _colors;

  Future<Either<MarkedDownloadFailure, MarkedDownloadDone>> call(
    DownloadMarkedDocumentParams params,
  ) async {
    if (params.options.isEmpty) {
      return left(
        const MarkedDownloadFailure(MarkedDownloadError.nothingSelected),
      );
    }

    final path = params.item.source.originalFilePath;
    final original = path == null ? null : await _readOriginal(path);
    if (path == null || original == null) {
      return left(
        const MarkedDownloadFailure(MarkedDownloadError.originalMissing),
      );
    }

    final format = markedDocumentFormatOf(
      kind: params.item.source.kind,
      head: original,
      name: p.basename(path),
    );
    final writer = format == null ? null : _writers[format];
    if (format == null || writer == null) {
      return left(
        const MarkedDownloadFailure(MarkedDownloadError.unsupportedFormat),
      );
    }

    final marks = buildDocumentMarks(
      content: params.content,
      options: params.options,
      study: params.study,
      highlights: params.highlights,
      colors: _colors,
    );
    if (marks.isEmpty) {
      return left(
        const MarkedDownloadFailure(MarkedDownloadError.nothingToMark),
      );
    }

    final Uint8List marked;
    try {
      marked = await writer.write(
        original,
        content: params.content,
        marks: marks,
      );
      // Cada escritor falla a su manera —un ZIP roto, un PDF cifrado—, sin un
      // tipo común.
      // ignore: avoid_catches_without_on_clauses
    } catch (e) {
      return left(MarkedDownloadFailure(MarkedDownloadError.writeFailed, '$e'));
    }

    final fileName = markedDocumentFileName(
      title: params.item.title,
      options: params.options,
      format: format,
    );
    try {
      final saved = await _saver.saveFile(fileName: fileName, bytes: marked);
      return right(MarkedDownloadDone(fileName: fileName, path: saved));
      // El diálogo del sistema puede caerse por motivos sin tipo propio.
      // ignore: avoid_catches_without_on_clauses
    } catch (e) {
      return left(MarkedDownloadFailure(MarkedDownloadError.saveFailed, '$e'));
    }
  }

  Future<Uint8List?> _readOriginal(String path) async {
    try {
      return await _files.read(path);
      // Un disco que se resiste no tiene tipo propio: igual que un archivo
      // que no está, no hay original que marcar.
      // ignore: avoid_catches_without_on_clauses
    } catch (_) {
      return null;
    }
  }
}

/// El nombre del archivo que se descarga: «título — lo elegido.ext», con
/// el título saneado.
///
/// Si el título ya termina con la extensión de un documento —un archivo
/// guardado con su nombre—, esa se saca para que no quede «Historia.pdf —
/// resumen.pdf».
String markedDocumentFileName({
  required String title,
  required MarkedDocumentOptions options,
  required MarkedDocumentFormat format,
}) {
  final withoutExtension =
      _documentExtensions.contains(p.extension(title).toLowerCase())
      ? p.withoutExtension(title)
      : title;
  final base = sanitizeFileName(withoutExtension);
  return '$base — ${options.fileLabel}.${format.extension}';
}

const _documentExtensions = {
  '.pdf',
  '.docx',
  '.epub',
  '.html',
  '.htm',
  '.txt',
  '.md',
  '.markdown',
};
