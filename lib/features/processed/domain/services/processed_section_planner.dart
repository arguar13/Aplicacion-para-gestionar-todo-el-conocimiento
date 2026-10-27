import 'package:flutter/foundation.dart';
import 'package:sinapsis/core/domain/entities/processed_section.dart';
import 'package:sinapsis/features/processed/domain/entities/processed_part.dart';
import 'package:sinapsis/features/processed/domain/entities/section_edit.dart';

/// Una parte que todavía no está guardada: lo que el caso de uso arma con lo
/// que la persona eligió, ya resuelto contra la fuente —el texto de un corte
/// copiado del original, las oraciones de su resumen, las páginas de su
/// texto—.
@immutable
class ProcessedCandidate {
  const ProcessedCandidate({
    required this.content,
    required this.origin,
    this.anchor,
    this.spans = const [],
  });

  final String content;
  final ProcessedPartOrigin origin;
  final ProcessedAnchor? anchor;

  /// En una oración con palabras clave, dónde está cada una dentro de
  /// [content].
  final List<ProcessedSpan> spans;

  @override
  bool operator ==(Object other) =>
      other is ProcessedCandidate &&
      other.content == content &&
      other.origin == origin &&
      other.anchor == anchor &&
      listEquals(other.spans, spans);

  @override
  int get hashCode =>
      Object.hash(content, origin, anchor, Object.hashAll(spans));
}

/// Una parte de cómo va a quedar una sección.
sealed class PlannedPart {
  const PlannedPart();
}

/// Una parte que ya estaba y se queda, tal cual —solo puede cambiar de lugar—.
final class KeptPart extends PlannedPart {
  const KeptPart(this.part);
  final ProcessedPart part;
}

/// Una parte nueva.
final class NewPart extends PlannedPart {
  const NewPart(this.candidate);
  final ProcessedCandidate candidate;
}

/// Cómo va a quedar una sección después de un cambio, sin haberlo guardado:
/// sirve igual para la vista previa de la hoja y para guardar.
@immutable
class SectionPlan {
  const SectionPlan({
    required this.section,
    required this.parts,
    required this.removed,
  });

  final ProcessedSection section;

  /// La sección como va a quedar, en orden.
  final List<PlannedPart> parts;

  /// Las partes que se van.
  final List<ProcessedPart> removed;

  /// Cuántas partes nuevas entran.
  int get added => parts.whereType<NewPart>().length;

  /// Cuántas de las que estaban se quedan.
  int get kept => parts.whereType<KeptPart>().length;

  /// Si no cambia nada: ni entra ni sale ninguna parte, ni se mueve ninguna.
  bool get isNoOp {
    if (removed.isNotEmpty) return false;
    for (var i = 0; i < parts.length; i++) {
      final part = parts[i];
      if (part is NewPart) return false;
      if (part is KeptPart && part.part.position != i) return false;
    }
    return true;
  }

  /// El texto de la sección como va a quedar, en orden: lo que la vista previa
  /// cuenta (oraciones, palabras).
  List<String> get contents => [
    for (final part in parts)
      switch (part) {
        KeptPart(:final part) => part.content,
        NewPart(:final candidate) => candidate.content,
      },
  ];
}

/// Si una sección se ordena como el texto de la fuente: las páginas, las
/// oraciones del resumen y de la síntesis, y los fragmentos van en el orden en
/// que aparecen en el original. Las notas, en el orden en que se escribieron.
bool _ordersByText(ProcessedSection section) =>
    section != ProcessedSection.notes;

/// Cómo queda la sección [section] —que hoy tiene [existing], en orden— si se
/// le hace [change] con [fresh] como lo nuevo (F41). Pura: no lee ni escribe
/// nada, así que la hoja la usa para la vista previa y el caso de uso para
/// guardar, con el mismo resultado.
///
/// La regla de cada cambio:
///
/// - **Quitar** saca todo.
/// - **Reemplazar** saca todo y pone [fresh], sin repetir.
/// - **Agregar** deja todo lo que estaba y suma de [fresh] lo que no lo repite.
///   Repetir es tener el mismo tramo del mismo texto de la fuente o, salvo en
///   las páginas del texto, el mismo texto (sin mirar mayúsculas ni espacios
///   de más). Superponerse no es repetir: dos cortes pueden compartir un
///   pedazo.
/// - **Actualizar** trae la versión de ahora ([fresh]) y conserva lo editado a
///   mano donde no choca:
///   - lo propio del procesado se queda siempre, tal como está: lo que la
///     persona editó o escribió, y lo estudiado o elegido en el procesado
///     (decisión I) —eso solo lo saca «Reemplazar»—;
///   - lo copiado sin editar se queda si la versión de ahora lo trae igual —el
///     mismo tramo con el mismo texto y, en las palabras clave, las mismas
///     palabras: no se reescribe nada—, y si no, se va;
///   - de la versión de ahora entra lo demás, salvo lo que **choca** con algo
///     editado: lo que se superpone, en el mismo texto, con una parte que la
///     persona editó o que estudió en el procesado. Ahí gana lo propio —es más
///     nuevo que la fuente y es suyo—, y por eso «Actualizar» nunca duplica un
///     pasaje con dos versiones.
///
/// Lo nuevo se ubica en el orden del texto de la fuente, entre lo que se queda:
/// justo antes de la primera parte con ancla, en el mismo texto, que empieza
/// después; lo que no tiene ninguna después, al final. Lo que se queda sin
/// ancla —su texto de la fuente ya no está— sigue pegado a lo que tenía antes.
/// En las notas, lo nuevo se suma al final, en el orden en que llega.
SectionPlan planSectionChange({
  required ProcessedSection section,
  required List<ProcessedPart> existing,
  required ProcessedChange change,
  List<ProcessedCandidate> fresh = const [],
}) {
  switch (change) {
    case ProcessedChange.remove:
      return SectionPlan(section: section, parts: const [], removed: existing);
    case ProcessedChange.replace:
      return SectionPlan(
        section: section,
        parts: [
          for (final candidate in _withoutRepeats(section, fresh, const []))
            NewPart(candidate),
        ],
        removed: existing,
      );
    case ProcessedChange.add:
      final added = _withoutRepeats(section, fresh, existing);
      return SectionPlan(
        section: section,
        parts: _merge(section, [for (final p in existing) KeptPart(p)], added),
        removed: const [],
      );
    case ProcessedChange.update:
      return _update(section, existing, fresh);
  }
}

