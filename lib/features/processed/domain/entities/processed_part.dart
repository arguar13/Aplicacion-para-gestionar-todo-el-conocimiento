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

/// Un tramo `[start, end)` dentro del texto de una parte: dónde está cada
/// palabra clave en su oración (v46).
@freezed
sealed class ProcessedSpan with _$ProcessedSpan {
  const factory ProcessedSpan({
    required int start,
    required int end,

    /// Si la eligió la persona a mano en el procesado («Elegir a mano»,
    /// decisión I): volver a analizar no la saca, y «Actualizar» desde la
    /// fuente no pisa su oración.
    @Default(false) bool chosen,
  }) = _ProcessedSpan;
}

/// Una parte de un documento procesado (F41): una página del texto, una oración
/// del resumen, de la síntesis o con palabras clave, una nota o un fragmento.
/// Ver `ProcessedParts`.
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

    /// Dónde está en el texto propio del procesado (decisión I): el tramo de su
    /// sección «Texto», sus páginas una detrás de la otra. Una página lo tiene
    /// siempre; una oración, mientras se sepa dónde está.
    int? textStart,
    int? textEnd,

    /// En las palabras clave, dónde está cada palabra dentro de [content], en
    /// orden. Vacío en las demás secciones.
    @Default(<ProcessedSpan>[]) List<ProcessedSpan> spans,
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

  /// Si es todavía lo de la fuente, letra por letra: copiada, sin editar y sin
  /// ninguna palabra clave elegida a mano en el procesado. Es lo único que
  /// «Actualizar» renueva.
  bool get isPristineCopy =>
      origin == ProcessedPartOrigin.copied &&
      !edited &&
      !spans.any((span) => span.chosen);

  /// Si es propia del procesado (decisión I): estudiada o elegida en él. Como
  /// lo escrito o lo editado, «Actualizar» desde la fuente no la pisa.
  bool get isStudiedHere =>
      origin == ProcessedPartOrigin.studied ||
      origin == ProcessedPartOrigin.chosen;

  /// Si [content] es, letra por letra, el texto que marca su ancla: lo copiado
  /// sin editar —aunque se le haya elegido una palabra clave—, y lo estudiado
  /// en el procesado —una oración de su texto—, que lleva el ancla en la
  /// fuente solo si esa página era la de la fuente.
  bool get isVerbatim =>
      (origin == ProcessedPartOrigin.copied && !edited) || isStudiedHere;

  /// Dónde está en el texto propio del procesado, si se sabe.
  ProcessedSpan? get textRange {
    final start = textStart;
    final end = textEnd;
    return start == null || end == null
        ? null
        : ProcessedSpan(start: start, end: end);
  }

  /// Las palabras clave, en orden: el texto de cada tramo de [spans].
  List<String> get keywords => [
    for (final span in spans) content.substring(span.start, span.end),
  ];

  /// La posición en el original de la posición [offset] de [content] —para
  /// citar en la fuente algo encontrado en esta parte, como una fecha del paso
  /// 6—, o `null` si no se puede: si la parte se editó, sus letras ya no son
  /// las de la fuente, y si no tiene ancla no hay a dónde llevarla.
  int? sourceOffsetOf(int offset) {
    final anchor = this.anchor;
    if (anchor == null || !isVerbatim) return null;
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
