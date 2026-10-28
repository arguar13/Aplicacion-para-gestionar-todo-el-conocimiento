import 'package:flutter/foundation.dart';
import 'package:sinapsis/core/domain/entities/knowledge_item.dart';
import 'package:sinapsis/core/util/extracted_text_format.dart';
import 'package:sinapsis/features/reading/domain/extractable_text.dart';

/// Dónde se cita algo que la IA encontró en el texto de un elemento: una forma
/// de texto y el tramo `[start, end)` de ella —lo que guardan `dated_events` y
/// lo que abre el lector justo ahí—.
typedef OrganizeCitation = ({String renditionId, int start, int end});

/// El texto que la IA lee de un elemento para organizarlo (F27), y cómo citar
/// lo que encuentra en él (F41, paso 6).
///
/// - De una fuente o una nota, es el de siempre: la forma de texto que abre la
///   lectura (`extractableRendition`) —y las posiciones son de ella— o, de una
///   nota de bloques, el texto que se busca, sin posiciones.
/// - De un **documento procesado**, es solo lo que la persona eligió al triar:
///   sus partes, armadas como las leen los vectores (`joinProcessedParts`). Lo
///   que se encuentra en una parte copiada sin editar se cita **en la fuente**,
///   en su lugar (`ProcessedPart.sourceOffsetOf`); en una editada o escrita por
///   la persona no hay un lugar del original que sea el mismo texto, y queda
///   sin cita.
@immutable
class OrganizeText {
  const OrganizeText({
    required this.text,
    this.markdown = false,
    OrganizeCitation? Function(int start, int end)? cite,
    this.ownRenditionId,
    this.processed = false,
  }) : _cite = cite;

  /// Si es el texto de un documento procesado: lo único cuyas fechas van a la
  /// línea de tiempo (F41, paso 6).
  final bool processed;

  /// Sin nada que leer.
  static const empty = OrganizeText(text: '');

  final String text;

  /// Si [text] es Markdown (`extractedTextIsMarkdown`): cambia cómo se buscan
  /// sus oraciones.
  final bool markdown;

  /// La forma del propio elemento de la que sale [text], si sale de una: las
  /// posiciones de [text] son las de ella. `null` en una nota de bloques y en
  /// un documento procesado, que no tienen una forma con ese texto.
  final String? ownRenditionId;

  final OrganizeCitation? Function(int start, int end)? _cite;

  /// Dónde citar el tramo `[start, end)` de [text], o `null` si no hay un
  /// lugar que abrir con ese mismo texto.
  OrganizeCitation? cite(int start, int end) {
    if (start < 0 || end <= start || end > text.length) return null;
    return _cite?.call(start, end);
  }
}

/// Lee [OrganizeText] de un elemento. Los pasos de la IA lo piden en vez de
/// mirar las formas del elemento: un documento procesado no tiene formas, y su
/// texto vive en sus partes.
// Una sola operación a propósito: los pasos dependen de esto y no de la base.
// ignore: one_member_abstracts
abstract interface class OrganizeTextReader {
  /// El texto de [item]. Vacío si no tiene ninguno.
  Future<OrganizeText> textOf(KnowledgeItem item);
}

/// El texto que [item] trae en sus propias formas (F27, F40): la que abre la
/// lectura (`extractableRendition`), con sus posiciones, o —una nota de
/// bloques— el texto que se busca, sin ellas. Es todo lo que tiene una fuente
/// o una nota; un documento procesado no tiene formas, y su texto lo lee
/// `OrganizeTextReaderImpl` de sus partes.
OrganizeText ownTextOf(KnowledgeItem item) {
  final markdown = extractedTextIsMarkdown(item.source);
  final rendition = extractableRendition(item);
  if (rendition == null) {
    return OrganizeText(text: item.searchableText, markdown: markdown);
  }
  return OrganizeText(
    text: rendition.content,
    markdown: markdown,
    ownRenditionId: rendition.id,
    cite: (start, end) => (renditionId: rendition.id, start: start, end: end),
  );
}

/// [OrganizeTextReader] de lo que el elemento trae en sus formas
/// ([ownTextOf]), sin mirar la base: el de los pasos que no reciben otro.
class OwnTextReader implements OrganizeTextReader {
  const OwnTextReader();

  @override
  Future<OrganizeText> textOf(KnowledgeItem item) async => ownTextOf(item);
}
