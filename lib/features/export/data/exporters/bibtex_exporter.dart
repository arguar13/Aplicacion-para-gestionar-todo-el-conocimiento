import 'dart:convert';
import 'dart:typed_data';

import 'package:sinapsis/core/domain/entities/knowledge_item.dart';
import 'package:sinapsis/core/storage/file_store.dart';
import 'package:sinapsis/features/citations/domain/entities/bibliography.dart';
import 'package:sinapsis/features/citations/domain/services/bibtex_formatter.dart';
import 'package:sinapsis/features/export/domain/entities/export_format.dart';
import 'package:sinapsis/features/export/domain/exporters/exporter.dart';

/// Exporta la referencia bibliográfica de un elemento como una entrada
/// `.bib`, lista para importar en Zotero, LaTeX o cualquier gestor de
/// citas.
///
/// Aparte del `MarkdownExporter` y compañía a propósito: los otros llevan
/// el *contenido* del elemento; este lleva su *procedencia*, formateada
/// como una norma bibliográfica entiende — dos exportaciones del mismo
/// elemento, con propósitos distintos y un botón cada una.
class BibtexExporter implements Exporter {
  const BibtexExporter();

  @override
  ExportFormat get format => ExportFormat.bibtex;

  @override
  String suggestedFileName(KnowledgeItem item) =>
      '${sanitizeFileName(item.title)}.${format.fileExtension}';

  // Una entrada `.bib` YA ES una referencia (F15, D13): agregarle la
  // bibliografía de lo que el elemento cita no tendría sentido en su propio
  // formato.
  @override
  Future<Uint8List> export(
    KnowledgeItem item, {
    Bibliography? bibliography,
  }) async {
    return Uint8List.fromList(utf8.encode(formatBibtex(item)));
  }
}
