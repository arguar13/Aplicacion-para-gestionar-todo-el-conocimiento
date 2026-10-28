import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/domain/entities/rendition_kind.dart';
import 'package:sinapsis/core/domain/entities/trashed_content_kind.dart';
import 'package:sinapsis/core/util/id_generator.dart';
import 'package:sinapsis/features/processed/domain/entities/processed_image.dart';
import 'package:sinapsis/features/processed/domain/services/processed_identity.dart';
import 'package:sinapsis/features/processed/domain/services/processed_images_planner.dart';

// Las imágenes de los documentos procesados en la base (F41, v47, decisión L):
// leerlas, guardar lo que planeó el caso de uso, quitarlas a la papelera del
// contenido y devolverlas. Todo lo que escribe corre dentro de la transacción
// de quien llama; ninguna toca el disco —las copias las hace y las borra el
// repositorio, afuera de la transacción—.

/// La subcarpeta de la del procesado donde viven las copias de sus imágenes:
/// `originales/<procesado>/imagenes/`.
const kProcessedImagesFolder = 'imagenes';

/// Las imágenes de [documentId], en orden; con [limit], solo ese tramo desde
/// [offset].
Future<List<ProcessedImage>> processedImagesOf(
  AppDatabase db,
  String documentId, {
  int offset = 0,
  int? limit,
}) async {
  final query =
      db.select(db.processedImages).join([
          innerJoin(
            db.renditions,
            db.renditions.id.equalsExp(db.processedImages.renditionId),
          ),
        ])
        ..where(db.processedImages.documentId.equals(documentId))
        ..orderBy([
          OrderingTerm.asc(db.processedImages.position),
          OrderingTerm.asc(db.processedImages.copiedAt),
          OrderingTerm.asc(db.processedImages.renditionId),
        ]);
  if (limit != null) query.limit(limit, offset: offset);
  return [
    for (final row in await query.get())
      processedImageFromRows(
        row.readTable(db.processedImages),
        row.readTable(db.renditions),
      ),
  ];
}

/// La imagen que guardan [row] y su forma [rendition].
ProcessedImage processedImageFromRows(
  ProcessedImageRow row,
  RenditionRow rendition,
) => ProcessedImage(
  renditionId: row.renditionId,
  documentId: row.documentId,
  position: row.position,
  relativePath: rendition.relativePath!,
  sizeBytes: rendition.sizeBytes ?? row.sourceFileSize,
  sourceFilePath: row.sourceFilePath,
  copiedAt: row.copiedAt,
  title: rendition.title,
  mimeType: rendition.mimeType,
);

/// Deja la galería de [documentId] como dice [plan]: las que se van, a la
/// papelera del contenido; las que se quedan, en su lugar; las nuevas —ya
/// copiadas en [staged], por la ruta de su archivo de la fuente— entran.
/// Devuelve cómo deshacerlo.
Future<ProcessedImagesUndo> applyProcessedImagesPlan(
  AppDatabase db, {
  required String documentId,
  required ImagesPlan plan,
  required Map<String, StagedImage> staged,
  required IdGenerator ids,
  required DateTime at,
}) async {
  final previous = await processedImagesOf(db, documentId);
  final trashed = <String>[];
  for (final image in plan.removed) {
    trashed.add(
      await trashProcessedImage(
        db,
        renditionId: image.renditionId,
        ids: ids,
        at: at,
      ),
    );
  }
  final created = <ProcessedImage>[];
  for (var position = 0; position < plan.images.length; position++) {
    switch (plan.images[position]) {
      case KeptImage(:final image) when image.position != position:
        await (db.update(db.processedImages)
              ..where((i) => i.renditionId.equals(image.renditionId)))
            .write(ProcessedImagesCompanion(position: Value(position)));
      case KeptImage():
        break;
      case NewImage(:final source):
        final copy = staged[source.path];
        if (copy == null) {
          throw StateError('La imagen ${source.path} no se copió.');
        }
        final image = ProcessedImage(
          renditionId: processedImageRenditionIdFor(documentId, source.path),
          documentId: documentId,
          position: position,
          relativePath: copy.relativePath,
          sizeBytes: copy.sizeBytes,
          sourceFilePath: source.path,
          copiedAt: at,
          title: source.title,
          mimeType: source.mimeType,
        );
        await _insert(db, image, sourceFileSize: source.sizeBytes);
        created.add(image);
    }
  }
  return ProcessedImagesUndo(
    previous: previous,
    created: created,
    trashed: trashed,
  );
}

