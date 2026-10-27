import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/database/knowledge_row_mapping.dart';
import 'package:sinapsis/core/domain/entities/processed_section.dart';
import 'package:sinapsis/core/domain/entities/source.dart';
import 'package:sinapsis/core/util/extracted_text_format.dart';
import 'package:sinapsis/features/processed/domain/entities/processed_part.dart';
import 'package:sinapsis/features/processed/domain/services/processed_study_layout.dart';

/// Los tramos de las palabras clave de una parte como los guarda
/// `processed_parts.spans` (v46): `[[inicio, fin], [inicio, fin, 1], …]`, con
/// un `1` al final de la que eligió la persona. `null` fuera de las palabras
/// clave —la base lo exige—.
String? encodeProcessedSpans(
  ProcessedSection section,
  List<ProcessedSpan> spans,
) => section != ProcessedSection.keywords
    ? null
    : jsonEncode([
        for (final span in spans) [span.start, span.end, if (span.chosen) 1],
      ]);

/// Lo guardado por [encodeProcessedSpans].
List<ProcessedSpan> decodeProcessedSpans(String? stored) {
  if (stored == null || stored.isEmpty) return const [];
  return [
    for (final raw in (jsonDecode(stored) as List).cast<List<dynamic>>())
      ProcessedSpan(
        start: raw[0] as int,
        end: raw[1] as int,
        chosen: raw.length > 2 && raw[2] == 1,
      ),
  ];
}

/// La parte que guarda [row].
ProcessedPart processedPartFromRow(ProcessedPartRow row) => ProcessedPart(
  id: row.id,
  documentId: row.documentId,
  section: row.section,
  position: row.position,
  content: row.content,
  origin: row.origin,
  edited: row.edited,
  createdAt: row.createdAt,
  updatedAt: row.updatedAt,
  sourceRenditionId: row.sourceRenditionId,
  sourceStart: row.sourceStart,
  sourceEnd: row.sourceEnd,
  textStart: row.textStart,
  textEnd: row.textEnd,
  spans: decodeProcessedSpans(row.spans),
);

/// La fila de [part] tal como está, para volver a ponerla —deshacer—, con la
/// forma de la fuente solo si [renditionAlive].
ProcessedPartsCompanion processedPartCompanion(
  ProcessedPart part, {
  required bool renditionAlive,
}) => ProcessedPartsCompanion.insert(
  id: part.id,
  documentId: part.documentId,
  section: part.section,
  position: part.position,
  content: part.content,
  origin: part.origin,
  edited: Value(part.edited),
  sourceRenditionId: Value(renditionAlive ? part.sourceRenditionId : null),
  sourceStart: Value(part.sourceStart),
  sourceEnd: Value(part.sourceEnd),
  textStart: Value(part.textStart),
  textEnd: Value(part.textEnd),
  spans: Value(encodeProcessedSpans(part.section, part.spans)),
  createdAt: part.createdAt,
  updatedAt: part.updatedAt,
);

/// Si el texto propio de [documentId] es Markdown (decisión I): como el de su
/// fuente; sin ella, lo que diga el nombre de la copia de su original.
Future<bool> processedTextIsMarkdown(AppDatabase db, String documentId) async {
  final document = await (db.select(
    db.processedDocuments,
  )..where((d) => d.itemId.equals(documentId))).getSingle();
  final sourceId = document.sourceItemId;
  if (sourceId != null) {
    final entry = await (db.select(
      db.knowledgeEntries,
    )..where((e) => e.id.equals(sourceId))).getSingleOrNull();
    final source = await (db.select(
      db.knowledgeSources,
    )..where((s) => s.itemId.equals(sourceId))).getSingleOrNull();
    if (entry != null && source != null) {
      return extractedTextIsMarkdown(sourceFor(entry, source));
    }
  }
  final original =
      await (db.select(db.processedOriginals).join([
            innerJoin(
              db.renditions,
              db.renditions.id.equalsExp(db.processedOriginals.renditionId),
            ),
          ])..where(db.processedOriginals.documentId.equals(documentId)))
          .getSingleOrNull();
  return extractedTextIsMarkdown(
    Source(
      id: documentId,
      kind: document.sourceKind,
      capturedAt: document.createdAt,
      originalFilePath: original?.readTable(db.renditions).relativePath,
    ),
  );
}

/// Cómo se corresponden el texto propio de [documentId] y el de su fuente
/// (decisión I), sin traer el texto: las páginas con dónde están y, las que
/// siguen siendo de la fuente, dónde están en ella. `null` si no tiene
/// sección «Texto».
Future<ProcessedStudyLayout?> pagesLayoutOf(
  AppDatabase db,
  String documentId,
) async {
  final p = db.processedParts;
  final rows =
      await (db.selectOnly(p)
            ..addColumns([
              p.id,
              p.textStart,
              p.textEnd,
              p.origin,
              p.edited,
              p.sourceRenditionId,
              p.sourceStart,
              p.sourceEnd,
            ])
            ..where(
              p.documentId.equals(documentId) &
                  p.section.equalsValue(ProcessedSection.text),
            )
            ..orderBy([OrderingTerm.asc(p.position), OrderingTerm.asc(p.id)]))
          .get();
  if (rows.isEmpty) return null;
  return ProcessedStudyLayout.pages([
    for (final row in rows)
      ProcessedTextPage(
        partId: row.read(p.id)!,
        start: row.read(p.textStart) ?? 0,
        end: row.read(p.textEnd) ?? 0,
        source: _pristineSource(
          origin: row.readWithConverter<ProcessedPartOrigin, String>(p.origin),
          edited: row.read(p.edited) ?? false,
          renditionId: row.read(p.sourceRenditionId),
          start: row.read(p.sourceStart),
          end: row.read(p.sourceEnd),
        ),
      ),
  ]);
}

ProcessedAnchor? _pristineSource({
  required ProcessedPartOrigin? origin,
  required bool edited,
  required String? renditionId,
  required int? start,
  required int? end,
}) {
  if (origin != ProcessedPartOrigin.copied || edited) return null;
  if (renditionId == null || start == null || end == null) return null;
  return ProcessedAnchor(renditionId: renditionId, start: start, end: end);
}
