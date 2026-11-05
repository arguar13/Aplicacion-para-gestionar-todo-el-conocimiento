import 'package:sinapsis/features/processed/domain/entities/processed_heading.dart';
import 'package:sinapsis/features/transform/domain/documents/document_parser.dart';

/// Quien lee de un PDF lo que necesita su Índice (F46, decisión B): cuántas
/// páginas tiene y sus marcadores, aplanados en el orden en que se leen, con
/// su profundidad y la página a la que lleva cada uno.
///
/// Interfaz propia, como `TextTidier`, y no una función: quien arma el
/// Índice no sabe de PDFium, y las pruebas le dan un doble que no abre
/// ningún archivo. En la app es `PdfiumOutlineReader`.
// ignore: one_member_abstracts
abstract interface class PdfOutlineReader {
  /// Lo que trae el PDF de [source]: sin marcadores, la lista vacía.
  ///
  /// Lanza `UnreadableDocumentException` si el archivo no se puede abrir
  /// —está cortado, cifrado o no es un PDF—.
  Future<PdfOutline> read(DocumentSource source);
}
