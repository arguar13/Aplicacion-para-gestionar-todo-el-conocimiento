import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/database/knowledge_source_chunking.dart';
import 'package:sinapsis/core/logging/app_logger.dart';
import 'package:sinapsis/core/util/id_generator.dart';

/// Qué hará el backfill de v16, calculado SIN escribir nada: el dry-run.
///
/// v16 completa dos cosas que la versión anterior dejó a medias:
///
/// - Los chunks de toda fuente que no los tiene. El backfill histórico de F1
///   solo cubrió lo capturado antes de v8, y el de F5 (v12) lo capturado hasta
///   entonces: todo lo que entró desde v12 quedó sin fragmentar, porque
///   `LibraryRepositoryImpl.save()` no los escribía. Sin chunks no hay
///   búsqueda por chunks: F10 la pone ahí, y esta migración es lo que hace que
///   ninguna fuente quede afuera.
/// - El texto libre de un elemento (`Items.notes`), que pasa a `item.notes`
///   porque `Items` se retira.
class ChunkBackfillPlan {
  const ChunkBackfillPlan({
    required this.sourcesTotal,
    required this.toChunk,
    required this.withoutText,
    required this.alreadyChunked,
    required this.notesToCopy,
  });

  /// Cuántas filas de `source` hay.
  final int sourcesTotal;

  /// Fuentes con una forma de texto y sin fragmentar: las que este paso
  /// trabaja.
  final List<String> toChunk;

  /// Fuentes sin ninguna forma de texto todavía —un archivo sin procesar, o
  /// cuyo procesamiento falló—. No hay nada que fragmentar; cuando el texto
  /// llegue, `save()` lo fragmenta.
  final List<String> withoutText;

  /// Fuentes que ya tenían sus chunks: no se tocan.
  final int alreadyChunked;

  /// Elementos con texto libre en `Items.notes` que todavía no está en
  /// `item.notes`.
  final int notesToCopy;

  bool get hasWork => toChunk.isNotEmpty || notesToCopy > 0;

  String summary() =>
      'Chunks: $sourcesTotal fuentes; ${toChunk.length} por fragmentar, '
      '$alreadyChunked ya fragmentadas, ${withoutText.length} sin texto '
      'todavía. Notas libres por copiar a item: $notesToCopy.';
}

/// Calcula qué haría [backfillChunksAndNotes], sin escribir NADA.
Future<ChunkBackfillPlan> planChunkBackfill(AppDatabase db) async {
  final sources = await db
      .customSelect(
        'SELECT s.item_id AS item_id, s.content_hash AS content_hash, '
        '  EXISTS (SELECT 1 FROM renditions r '
        '           WHERE r.item_id = s.item_id AND r.content IS NOT NULL) '
        '  AS has_text '
        'FROM source s ORDER BY s.item_id',
      )
      .get();

  final toChunk = <String>[];
  final withoutText = <String>[];
  var alreadyChunked = 0;
  for (final row in sources) {
    final itemId = row.read<String>('item_id');
    if (row.read<String>('content_hash').isNotEmpty) {
      alreadyChunked++;
    } else if (row.read<bool>('has_text')) {
      toChunk.add(itemId);
    } else {
      withoutText.add(itemId);
    }
  }

  final notes = await db
      .customSelect(
        'SELECT COUNT(*) AS n FROM items i JOIN item e ON e.id = i.id '
        'WHERE i.notes IS NOT NULL AND e.notes IS NULL',
      )
      .getSingle();

  return ChunkBackfillPlan(
    sourcesTotal: sources.length,
    toChunk: toChunk,
    withoutText: withoutText,
    alreadyChunked: alreadyChunked,
    notesToCopy: notes.read<int>('n'),
  );
}

/// El paso completo de la migración v16: calcula el plan, lo informa y lo
/// aplica —fragmenta cada fuente y copia el texto libre—.
///
/// Fragmentar una fuente reutiliza `chunkAndPersistSource`, el mismo camino
/// que el resto de la app: si el texto no se reconstruye exacto a partir de sus
/// chunks, esa fuente no se toca y queda en `MigrationIssues`, y se sigue con
/// la próxima. Nunca se pierde ni se reescribe el texto de una fuente.
///
/// Idempotente: una segunda corrida no encuentra nada por hacer.
Future<ChunkBackfillPlan> backfillChunksAndNotes(
  AppDatabase db, {
  required IdGenerator ids,
  required AppLogger logger,
}) async {
  final plan = await planChunkBackfill(db);
  if (!plan.hasWork) return plan;

  logger.info(plan.summary());

  for (final itemId in plan.toChunk) {
    await chunkAndPersistSource(
      db,
      itemId: itemId,
      ids: ids,
      reportedBy: 'f10_chunks_v16',
    );
  }

  await db.customStatement(
    'UPDATE item '
    'SET notes = (SELECT i.notes FROM items i WHERE i.id = item.id) '
    'WHERE notes IS NULL AND EXISTS ('
    '  SELECT 1 FROM items i WHERE i.id = item.id AND i.notes IS NOT NULL)',
  );

  // Las fuentes que no se pudieron fragmentar ya quedaron en MigrationIssues;
  // acá se deja constancia de cuántas fueron.
  final chunked = await db
      .customSelect("SELECT COUNT(*) AS n FROM source WHERE content_hash <> ''")
      .getSingle();
  final failed =
      plan.toChunk.length - (chunked.read<int>('n') - plan.alreadyChunked);
  if (failed > 0) {
    logger.warning(
      '$failed fuentes no se pudieron fragmentar; están en MigrationIssues '
      'y su texto no se tocó.',
    );
  }
  return plan;
}
