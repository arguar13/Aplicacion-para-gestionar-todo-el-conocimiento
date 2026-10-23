import 'dart:typed_data';

import 'package:sinapsis/core/domain/entities/source_kind.dart';
import 'package:sinapsis/core/storage/file_format.dart';

/// El formato del original que se descarga con tramos marcados (F38): sale en
/// el mismo formato en el que está guardado.
enum MarkedDocumentFormat {
  pdf,
  docx,
  epub,

  /// La página web que la app archivó al guardarla: un `.html`.
  webPage,

  /// Un texto suelto: no tiene dónde guardar un color, así que sale como un
  /// Word con el mismo texto (decisión C del plan).
  plainText,

  markdown;

  /// La extensión del archivo que se descarga, sin el punto.
  ///
  /// Casi siempre es la del original. Las dos que no: un texto suelto sale
  /// como `.docx` (decisión C), y una página web, como `.html`.
  String get extension => switch (this) {
    MarkedDocumentFormat.pdf => 'pdf',
    MarkedDocumentFormat.docx => 'docx',
    MarkedDocumentFormat.epub => 'epub',
    MarkedDocumentFormat.webPage => 'html',
    MarkedDocumentFormat.plainText => 'docx',
    MarkedDocumentFormat.markdown => 'md',
  };
}

/// En qué formato está el original de un elemento de [kind], o `null` si no
/// se puede descargar marcado: una foto, un audio, un Word viejo.
///
/// [head] son los bytes del principio del archivo, o el archivo entero:
/// el formato se reconoce por los bytes y no por el nombre —un `.pdf`
/// renombrado sigue siendo un PDF—, y [name] solo desempata los que no tienen
/// firma, un `.txt` o un `.md`. Una página web archivada es un HTML de verdad
/// y no tiene nada que reconocer.
MarkedDocumentFormat? markedDocumentFormatOf({
  required SourceKind kind,
  required Uint8List head,
  required String name,
}) {
  return switch (kind) {
    SourceKind.webPage => MarkedDocumentFormat.webPage,
    SourceKind.document => switch (detectFileFormat(head, name: name)) {
      FileFormat.pdf => MarkedDocumentFormat.pdf,
      FileFormat.docx => MarkedDocumentFormat.docx,
      FileFormat.epub => MarkedDocumentFormat.epub,
      FileFormat.plainText => MarkedDocumentFormat.plainText,
      FileFormat.markdown => MarkedDocumentFormat.markdown,
      _ => null,
    },
    _ => null,
  };
}
