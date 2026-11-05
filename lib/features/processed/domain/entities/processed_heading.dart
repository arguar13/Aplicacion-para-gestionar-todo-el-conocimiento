import 'package:flutter/foundation.dart';

/// De dónde sale un título del Índice (F46, decisiones B y C): qué lo hizo
/// título, y con eso qué número de página lleva.
///
/// Se guarda por su nombre (`processed_headings`, paso 2): renombrar un valor
/// es una migración.
enum ProcessedHeadingOrigin {
  /// Un marcador del PDF, el índice que trae el propio archivo y que puso su
  /// autor: con su nivel y **su página real** (decisión B).
  bookmark,

  /// Un título del texto —`#`, `##`, `###`… o subrayado con `===` y `---`—: lo
  /// que la extracción de una página web, un Word, un EPUB o un Markdown ya
  /// guarda como título. Lleva la página del texto procesado (decisión C).
  textHeading,

  /// Un título de un PDF sin marcadores tal como lo dejó la IA al ordenar el
  /// texto al triar (F45, decisión B): solo en su renglón, con un renglón en
  /// blanco antes y otro después. Lleva la página del PDF donde cae, si se
  /// sabe.
  aiTitle,

  /// Un texto sin títulos —una transcripción, una nota larga, un artículo
  /// plano— es una sola entrada, «Texto completo», que lo abre desde el
  /// principio: el Índice no inventa capítulos.
  wholeText,
}

/// Un título de un documento procesado, ya listo para el Índice (F46, paso 1):
/// lo que guarda una fila de `processed_headings`.
///
/// - [level] es el nivel **corrido**: el primero es el 1 y ninguno salta uno
///   respecto del que lo contiene (`runningLevels`). Un `#` seguido de un
///   `###` queda en 1 y 2; un documento que empieza en `###` no queda
///   colgando.
/// - [start] y [end] son el tramo del título en el texto procesado —sus
///   páginas de «Texto» una detrás de la otra (`joinProcessedParts`)—, el
///   mismo texto con las mismas posiciones que lee el lector único (F45,
///   mejora 12): con eso el paso 4 lo abre justo ahí y lo resalta. Un
///   marcador que no se encontró en el texto los deja en `null`, y queda con
///   su [pdfPage].
/// - [textPage] es la página del texto procesado donde cae, de 1 en adelante:
///   la misma «Página 3 de 6» del lector y el mismo «Texto · 6 páginas» del
///   documento, porque son sus páginas guardadas (`kProcessedTextPageChars`).
/// - [pdfPage] es la página real del PDF, de 1 en adelante: la del marcador,
///   o la del PDF donde cae un título de la IA. `null` en lo que no es un PDF
///   o si no se puede saber.
@immutable
class ProcessedHeading {
  const ProcessedHeading({
    required this.order,
    required this.level,
    required this.title,
    required this.origin,
    this.start,
    this.end,
    this.textPage,
    this.pdfPage,
  }) : assert(order >= 0, 'El orden empieza en 0.'),
       assert(level >= 1, 'El nivel empieza en 1.'),
       assert((start == null) == (end == null), 'El tramo va entero o no va.'),
       assert(
         (start == null) == (textPage == null),
         'Lo que está en el texto lleva su página del texto.',
       );

  /// Su lugar en el documento, de 0 en adelante: el orden en que se leen.
  final int order;

  final int level;

  /// El título como se lee: sin las marcas de Markdown, con sus mayúsculas y
  /// su numeración («1.2.3 El origen»). Vacío en un texto sin títulos
  /// ([ProcessedHeadingOrigin.wholeText]), cuyo nombre —«Texto completo»— lo
  /// pone la pantalla en su idioma.
  final String title;

  final ProcessedHeadingOrigin origin;

  final int? start;
  final int? end;
  final int? textPage;
  final int? pdfPage;

  /// Si se sabe dónde está en el texto procesado.
  bool get located => start != null;

  @override
  bool operator ==(Object other) =>
      other is ProcessedHeading &&
      other.order == order &&
      other.level == level &&
      other.title == title &&
      other.origin == origin &&
      other.start == start &&
      other.end == end &&
      other.textPage == textPage &&
      other.pdfPage == pdfPage;

  @override
  int get hashCode =>
      Object.hash(order, level, title, origin, start, end, textPage, pdfPage);

  @override
  String toString() =>
      'ProcessedHeading($order, $level, "$title", ${origin.name}, '
      '[$start, $end), pág. $textPage, p. $pdfPage)';
}

/// Un marcador de un PDF (F46, decisión B), ya aplanado en el orden en que se
/// leen: el de un capítulo y después los de sus secciones.
@immutable
class PdfBookmark {
  const PdfBookmark({required this.title, required this.depth, this.page})
    : assert(depth >= 1, 'La profundidad empieza en 1.');

  /// El título tal como lo trae el PDF, sin espacios de más.
  final String title;

  /// A qué profundidad del árbol de marcadores está: 1 los de arriba.
  final int depth;

  /// La página a la que lleva, de 1 en adelante; `null` si no lleva a
  /// ninguna página del documento.
  final int? page;

  @override
  bool operator ==(Object other) =>
      other is PdfBookmark &&
      other.title == title &&
      other.depth == depth &&
      other.page == page;

  @override
  int get hashCode => Object.hash(title, depth, page);

  @override
  String toString() => 'PdfBookmark("$title", $depth, p. $page)';
}

/// Lo que se lee de un PDF para su Índice: cuántas páginas tiene y sus
/// marcadores —ninguno, si no trae—.
@immutable
class PdfOutline {
  PdfOutline({required this.pageCount, List<PdfBookmark> bookmarks = const []})
    : assert(pageCount >= 0, 'Las páginas no son negativas.'),
      bookmarks = List.unmodifiable(bookmarks);

  final int pageCount;
  final List<PdfBookmark> bookmarks;

  @override
  bool operator ==(Object other) =>
      other is PdfOutline &&
      other.pageCount == pageCount &&
      listEquals(other.bookmarks, bookmarks);

  @override
  int get hashCode => Object.hash(pageCount, Object.hashAll(bookmarks));

  @override
  String toString() => 'PdfOutline($pageCount páginas, $bookmarks)';
}
