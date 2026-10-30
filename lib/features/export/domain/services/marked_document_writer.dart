import 'dart:typed_data';

import 'package:sinapsis/features/export/domain/entities/document_mark.dart';
import 'package:sinapsis/features/export/domain/entities/document_note.dart';

/// Escribe los tramos marcados en el original, en su mismo formato (F38).
///
/// Un escritor por formato —ver `MarkedDocumentFormat`—. Cada uno entiende de
/// cómo se marca *su* archivo, y no de qué tramos se eligieron ni de dónde se
/// guarda lo que sale.
///
/// Los escritores reales son de la capa de datos y tienen cada uno su propia
/// firma: `PdfDocumentMarker.mark`, `DocxMarkWriter.write`,
/// `TextDocxMarkWriter.write`, `MarkdownMarkWriter.write`,
/// `EpubMarkWriter.write` y `HtmlMarkWriter.write`. Para llegar a esta
/// interfaz se los envuelve con un adaptador de una línea que acomoda los
/// parámetros —el Markdown y el HTML son texto: el adaptador lo
/// decodifica de UTF-8 y vuelve a codificar lo que sale— y se registran en
/// `markedDocumentWritersProvider`, por formato.
// ignore: one_member_abstracts
abstract interface class MarkedDocumentWriter {
  /// El [original] con [marks] marcados.
  ///
  /// [content] es el texto extraído del original, el de la forma de texto, y
  /// las posiciones de cada tramo son de ese texto. Las marcas vienen en el
  /// orden de las capas: de dos que se pisan, gana la que viene después en
  /// la lista.
  ///
  /// [notes] son las notas en el texto (F45, mejora 19), en el orden del
  /// texto: en un PDF, notas del PDF —las que se abren con un toque—; en el
  /// texto, notas al pie, numeradas en ese orden. Una que no se encuentra en
  /// el archivo se saltea, como un tramo.
  Future<Uint8List> write(
    Uint8List original, {
    required String content,
    required List<DocumentMark> marks,
    List<DocumentNote> notes = const [],
  });
}
