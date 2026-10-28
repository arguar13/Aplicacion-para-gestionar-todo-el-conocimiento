import 'package:drift/drift.dart';
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/database/knowledge_mirror_mapping.dart';
import 'package:sinapsis/core/domain/entities/item_kind.dart';
import 'package:sinapsis/core/domain/entities/item_state.dart';
import 'package:sinapsis/core/domain/entities/note_kind.dart';
import 'package:sinapsis/core/domain/entities/note_maturity.dart';
import 'package:sinapsis/core/domain/entities/processed_section.dart';
import 'package:sinapsis/core/domain/entities/source_kind.dart';

/// Un documento procesado (F41) escrito directo en las tablas, como lo deja
/// `ProcessedRepositoryImpl`: su fila de `item`, su `note` de tipo
/// `NoteKind.processed`, su fila de `processed_documents` y una parte por cada
/// texto de [parts], sin ancla —escrita por la persona en las notas, copiada
/// en el resto—.
///
/// Para las pruebas que necesitan procesados sin pasar por triar una fuente:
/// las de los cuadernos (paso 5), que solo miran cuáles hay y qué tienen.
Future<void> insertProcessedRows(
  AppDatabase db, {
  required String id,
  required String title,
  String? sourceItemId,
  SourceKind sourceKind = SourceKind.document,
  Map<ProcessedSection, List<String>> parts = const {
    ProcessedSection.notes: ['Una nota.'],
  },
  DateTime? createdAt,
}) async {
  final at = createdAt ?? DateTime(2026, 10, 27, 10);
  await db
      .into(db.knowledgeEntries)
      .insert(
        KnowledgeEntriesCompanion.insert(
          id: id,
          title: title,
          kind: ItemKind.note,
          state: ItemState.processed,
          createdAt: at,
          updatedAt: at,
          deviceId: kMirrorDeviceIdPlaceholder,
        ),
      );
  await db
      .into(db.knowledgeNotes)
      .insert(
        KnowledgeNotesCompanion.insert(
          itemId: id,
          noteKind: NoteKind.processed,
          maturity: NoteMaturity.seed,
        ),
      );
  await db
      .into(db.processedDocuments)
      .insert(
        ProcessedDocumentsCompanion.insert(
          itemId: id,
          sourceItemId: Value(sourceItemId),
          sourceKind: sourceKind,
          createdAt: at,
        ),
      );
  for (final MapEntry(key: section, value: texts) in parts.entries) {
    final copied = section != ProcessedSection.notes;
    var start = 0;
    for (var position = 0; position < texts.length; position++) {
      final end = start + texts[position].length;
      await db
          .into(db.processedParts)
          .insert(
            ProcessedPartsCompanion.insert(
              id: '$id-${section.name}-$position',
              documentId: id,
              section: section,
              position: position,
              content: texts[position],
              // Solo una nota es de la persona; lo demás se copió, y lo
              // copiado guarda dónde estaba aunque su forma ya no esté.
              origin: copied
                  ? ProcessedPartOrigin.copied
                  : ProcessedPartOrigin.user,
              sourceStart: Value(copied ? start : null),
              sourceEnd: Value(copied ? end : null),
              // Una oración con palabras clave lleva sus tramos (v46).
              spans: Value(section == ProcessedSection.keywords ? '[]' : null),
              createdAt: at,
              updatedAt: at,
            ),
          );
      start = end + 1;
    }
  }
}

/// Un documento procesado con un mismo texto —[text], o el título— en cada una
/// de [sections]: lo que leen el Atlas, el Mapa, el grafo local y la Línea de
/// tiempo (F41, paso 6), que miran qué secciones tiene y no qué dice cada una.
/// Lo escribe [insertProcessedRows]; las pruebas que necesitan el camino
/// entero —una fuente que se tría— pasan por `ProcessSourceUseCase`.
Future<void> insertProcessedDocument(
  AppDatabase db, {
  required String id,
  required String title,
  DateTime? createdAt,
  Set<ProcessedSection> sections = const {ProcessedSection.text},
  SourceKind sourceKind = SourceKind.webPage,
  String? text,
}) => insertProcessedRows(
  db,
  id: id,
  title: title,
  sourceKind: sourceKind,
  createdAt: createdAt ?? DateTime(2026, 9, 19, 10),
  parts: {
    for (final section in sections) section: [text ?? title],
  },
);
