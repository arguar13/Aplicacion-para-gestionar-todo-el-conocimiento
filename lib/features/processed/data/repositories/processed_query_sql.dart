import 'package:drift/drift.dart';
import 'package:sinapsis/core/database/active_entries.dart';
import 'package:sinapsis/core/database/search_index.dart';
import 'package:sinapsis/features/processed/domain/entities/processed_query.dart';

/// El SQL de una [ProcessedQuery] (F41): qué documentos procesados entran, en
/// qué orden y cuáles de ellos.
///
/// Escrito a mano por lo mismo que `LibraryQuerySql`: el texto se busca en dos
/// índices FTS5 que drift no conoce —`item_search`, por el título, y
/// `processed_part_search`, por el texto de cada parte— y hay que unirlos con
/// el resto. Cada palabra buscada tiene que estar en el documento, en su título
/// o en cualquiera de sus partes: un documento por palabra, y la intersección
/// de todas. Así «kuhn paradigma» encuentra el libro que nombra a Kuhn en una
/// página y habla del paradigma diez páginas después.
///
/// Lo que está en la papelera no entra nunca.
class ProcessedQuerySql {
  ProcessedQuerySql(this.query) {
    _where.add(kActiveItemSql);
    if (query.hasSearchText) {
      final terms = searchTerms(query.searchText!);
      if (terms.isEmpty) {
        _where.add('0');
      } else {
        final everyTerm = List.filled(terms.length, _documentsWithTerm);
        _where.add('item.id IN (${everyTerm.join(' INTERSECT ')})');
        for (final term in terms) {
          _args
            ..add(Variable.withString(term.match))
            ..add(Variable.withString(term.match));
        }
      }
    }
    if (query.spaceId case final spaceId?) {
      _where.add(
        'EXISTS (SELECT 1 FROM item_spaces s '
        'WHERE s.item_id = item.id AND s.space_id = ?)',
      );
      _args.add(Variable.withString(spaceId));
    }
    if (query.sourceKinds.isNotEmpty) {
      _where.add('pd.source_kind IN (${_marks(query.sourceKinds.length)})');
      _args.addAll(query.sourceKinds.map((k) => Variable.withString(k.name)));
    }
    // Qué partes tiene: cualquiera de las secciones pedidas, o la copia del
    // original (decisión H).
    final inSections =
        'EXISTS (SELECT 1 FROM processed_parts ps '
        'WHERE ps.document_id = item.id '
        'AND ps.section IN (${_marks(query.sections.length)}))';
    const withOriginal =
        'EXISTS (SELECT 1 FROM processed_originals po '
        'WHERE po.document_id = item.id)';
    final has = [
      if (query.sections.isNotEmpty) inSections,
      if (query.withOriginal) withOriginal,
    ];
    if (has.isNotEmpty) {
      _where.add('(${has.join(' OR ')})');
      _args.addAll(query.sections.map((s) => Variable.withString(s.name)));
    }
    final ids = query.ids;
    if (ids != null) {
      if (ids.isEmpty) {
        _where.add('0');
      } else {
        _where.add('item.id IN (${_marks(ids.length)})');
        _args.addAll(ids.map(Variable.withString));
      }
    }
  }

  final ProcessedQuery query;

  final List<String> _where = [];
  final List<Variable<Object>> _args = [];

  /// Los documentos que tienen UNA palabra —dos parámetros: la palabra para el
  /// título y para las partes—, vivos o no: lo vivo lo decide el `WHERE`.
  ///
  /// Envuelta en su propio `SELECT … FROM (…)` a propósito: en SQLite `UNION` e
  /// `INTERSECT` tienen la misma precedencia y se asocian a la izquierda, así
  /// que sin envolverla `A UNION B INTERSECT C UNION D` sería
  /// `((A UNION B) INTERSECT C) UNION D`.
  static const _documentsWithTerm =
      'SELECT doc FROM ( '
      'SELECT item_search.item_id AS doc FROM item_search '
      'WHERE item_search MATCH ? '
      'UNION SELECT pp.document_id AS doc FROM processed_part_search '
      'JOIN processed_parts pp ON pp.row_key = processed_part_search.rowid '
      'WHERE processed_part_search MATCH ?)';

  static const _from =
      'processed_documents pd JOIN item ON item.id = pd.item_id';

  String get _whereClause => ' WHERE ${_where.join(' AND ')}';

  String get _orderBy {
    final direction = query.descending ? 'DESC' : 'ASC';
    final column = switch (query.sortBy) {
      ProcessedSort.updatedAt => 'item.updated_at',
      ProcessedSort.createdAt => 'item.created_at',
      ProcessedSort.title => 'item.title',
    };
    return '$column $direction, item.id $direction';
  }

  /// Los ids de la página —o de todo, sin límite—, en orden.
  ({String sql, List<Variable<Object>> variables}) ids() {
    final sql = StringBuffer('SELECT item.id AS id FROM $_from')
      ..write(_whereClause)
      ..write(' ORDER BY $_orderBy');
    final variables = [..._args];
    final limit = query.limit;
    if (limit != null) {
      sql.write(' LIMIT ? OFFSET ?');
      variables
        ..add(Variable.withInt(limit))
        ..add(Variable.withInt(query.offset));
    }
    return (sql: sql.toString(), variables: variables);
  }

  /// Cuántos documentos cumplen la consulta, sin paginar.
  ({String sql, List<Variable<Object>> variables}) count() => (
    sql: 'SELECT COUNT(*) AS n FROM $_from$_whereClause',
    variables: [..._args],
  );

  static String _marks(int count) => List.filled(count, '?').join(', ');
}