/// Deshace [undo]: saca lo que entró, devuelve lo que se fue y deja cada una en
/// el lugar que tenía. Devuelve los archivos que entraron con él, para que
/// quien llama los borre del disco después de la transacción.
Future<List<String>> undoProcessedImages(
  AppDatabase db,
  ProcessedImagesUndo undo,
) async {
  final files = <String>[];
  for (final image in undo.created) {
    final deleted = await (db.delete(
      db.renditions,
    )..where((r) => r.id.equals(image.renditionId))).go();
    if (deleted > 0) files.add(image.relativePath);
  }
  for (final id in undo.trashed) {
    final row = await (db.select(
      db.trashedContents,
    )..where((t) => t.id.equals(id))).getSingleOrNull();
    if (row != null) await restoreTrashedProcessedImage(db, row, shift: false);
  }
  for (final image in undo.previous) {
    await (db.update(db.processedImages)
          ..where((i) => i.renditionId.equals(image.renditionId)))
        .write(ProcessedImagesCompanion(position: Value(image.position)));
  }
  return files;
}

/// Lo que guarda la papelera del contenido de una imagen de un procesado: lo
/// de su fila de `processed_images` y lo que su forma decía de ella, para que
/// al recuperarla vuelva a su galería tal como estaba.
String encodeTrashedProcessedImage(
  ProcessedImageRow row,
  RenditionRow rendition,
) => jsonEncode({
  'position': row.position,
  'sourceFilePath': row.sourceFilePath,
  'sourceFileSize': row.sourceFileSize,
  'copiedAt': row.copiedAt.millisecondsSinceEpoch,
  if (rendition.title != null) 'title': rendition.title,
  if (rendition.mimeType != null) 'mimeType': rendition.mimeType,
});

/// Manda a la papelera del contenido la imagen [renditionId] de su procesado
/// —la forma con su archivo y lo que decía de ella— y devuelve la fila de la
/// papelera. El archivo no se toca: se borra recién al vencer, como todo lo
/// soltado. No corre las que la seguían: eso es de quien llama.
Future<String> trashProcessedImage(
  AppDatabase db, {
  required String renditionId,
  required IdGenerator ids,
  required DateTime at,
}) async {
  final row = await (db.select(
    db.processedImages,
  )..where((i) => i.renditionId.equals(renditionId))).getSingle();
  final rendition = await (db.select(
    db.renditions,
  )..where((r) => r.id.equals(renditionId))).getSingle();
  final id = ids.next();
  await db
      .into(db.trashedContents)
      .insert(
        TrashedContentsCompanion.insert(
          id: id,
          itemId: row.documentId,
          kind: TrashedContentKind.file,
          relativePath: Value(rendition.relativePath),
          sizeBytes: Value(rendition.sizeBytes),
          renditionId: Value(rendition.id),
          renditionKind: Value(rendition.kind),
          isPrimary: Value(rendition.isPrimary),
          renditionCreatedAt: Value(rendition.createdAt),
          processedImage: Value(encodeTrashedProcessedImage(row, rendition)),
          trashedAt: at,
        ),
      );
  // Con la forma se va su fila de `processed_images`, en cascada.
  await (db.delete(db.renditions)..where((r) => r.id.equals(renditionId))).go();
  return id;
}

