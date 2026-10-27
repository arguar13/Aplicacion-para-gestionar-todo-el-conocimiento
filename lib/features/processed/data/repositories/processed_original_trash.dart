import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/domain/entities/trashed_content_kind.dart';
import 'package:sinapsis/core/util/id_generator.dart';

/// Lo que guarda la papelera del contenido de la copia del original de un
/// documento procesado (F41, decisión H): lo de su fila de
/// `processed_originals`, para que al recuperarla vuelva a ser su original.
String encodeTrashedProcessedOriginal(ProcessedOriginalRow row) => jsonEncode({
  'sourceFilePath': row.sourceFilePath,
  'sourceFileSize': row.sourceFileSize,
  if (row.textHash != null) 'textHash': row.textHash,
  'copiedAt': row.copiedAt.millisecondsSinceEpoch,
});

/// Manda a la papelera del contenido la copia del original de [documentId]
/// —la forma con su archivo y lo que decía de él— y devuelve la fila de la
/// papelera, o `null` si no tenía. El archivo no se toca: se borra recién al
/// vencer, como todo lo soltado. Corre dentro de la transacción de quien
/// llama.
Future<String?> trashProcessedOriginal(
  AppDatabase db, {
  required String documentId,
  required IdGenerator ids,
  required DateTime at,
}) async {
  final original = await (db.select(
    db.processedOriginals,
  )..where((o) => o.documentId.equals(documentId))).getSingleOrNull();
  if (original == null) return null;
  final rendition = await (db.select(
    db.renditions,
  )..where((r) => r.id.equals(original.renditionId))).getSingle();
  final id = ids.next();
  await db
      .into(db.trashedContents)
      .insert(
        TrashedContentsCompanion.insert(
          id: id,
          itemId: documentId,
          kind: TrashedContentKind.file,
          relativePath: Value(rendition.relativePath),
          sizeBytes: Value(rendition.sizeBytes),
          renditionId: Value(rendition.id),
          renditionKind: Value(rendition.kind),
          isPrimary: Value(rendition.isPrimary),
          renditionCreatedAt: Value(rendition.createdAt),
          processedOriginal: Value(encodeTrashedProcessedOriginal(original)),
          trashedAt: at,
        ),
      );
  // Con la forma se va su fila de `processed_originals`, en cascada.
  await (db.delete(
    db.renditions,
  )..where((r) => r.id.equals(rendition.id))).go();
  return id;
}

/// Vuelve a poner como el original de su documento lo que [row] guardó con
/// [trashProcessedOriginal], y la saca de la papelera. Devuelve `false`, sin
/// tocar nada, si el documento ya tiene otro original o ya no existe. Corre
/// dentro de la transacción de quien llama.
Future<bool> restoreTrashedProcessedOriginal(
  AppDatabase db,
  TrashedContentRow row,
) async {
  final stored = row.processedOriginal;
  if (stored == null) return false;
  final document = await (db.select(
    db.processedDocuments,
  )..where((d) => d.itemId.equals(row.itemId))).getSingleOrNull();
  final taken = await (db.select(
    db.processedOriginals,
  )..where((o) => o.documentId.equals(row.itemId))).getSingleOrNull();
  final renditionTaken = await (db.select(
    db.renditions,
  )..where((r) => r.id.equals(row.renditionId!))).getSingleOrNull();
  if (document == null || taken != null || renditionTaken != null) {
    return false;
  }
  final data = jsonDecode(stored) as Map<String, dynamic>;
  await db
      .into(db.renditions)
      .insert(
        RenditionsCompanion.insert(
          id: row.renditionId!,
          itemId: row.itemId,
          kind: row.renditionKind!,
          relativePath: Value(row.relativePath),
          isPrimary: row.isPrimary ?? false,
          sizeBytes: Value(row.sizeBytes),
          createdAt: row.renditionCreatedAt!,
        ),
      );
  await db
      .into(db.processedOriginals)
      .insert(
        ProcessedOriginalsCompanion.insert(
          documentId: row.itemId,
          renditionId: row.renditionId!,
          sourceFilePath: data['sourceFilePath'] as String,
          sourceFileSize: data['sourceFileSize'] as int,
          textHash: Value(data['textHash'] as String?),
          copiedAt: DateTime.fromMillisecondsSinceEpoch(
            data['copiedAt'] as int,
          ),
        ),
      );
  await (db.delete(db.trashedContents)..where((t) => t.id.equals(row.id))).go();
  return true;
}
