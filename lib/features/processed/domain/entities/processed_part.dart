import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:sinapsis/core/domain/entities/processed_section.dart';

part 'processed_part.freezed.dart';

/// Dónde está algo en el texto de una fuente (F41): la forma de texto y el
/// tramo `[start, end)` de su texto entero —las mismas posiciones que
/// `study_marks` y `dated_events`—. Es lo que abre «Abrir en el original» justo
/// ahí.
@freezed
sealed class ProcessedAnchor with _$ProcessedAnchor {
  const factory ProcessedAnchor({
    required String renditionId,
    required int start,
    required int end,
  }) = _ProcessedAnchor;

  const ProcessedAnchor._();

  /// Lo que falla para que sea un ancla, o `null` si está bien.
  String? get problem {
    if (start < 0) return 'El ancla empieza antes del texto.';
    if (end <= start) return 'El ancla no abarca ningún carácter.';
    return null;
  }

  /// Si comparte algún carácter con [other] en el mismo texto.
  bool overlaps(ProcessedAnchor other) =>
      renditionId == other.renditionId &&
      start < other.end &&
      other.start < end;
}

/// Una parte de un documento procesado (F41): una página del texto, una oración
/// del resumen o de la síntesis, una nota o un fragmento. Ver `ProcessedParts`.
@freezed
sealed class ProcessedPart with _$ProcessedPart {
  const factory ProcessedPart({
    required String id,
    required String documentId,
    required ProcessedSection section,

    /// El orden dentro de su sección, de 0 en adelante.
    required int position,

    /// El texto tal como se lee hoy.
    required String content,
    required ProcessedPartOrigin origin,

    /// Si la persona editó una parte copiada.
    required bool edited,
    required DateTime createdAt,
    required DateTime updatedAt,

    /// La forma de la fuente de la que salió, si todavía existe.
    String? sourceRenditionId,

    /// Dónde estaba en el texto de la fuente. Se conservan aunque la forma ya
    /// no esté: recuperar el texto devuelve el ancla.
    int? sourceStart,
    int? sourceEnd,
  }) = _ProcessedPart;

  const ProcessedPart._();

  /// Dónde está en el original, si se puede abrir ahí: la forma existe y se
  /// sabe el tramo.
  ProcessedAnchor? get anchor {
    final renditionId = sourceRenditionId;
    final start = sourceStart;
    final end = sourceEnd;
    if (renditionId == null || start == null || end == null) return null;
    return ProcessedAnchor(renditionId: renditionId, start: start, end: end);
  }

  /// Si es todavía lo de la fuente, letra por letra: copiada y sin editar. Es
  /// lo único que «Actualizar» renueva.
  bool get isPristineCopy => origin == ProcessedPartOrigin.copied && !edited;

  /// La posición en el original de la posición [offset] de [content] —para
  /// citar en la fuente algo encontrado en esta parte, como una fecha del paso
  /// 6—, o `null` si no se puede: si la parte se editó, sus letras ya no son
  /// las de la fuente, y si no tiene ancla no hay a dónde llevarla.
  int? sourceOffsetOf(int offset) {
    final anchor = this.anchor;
    if (anchor == null || !isPristineCopy) return null;
    if (offset < 0 || offset > content.length) return null;
    return anchor.start + offset;
  }
}

/// Lo que la persona elige poner en una sección, antes de guardarlo (F41).
@freezed
sealed class ProcessedDraft with _$ProcessedDraft {
  /// Un pasaje literal de la fuente: un fragmento cortado a mano, o una nota
  /// extraída tal cual. El texto lo copia el caso de uso de la fuente misma
  /// —nunca de lo que diga quien llama—, así que siempre es el del original.
  const factory ProcessedDraft.cut(ProcessedAnchor anchor) = ProcessedCut;

  /// Lo que la persona escribe: una nota, con el pasaje del que salió si lo
  /// hay.
  const factory ProcessedDraft.written(
    String content, {
    ProcessedAnchor? anchor,
  }) = ProcessedWritten;
}
