import 'package:flutter/foundation.dart';
import 'package:fpdart/fpdart.dart';
import 'package:sinapsis/core/domain/entities/processed_section.dart';
import 'package:sinapsis/core/error/failures.dart';
import 'package:sinapsis/features/processed/domain/entities/processed_part.dart';
import 'package:sinapsis/features/processed/domain/repositories/processed_repository.dart';
import 'package:sinapsis/features/processed/domain/services/processed_text.dart';

/// Qué separa una parte de la siguiente en el texto de las tarjetas: un
/// renglón en blanco, como entre párrafos. Así una tarjeta no junta el final
/// de una oración del resumen con el principio de una nota.
const kProcessedCardSeparator = '\n\n';

/// Si las partes de [section] entran en el texto del que salen las tarjetas
/// de un documento procesado (F41, decisión I): todo lo que es texto para
/// leer. Las palabras clave también: cada parte es una oración con sus claves
/// marcadas, lo que la persona eligió conservar, y justo lo que sirve para una
/// tarjeta. Que alguna se repita con el Texto solo le da más peso.
///
/// Es un `switch` a propósito: una sección nueva no entra ni sale sola, quien
/// la agrega tiene que decidirlo acá. La consulta de la cobertura de tarjetas
/// (`processedHasCardTextSql`) sale de esta misma regla.
bool isCardSection(ProcessedSection section) => switch (section) {
  ProcessedSection.text ||
  ProcessedSection.summary ||
  ProcessedSection.synthesis ||
  ProcessedSection.keywords ||
  ProcessedSection.notes ||
  ProcessedSection.fragments => true,
  // Las imágenes no son texto del que salga una tarjeta (decisión L).
  ProcessedSection.images => false,
};

/// Las secciones de las que salen las tarjetas, en el orden en que se leen.
List<ProcessedSection> get cardSections => [
  for (final section in ProcessedSection.values)
    if (isCardSection(section)) section,
];

/// Dónde cae una parte dentro del texto de las tarjetas.
@immutable
class ProcessedCardSegment {
  const ProcessedCardSegment({
    required this.partId,
    required this.section,
    required this.start,
    required this.end,
    required this.sourceAnchor,
  });

  final String partId;
  final ProcessedSection section;

  /// El tramo `[start, end)` de la parte en [ProcessedCardText.content].
  final int start;
  final int end;

  /// Dónde está la parte en el original, si sigue siendo letra por letra lo
  /// de la fuente (`ProcessedPart.isPristineCopy`) y tiene ancla; `null` si
  /// se escribió o se editó, o si no se sabe de dónde vino.
  final ProcessedAnchor? sourceAnchor;
}

/// El texto del que salen las tarjetas de repaso de un documento procesado
/// (F41, decisión I): sus partes, en el orden en que se leen —el texto, el
/// resumen, la síntesis, las palabras clave, las notas, los fragmentos—,
/// separadas por [kProcessedCardSeparator]. Es lo que leen las tarjetas y su
/// cobertura; nunca la fuente.
///
/// No es el texto que se resume y se estudia en el procesado
/// (`ProcessedRepository.studyTextOf`, `ProcessedStudyText`): ese son solo las
/// páginas de Texto, o el de la fuente con la copia del original, porque lo
/// estudiado se marca sobre él.
///
/// Sabe de qué parte sale cada tramo ([segments]) y, si esa parte es una copia
/// intacta de la fuente, dónde está en el original ([sourceAnchorOf]).
@immutable
class ProcessedCardText {
  const ProcessedCardText({
    required this.documentId,
    required this.content,
    required this.segments,
  });

  final String documentId;
  final String content;

  /// Una por parte con texto, en el orden de [content].
  final List<ProcessedCardSegment> segments;

  /// Dónde está en el original el tramo `[start, end)` de [content]: solo si
  /// cae entero dentro de una parte copiada intacta. Un tramo que cruza dos
  /// partes, o que es de una parte escrita o editada, no tiene ancla.
  ProcessedAnchor? sourceAnchorOf(int start, int end) {
    if (start < 0 || end <= start || end > content.length) return null;
    // Las partes están en orden: la búsqueda binaria encuentra la de [start]
    // sin recorrer un libro de cientos de páginas.
    var low = 0;
    var high = segments.length - 1;
    while (low <= high) {
      final mid = (low + high) >> 1;
      final segment = segments[mid];
      if (start < segment.start) {
        high = mid - 1;
      } else if (start >= segment.end) {
        low = mid + 1;
      } else {
        final anchor = segment.sourceAnchor;
        if (anchor == null || end > segment.end) return null;
        final offset = start - segment.start;
        return ProcessedAnchor(
          renditionId: anchor.renditionId,
          start: anchor.start + offset,
          end: anchor.start + offset + (end - start),
        );
      }
    }
    return null;
  }
}

/// El texto de las tarjetas de [parts], de [documentId]: solo las secciones
/// de las que salen ([isCardSection]), en el orden en que se leen y, dentro
/// de cada una, en su lugar; sin las partes en blanco. `null` si no queda
/// nada.
///
/// [joined], si se da, es el texto ya armado —el de otro hilo, ver
/// [readProcessedCardText]—; sin él se arma acá.
ProcessedCardText? buildProcessedCardText(
  String documentId,
  List<ProcessedPart> parts, {
  String? joined,
}) {
  final studied = _studied(parts);
  if (studied.isEmpty) return null;
  final segments = <ProcessedCardSegment>[];
  var offset = 0;
  for (final part in studied) {
    if (segments.isNotEmpty) offset += kProcessedCardSeparator.length;
    final end = offset + part.content.length;
    final anchor = part.anchor;
    segments.add(
      ProcessedCardSegment(
        partId: part.id,
        section: part.section,
        start: offset,
        end: end,
        sourceAnchor: part.isPristineCopy ? anchor : null,
      ),
    );
    offset = end;
  }
  return ProcessedCardText(
    documentId: documentId,
    content: joined ?? _join([for (final part in studied) part.content]),
    segments: segments,
  );
}

List<ProcessedPart> _studied(List<ProcessedPart> parts) =>
    [
      for (final part in parts)
        if (isCardSection(part.section) && part.content.trim().isNotEmpty) part,
    ]..sort((a, b) {
      final bySection = a.section.index.compareTo(b.section.index);
      if (bySection != 0) return bySection;
      return a.position.compareTo(b.position);
    });

String _join(List<String> contents) => contents.join(kProcessedCardSeparator);

/// El texto de las tarjetas del elemento [itemId], si es un documento
/// procesado con algo que estudiar; `null` si no lo es o no tiene nada.
///
/// Lee todas sus partes de una vez —las tarjetas se reparten por el texto
/// entero—, y un libro largo se junta en otro hilo, desde
/// [kProcessedInlineChars] caracteres, como el resto de F41: unir tres
/// millones de caracteres no traba la interfaz.
Future<Either<Failure, ProcessedCardText?>> readProcessedCardText(
  ProcessedRepository repository,
  String itemId,
) async {
  final read = await repository.partsOf(itemId, sections: cardSections.toSet());
  final parts = read.getRight().toNullable();
  if (parts == null) return left(read.getLeft().toNullable()!);
  final studied = _studied(parts);
  if (studied.isEmpty) return right(null);
  final contents = [for (final part in studied) part.content];
  final total = contents.fold<int>(0, (sum, c) => sum + c.length);
  final joined = total < kProcessedInlineChars
      ? _join(contents)
      : await compute(_join, contents);
  return right(buildProcessedCardText(itemId, studied, joined: joined));
}
