/// Lo que va entre página y página en el texto de un PDF: el texto número N
/// entre separadores es la página N (ver `PdfParser`).
const pdfPageSeparator = '\n\n---\n\n';

/// El texto de una página de PDF, tal como lo trae el documento (F22).
///
/// Lo único que cambia son los finales de línea —`\r\n` y `\r` pasan a
/// `\n`, el mismo salto escrito de otra forma— y una página que es solo
/// espacios cuenta como vacía: no tiene ninguna letra, y es lo que marca una
/// página escaneada (ver `PdfParser`).
///
/// El resto queda: los saltos de línea de la maquetación, los guiones
/// de corte al final del renglón, los espacios que alinean columnas. Antes
/// se "limpiaba" —se unían los renglones, se juntaban `cono-` y `cimiento`,
/// se colapsaban los espacios—, y eso borraba la forma de poemas, listas,
/// tablas e índices, pegaba compuestos como `teórico-práctico` en
/// `teóricopráctico` y rangos como `1990-1995` en `19901995`. Ninguna de
/// esas uniones hacía falta: la búsqueda encuentra una frase aunque cruce un
/// salto de línea, y encuentra la palabra cortada por guion porque el índice
/// —solo el índice— recibe también la versión con esas palabras unidas (ver
/// `chunkSearchText` en `search_index.dart`).
String cleanPdfPageText(String raw) {
  final text = raw.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
  return text.trim().isEmpty ? '' : text;
}

/// Para cada letra de `cleanPdfPageText(raw)`, cuál es en [raw] (F36): el
/// PDF ubica cada letra de [raw] en la página, y lo resaltado se cuenta en el
/// texto limpio. Solo cambia algo donde un `\r\n` quedó en un `\n`, que es el
/// del par.
List<int> pdfCleanToRawIndices(String raw) {
  if (cleanPdfPageText(raw).isEmpty) return const [];
  final indices = <int>[];
  for (var i = 0; i < raw.length; i++) {
    final crlf =
        raw.codeUnitAt(i) == 0x0D &&
        i + 1 < raw.length &&
        raw.codeUnitAt(i + 1) == 0x0A;
    if (!crlf) indices.add(i);
  }
  return indices;
}
