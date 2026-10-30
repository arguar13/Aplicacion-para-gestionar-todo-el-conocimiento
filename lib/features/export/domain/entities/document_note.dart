/// Una nota en el texto para el documento que se descarga (F45, mejora 19):
/// lo que la persona escribió sobre un pedazo, que sale como nota del PDF —la
/// que se abre con un toque en cualquier lector— y, en el texto, como nota al
/// pie.
///
/// Va aparte de los tramos que se pintan (`DocumentMark`) a propósito: no es
/// una capa de color que pueda tapar a otra —un resaltado y una nota sobre el
/// mismo pedazo conviven—, sino una llamada al final del pedazo con su texto.
///
/// Las posiciones son del texto extraído, como las de un tramo: cada formato
/// ubica el pedazo en su archivo con ellas y con [excerpt].
class DocumentNote {
  const DocumentNote({
    required this.start,
    required this.end,
    required this.excerpt,
    required this.note,
    required this.color,
  });

  /// Dónde empieza el pedazo en el texto extraído.
  final int start;

  /// Dónde termina en el texto extraído (sin incluir).
  final int end;

  /// El pedazo citado.
  final String excerpt;

  /// Lo que la persona escribió.
  final String note;

  /// El color de la nota, en ARGB (`0xAARRGGBB`): el de su ícono en el PDF y
  /// la línea que marca el pedazo.
  final int color;
}
