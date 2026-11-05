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

/// Una nota sobre el documento entero para lo que se descarga (F45, paso
/// 8c): la que se escribió desde «Notas (N)» sin elegir nada. No cita ningún
/// pedazo, así que no tiene dónde ir en el texto: va al comienzo, como nota
/// del documento ([WholeDocumentNotes]).
class WholeDocumentNote {
  const WholeDocumentNote({required this.note, required this.color});

  /// Lo que la persona escribió.
  final String note;

  /// El color de la nota, en ARGB (`0xAARRGGBB`), el de su línea sobre el
  /// papel: el de su ícono en el PDF y la raya que la acompaña en el texto.
  final int color;
}

/// Las notas sobre el documento entero, al comienzo de lo que se descarga
/// (F45, paso 8c), en un bloque prolijo con el mismo estilo de las demás
/// notas de cada formato: en el PDF, notas del PDF arriba a la izquierda de
/// la primera página; en el texto, un bloque con su título ([title], «Notas
/// del documento») antes de lo primero que se lee.
class WholeDocumentNotes {
  const WholeDocumentNotes({required this.title, required this.notes});

  /// Sin ninguna.
  static const none = WholeDocumentNotes(title: '', notes: []);

  /// El título del bloque, ya traducido.
  final String title;

  /// En el orden en que se escribieron.
  final List<WholeDocumentNote> notes;

  bool get isEmpty => notes.isEmpty;
}
