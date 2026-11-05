import 'package:pdfrx/pdfrx.dart';
import 'package:sinapsis/features/processed/domain/entities/processed_heading.dart';
import 'package:sinapsis/features/processed/domain/services/headings/pdf_outline_reader.dart';
import 'package:sinapsis/features/processed/domain/services/headings/processed_headings.dart';
import 'package:sinapsis/features/transform/data/documents/pdf_parser.dart';
import 'package:sinapsis/features/transform/domain/documents/document_parser.dart';

/// Lee los marcadores de un PDF con PDFium (`loadOutline` de `pdfrx_engine`),
/// el mismo motor con que se le saca el texto (F46, decisión B).
///
/// Abre el archivo como `PdfParser` ([openPdfDocument]): desde el disco si
/// está en uno, sin pasarlo entero por la memoria de Dart. No le saca el
/// texto a ninguna página: los marcadores y la cuenta de páginas están en el
/// catálogo del documento, así que un libro de mil páginas se lee en un
/// instante.
class PdfiumOutlineReader implements PdfOutlineReader {
  const PdfiumOutlineReader({PdfEngineInitializer? initialize})
    : _initialize = initialize ?? pdfrxFlutterInitialize;

  /// Cómo se prepara PDFium: en la app, [pdfrxFlutterInitialize]; en las
  /// pruebas, el PDFium de `PDFIUM_PATH` (ver `PdfParser`).
  final PdfEngineInitializer _initialize;

  @override
  Future<PdfOutline> read(DocumentSource source) async {
    await _initialize();
    final document = await openPdfDocument(source);
    try {
      return PdfOutline(
        pageCount: document.pages.length,
        bookmarks: flattenPdfOutline(await document.loadOutline()),
      );
    } finally {
      // Sin esto se filtra memoria nativa, que el recolector no ve.
      await document.dispose();
    }
  }
}

/// El árbol de marcadores [nodes] en el orden en que se leen —cada uno y
/// después los suyos—, con la profundidad de cada uno (1 los de arriba), su
/// título limpio (`cleanBookmarkTitle`) y su página.
///
/// Un marcador sin título sigue en la lista —sus hijos cuelgan de él—, y
/// quien arma el Índice lo saltea. Se recorre con una pila y no con
/// recursión: un PDF con un árbol absurdamente hondo no agota la pila de
/// llamadas.
List<PdfBookmark> flattenPdfOutline(List<PdfOutlineNode> nodes) {
  final bookmarks = <PdfBookmark>[];
  final pending = <(PdfOutlineNode, int)>[
    for (final node in nodes.reversed) (node, 1),
  ];
  while (pending.isNotEmpty) {
    final (node, depth) = pending.removeLast();
    bookmarks.add(
      PdfBookmark(
        title: cleanBookmarkTitle(node.title),
        depth: depth,
        page: node.dest?.pageNumber,
      ),
    );
    for (final child in node.children.reversed) {
      pending.add((child, depth + 1));
    }
  }
  return bookmarks;
}
