import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/database/knowledge_source_chunking.dart';
import 'package:sinapsis/core/util/id_generator.dart';

/// Puebla `chunk`/`fullText`/`contentHash` de toda `KnowledgeSources`
/// que quedó vacía —F5, ver la decisión sobre el motor de relaciones en
/// docs/arquitectura.md.
///
/// El backfill histórico de F1 (`fragmentExistingSources`,
/// `fragment_existing_sources_v8.dart`) corrió una sola vez, y solo
/// cubrió lo capturado ANTES de esa migración. Todo lo capturado
/// después —prácticamente todo el uso real hoy— quedó con
/// `contentHash: ''`, preservado así a propósito por
/// `LibraryRepositoryImpl._mirrorItem` y `mirrorUnmirroredItems` (F3).
/// [chunkAndPersistSource] ya filtra por `contentHash.isNotEmpty` como
/// idempotencia, así que recorrer TODA la tabla acá es seguro: lo que
/// ya tiene texto fragmentado no se vuelve a tocar.
Future<void> backfillSourceChunks(
  AppDatabase db, {
  required IdGenerator ids,
}) async {
  final sources = await db.select(db.knowledgeSources).get();
  for (final source in sources) {
    await chunkAndPersistSource(
      db,
      itemId: source.itemId,
      ids: ids,
      reportedBy: 'f5_backfill_v12',
    );
  }
}
