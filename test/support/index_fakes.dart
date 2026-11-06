import 'package:sinapsis/core/storage/file_format.dart';
import 'package:sinapsis/features/processed/domain/entities/processed_heading.dart';
import 'package:sinapsis/features/processed/domain/services/headings/headings_extractor.dart';
import 'package:sinapsis/features/processed/domain/services/headings/pdf_outline_reader.dart';
import 'package:sinapsis/features/processed/domain/services/headings/processed_headings.dart';
import 'package:sinapsis/features/transform/domain/documents/document_parser.dart';

/// Un [HeadingsExtractor] de prueba (F46, paso 2): saca como títulos las
/// líneas que empiezan con `#` —su nivel, cuántos `#`—, con su tramo y la
/// página del texto procesado donde caen; de un PDF, sus marcadores tal cual,
/// sin ubicar. Lo que hace el de verdad lo prueba el paso 1; esto es lo que
/// el Índice necesita para probar lo suyo, sin depender de cómo se leen los
/// títulos.
///
/// Anota cada pedido, y puede fallar ([failWith]), devolver otra cosa
/// ([answer]) o hacer algo mientras trabaja ([during]).
class FakeHeadingsExtractor implements HeadingsExtractor {
  FakeHeadingsExtractor({this.answer, this.during});

  /// Lo que devuelve en lugar de los títulos de Markdown.
  List<ProcessedHeading> Function(ProcessedHeadingsSource source)? answer;

  /// Lo que hace antes de responder: mirar la base desde afuera, por ejemplo.
  Future<void> Function(ProcessedHeadingsSource source)? during;

  /// Si no es `null`, lo lanza en lugar de responder.
  Exception? failWith;

  /// Cada pedido, en orden.
  final calls = <ProcessedHeadingsSource>[];

  @override
  Future<List<ProcessedHeading>> headingsOf(
    ProcessedHeadingsSource source,
  ) async {
    calls.add(source);
    await during?.call(source);
    final failure = failWith;
    if (failure != null) throw failure;
    return (answer ?? fakeHeadings)(source);
  }
}

/// Los títulos de prueba de [source]: los marcadores de su PDF, si los trae;
/// si no, las líneas que empiezan con `#`; sin ninguno, «Texto completo».
List<ProcessedHeading> fakeHeadings(ProcessedHeadingsSource source) {
  final bookmarks = source.pdf?.bookmarks ?? const <PdfBookmark>[];
  if (bookmarks.isNotEmpty) {
    return [
      for (final (order, bookmark) in bookmarks.indexed)
        ProcessedHeading(
          order: order,
          level: bookmark.depth,
          title: bookmark.title,
          origin: ProcessedHeadingOrigin.bookmark,
          pdfPage: bookmark.page,
        ),
    ];
  }
  final text = source.pages.join();
  final found = <ProcessedHeading>[];
  var at = 0;
  for (final line in text.split('\n')) {
    final match = RegExp(r'^(#{1,6})\s+(.+)$').firstMatch(line);
    if (match != null) {
      final start = at + match.group(1)!.length + 1;
      final title = match.group(2)!;
      found.add(
        ProcessedHeading(
          order: found.length,
          level: match.group(1)!.length,
          title: title,
          origin: ProcessedHeadingOrigin.textHeading,
          start: start,
          end: start + title.length,
          textPage: _pageOf(source, start),
        ),
      );
    }
    at += line.length + 1;
  }
  if (found.isNotEmpty || text.trim().isEmpty) return found;
  return const [
    ProcessedHeading(
      order: 0,
      level: 1,
      title: '',
      origin: ProcessedHeadingOrigin.wholeText,
      start: 0,
      end: 0,
      textPage: 1,
    ),
  ];
}

int _pageOf(ProcessedHeadingsSource source, int offset) {
  var end = 0;
  for (var i = 0; i < source.pages.length; i++) {
    end += source.pages[i].length;
    if (offset < end) return i + 1;
  }
  return source.pages.length;
}

/// Un [PdfOutlineReader] de prueba: no abre ningún archivo. Responde por el
/// nombre del archivo —[outlines]— y lanza `UnreadableDocumentException` con
/// los de [unreadable]. Anota qué se le pidió leer.
class FakePdfOutlineReader implements PdfOutlineReader {
  FakePdfOutlineReader({Map<String, PdfOutline>? outlines})
    : outlines = outlines ?? {};

  final Map<String, PdfOutline> outlines;
  final unreadable = <String>{};

  /// Si no es `null`, lo lanza —una falla que no es del archivo—.
  Exception? failWith;

  /// El nombre de cada archivo que se leyó, en orden.
  final reads = <String>[];

  @override
  Future<PdfOutline> read(DocumentSource source) async {
    reads.add(source.name);
    final failure = failWith;
    if (failure != null) throw failure;
    if (unreadable.contains(source.name)) {
      throw const UnreadableDocumentException(FileFormat.pdf, 'cifrado');
    }
    return outlines[source.name] ?? PdfOutline(pageCount: 1);
  }
}
