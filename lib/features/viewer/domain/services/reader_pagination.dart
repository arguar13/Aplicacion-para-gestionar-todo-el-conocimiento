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
List<String> splitIntoReaderPages(
  String content, {
  int targetPageLength = 2400,
}) {
  final trimmed = content.trim();
  if (trimmed.isEmpty) return const [];

  final sourcePages = trimmed.split(RegExp(r'\n{2,}-{3,}\n{2,}'));
  final pages = <String>[];
  for (final sourcePage in sourcePages) {
    pages.addAll(_paginateByParagraph(sourcePage.trim(), targetPageLength));
  }
  return pages;
}

/// Agrupa los párrafos de [text] —separados por una línea en blanco— en
/// páginas de hasta [targetPageLength] caracteres, cerrando la página actual
/// apenas agregar el próximo párrafo la haría pasarse. Una página nunca
/// queda vacía: si el primer párrafo solo ya supera el límite, se lo corta
/// él mismo (ver [_hardSplit]) en vez de dejar una página sin nada.
List<String> _paginateByParagraph(String text, int targetPageLength) {
  if (text.isEmpty) return const [];

  final paragraphs = text.split(RegExp(r'\n{2,}'));
  final pages = <String>[];
  final current = StringBuffer();

  void flush() {
    if (current.isEmpty) return;
    pages.add(current.toString());
    current.clear();
  }

  for (final paragraph in paragraphs) {
    if (paragraph.isEmpty) continue;

    if (paragraph.length > targetPageLength) {
      flush();
      pages.addAll(_hardSplit(paragraph, targetPageLength));
      continue;
    }

    final wouldBe = current.isEmpty
        ? paragraph.length
        : current.length + 2 + paragraph.length;
    if (wouldBe > targetPageLength) flush();

    if (current.isNotEmpty) current.write('\n\n');
    current.write(paragraph);
  }
  flush();

  return pages;
}

/// Corta un párrafo que por sí solo ya supera [targetPageLength] en tramos
/// de ese tamaño, en el espacio más cercano hacia atrás para no partir una
/// palabra al medio — salvo que no haya ningún espacio en todo el tramo, un
/// caso patológico donde cortar a lo bruto es preferible a no cortar nunca.
List<String> _hardSplit(String paragraph, int targetPageLength) {
  final parts = <String>[];
  var start = 0;

  while (start < paragraph.length) {
    var end = (start + targetPageLength).clamp(0, paragraph.length);
    if (end < paragraph.length) {
      final lastSpace = paragraph.lastIndexOf(' ', end);
      if (lastSpace > start) end = lastSpace;
    }
    parts.add(paragraph.substring(start, end).trim());
    start = end;
    while (start < paragraph.length && paragraph[start] == ' ') {
      start++;
    }
  }

  return parts;
}
