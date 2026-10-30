import 'package:meta/meta.dart';
import 'package:sinapsis/core/domain/entities/highlight_color.dart';
import 'package:sinapsis/features/text_notes/domain/entities/text_note_target.dart';

/// De dónde viene una nota en el texto (decisión I).
enum TextNoteOrigin {
  /// Una nota de `text_notes` (F45, mejora 19).
  note,

  /// La nota de un resaltado de antes (F38): no se migra, pero se lee, se ve y
  /// se busca como una nota más. Sus cambios van al resaltado, y borrarla le
  /// saca la nota y deja el resaltado.
  highlight,
}

/// Una nota en el texto (F45, mejora 19): lo que la persona escribió sobre un
/// pedazo de un texto, con su color.
///
/// Es una sola forma para las notas nuevas y para las de los resaltados de
/// antes (F38, [TextNoteOrigin.highlight]): la segunda parte del paso las
/// muestra con el mismo globito, en la misma lista, con las mismas acciones.
@immutable
class TextNote {
  const TextNote({
    required this.id,
    required this.origin,
    required this.target,
    required this.excerpt,
    required this.note,
    required this.createdAt,
    required this.updatedAt,
    this.start,
    this.end,
    this.color,
    this.renditionId,
  }) : assert((start == null) == (end == null), 'el lugar va entero o no va');

  /// El id de la nota, o el del resaltado si viene de uno.
  final String id;
  final TextNoteOrigin origin;

  /// De qué texto es.
  final TextNoteTarget target;

  /// Su lugar en el texto, `[start, end)`; los dos `null` si quedó sin lugar
  /// —el texto cambió y el pedazo citado ya no se encontró—.
  final int? start;
  final int? end;

  /// El pedazo citado, copiado: con él se reubica.
  final String excerpt;

  /// Lo que la persona escribió.
  final String note;

  /// Uno de los colores de resaltar. `null` solo en un resaltado de antes
  /// que no eligió color: se ve con el de siempre.
  final HighlightColor? color;

  /// La forma de texto sobre la que valen [start] y [end], en el original de
  /// la Biblioteca; `null` en los demás textos.
  final String? renditionId;

  final DateTime createdAt;

  /// Cuándo se editó por última vez; en un resaltado de antes, cuándo se hizo.
  final DateTime updatedAt;

  /// Si tiene un lugar guardado.
  bool get hasPlace => start != null;

  TextNote copyWith({
    String? note,
    HighlightColor? color,
    DateTime? updatedAt,
  }) => TextNote(
    id: id,
    origin: origin,
    target: target,
    start: start,
    end: end,
    excerpt: excerpt,
    note: note ?? this.note,
    color: color ?? this.color,
    renditionId: renditionId,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );

  @override
  bool operator ==(Object other) =>
      other is TextNote &&
      other.id == id &&
      other.origin == origin &&
      other.target == target &&
      other.start == start &&
      other.end == end &&
      other.excerpt == excerpt &&
      other.note == note &&
      other.color == color &&
      other.renditionId == renditionId &&
      other.createdAt == createdAt &&
      other.updatedAt == updatedAt;

  @override
  int get hashCode => Object.hash(
    id,
    origin,
    target,
    start,
    end,
    excerpt,
    note,
    color,
    renditionId,
    createdAt,
    updatedAt,
  );

  @override
  String toString() =>
      'TextNote($origin $id, $target, [$start, $end), «$excerpt»)';
}

/// El orden del texto (F45, mejora 19, «Notas (N)»): primero las que tienen
/// lugar, por dónde empiezan —y a igual comienzo, la más corta, después la
/// más vieja—; al final las que quedaron sin lugar, de la más vieja a la más
/// nueva. El id desempata: el orden no depende de cómo los entregó la base.
int compareInTextOrder(TextNote a, TextNote b) {
  final aStart = a.start;
  final bStart = b.start;
  if ((aStart == null) != (bStart == null)) return aStart == null ? 1 : -1;
  if (aStart != null && bStart != null) {
    final byStart = aStart.compareTo(bStart);
    if (byStart != 0) return byStart;
    final byEnd = a.end!.compareTo(b.end!);
    if (byEnd != 0) return byEnd;
  }
  final byTime = a.createdAt.compareTo(b.createdAt);
  return byTime != 0 ? byTime : a.id.compareTo(b.id);
}
