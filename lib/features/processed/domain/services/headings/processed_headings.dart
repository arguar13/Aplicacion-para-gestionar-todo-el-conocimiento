import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:sinapsis/features/processed/domain/entities/processed_heading.dart';
import 'package:sinapsis/features/processed/domain/services/headings/bookmark_locator.dart';
import 'package:sinapsis/features/processed/domain/services/headings/heading_text.dart';
import 'package:sinapsis/features/processed/domain/services/headings/isolated_titles.dart';
import 'package:sinapsis/features/processed/domain/services/headings/markdown_headings.dart';
import 'package:sinapsis/features/viewer/domain/services/pdf_study_pages.dart';

/// Qué clase de texto es el de un documento procesado, para leerle los
/// títulos (F46, paso 1).
enum ProcessedTextKind {
  /// Markdown: una página web, un Word, un EPUB, un `.md` o una nota. Sus
  /// títulos son los suyos (`#`, `##`…).
  markdown,

  /// El texto de un PDF: sus títulos son sus marcadores, o los que dejó la IA
  /// al ordenarlo (decisión B).
  pdf,

  /// Texto tal cual —una transcripción, lo que se reconoció en una foto, un
  /// `.txt`, una publicación—: no tiene títulos, y es «Texto completo».
  plain,
}

/// La clase de texto de un documento procesado: [markdown] es si su texto es
/// Markdown —`processedTextIsMarkdown`, la misma regla con que lo muestra el
/// lector—, y [originalFileName], el nombre del archivo de su fuente o de la
/// copia del original, dice si es un PDF.
ProcessedTextKind processedTextKindOf({
  required bool markdown,
  String? originalFileName,
}) {
  if (markdown) return ProcessedTextKind.markdown;
  final extension = p.extension(originalFileName ?? '').toLowerCase();
  return extension == '.pdf' ? ProcessedTextKind.pdf : ProcessedTextKind.plain;
}

/// Lo que hace falta para leerle los títulos a un documento procesado: el
/// texto, como se guarda, y —si es un PDF— lo que se leyó del archivo.
///
/// Solo datos: viaja a otro hilo (`runProcessedWork`) tal cual.
@immutable
class ProcessedHeadingsSource {
  ProcessedHeadingsSource({
    required List<String> pages,
    required this.kind,
    this.pdf,
  }) : pages = List.unmodifiable(pages);

  /// Las páginas de su sección «Texto», en orden (`processed_parts`, por
  /// `position`): una detrás de la otra son el texto procesado, y cada una
  /// es una página del lector.
  final List<String> pages;

  final ProcessedTextKind kind;

  /// Los marcadores del PDF y cuántas páginas tiene (`PdfOutlineReader`);
  /// `null` si no es un PDF o no se pudo leer el archivo.
  final PdfOutline? pdf;
}

/// Los títulos de un documento procesado, en su orden, listos para el Índice
/// (F46, paso 1, decisiones B y C).
///
/// - **Markdown**: los títulos del texto (`markdownHeadings`).
/// - **PDF**: sus marcadores, con su página real, ubicados en el texto
///   (`locateBookmarks`); si no trae, los títulos que dejó la IA al ordenarlo
///   al triar (`isolatedTitles`), con la página del PDF donde caen si el
///   texto todavía tiene una raya por página.
/// - **Texto tal cual**, o cualquiera sin títulos: una sola entrada,
///   «Texto completo» ([ProcessedHeadingOrigin.wholeText]), que abre el texto
///   desde el principio. Nunca capítulos inventados.
///
/// Los niveles quedan corridos (`runningLevels`) y cada título lleva la
/// página del texto procesado donde cae. Sin texto —un documento de solo
/// imágenes—, ninguno: el Índice sale de la sección «Texto».
///
/// Lineal en el largo del texto: un libro de miles de títulos se lee en lo
/// que se tarda en recorrerlo.
List<ProcessedHeading> readProcessedHeadings(ProcessedHeadingsSource source) {
  final text = source.pages.join();
  if (text.trim().isEmpty) return const [];
  final pageStarts = <int>[];
  var offset = 0;
  for (final page in source.pages) {
    pageStarts.add(offset);
    offset += page.length;
  }
  int textPageOf(int at) => _countAtOrBefore(pageStarts, at);

  final pdf = source.kind == ProcessedTextKind.pdf ? source.pdf : null;
  final pageSlices = pdf == null
      ? null
      : pdfPageSlicesBySeparator(text, pdf.pageCount);

  final headings = switch (source.kind) {
    ProcessedTextKind.markdown => _fromText(
      markdownHeadings(text),
      ProcessedHeadingOrigin.textHeading,
      textPageOf,
    ),
    ProcessedTextKind.pdf => _fromPdf(text, pdf, pageSlices, textPageOf),
    ProcessedTextKind.plain => const <ProcessedHeading>[],
  };
  if (headings.isNotEmpty) return headings;
  return [
    ProcessedHeading(
      order: 0,
      level: 1,
      title: '',
      origin: ProcessedHeadingOrigin.wholeText,
      start: 0,
      end: 0,
      textPage: 1,
      pdfPage: pdf != null && pdf.pageCount > 0 ? 1 : null,
    ),
  ];
}

