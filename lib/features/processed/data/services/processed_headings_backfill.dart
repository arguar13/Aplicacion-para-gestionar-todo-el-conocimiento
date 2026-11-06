import 'dart:async';

import 'package:drift/drift.dart';
import 'package:meta/meta.dart';
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/database/processed_heading_triggers.dart';
import 'package:sinapsis/core/database/search_index.dart';
import 'package:sinapsis/features/processed/data/services/processed_headings_indexer.dart';
import 'package:sinapsis/features/processed/domain/services/processed_image_title.dart';

/// Lo que hizo una pasada de [ProcessedHeadingsBackfill.run].
@immutable
class HeadingsBackfillReport {
  const HeadingsBackfillReport({
    this.documentsIndexed = 0,
    this.documentsSkipped = 0,
    this.imagesTitled = 0,
  });

  /// Los documentos que quedaron indexados.
  final int documentsIndexed;

  /// Los que no se pudieron indexar —el lector falló, o su PDF no se pudo
  /// leer—: quedan para la próxima vez que se abra la app.
  final int documentsSkipped;

  /// Las imágenes que recibieron su título.
  final int imagesTitled;

  @override
  String toString() =>
      'HeadingsBackfillReport(indexados: $documentsIndexed, salteados: '
      '$documentsSkipped, imágenes: $imagesTitled)';
}

/// El relleno del Índice (F46, paso 2, decisión F): indexa lo que está «sin
/// indexar» —lo que ya estaba procesado al actualizar la app, lo que trajo la
/// unión de bóvedas o la papelera del contenido— y titula las imágenes que
/// todavía no tienen título.
///
/// - **Por tandas y en segundo plano**: un documento por transacción —su PDF
///   se lee antes, afuera—, y entre uno y otro le devuelve el turno a la
///   interfaz. Las imágenes, de a [imagesPerBatch] por transacción.
/// - **Con su punto de retome en la base misma**: lo que falta es lo que la
///   base dice que falta —un documento con texto y sin entradas de texto, una
///   imagen sin titular—, así que si la app se cierra a mitad de camino, la
///   próxima vez sigue desde ahí, sin un cursor aparte que pueda mentir (una
///   copia de la bóveda restaurada, una unión). Lo que ya se hizo no se vuelve
///   a hacer: es idempotente.
/// - **Se puede borrar y rehacer entero** ([rebuildAll]): el Índice es
///   derivado. De la Biblioteca no toca nada.
///
/// Un documento que no se pudo indexar se deja de intentar en este relleno
/// —en la app, hasta la próxima vez que se abra—: si falla siempre con él, no
/// se lo reintenta en una vuelta sin fin.
class ProcessedHeadingsBackfill {
  ProcessedHeadingsBackfill({
    required AppDatabase database,
    required ProcessedHeadingsIndexer indexer,
    this.documentsPerRead = 16,
    this.imagesPerBatch = 200,
  }) : _db = database,
       _indexer = indexer;

  final AppDatabase _db;
  final ProcessedHeadingsIndexer _indexer;

  /// Cuántos documentos sin indexar se leen de una vez. Cada uno se indexa en
  /// su propia transacción.
  final int documentsPerRead;

  /// Cuántas imágenes se titulan por transacción.
  final int imagesPerBatch;

  /// Los documentos que no se pudieron indexar en este relleno.
  final _skipped = <String>{};

  /// La pasada en curso: dos pedidos a la vez comparten la misma.
  Future<HeadingsBackfillReport>? _running;

  /// Si queda algo para hacer, sin contar lo que ya se salteó en este relleno.
  Future<bool> hasPendingWork() async {
    final row = await _db
        .customSelect(
          headingsPendingWorkSql,
          readsFrom: {
            _db.processedDocuments,
            _db.processedParts,
            _db.processedHeadings,
            _db.processedImages,
          },
        )
        .getSingle();
    if (!row.read<bool>('pending')) return false;
    if (_skipped.isEmpty) return true;
    return (await _untitledImages(1)).isNotEmpty ||
        (await _pendingDocuments()).isNotEmpty;
  }

  /// Hace todo lo que falta: primero las imágenes —son rápidas—, después los
  /// documentos, los vivos y los más recientes primero. Con [shouldStop] se
  /// corta entre un documento y el siguiente, y lo hecho queda hecho.
  Future<HeadingsBackfillReport> run({bool Function()? shouldStop}) =>
      _running ??= _run(
        shouldStop ?? () => false,
      ).whenComplete(() => _running = null);

  Future<HeadingsBackfillReport> _run(bool Function() shouldStop) async {
    var titled = 0;
    var indexed = 0;
    var skipped = 0;
    HeadingsBackfillReport report() => HeadingsBackfillReport(
      documentsIndexed: indexed,
      documentsSkipped: skipped,
      imagesTitled: titled,
    );

    while (!shouldStop()) {
      final batch = await _titleImages();
      if (batch == 0) break;
      titled += batch;
      await _yield();
    }
    while (!shouldStop()) {
      final pending = await _pendingDocuments();
      if (pending.isEmpty) break;
      for (final documentId in pending) {
        if (shouldStop()) return report();
        await _indexer.prepare(documentId);
        switch (await _indexer.refresh(documentId)) {
          case HeadingsRefresh.indexed:
            indexed++;
          case HeadingsRefresh.failed || HeadingsRefresh.deferred:
            skipped++;
            _skipped.add(documentId);
          case HeadingsRefresh.noText || HeadingsRefresh.upToDate:
            // Lo resolvió otro mientras tanto: el repositorio al guardar.
            break;
        }
        await _yield();
      }
    }
    return report();
  }