SectionPlan _update(
  ProcessedSection section,
  List<ProcessedPart> existing,
  List<ProcessedCandidate> fresh,
) {
  // Lo de ahora, por su tramo: lo copiado sin editar que la fuente sigue
  // trayendo igual se queda tal cual.
  final freshByAnchor = <ProcessedAnchor, ProcessedCandidate>{
    for (final candidate in fresh)
      if (candidate.anchor case final anchor?) anchor: candidate,
  };
  final consumed = <ProcessedCandidate>{};
  final kept = <KeptPart>[];
  final removed = <ProcessedPart>[];
  final edits = <ProcessedAnchor>[];
  for (final part in existing) {
    if (!part.isPristineCopy) {
      kept.add(KeptPart(part));
      if (part.anchor case final anchor?) edits.add(anchor);
      continue;
    }
    final same = part.anchor == null ? null : freshByAnchor[part.anchor];
    if (same != null &&
        same.content == part.content &&
        listEquals(same.spans, part.spans)) {
      kept.add(KeptPart(part));
      consumed.add(same);
    } else {
      removed.add(part);
    }
  }
  final keptParts = [for (final k in kept) k.part];
  final incoming = _withoutRepeats(section, [
    for (final candidate in fresh)
      if (!consumed.contains(candidate) && !_clashes(candidate.anchor, edits))
        candidate,
  ], keptParts);
  return SectionPlan(
    section: section,
    parts: _merge(section, kept, incoming),
    removed: removed,
  );
}

/// Si [anchor] se superpone con alguna parte editada de [edits].
bool _clashes(ProcessedAnchor? anchor, List<ProcessedAnchor> edits) {
  if (anchor == null) return false;
  for (final edit in edits) {
    if (anchor.overlaps(edit)) return true;
  }
  return false;
}

/// [candidates] sin lo que repite algo de [existing] ni lo que se repite
/// entre sí: ver [planSectionChange].
List<ProcessedCandidate> _withoutRepeats(
  ProcessedSection section,
  List<ProcessedCandidate> candidates,
  List<ProcessedPart> existing,
) {
  final byText = section != ProcessedSection.text;
  final anchors = <ProcessedAnchor>{for (final part in existing) ?part.anchor};
  final texts = <String>{
    if (byText)
      for (final part in existing) _normalized(part.content),
  };
  final accepted = <ProcessedCandidate>[];
  for (final candidate in candidates) {
    final anchor = candidate.anchor;
    if (anchor != null && !anchors.add(anchor)) continue;
    if (byText && !texts.add(_normalized(candidate.content))) continue;
    accepted.add(candidate);
  }
  return accepted;
}

final _spaces = RegExp(r'\s+');

String _normalized(String text) =>
    text.trim().replaceAll(_spaces, ' ').toLowerCase();

/// Lo que se queda ([kept], en su orden) con lo nuevo ([incoming]) en el
/// lugar que le toca: en el orden del texto de la fuente, o al final en las
/// notas. Ver [planSectionChange].
List<PlannedPart> _merge(
  ProcessedSection section,
  List<KeptPart> kept,
  List<ProcessedCandidate> incoming,
) {
  if (!_ordersByText(section) || incoming.isEmpty) {
    return [...kept, for (final candidate in incoming) NewPart(candidate)];
  }
  final sorted = [...incoming]..sort(_byPlaceInSource);
  final merged = <PlannedPart>[];
  var next = 0;
  for (final part in kept) {
    final anchor = part.part.anchor;
    if (anchor != null) {
      while (next < sorted.length && _goesBefore(sorted[next].anchor, anchor)) {
        merged.add(NewPart(sorted[next++]));
      }
    }
    merged.add(part);
  }
  for (; next < sorted.length; next++) {
    merged.add(NewPart(sorted[next]));
  }
  return merged;
}

/// Lo nuevo con ancla va en el orden del texto; lo que no tiene, al final, en
/// el orden en que llegó (el orden de `sort` de Dart es estable).
int _byPlaceInSource(ProcessedCandidate a, ProcessedCandidate b) {
  final x = a.anchor;
  final y = b.anchor;
  if (x == null || y == null) return (x == null ? 1 : 0) - (y == null ? 1 : 0);
  final byText = x.renditionId.compareTo(y.renditionId);
  if (byText != 0) return byText;
  final byStart = x.start.compareTo(y.start);
  return byStart != 0 ? byStart : x.end.compareTo(y.end);
}

/// Si lo nuevo anclado en [candidate] va antes de lo que se queda anclado en
/// [kept]: en el mismo texto y empezando antes. En otro texto no se compara.
bool _goesBefore(ProcessedAnchor? candidate, ProcessedAnchor kept) =>
    candidate != null &&
    candidate.renditionId == kept.renditionId &&
    (candidate.start < kept.start ||
        (candidate.start == kept.start && candidate.end < kept.end));
