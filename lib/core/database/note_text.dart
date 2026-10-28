import 'package:drift/drift.dart';
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/domain/entities/rendition.dart';
import 'package:sinapsis/core/domain/services/processed_reading.dart';

/// El texto de la nota [itemId] tal como lo lee la persona (F27): el de cada
/// una de sus formas de texto —los bloques, decodificados—, de la primera que
/// se guardó a la última. `null` si no tiene ninguna.
///
/// Un documento procesado (F41) no tiene formas: su texto son sus partes, lo
/// que la persona eligió al triar, armadas como las lee la IA
/// (`joinProcessedParts`). Así sus vectores describen eso y no la fuente, y
/// los vínculos que la IA le busca salen de lo elegido (paso 6). Con [upTo],
/// de un procesado se leen solo las partes hasta juntar esos caracteres —lo
/// justo para mostrar su comienzo—: el de un libro son cientos de páginas.
///
/// Es lo que describen los vectores de una nota (`note_embedding`): el mismo
/// texto lo calcula quien los guarda y quien muestra su comienzo, sin cargar
/// el elemento entero. Lee por clave: quien lo llama ya decidió qué elementos
/// cuentan.
Future<String?> noteTextOf(AppDatabase db, String itemId, {int? upTo}) async {
  final processed = await _processedTextOf(db, itemId, upTo: upTo);
  if (processed != null) return processed;
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

/// El texto de las partes del procesado [itemId], o `null` si no tiene
/// ninguna —no es un procesado, o se quedó sin partes—. Ver [noteTextOf].
///
/// Primero se pide el orden —sección, lugar, sin el texto— y después el texto
/// de cada parte, por su clave, hasta [upTo]: así mostrar el comienzo de un
/// libro procesado lee una página y no el libro.
Future<String?> _processedTextOf(
  AppDatabase db,
  String itemId, {
  int? upTo,
}) async {
  final p = db.processedParts;
  final heads =
      await (db.selectOnly(p)
            ..addColumns([p.id, p.section, p.position])
            ..where(p.documentId.equals(itemId)))
          .map(
            (row) => (
              id: row.read(p.id)!,
              section: row.readWithConverter(p.section)!,
              position: row.read(p.position)!,
            ),
          )
          .get();
  if (heads.isEmpty) return null;
  heads.sort((a, b) {
    final bySection = a.section.index.compareTo(b.section.index);
    if (bySection != 0) return bySection;
    final byPosition = a.position.compareTo(b.position);
    return byPosition != 0 ? byPosition : a.id.compareTo(b.id);
  });

  final Map<String, String> contents;
  if (upTo == null) {
    contents = {
      for (final row in await (db.select(
        p,
      )..where((part) => part.documentId.equals(itemId))).get())
        row.id: row.content,
    };
  } else {
    contents = {};
    var length = 0;
    for (final head in heads) {
      if (length >= upTo) break;
      final row = await (db.select(
        p,
      )..where((part) => part.id.equals(head.id))).getSingleOrNull();
      if (row == null) continue;
      contents[head.id] = row.content;
      length += row.content.length + kProcessedPartSeparator.length;
    }
  }
  return joinProcessedParts([
    for (final head in heads)
      if (contents[head.id] case final content?)
        (section: head.section, content: content),
  ]).text;
}
