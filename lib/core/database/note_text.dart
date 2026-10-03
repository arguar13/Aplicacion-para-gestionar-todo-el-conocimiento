import 'package:drift/drift.dart';
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/domain/entities/rendition.dart';

/// El texto de la nota [itemId] tal como lo lee la persona (F27): el de cada
/// una de sus formas de texto —los bloques, decodificados—, de la primera que
/// se guardó a la última. `null` si no tiene ninguna.
///
/// Es lo que describen los vectores de una nota (`note_embedding`): el mismo
/// texto lo calcula quien los guarda y quien muestra su comienzo, sin cargar
/// el elemento entero. Lee por clave: quien lo llama ya decidió qué elementos
/// cuentan.
Future<String?> noteTextOf(AppDatabase db, String itemId) async {
  final rows =
      await (db.select(db.renditions)
            ..where((r) => r.itemId.equals(itemId) & r.content.isNotNull())
            ..orderBy([
              (r) => OrderingTerm.asc(r.createdAt),
              (r) => OrderingTerm.asc(r.id),
            ]))
          .get();
  if (rows.isEmpty) return null;
  return [
    for (final row in rows)
      Rendition.text(
        id: row.id,
        itemId: row.itemId,
        kind: row.kind,
        content: row.content!,
        isPrimary: row.isPrimary,
        createdAt: row.createdAt,
      ).searchableText,
  ].whereType<String>().join('\n\n');
}
