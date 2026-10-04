import 'package:drift/drift.dart';
import 'package:sinapsis/core/database/active_entries.dart';
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/domain/entities/chat_source.dart';
import 'package:sinapsis/features/chat/domain/services/chat_passages.dart';
import 'package:sinapsis/features/chat/domain/services/vault_retriever.dart';

/// Cuántos fragmentos se piden al índice por cada fuente que se busca: el
/// mejor de cada elemento tiene que estar entre ellos, y un elemento largo
/// puede tener muchos buenos.
const _chunksPerSource = 6;

/// [VaultRetriever] que busca los PASAJES de la bóveda que hablan de lo
/// preguntado (F30), con una sola consulta a los dos índices de texto: el de
/// los fragmentos de las fuentes (`chunk_search`) y el de los títulos y las
/// notas (`item_search`).
///
/// Reemplaza a `LibraryVaultRetriever`, que hacía una búsqueda por cada
/// palabra de la pregunta —también «de» o «qué»—, en serie, armando cada
/// elemento entero —con libros enteros adentro— solo para citar sus
/// primeras 400 letras, casi nunca las que respondían la pregunta.
///
/// - **Las palabras**: las de la pregunta sin las vacías ([questionTerms]),
///   unidas con `OR`: un fragmento que tiene más de ellas, y las más raras de
///   la bóveda, sale antes (el `rank` de FTS5, BM25).
/// - **Lo que se trae**: el título y el fragmento, nada más.
/// - **El pasaje**: dentro del mejor fragmento de cada elemento, la ventana
///   que más palabras de la pregunta junta ([passageWindow]), con dónde
///   empieza y termina en el texto de la fuente —la cita apunta justo ahí—.
///   Una nota, que no se fragmenta, da su pasaje sin posición; una fuente
///   que coincide solo por el título, el principio de su texto.
/// - **Lo que entra**: como mucho [kChatMaxSources] fuentes de
///   [kChatPassageChars] caracteres.
class ChunkPassageRetriever implements VaultRetriever {
  const ChunkPassageRetriever({required AppDatabase database}) : _db = database;

  final AppDatabase _db;

  @override
  Future<List<ChatSource>> retrieve(
    String question, {
    int limit = kChatMaxSources,
    Set<String>? scopeIds,
  }) async {
    final terms = questionTerms(question);
    if (terms.isEmpty || limit <= 0) return const [];
    if (scopeIds != null && scopeIds.isEmpty) return const [];

    final match = terms
        .map((term) => '"${term.replaceAll('"', '""')}"*')
        .join(' OR ');
    final scope = scopeIds?.toList();
    // Los ids del alcance van numerados desde ?4: se usan dos veces.
    final scopeList = scope == null
        ? null
        : [for (var i = 0; i < scope.length; i++) '?${i + 4}'].join(', ');
    final chunksInScope = scopeList == null
        ? ''
        : 'AND chunk_search.rowid IN (SELECT sc.row_key FROM chunks sc '
              'WHERE sc.item_id IN ($scopeList)) ';
    final itemsInScope = scopeList == null
        ? ''
        : 'AND item_search.item_id IN ($scopeList) ';

    final rows = await _db
        .customSelect(
          'SELECT item_id, title, content, char_start, score, whole FROM ( '
          // Los mejores fragmentos: el corte se hace sobre el índice solo,
          // sin lo de la papelera ni lo de fuera del alcance.
          'SELECT c.item_id AS item_id, i.title AS title, '
          'c.content AS content, c.char_start AS char_start, '
          'top.s AS score, 0 AS whole FROM ( '
          'SELECT chunk_search.rowid AS rid, chunk_search.rank AS s '
          'FROM chunk_search WHERE chunk_search MATCH ?1 '
          'AND $kChunkOutsideTrashSql '
          '$chunksInScope'
          'ORDER BY chunk_search.rank LIMIT ?2) top '
          'JOIN chunks c ON c.row_key = top.rid '
          'JOIN item i ON i.id = c.item_id '
          'UNION ALL '
          // Los títulos y las notas: de una nota, su texto; de una fuente
          // que coincide por el título, su primer fragmento.
          'SELECT i.id, i.title, '
          "CASE WHEN ts.body <> '' THEN ts.body ELSE COALESCE(( "
          'SELECT fc.content FROM chunks fc WHERE fc.item_id = i.id '
          "ORDER BY fc.seq LIMIT 1), i.subtitle, '') END, "
          "CASE WHEN ts.body <> '' THEN NULL ELSE ( "
          'SELECT fc.char_start FROM chunks fc WHERE fc.item_id = i.id '
          'ORDER BY fc.seq LIMIT 1) END, '
          'topi.s, 1 FROM ( '
          'SELECT item_search.rowid AS rid, item_search.rank AS s '
          'FROM item_search WHERE item_search MATCH ?1 '
          'AND item_search.item_id NOT IN ( '
          'SELECT ti.id FROM item ti WHERE ti.deleted_at IS NOT NULL) '
          '$itemsInScope'
          'ORDER BY item_search.rank LIMIT ?3) topi '
          'JOIN item_search ts ON ts.rowid = topi.rid '
          'JOIN item i ON i.id = ts.item_id) '
          'ORDER BY score',
          variables: [
            Variable.withString(match),
            Variable.withInt(limit * _chunksPerSource),
            Variable.withInt(limit * 2),
            for (final id in scope ?? const <String>[]) Variable.withString(id),
          ],
        )
        .get();

    // De cada elemento, su mejor fragmento; si solo coincidió por el título
    // o es una nota, lo que trajo el índice de elementos. En el orden del
    // mejor puntaje de cada uno.
    final order = <String>[];
    final best = <String, QueryRow>{};
    for (final row in rows) {
      final itemId = row.read<String>('item_id');
      final current = best[itemId];
      if (current == null) {
        order.add(itemId);
        best[itemId] = row;
      } else if (current.read<int>('whole') == 1 &&
          row.read<int>('whole') == 0) {
        best[itemId] = row;
      }
    }

    return [
      for (final itemId in order.take(limit))
        _sourceFrom(itemId, best[itemId]!, terms),
    ];
  }

  ChatSource _sourceFrom(String itemId, QueryRow row, List<String> terms) {
    final content = row.read<String>('content');
    final base = row.readNullable<int>('char_start');
    final window = passageWindow(content, terms);
    var start = window.start;
    var end = window.end;
    // Sin los espacios de las puntas, con la posición corrida a la par.
    while (start < end && _isSpace(content.codeUnitAt(start))) {
      start++;
    }
    while (end > start && _isSpace(content.codeUnitAt(end - 1))) {
      end--;
    }
    final passage = content.substring(start, end);
    return ChatSource(
      itemId: itemId,
      itemTitle: row.read<String>('title'),
      // Puntos suspensivos donde el pasaje corta el texto, no donde solo
      // quedaron espacios afuera.
      excerpt: [
        if (content.substring(0, start).trim().isNotEmpty) '…',
        passage,
        if (content.substring(end).trim().isNotEmpty) '…',
      ].join(),
      sourceCharStart: base == null ? null : base + start,
      sourceCharEnd: base == null ? null : base + end,
    );
  }

  static bool _isSpace(int unit) =>
      unit == 0x20 || unit == 0x0A || unit == 0x0D || unit == 0x09;
}
