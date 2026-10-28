import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/domain/entities/knowledge_item.dart';
import 'package:sinapsis/core/domain/entities/source.dart';
import 'package:sinapsis/core/domain/services/processed_reading.dart';
import 'package:sinapsis/core/util/extracted_text_format.dart';
import 'package:sinapsis/features/ai_organize/domain/services/organize_text.dart';
import 'package:sinapsis/features/processed/data/repositories/processed_repository_impl.dart';
import 'package:sinapsis/features/processed/domain/entities/processed_part.dart';

/// [OrganizeTextReader] contra la base: las formas del elemento, o las partes
/// de un documento procesado (F41, paso 6).
///
/// Lo leído se guarda con el elemento que se pasó —la cola de la IA arma uno
/// por pasada—: los pasos de una misma pasada piden el texto uno tras otro, y
/// el de un libro procesado son cientos de páginas que no vale la pena leer
/// siete veces. Se va con el elemento.
class OrganizeTextReaderImpl implements OrganizeTextReader {
  OrganizeTextReaderImpl(this._db);

  final AppDatabase _db;

  final _read = Expando<Future<OrganizeText>>();

  @override
  Future<OrganizeText> textOf(KnowledgeItem item) =>
      _read[item] ??= _textOf(item);

  Future<OrganizeText> _textOf(KnowledgeItem item) async {
    final processed = await (_db.select(
      _db.processedDocuments,
    )..where((d) => d.itemId.equals(item.id))).getSingleOrNull();
    if (processed == null) return ownTextOf(item);

    final rows = await (_db.select(
      _db.processedParts,
    )..where((p) => p.documentId.equals(item.id))).get();
    final parts = [for (final row in rows) processedPartFromRow(row)]
      ..sort((a, b) {
        final bySection = a.section.index.compareTo(b.section.index);
        if (bySection != 0) return bySection;
        final byPosition = a.position.compareTo(b.position);
        return byPosition != 0 ? byPosition : a.id.compareTo(b.id);
      });
    final joined = joinProcessedParts([
      for (final part in parts) (section: part.section, content: part.content),
    ]);
    return OrganizeText(
      text: joined.text,
      markdown: await _sourceIsMarkdown(processed),
      cite: (start, end) => citeInSource(parts, joined, start, end),
      processed: true,
    );
  }

  /// Si lo copiado de la fuente de [processed] es Markdown, como lo era en
  /// ella: una página o un Word convertidos sí, la transcripción o el texto de
  /// un PDF no. Se mira el tipo que se guardó al procesarla y, si la fuente
  /// sigue, su archivo.
  Future<bool> _sourceIsMarkdown(ProcessedDocumentRow processed) async {
    final sourceId = processed.sourceItemId;
    final row = sourceId == null
        ? null
        : await (_db.select(
            _db.knowledgeSources,
          )..where((s) => s.itemId.equals(sourceId))).getSingleOrNull();
    return extractedTextIsMarkdown(
      Source(
        id: sourceId ?? processed.itemId,
        kind: processed.sourceKind,
        capturedAt: processed.createdAt,
        originalFilePath: row?.originalBlobPath,
      ),
    );
  }
}

/// Dónde citar en la fuente el tramo `[start, end)` del texto [joined] de
/// [parts] (F41, paso 6), o `null` si no hay un lugar del original con ese
/// mismo texto.
///
/// Los dos extremos tienen que caer en partes copiadas sin editar
/// (`ProcessedPart.sourceOffsetOf`) de la misma forma de la fuente. Un tramo
/// que cruza de una parte a otra solo se cita si entre ellas no hay nada que el
/// original no tenga: partes pegadas —dos páginas seguidas del texto— y
/// contiguas en la fuente. Dos oraciones del resumen están separadas en el
/// texto y quizás a párrafos de distancia en el original: citarlas juntas
/// marcaría lo que no se eligió.
OrganizeCitation? citeInSource(
  List<ProcessedPart> parts,
  ProcessedJoin joined,
  int start,
  int end,
) {
  if (start < 0 || end <= start || end > joined.text.length) return null;
  final first = _partAt(joined.starts, start);
  final last = _partAt(joined.starts, end - 1);
  if (first < 0 || last < 0) return null;
  for (var i = first + 1; i <= last; i++) {
    final before = parts[i - 1];
    final after = parts[i];
    if (!joined.glued[i] ||
        before.sourceRenditionId != after.sourceRenditionId ||
        before.sourceEnd == null ||
        before.sourceEnd != after.sourceStart ||
        !before.isPristineCopy) {
      return null;
    }
  }
  final from = parts[first].sourceOffsetOf(start - joined.starts[first]);
  final to = parts[last].sourceOffsetOf(end - joined.starts[last]);
  final renditionId = parts[first].sourceRenditionId;
  if (from == null || to == null || renditionId == null) return null;
  return (renditionId: renditionId, start: from, end: to);
}

/// La parte que contiene la posición [offset] del texto: la última que empieza
/// en ella o antes. `-1` si cae en el separador antes de la primera —no pasa—
/// o no hay partes. Una posición en el separador entre dos partes cae en la de
/// antes, fuera de su texto: `sourceOffsetOf` la rechaza.
int _partAt(List<int> starts, int offset) {
  var low = 0;
  var high = starts.length - 1;
  var found = -1;
  while (low <= high) {
    final middle = (low + high) >> 1;
    if (starts[middle] <= offset) {
      found = middle;
      low = middle + 1;
    } else {
      high = middle - 1;
    }
  }
  return found;
}
