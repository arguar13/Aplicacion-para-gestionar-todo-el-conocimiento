import 'dart:typed_data';

import 'package:sinapsis/features/transform/domain/documents/document_parser.dart';

/// Leer un documento armado en memoria, como hacen casi todas las pruebas de
/// los lectores: la app los lee desde el almacén (ver `DocumentSource`).
extension ParseBytes on DocumentParser {
  Future<ParsedDocument> parseBytes(Uint8List bytes) =>
      parse(DocumentSource.memory(bytes));
}