/// [title], el de un marcador tal como lo trae el PDF, como se lee: sin
/// caracteres de control —el nulo con que lo termina PDFium, un `\r`— y con
/// un solo espacio entre palabra y palabra.
String cleanBookmarkTitle(String title) => title
    .replaceAll(_controlCharacters, ' ')
    .replaceAll(_whitespace, ' ')
    .trim();

List<ProcessedHeading> _fromText(
  List<RawHeading> raw,
  ProcessedHeadingOrigin origin,
  int Function(int at) textPageOf, {
  int? Function(int at)? pdfPageOf,
}) {
  final levels = runningLevels(raw.map((heading) => heading.level));
  return [
    for (var i = 0; i < raw.length; i++)
      ProcessedHeading(
        order: i,
        level: levels[i],
        title: raw[i].title,
        origin: origin,
        start: raw[i].start,
        end: raw[i].end,
        textPage: textPageOf(raw[i].start),
        pdfPage: pdfPageOf?.call(raw[i].start),
      ),
  ];
}

List<ProcessedHeading> _fromPdf(
  String text,
  PdfOutline? pdf,
  List<TextSlice>? pageSlices,
  int Function(int at) textPageOf,
) {
  final bookmarks = [
    for (final bookmark in pdf?.bookmarks ?? const <PdfBookmark>[])
      if (cleanBookmarkTitle(bookmark.title) case final title
          when hasReadableText(title))
        PdfBookmark(
          title: title,
          depth: bookmark.depth,
          page: switch (bookmark.page) {
            final page? when page >= 1 && page <= pdf!.pageCount => page,
            _ => null,
          },
        ),
  ];
  if (bookmarks.isEmpty) {
    return _fromText(
      isolatedTitles(text),
      ProcessedHeadingOrigin.aiTitle,
      textPageOf,
      pdfPageOf: pageSlices == null ? null : _pdfPageFinder(pageSlices),
    );
  }
  final places = locateBookmarks(text, bookmarks, pageSlices: pageSlices);
  final levels = runningLevels(bookmarks.map((bookmark) => bookmark.depth));
  return [
    for (var i = 0; i < bookmarks.length; i++)
      ProcessedHeading(
        order: i,
        level: levels[i],
        title: bookmarks[i].title,
        origin: ProcessedHeadingOrigin.bookmark,
        start: places[i]?.start,
        end: places[i]?.end,
        textPage: switch (places[i]) {
          final place? => textPageOf(place.start),
          null => null,
        },
        pdfPage: bookmarks[i].page,
      ),
  ];
}

/// Con [slices] —dónde cae cada página del PDF en el texto—, la página de
/// una posición, de 1 en adelante: la del tramo que la tiene. Los comienzos
/// se juntan una sola vez, y cada pregunta es una búsqueda binaria.
int Function(int at) _pdfPageFinder(List<TextSlice> slices) {
  final starts = [for (final slice in slices) slice.start];
  // La primera página empieza en 0, y un título nunca empieza en la raya
  // entre dos páginas —son renglones en blanco y `---`—: su página es la del
  // último comienzo que tiene antes o en su lugar.
  return (at) => _countAtOrBefore(starts, at);
}

/// Cuántos de [starts] —en orden— son [at] o menos: con los comienzos de las
/// páginas, la página de [at], de 1 en adelante.
int _countAtOrBefore(List<int> starts, int at) {
  var low = 0;
  var high = starts.length;
  while (low < high) {
    final middle = (low + high) >> 1;
    if (starts[middle] <= at) {
      low = middle + 1;
    } else {
      high = middle;
    }
  }
  return low;
}

final _controlCharacters = RegExp(r'[\x00-\x1F\x7F]');
final _whitespace = RegExp(r'\s+');
