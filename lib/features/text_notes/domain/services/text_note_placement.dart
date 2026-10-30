import 'package:meta/meta.dart';
import 'package:sinapsis/core/util/text_anchor_locator.dart';
import 'package:sinapsis/features/text_notes/domain/entities/text_note.dart';

/// Una nota con su lugar en el texto que se está mostrando, o sin lugar.
@immutable
class PlacedTextNote {
  const PlacedTextNote(this.note, {this.start, this.end})
    : assert((start == null) == (end == null), 'el lugar va entero o no va');

  final TextNote note;

  /// Dónde está en el texto que se muestra, `[start, end)`; `null` si en él
  /// ya no se encuentra el pedazo citado: va a la lista como «Sin lugar».
  final int? start;
  final int? end;

  bool get placed => start != null;

  @override
  bool operator ==(Object other) =>
      other is PlacedTextNote &&
      other.note == note &&
      other.start == start &&
      other.end == end;

  @override
  int get hashCode => Object.hash(note, start, end);

  @override
  String toString() => 'PlacedTextNote(${note.id}, [$start, $end))';
}

/// Dónde cae cada una de [notes] en [content], el texto que se muestra con la
/// clave [textKey] (`StudyText.renditionId`), en el orden del texto.
///
/// Lo guardado manda mientras siga siendo verdad: si en su lugar sigue el
/// pedazo citado —y es el mismo texto: una nota del original de la Biblioteca
/// escrita sobre otra forma no vale por sus posiciones—, queda ahí. Si no, se
/// busca el pedazo citado como se reubica un subrayado (`ExcerptLocator`),
/// cerca de donde estaba; si no se encuentra, queda sin lugar. Nunca se
/// pierde ninguna.
///
/// Es la red de todo lo que cambia un texto sin pasar por la reubicación de
/// la base —una página corregida de un procesado, lo creado que se vuelve a
/// generar—: la base reubica al volver a extraer, y esto se asegura de que lo
/// que se pinta caiga siempre sobre su pedazo.
List<PlacedTextNote> placeTextNotes(
  List<TextNote> notes, {
  required String textKey,
  required String content,
}) {
  final locator = ExcerptLocator(content);
  final placed = <PlacedTextNote>[];
  for (final note in notes) {
    final start = note.start;
    final end = note.end;
    final sameText = note.renditionId == null || note.renditionId == textKey;
    if (sameText &&
        start != null &&
        end != null &&
        end <= content.length &&
        content.substring(start, end) == note.excerpt) {
      placed.add(PlacedTextNote(note, start: start, end: end));
      continue;
    }
    final found = locator.locate(note.excerpt, near: start ?? 0);
    placed.add(
      found == null
          ? PlacedTextNote(note)
          : PlacedTextNote(note, start: found.start, end: found.end),
    );
  }
  return placed..sort(_inTextOrder);
}

int _inTextOrder(PlacedTextNote a, PlacedTextNote b) {
  final aStart = a.start;
  final bStart = b.start;
  if ((aStart == null) != (bStart == null)) return aStart == null ? 1 : -1;
  if (aStart != null && bStart != null) {
    final byStart = aStart.compareTo(bStart);
    if (byStart != 0) return byStart;
    final byEnd = a.end!.compareTo(b.end!);
    if (byEnd != 0) return byEnd;
  }
  final byTime = a.note.createdAt.compareTo(b.note.createdAt);
  return byTime != 0 ? byTime : a.note.id.compareTo(b.note.id);
}