/// Vuelve a poner en su galería, en su lugar, la imagen que [row] guardó con
/// [trashProcessedImage], y la saca de la papelera. Con [shift], corre las que
/// están de ese lugar en adelante para hacerle lugar —recuperarla sola—; sin
/// él, quien llama deja cada una donde estaba —deshacer un procesado entero—.
///
/// Devuelve la imagen, o `null` sin tocar nada si el documento ya no existe o
/// ya tiene esa imagen.
Future<ProcessedImage?> restoreTrashedProcessedImage(
  AppDatabase db,
  TrashedContentRow row, {
  bool shift = true,
}) async {
  final stored = row.processedImage;
  final renditionId = row.renditionId;
  if (stored == null || renditionId == null) return null;
  final data = jsonDecode(stored) as Map<String, dynamic>;
  final sourceFilePath = data['sourceFilePath'] as String;
  final document = await (db.select(
    db.processedDocuments,
  )..where((d) => d.itemId.equals(row.itemId))).getSingleOrNull();
  // Si la forma ya está, el documento ya tiene esa imagen: su id sale del
  // documento y del archivo de la fuente (`processedImageRenditionIdFor`), así
  // que otra copia del mismo archivo es esta misma forma.
  final renditionTaken = await (db.select(
    db.renditions,
  )..where((r) => r.id.equals(renditionId))).getSingleOrNull();
  if (document == null || renditionTaken != null) return null;
  final image = ProcessedImage(
    renditionId: renditionId,
    documentId: row.itemId,
    position: data['position'] as int,
    relativePath: row.relativePath!,
    sizeBytes: row.sizeBytes ?? data['sourceFileSize'] as int,
    sourceFilePath: sourceFilePath,
    copiedAt: DateTime.fromMillisecondsSinceEpoch(data['copiedAt'] as int),
    title: data['title'] as String?,
    mimeType: data['mimeType'] as String?,
  );
  if (shift) await shiftProcessedImages(db, image, by: 1);
  await _insert(
    db,
    image,
    sourceFileSize: data['sourceFileSize'] as int,
    createdAt: row.renditionCreatedAt,
  );
  await (db.delete(db.trashedContents)..where((t) => t.id.equals(row.id))).go();
  return image;
}

/// Corre [by] lugares las imágenes del documento de [image] que van desde su
/// lugar en adelante: para cerrar el hueco de una que se va (`by: -1`, desde
/// la que la seguía), o abrírselo a una que vuelve (`by: 1`).
Future<void> shiftProcessedImages(
  AppDatabase db,
  ProcessedImage image, {
  required int by,
}) => db.customUpdate(
  'UPDATE processed_images SET position = position + ? '
  'WHERE document_id = ? AND position >= ?',
  variables: [
    Variable.withInt(by),
    Variable.withString(image.documentId),
    Variable.withInt(by < 0 ? image.position + 1 : image.position),
  ],
  updates: {db.processedImages},
);

Future<void> _insert(
  AppDatabase db,
  ProcessedImage image, {
  required int sourceFileSize,
  DateTime? createdAt,
}) async {
  await db
      .into(db.renditions)
      .insert(
        RenditionsCompanion.insert(
          id: image.renditionId,
          itemId: image.documentId,
          kind: RenditionKind.image,
          relativePath: Value(image.relativePath),
          isPrimary: false,
          createdAt: createdAt ?? image.copiedAt,
          title: Value(image.title),
          mimeType: Value(image.mimeType),
          sizeBytes: Value(image.sizeBytes),
        ),
      );
  await db
      .into(db.processedImages)
      .insert(
        ProcessedImagesCompanion.insert(
          renditionId: image.renditionId,
          documentId: image.documentId,
          position: image.position,
          sourceFilePath: image.sourceFilePath,
          sourceFileSize: sourceFileSize,
          copiedAt: image.copiedAt,
        ),
      );
}
