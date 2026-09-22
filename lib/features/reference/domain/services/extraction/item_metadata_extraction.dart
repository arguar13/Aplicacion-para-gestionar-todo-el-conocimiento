import 'dart:convert';

import 'package:path/path.dart' as p;
import 'package:sinapsis/core/domain/entities/extracted_metadata.dart';
import 'package:sinapsis/core/domain/entities/knowledge_item.dart';
import 'package:sinapsis/core/domain/entities/source_kind.dart';
import 'package:sinapsis/core/storage/file_format.dart';
import 'package:sinapsis/core/storage/file_store.dart';
import 'package:sinapsis/features/reference/domain/services/extraction/html_metadata_reader.dart';
import 'package:sinapsis/features/reference/domain/services/extraction/pdf_metadata_reader.dart';
import 'package:sinapsis/features/reference/domain/services/extraction/youtube_reference_metadata.dart';

/// Lo que se puede proponer como referencia de [item], leyendo su archivo
/// original del almacén si hace falta (F15, D12). `null` si no hay de dónde
/// leer nada —una nota, un PDF que todavía no bajó, una página que no se
/// pudo archivar—: a quien llama no le importa por qué no hay nada, solo que
/// no lo hay, así que no se distingue de un [ExtractedMetadata] vacío.
///
/// Es una función aparte de cada lector porque es la única parte que sabe DE
/// DÓNDE sale cada fuente —el archivo original guardado en el almacén, o
/// directamente la fuente ya guardada, para YouTube—; los lectores en sí no
/// saben de [FileStore]. Sirve tanto para generar la sugerencia al terminar
/// de capturar como para volver a intentarlo al abrir el formulario: las dos
/// veces se lee lo mismo, del mismo lugar.
Future<ExtractedMetadata?> extractedMetadataOf(
  KnowledgeItem item,
  FileStore files,
) async {
  switch (item.source.kind) {
    case SourceKind.youtube:
      return youtubeReferenceMetadata(item.source);

    case SourceKind.document:
      final path = item.source.originalFilePath;
      if (path == null) return null;
      final bytes = await files.read(path);
      if (bytes == null) return null;
      // Solo el PDF: es el único formato que no trae su propio título ni su
      // propio autor (ver `PdfParser`, F15, 11a) — un EPUB o un DOCX ya los
      // completan por su cuenta, sin pasar por una sugerencia.
      if (detectFileFormat(bytes, name: p.basename(path)) != FileFormat.pdf) {
        return null;
      }
      return readPdfMetadata(bytes);

    case SourceKind.webPage:
      final path = item.source.originalFilePath;
      if (path == null) return null;
      final bytes = await files.read(path);
      if (bytes == null) return null;
      return readHtmlMetadata(utf8.decode(bytes, allowMalformed: true));

    case SourceKind.socialPost:
    case SourceKind.image:
    case SourceKind.audio:
    case SourceKind.video:
    case SourceKind.manualNote:
    case SourceKind.reference:
      return null;
  }
}
