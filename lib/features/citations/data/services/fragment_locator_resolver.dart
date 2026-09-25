import 'package:drift/drift.dart';
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/database/knowledge_source_chunking.dart';
import 'package:sinapsis/core/util/format_clock.dart';
import 'package:sinapsis/features/citations/domain/entities/citation_source.dart';

/// Dónde de una fuente está un pasaje (F15): la página de un PDF o el minuto de
/// un video o un audio, para citarlo.
///
/// Lo dice el fragmento —el chunk— que contiene el pasaje: cada chunk sabe su
/// página o su minuto. Sirve para un resaltado, que guarda dónde empieza dentro
/// del texto de la fuente, y no para una nota atómica, que ya trae su página o
/// su minuto.
class FragmentLocatorResolver {
  const FragmentLocatorResolver(this._db);

  final AppDatabase _db;

  /// La página o el minuto del pasaje que empieza en [charOffset] del texto de
  /// la forma [renditionId] de [itemId], o `null` si no se sabe.
  ///
  /// Solo vale para la forma de texto principal de la fuente: los chunks salen
  /// de ella, y las posiciones de otra forma —un resumen, una transcripción
  /// rehecha— no significan nada en esos chunks.
  Future<CitationLocator?> locate({
    required String itemId,
    required String renditionId,
    required int charOffset,
  }) async {
    final main = await sourceTextRendition(_db, itemId);
    if (main == null || main.id != renditionId) return null;

    final chunk =
        await (_db.select(_db.chunks)
              ..where(
                (c) =>
                    c.itemId.equals(itemId) &
                    c.charStart.isSmallerOrEqualValue(charOffset) &
                    c.charEnd.isBiggerThanValue(charOffset),
              )
              ..limit(1))
            .getSingleOrNull();
    if (chunk == null) return null;
    return _locatorOf(chunk);
  }

  /// El locator de un lote de pasajes a la vez, cada uno con su propia
  /// `key` para el resultado —un mismo `itemId` puede repetirse con
  /// `charOffset` distintos, dos tarjetas citando la misma fuente—. Para
  /// exportar en masa (Anki, F17): una consulta por tarjeta no entra en el
  /// objetivo de rendimiento.
  ///
  /// A diferencia de [locate], no pide `renditionId`: los chunks de un
  /// elemento salen siempre de su única forma de texto principal —ver
  /// [sourceTextRendition]—, así que el `itemId` solo ya alcanza para saber
  /// de qué forma son.
  Future<Map<String, CitationLocator>> locateMany(
    List<({String key, String itemId, int charOffset})> requests,
  ) async {
    if (requests.isEmpty) return const {};

    final itemIds = {for (final request in requests) request.itemId};
    final rows = await (_db.select(
      _db.chunks,
    )..where((c) => c.itemId.isIn(itemIds))).get();

    final chunksByItem = <String, List<ChunkRow>>{};
    for (final row in rows) {
      (chunksByItem[row.itemId] ??= []).add(row);
    }

    final result = <String, CitationLocator>{};
    for (final request in requests) {
      final chunks = chunksByItem[request.itemId];
      if (chunks == null) continue;
      for (final chunk in chunks) {
        if (chunk.charStart <= request.charOffset &&
            request.charOffset < chunk.charEnd) {
          final locator = _locatorOf(chunk);
          if (locator != null) result[request.key] = locator;
          break;
        }
      }
    }
    return result;
  }

  CitationLocator? _locatorOf(ChunkRow chunk) {
    final page = chunk.pageNumber;
    if (page != null) return CitationLocator.page('$page');
    final startMs = chunk.startMs;
    if (startMs != null) return CitationLocator.time(formatClock(startMs));
    return null;
  }
}
