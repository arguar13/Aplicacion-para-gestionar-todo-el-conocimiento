/// Cómo se deduce un título cuando el usuario no puso uno.
///
/// Son títulos **provisionales**: valen hasta que la etapa de transformación
/// traiga el real (el `<title>` de la página, el nombre del video). Lo que
/// tienen que lograr mientras tanto es que la lista se pueda leer — una fila
/// que dice `https://ejemplo.org/blog/2019/03/la-estructura-de-las-revoluciones`
/// es ruido; una que dice "La estructura de las revoluciones" es útil desde
/// el primer segundo.
///
/// Ninguno de estos textos pasa por el sistema de traducciones, y es
/// deliberado: esto termina guardado como el título de un elemento, no
/// dibujado en la pantalla. Si dependiera del idioma de la interfaz, cambiar
/// de idioma renombraría lo que el usuario ya tiene guardado.
library;

/// Un título sacado de la dirección.
///
/// Usa el último tramo del camino, que en la mayoría de los sitios es el
/// título del artículo convertido a minúsculas y guiones. Cuando ese tramo no
/// dice nada —un identificador, un número, una ruta vacía— cae al host, que
/// al menos ubica de dónde salió.
String titleFromUrl(Uri url) {
  final segments = url.pathSegments.where((s) => s.trim().isNotEmpty).toList();
  if (segments.isEmpty) return url.host;

  var last = segments.last;

  // Quita la extensión, si la hay: "articulo.html" -> "articulo".
  final dot = last.lastIndexOf('.');
  if (dot > 0) last = last.substring(0, dot);

  final words = last.replaceAll(RegExp('[-_]+'), ' ').trim();

  // Un tramo que es solo dígitos (el "12345" de /post/12345) o demasiado
  // corto no es un título: no aporta nada y el host ubica mejor.
  final isJustDigits = RegExp(r'^\d+$').hasMatch(words);
  if (words.isEmpty || isJustDigits || words.length < 3) return url.host;

  return _capitalize(words);
}

/// Un título sacado del propio texto: su primera línea con contenido.
///
/// Se corta en el último espacio antes del límite para no partir una palabra
/// al medio, que se lee peor que un título más corto.
String titleFromText(String text, {int maxLength = 80}) {
  final firstLine = text
      .split('\n')
      .map((line) => line.trim())
      .firstWhere((line) => line.isNotEmpty, orElse: () => '');

  if (firstLine.isEmpty) return '';
  if (firstLine.length <= maxLength) return firstLine;

  final cut = firstLine.substring(0, maxLength);
  final lastSpace = cut.lastIndexOf(' ');
  final trimmed = lastSpace > maxLength ~/ 2
      ? cut.substring(0, lastSpace)
      : cut;

  return '$trimmed…';
}

String _capitalize(String text) => text[0].toUpperCase() + text.substring(1);
