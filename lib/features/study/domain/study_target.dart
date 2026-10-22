import 'package:sinapsis/core/domain/entities/knowledge_item.dart';
import 'package:sinapsis/core/domain/entities/rendition.dart';
import 'package:sinapsis/core/domain/entities/source_kind.dart';
import 'package:sinapsis/features/reading/domain/extractable_text.dart';

/// El texto que se estudia de [item] (F36), o `null` si no se estudia: un
/// documento —un PDF, un Word, un EPUB, un texto— o una página web (decisión
/// E), y de él la forma de texto de la que se sacan notas, la misma que
/// muestra el lector.
TextRendition? studyRendition(KnowledgeItem item) {
  if (!_studied.contains(item.source.kind)) return null;
  final rendition = extractableRendition(item);
  if (rendition == null || rendition.content.trim().isEmpty) return null;
  return rendition;
}

const _studied = {SourceKind.document, SourceKind.webPage};
