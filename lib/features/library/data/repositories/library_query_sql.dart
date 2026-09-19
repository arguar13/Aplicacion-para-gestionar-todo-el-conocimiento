import 'package:drift/drift.dart';
import 'package:sinapsis/core/database/search_index.dart';
import 'package:sinapsis/features/library/domain/entities/library_query.dart';

/// El SQL de una [LibraryQuery]: qué elementos entran, en qué orden y cuáles
/// de ellos, página por página.
///
/// Está escrito a mano y no con el constructor de consultas de Drift porque la
/// búsqueda de texto entra por una tabla virtual FTS5 que Drift no conoce, y
/// hace falta UNIRLA con el resto: solo así el orden por relevancia y la
/// paginación los resuelve SQLite. La versión anterior traía a Dart todos los
/// resultados del índice, armaba una consulta con un parámetro por cada uno y
/// recién después paginaba: con una palabra común en 10.000 elementos eran
/// 700 ms para mostrar cincuenta filas, y el costo crecía con la cantidad de
/// coincidencias y no con el tamaño de la página.
///
/// Un único lugar arma los filtros —tipo de fuente, estado, espacio,
/// etiquetas, propiedades— para las tres preguntas que se le hacen a una
/// consulta (los ids de una página, los ids de todo lo que coincide y cuántos
/// son), de modo que no puedan discrepar.
class LibraryQuerySql {
  LibraryQuerySql(this.query) {
    final match = query.hasSearchText
        ? buildSearchQuery(query.searchText!)
        : null;
    // Un texto que no deja ninguna palabra que buscar (solo comillas, por
    // ejemplo) no encuentra nada: no es "sin filtro de texto".
    matchesNothing = match != null && match.isEmpty;

    if (match != null && match.isNotEmpty) {
      _from = _textFrom;
      _where.add('item_search MATCH ?');
      _args.add(Variable.withString(match));
    } else {
      _from = _plainFrom;
    }

    if (query.sourceKinds.isNotEmpty) {
      _where.add('sources.kind IN (${_marks(query.sourceKinds.length)})');
      _args.addAll(query.sourceKinds.map((k) => Variable.withString(k.name)));
    }
    if (query.processingStates.isNotEmpty) {
      _where.add(
        'items.processing_state IN (${_marks(query.processingStates.length)})',
      );
      _args.addAll(
        query.processingStates.map((s) => Variable.withString(s.name)),
      );
    }
    if (query.spaceId != null) {
      _where.add('items.space_id = ?');
      _args.add(Variable.withString(query.spaceId!));
    }
    // Subconsulta en vez de un join: con un join, un elemento que tiene tres
    // de los valores buscados aparecería tres veces en el resultado.
    for (final valueIds in [query.tagIds, query.propertyValueIds]) {
      if (valueIds.isEmpty) continue;
      _where.add(
        'items.id IN (SELECT item_id FROM item_property_values '
        'WHERE property_value_id IN (${_marks(valueIds.length)}))',
      );
      _args.addAll(valueIds.map(Variable.withString));
    }

    _orderBy = _orderingFor(query, ranked: match != null && match.isNotEmpty);
  }

  final LibraryQuery query;

  /// `true` si hay un texto que buscar pero no queda ninguna palabra en él: el
  /// resultado es vacío sin necesidad de preguntarle nada a la base.
  late final bool matchesNothing;

  static const _plainFrom =
      'items JOIN sources ON sources.id = items.source_id';
  static const _textFrom =
      'item_search '
      'JOIN items ON items.id = item_search.item_id '
      'JOIN sources ON sources.id = items.source_id';

  late final String _from;
  late final String _orderBy;
  final List<String> _where = [];
  final List<Variable<Object>> _args = [];

  String get _whereClause =>
      _where.isEmpty ? '' : ' WHERE ${_where.join(' AND ')}';

  /// Los ids de la página que pide [query] —o de todo lo que coincide, si no
  /// trae límite—, en el orden que pide.
  ({String sql, List<Variable<Object>> variables}) ids() {
    final sql = StringBuffer('SELECT items.id AS id FROM $_from')
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

  /// Cuántos elementos coinciden, sin paginar: "hay 340 resultados" es el
  /// total, no lo que entró en la página actual.
  ({String sql, List<Variable<Object>> variables}) count() => (
    sql: 'SELECT COUNT(*) AS n FROM $_from$_whereClause',
    variables: [..._args],
  );

  static String _marks(int count) => List.filled(count, '?').join(', ');

  /// Con orden por relevancia el criterio lo pone FTS5, que expone una
  /// columna `rank` en la propia tabla virtual. Sin texto buscado no hay
  /// relevancia que medir y se cae en el orden por fecha de captura.
  static String _orderingFor(LibraryQuery query, {required bool ranked}) {
    final direction = query.descending ? 'DESC' : 'ASC';
    return switch (query.sortBy) {
      LibrarySort.relevance when ranked => 'item_search.rank',
      LibrarySort.relevance ||
      LibrarySort.capturedAt => 'sources.captured_at $direction',
      LibrarySort.publishedAt => 'sources.published_at $direction',
      LibrarySort.updatedAt => 'items.updated_at $direction',
      LibrarySort.title => 'items.title $direction',
    };
  }
}
