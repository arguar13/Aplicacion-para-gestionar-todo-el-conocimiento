/// Corta el contenido de un documento en páginas para el modo de lectura,
/// para que `DocumentReaderScreen` nunca tenga que ponerle formato ni
/// dibujar el libro entero de una sola vez.
///
/// Sin esto, un libro de mil o dos mil páginas reales —varios millones de
/// caracteres— termina en un solo `SelectableText` gigante dentro de un
/// `SingleChildScrollView`: ese widget no recorta lo que no se ve, así que
/// Flutter tiene que calcular el layout de texto del libro entero apenas se
/// abre la pantalla, congelando la app por varios segundos o quedándose sin
/// memoria en un equipo modesto. Separado en páginas y mostrado con
/// `PageView.builder`, cada una se arma —y se descarta— sola, así que el
/// costo de abrir el libro no depende de cuántas páginas tenga.
///
/// **Un PDF ya trae sus propias páginas.** `PdfParser` une el texto de cada
/// página del documento original con el separador `\n\n---\n\n` (ver
/// `pdf_parser.dart`), así que la primera pasada corta exactamente ahí: una
/// página del libro de verdad es una página del lector, ni una letra de
/// diferencia. Para lo que no trae ese separador —un DOCX, un EPUB, texto
/// suelto— no hay páginas "de verdad" a las que volver: se arman juntando
/// párrafos hasta acercarse a [targetPageLength], nunca partiendo un párrafo
/// a la mitad *salvo* que un párrafo solo ya sea más largo que eso —un bloque
/// de texto sin ningún salto de línea real—, donde sí hace falta cortarlo a
/// la fuerza para no dejar una página sin límite de tamaño.
///
/// Cada página es un tramo **tal cual** del contenido —ver
/// [readerPageRanges]—: lo que se resalta en el texto guardado (F36) cae en
/// su página sin traducir nada.
List<String> splitIntoReaderPages(
  String content, {
  int targetPageLength = 2400,
}) => [
  for (final page in readerPageRanges(
    content,
    targetPageLength: targetPageLength,
  ))
    content.substring(page.start, page.end),
];

/// Dónde está cada página de [splitIntoReaderPages] en [content]: el rango
/// `[start, end)`, sin los espacios de los bordes (F36).
///
/// Las posiciones de lo que se resalta —un subrayado, una oración del
/// resumen— son las del contenido entero; con esto, una posición de la
/// página es `posición − start`.
List<({int start, int end})> readerPageRanges(
  String content, {
  int targetPageLength = 2400,
}) {
  final whole = _trim(content, 0, content.length);
  if (whole == null) return const [];

  final pages = <({int start, int end})>[];
  var from = whole.start;
  for (final separator in _pageSeparator.allMatches(content)) {
    _paginateByParagraph(
      content,
      from,
      separator.start,
      targetPageLength,
      pages,
    );
    from = separator.end;
  }
  _paginateByParagraph(content, from, whole.end, targetPageLength, pages);
  return pages;
}

final _pageSeparator = RegExp(r'\n{2,}-{3,}\n{2,}');
final _paragraphBreak = RegExp(r'\n{2,}');

/// Agrupa los párrafos de `[start, end)` —separados por una línea en
/// blanco— en páginas de hasta [targetPageLength] caracteres, cerrando la
/// página actual apenas agregar el próximo párrafo la haría pasarse. Una
/// página nunca queda vacía: si el primer párrafo solo ya supera el límite,
/// se lo corta él mismo (ver [_hardSplit]) en vez de dejar una página sin
/// nada.
///
/// El largo que cuenta es el de los párrafos unidos por un renglón en blanco,
/// aunque en el contenido haya más de uno entre medio.
void _paginateByParagraph(
  String content,
  int start,
  int end,
  int targetPageLength,
  List<({int start, int end})> pages,
) {
  final page = _trim(content, start, end);
  if (page == null) return;

  final paragraphs = <({int start, int end})>[];
  var from = page.start;
  // Sobre el contenido entero y no sobre una copia de la página: en un libro
  // de miles de páginas, copiar cada una costaría lo que no cuesta mostrarla.
  for (final gap in _paragraphBreak.allMatches(content, from)) {
    if (gap.end > page.end) break;
    if (gap.start > from) paragraphs.add((start: from, end: gap.start));
    from = gap.end;
  }
  if (page.end > from) paragraphs.add((start: from, end: page.end));

  int? currentStart;
  var currentEnd = 0;
  var currentLength = 0;

  void flush() {
    if (currentStart == null) return;
    pages.add((start: currentStart!, end: currentEnd));
    currentStart = null;
    currentLength = 0;
  }

  for (final paragraph in paragraphs) {
    final length = paragraph.end - paragraph.start;
    if (length > targetPageLength) {
      flush();
      _hardSplit(content, paragraph, targetPageLength, pages);
      continue;
    }

    final wouldBe = currentStart == null ? length : currentLength + 2 + length;
    if (wouldBe > targetPageLength) flush();

    currentLength = currentStart == null ? length : currentLength + 2 + length;
    currentStart ??= paragraph.start;
    currentEnd = paragraph.end;
  }
  flush();
}

/// Corta un párrafo que por sí solo ya supera [targetPageLength] en tramos
/// de ese tamaño, en el espacio más cercano hacia atrás para no partir una
/// palabra al medio — salvo que no haya ningún espacio en todo el tramo, un
/// caso patológico donde cortar a lo bruto es preferible a no cortar nunca.
void _hardSplit(
  String content,
  ({int start, int end}) paragraph,
  int targetPageLength,
  List<({int start, int end})> pages,
) {
  var start = paragraph.start;

  while (start < paragraph.end) {
    var end = (start + targetPageLength).clamp(0, paragraph.end);
    if (end < paragraph.end) {
      final lastSpace = content.lastIndexOf(' ', end);
      if (lastSpace > start) end = lastSpace;
    }
    if (_trim(content, start, end) case final piece?) pages.add(piece);
    start = end;
    while (start < paragraph.end && content[start] == ' ') {
      start++;
    }
  }
}

/// `[start, end)` de [content] sin espacios en los bordes, o `null` si no
/// queda nada.
({int start, int end})? _trim(String content, int start, int end) {
  var s = start;
  var e = end;
  while (s < e && content[s].trim().isEmpty) {
    s++;
  }
  while (e > s && content[e - 1].trim().isEmpty) {
    e--;
  }
  return s < e ? (start: s, end: e) : null;
}
