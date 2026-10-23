import 'package:sinapsis/core/domain/entities/knowledge_item.dart';
import 'package:sinapsis/core/domain/entities/rendition.dart';
import 'package:sinapsis/core/domain/entities/source_kind.dart';
import 'package:sinapsis/core/util/extracted_text_format.dart';
import 'package:sinapsis/features/reading/domain/extractable_text.dart';

/// El texto que se estudia de [item], o `null` si no se estudia: el de todo
/// lo que trae un texto propio —un documento, una página web (F36), una
/// publicación, lo que se leyó de una imagen, la transcripción de un audio o
/// un video (F39)—, y de él la forma de texto de la que se sacan notas, la
/// misma que muestra el lector.
///
/// Una nota no: la escribió la persona, no hay qué resumir de ella. Una
/// referencia tampoco: son los datos para citar algo, no su texto.
TextRendition? studyRendition(KnowledgeItem item) {
  if (_notStudied.contains(item.source.kind)) return null;
  final rendition = extractableRendition(item);
  if (rendition == null || rendition.content.trim().isEmpty) return null;
  return rendition;
}

const _notStudied = {SourceKind.manualNote, SourceKind.reference};

/// El texto que se estudia, para quien lo muestra o lo analiza (F36): el
/// elemento al que pertenece, la forma de texto —lo estudiado y lo que se
/// resalta a mano (F38) se guardan contados en ella—, su contenido y si es
/// Markdown.
typedef StudyText = ({
  String itemId,
  String renditionId,
  String content,
  bool markdown,
});

/// El texto que se estudia de [item], o `null` si no se estudia: ver
/// [studyRendition].
StudyText? studyTextOf(KnowledgeItem item) {
  final rendition = studyRendition(item);
  if (rendition == null) return null;
  return (
    itemId: item.id,
    renditionId: rendition.id,
    content: rendition.content,
    markdown: extractedTextIsMarkdown(item.source),
  );
}