  /// Borra el Índice entero y lo deja para rehacer (decisión F): las entradas
  /// de las imágenes se vuelven a escribir en el acto —salen de sus títulos—,
  /// y los documentos quedan todos sin indexar para la próxima pasada de
  /// [run]. Lo que se había salteado se vuelve a intentar.
  Future<void> rebuildAll() async {
    await _db.transaction(() async {
      await _db.customStatement('DELETE FROM processed_headings');
      await _db.customStatement(rebuildProcessedHeadingSearch);
      await _db.customStatement(populateProcessedImageHeadings);
    });
    _db.markTablesUpdated([_db.processedHeadings]);
    _skipped.clear();
  }

  /// Los documentos sin indexar que siguen, sin los salteados.
  Future<List<String>> _pendingDocuments() async {
    final rows = await _db
        .customSelect(
          headingsPendingDocumentsSql,
          variables: [Variable.withInt(documentsPerRead + _skipped.length)],
          readsFrom: {
            _db.processedDocuments,
            _db.knowledgeEntries,
            _db.processedParts,
            _db.processedHeadings,
          },
        )
        .get();
    return [
      for (final row in rows)
        if (!_skipped.contains(row.read<String>('id'))) row.read<String>('id'),
    ].take(documentsPerRead).toList();
  }

  Future<List<({String id, String file, String? alt})>> _untitledImages(
    int limit,
  ) async => [
    for (final row
        in await _db
            .customSelect(
              untitledProcessedImagesSql,
              variables: [Variable.withInt(limit)],
              readsFrom: {_db.processedImages, _db.renditions},
            )
            .get())
      (
        id: row.read<String>('id'),
        file: row.read<String>('file'),
        alt: row.read<String?>('alt'),
      ),
  ];

  /// Titula la tanda siguiente de imágenes sin titular —lo que dice de cada
  /// una la fuente, o el nombre de su archivo, limpio; vacío si ninguno dice
  /// nada— y devuelve cuántas tituló: ninguna, si no queda ninguna. Leerlas y
  /// titularlas es una transacción: una que mientras tanto se renombra no se
  /// pisa.
  Future<int> _titleImages() => _db.transaction(() async {
    final images = await _untitledImages(imagesPerBatch);
    for (final image in images) {
      final title =
          processedImageTitle(
            ImageTitleClues(alt: image.alt, fileName: image.file),
          ) ??
          '';
      await (_db.update(_db.processedImages)
            ..where((i) => i.renditionId.equals(image.id)))
          .write(ProcessedImagesCompanion(title: Value(title)));
    }
    return images.length;
  });

  /// Le devuelve el turno a la interfaz entre una tanda y la siguiente.
  static Future<void> _yield() => Future<void>.delayed(Duration.zero);
}

/// Que el documento procesado `d` tenga la sección «Texto»: una búsqueda por
/// `idx_processed_parts_document`.
const _hasTextSql =
    'EXISTS (SELECT 1 FROM processed_parts tp '
    "WHERE tp.document_id = d.item_id AND tp.section = 'text')";

/// Que las entradas de texto del documento `d` estén escritas: una búsqueda
/// por `idx_processed_headings_document`.
const _indexedSql =
    'EXISTS (SELECT 1 FROM processed_headings ih '
    "WHERE ih.document_id = d.item_id AND ih.origin <> 'image')";

/// Los documentos sin indexar —con texto y sin sus entradas de texto—, vivos
/// o en la papelera (uno que vuelve tiene que estar listo), los vivos y los
/// que llegaron más recientemente primero —lo que la persona va a buscar
/// primero—, como mucho `?1`.
const headingsPendingDocumentsSql =
    '''
SELECT d.item_id AS id
FROM processed_documents d
CROSS JOIN item ON item.id = d.item_id
WHERE $_hasTextSql AND NOT $_indexedSql
ORDER BY item.deleted_at IS NOT NULL, d.created_at DESC, d.item_id
LIMIT ?1
''';

/// Si queda algo para el relleno: un documento sin indexar o una imagen sin
/// titular —por su índice parcial—.
const headingsPendingWorkSql =
    '''
SELECT EXISTS (
         SELECT 1 FROM processed_documents d
          WHERE $_hasTextSql AND NOT $_indexedSql)
    OR EXISTS (SELECT 1 FROM processed_images ui WHERE ui.title IS NULL)
       AS pending
''';

/// Las imágenes sin titular —por su índice parcial—, con lo que hace falta
/// para titularlas: el archivo de la fuente y el nombre con que se ofrecía
/// (el de su forma, el texto alternativo), como mucho `?1`.
const untitledProcessedImagesSql = '''
SELECT ui.rendition_id AS id,
       ui.source_file_path AS file,
       r.title AS alt
FROM processed_images ui
CROSS JOIN renditions r ON r.id = ui.rendition_id
WHERE ui.title IS NULL
ORDER BY ui.rendition_id
LIMIT ?1
''';
