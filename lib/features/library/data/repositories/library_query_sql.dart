import 'package:drift/drift.dart';
import 'package:sinapsis/core/database/active_entries.dart';
import 'package:sinapsis/core/database/search_index.dart';
import 'package:sinapsis/core/domain/entities/item_kind.dart';
import 'package:sinapsis/features/library/domain/entities/library_query.dart';

/// Cuántos chunks puede tener una palabra para que valga la pena ordenar los
/// resultados por relevancia.
///
/// Ordenar por relevancia cuesta lo que cuestan las coincidencias —unos 1,5 µs
/// cada una—: 137 ms para una palabra en dos tercios de los 312.793 chunks de
/// una bóveda de 10.000 elementos, 168 ms para un prefijo de dos letras. Y una
/// palabra que está en todas partes no distingue nada: su relevancia es casi
/// igual en todos los chunks, así que ordenar por ella es pagar por un orden
/// que no dice nada. Pasado este número se busca en una ventana, sin ordenar.
const kRankedHitsCap = 30000;

/// Cuántos chunks se miran, como mucho, cuando se busca sin ordenar por
/// relevancia. Son los más recientes: el orden que sí dice algo cuando la
/// relevancia no dice nada.
const kSearchWindowChunks = 600;

/// Los `rowid` de la ventana: los [kSearchWindowChunks] chunks vivos más
/// recientes que coinciden con lo buscado, del más nuevo al más viejo.
///
/// Lleva tres parámetros, en este orden: lo buscado, la cota inferior
/// —[TextSearchPlan.windowFloor]— y cuántos.
///
/// El orden se pide sobre `rowid + 0` y no sobre `rowid`, A PROPÓSITO. Con
/// `ORDER BY rowid DESC` SQLite le encarga el orden a FTS5, y una palabra
/// buscada como prefijo se resuelve leyendo TODA su lista de coincidencias
/// antes de dar la primera: 300 ms con una palabra en 122.531 chunks en un
/// emulador de Android, pidiera lo que se pidiera y desde donde se pidiera
/// —una ventana de 600 no era una fracción de eso—. Recorrida hacia adelante
/// desde una cota, la misma búsqueda cuesta lo que cuestan las coincidencias
/// del tramo (5 ms), y el orden lo pone SQLite sobre lo poco que la cota deja.
/// A una tabla virtual solo se le pasan columnas: con una expresión no hay
/// forma de que el orden vuelva a caerle encima.
const kSearchWindowSql =
    'SELECT chunk_search.rowid AS rid FROM chunk_search '
    'WHERE chunk_search MATCH ? AND chunk_search.rowid > ? '
    'AND $kChunkOutsideTrashSql '
    'ORDER BY chunk_search.rowid + 0 DESC LIMIT ?';

/// Los ids de [count] valores del vocabulario —que se pasan como parámetros—
/// MÁS todo lo que cuelga de ellos: filtrar por «Roma» trae también lo asignado
/// a «Roma republicana» y a «Reformas de los Gracos» (F13).
///
/// Es una consulta recursiva sobre los VALORES, no sobre los elementos: el
/// árbol tiene, como mucho, unos miles de valores y cinco niveles, y se recorre
/// por `idx_property_values_parent`; lo que después se une con
/// `item_property_values` es lo mismo que sin jerarquía. No hay una tabla de
/// cierre que mantener en cada asignación, fusión y migración. Asignar un
/// valor hijo NO asigna a su padre: la jerarquía se resuelve acá, al
/// consultar, sin duplicar filas.
///
/// `UNION` y no `UNION ALL`: si un valor y uno de sus descendientes están
/// entre los pedidos, cada uno cuenta una vez.
String valuesWithDescendantsSql(int count) =>
    'WITH RECURSIVE branch(id) AS ( '
    'SELECT id FROM property_values '
    'WHERE id IN (${List.filled(count, '?').join(', ')}) '
    'UNION SELECT child.id FROM property_values child '
    'JOIN branch ON child.parent_id = branch.id) '
    'SELECT id FROM branch';

/// Cuántos chunks se piden, como mínimo, cuando se busca ordenando por
/// relevancia una página de resultados: ver [topChunksFor].
const kMinTopChunks = 300;

/// Cuántos chunks pedir para ordenar una página que termina en el resultado
/// número [pageEnd]: el mejor chunk de cada uno de esos elementos tiene que
/// estar entre ellos.
///
/// Ordenar TODAS las coincidencias y agruparlas por elemento cuesta lo que
/// cuestan las coincidencias (62 ms con una palabra en 9.770 chunks); pedir los
/// mejores es una fracción (15 ms) —siempre que el corte se haga sobre el
/// índice SOLO y recién después se una con `chunks`: unir primero costaba una
/// búsqueda por cada coincidencia—. Es aproximado en la cola: un elemento cuyo
/// mejor chunk quede más allá de los pedidos no aparece, y aparece uno menos
/// relevante en su lugar. Con muchos chunks buenos por elemento, una página
/// puede traer menos filas que las pedidas; nunca filas equivocadas.
int topChunksFor(int pageEnd) =>
    pageEnd * 12 < kMinTopChunks ? kMinTopChunks : pageEnd * 12;

/// Cómo se va a resolver el texto buscado: la consulta ya en la sintaxis de
/// FTS5, y si se ordena por relevancia o se mira una ventana.
class TextSearchPlan {
  const TextSearchPlan({
    required this.match,
    this.windowed = false,
    this.windowFloor = 0,
    this.termMatches = const [],
  });

  /// Lo que se le pasa a `MATCH`: ver `buildSearchQuery`.
  final String match;

  /// `true` cuando la palabra está en tantos chunks que ordenar por relevancia
  /// no vale su costo: ver [kRankedHitsCap].
  final bool windowed;

  /// Con [windowed], el `row_key` desde el que se busca —sin incluirlo—: los
  /// chunks más recientes están todos por encima. Ver `searchWindowFloor` para
  /// cómo se elige, y [kSearchWindowSql] para por qué hace falta.
  final int windowFloor;

  /// Cada palabra por separado, para encontrar los elementos que las tienen
  /// TODAS aunque estén en fragmentos distintos. Vacío con una sola palabra.
  ///
  /// Sin esto, "kuhn paradigma" no encontraría un artículo que nombra a Kuhn en
  /// la introducción y habla del paradigma cinco párrafos después: la
  /// búsqueda por chunks exige las dos palabras en el MISMO fragmento, y
  /// no encontrar algo que sí está guardado es el peor fallo de una búsqueda.
  /// Las palabras que están en casi todo se dejan afuera: no discriminan.
  final List<String> termMatches;
}

/// El SQL de una [LibraryQuery]: qué elementos entran, en qué orden y cuáles
/// de ellos, página por página.
///
/// Está escrito a mano y no con el constructor de consultas de Drift porque la
/// búsqueda de texto entra por tablas virtuales FTS5 que Drift no conoce, y
/// hace falta UNIRLAS con el resto: solo así el orden por relevancia y la
/// paginación los resuelve SQLite. La versión anterior traía a Dart todos los
/// resultados del índice, armaba una consulta con un parámetro por cada uno y
/// recién después paginaba: con una palabra común en 10.000 elementos eran
/// 700 ms para mostrar cincuenta filas, y el costo crecía con la cantidad de
/// coincidencias y no con el tamaño de la página.
///
/// El texto se busca en DOS índices a la vez —el de chunks, que cubre el texto
/// de las fuentes, y el de elementos, que cubre título, subtítulo y las
/// notas— y se junta por elemento: un elemento entra si coincide en cualquiera
/// de los dos, y los que coinciden en el título, el subtítulo o su propio
/// texto van antes que los que solo mencionan la palabra en el cuerpo de una
/// fuente.
///
/// Un único lugar arma los filtros —tipo de fuente, estado, Bandeja, espacio,
/// etiquetas, propiedades— para las tres preguntas que se le hacen a una
/// consulta (los ids de una página, los ids de todo lo que coincide y cuántos
/// son), de modo que no puedan discrepar.
class LibraryQuerySql {
  LibraryQuerySql(this.query, {TextSearchPlan? plan})
    : plan = plan ?? const TextSearchPlan(match: '') {
    final match = query.hasSearchText
        ? (plan?.match ?? buildSearchQuery(query.searchText!))
        : null;
    // Un texto que no deja ninguna palabra que buscar (solo comillas, por
    // ejemplo) no encuentra nada: no es "sin filtro de texto".
    matchesNothing = match != null && match.isEmpty;
    final searching = match != null && match.isNotEmpty;
    _windowed = searching && (plan?.windowed ?? false);

    if (searching) {
      final terms = _windowed
          ? const <String>[]
          : plan?.termMatches ?? const [];
      // Solo una búsqueda de texto pura, por relevancia y con página: con
      // otros filtros hay que mirar TODAS las coincidencias, porque los
      // filtros se aplican después y podrían dejar la página vacía.
      final onlyText =
          query.sourceKinds.isEmpty &&
          query.processingStates.isEmpty &&
          query.inboxStatuses.isEmpty &&
          query.spaceId == null &&
          query.ids == null &&
          query.tagIds.isEmpty &&
          query.propertyValueIds.isEmpty;
      final limit = query.limit;
      final top =
          !_windowed &&
              onlyText &&
              limit != null &&
              query.sortBy == LibrarySort.relevance
          ? topChunksFor(query.offset + limit)
          : null;
      _from = _textFrom(
        windowed: _windowed,
        termCount: terms.length,
        topChunks: top != null,
      );
      _fromArgs
        ..add(Variable.withString(match))
        ..add(Variable.withString(match));
      if (_windowed) {
        _fromArgs
          ..add(Variable.withInt(this.plan.windowFloor))
          ..add(Variable.withInt(kSearchWindowChunks));
      }
      if (top != null) _fromArgs.add(Variable.withInt(top));
      _fromArgs.addAll(terms.map(Variable.withString));
      _match = match;
      _topChunks = top;
      _termMatches = terms;
    } else {
      _from = _plainFrom;
    }

    // Lo que está en la papelera no es de la biblioteca, sea cual sea el resto
    // de la consulta.
    _where.add(kActiveItemSql);
    if (query.sourceKinds.isNotEmpty) {
      _where.add('$_kindSql IN (${_marks(query.sourceKinds.length)})');
      _args.addAll(query.sourceKinds.map((k) => Variable.withString(k.name)));
    }
    if (query.processingStates.isNotEmpty) {
      _where.add(
        '$_processingStateSql IN (${_marks(query.processingStates.length)})',
      );
      _args.addAll(
        query.processingStates.map((s) => Variable.withString(s.name)),
      );
    }
    if (query.inboxStatuses.isNotEmpty) {
      // Lo decidido en la Bandeja (F28): el estado de trabajo del elemento,
      // y solo de fuentes —una nota también está `processed`, pero nunca
      // esperó en la Bandeja—.
      final states = {
        for (final status in query.inboxStatuses) ...status.itemStates,
      };
      _where.add('item.kind = ? AND item.state IN (${_marks(states.length)})');
      _args
        ..add(Variable.withString(ItemKind.source.name))
        ..addAll(states.map((s) => Variable.withString(s.name)));
    }
    if (query.spaceId != null) {
      _where.add('item.space_id = ?');
      _args.add(Variable.withString(query.spaceId!));
    }
    final ids = query.ids;
    if (ids != null) {
      if (ids.isEmpty) {
        // `IN ()` no es SQL válido y un conjunto vacío no deja pasar nada.
        _where.add('0');
      } else {
        _where.add('item.id IN (${_marks(ids.length)})');
        _args.addAll(ids.map(Variable.withString));
      }
    }
    // Subconsulta en vez de un join: con un join, un elemento que tiene tres
    // de los valores buscados aparecería tres veces en el resultado.
    for (final valueIds in [query.tagIds, query.propertyValueIds]) {
      if (valueIds.isEmpty) continue;
      _where.add(
        'item.id IN (SELECT item_id FROM item_property_values '
        'WHERE property_value_id IN '
        '(${valuesWithDescendantsSql(valueIds.length)}))',
      );
      _args.addAll(valueIds.map(Variable.withString));
    }

    _orderBy = _orderingFor(query, ranked: searching, windowed: _windowed);
  }

  final LibraryQuery query;

  /// Cómo se resuelve el texto buscado: ver [TextSearchPlan].
  final TextSearchPlan plan;

  /// `true` si hay un texto que buscar pero no queda ninguna palabra en él: el
  /// resultado es vacío sin necesidad de preguntarle nada a la base.
  late final bool matchesNothing;

  late final bool _windowed;

  String _match = '';

  /// Cuántos chunks se piden, si esta consulta se resuelve por los mejores.
  int? _topChunks;
  List<String> _termMatches = const [];

  /// Si esta consulta se puede resolver junto con el mejor chunk de cada
  /// resultado: ver [mergedIds].
  bool get canMerge => _topChunks != null;

  /// `true` si hay palabras sueltas para buscar elementos que las tienen todas
  /// en fragmentos distintos.
  bool get hasEveryWordBranch => _termMatches.isNotEmpty;

  /// Un elemento con su fuente, si la tiene: una nota no tiene fila en
  /// `source`.
  static const _plainFrom = 'item LEFT JOIN source ON source.item_id = item.id';

  /// De qué tipo de fuente es el elemento: el de su fila de `source`, o nota si
  /// no tiene.
  static const _kindSql = "COALESCE(source.source_type, 'manualNote')";

  /// Cuándo se capturó: lo dice su fuente; una nota, cuando se creó.
  static const _capturedAtSql = 'COALESCE(source.captured_at, item.created_at)';

  /// El estado del pipeline técnico —pendiente, procesando, listo, fallido— a
  /// partir del estado de la fuente. Una nota está lista desde que se guarda.
  static const _processingStateSql =
      'CASE source.processing_status '
      "WHEN 'pending' THEN 'pending' "
      "WHEN 'running' THEN 'processing' "
      "WHEN 'failed' THEN 'failed' "
      "ELSE 'ready' END";

  /// Los elementos que coinciden con el texto, uno por elemento: si coincide
  /// en el índice de elementos (`t` = 1) y con qué relevancia en el mejor de
  /// sus chunks (`s`, menor es mejor).
  ///
  /// Con [windowed], los chunks se toman sin ordenar, los más recientes, y no
  /// tienen relevancia. Con [termCount] palabras, se suman los elementos que
  /// las tienen todas en fragmentos cualesquiera: sin relevancia propia, van
  /// después de los que las tienen juntas.
  static String _textFrom({
    required bool windowed,
    required int termCount,
    required bool topChunks,
  }) {
    final chunkHits = windowed
        ? 'SELECT c.item_id AS item_id, 0 AS t, NULL AS s '
              'FROM ($kSearchWindowSql) w '
              'JOIN chunks c ON c.row_key = w.rid'
        : topChunks
        ? 'SELECT c.item_id, 0 AS t, top.s FROM ( '
              'SELECT chunk_search.rowid AS rid, chunk_search.rank AS s '
              'FROM chunk_search '
              'WHERE chunk_search MATCH ? AND $kChunkOutsideTrashSql '
              'ORDER BY chunk_search.rank LIMIT ?) top '
              'JOIN chunks c ON c.row_key = top.rid'
        : 'SELECT c.item_id, 0 AS t, chunk_search.rank AS s '
              'FROM chunk_search '
              'JOIN chunks c ON c.row_key = chunk_search.rowid '
              'WHERE chunk_search MATCH ?';
    const oneTerm =
        'SELECT c.item_id AS item_id FROM chunk_search '
        'JOIN chunks c ON c.row_key = chunk_search.rowid '
        'WHERE chunk_search MATCH ?';
    final everyWord = termCount == 0
        ? ''
        : ' UNION ALL SELECT item_id, 0 AS t, NULL AS s FROM ( '
              '${List.filled(termCount, oneTerm).join(' INTERSECT ')})';
    return '(SELECT hit.item_id AS item_id, MAX(hit.t) AS t, MIN(hit.s) AS s '
        'FROM ( '
        'SELECT item_search.item_id AS item_id, 1 AS t, NULL AS s '
        'FROM item_search WHERE item_search MATCH ? '
        'UNION ALL $chunkHits$everyWord'
        ') hit GROUP BY hit.item_id) hits '
        'JOIN item ON item.id = hits.item_id '
        'LEFT JOIN source ON source.item_id = item.id';
  }

  late final String _from;
  late final String _orderBy;

  /// Los parámetros del `FROM` —el texto buscado, y la ventana si la hay—,
  /// que van antes que los del `WHERE` porque aparecen antes en el SQL.
  final List<Variable<Object>> _fromArgs = [];
  final List<String> _where = [];
  final List<Variable<Object>> _args = [];

  String get _whereClause =>
      _where.isEmpty ? '' : ' WHERE ${_where.join(' AND ')}';

  /// Los ids de la página que pide [query] —o de todo lo que coincide, si no
  /// trae límite—, en el orden que pide.
  ({String sql, List<Variable<Object>> variables}) ids() {
    final sql = StringBuffer('SELECT item.id AS id FROM $_from')
      ..write(_whereClause)
      ..write(' ORDER BY $_orderBy');
    final variables = [..._fromArgs, ..._args];
    final limit = query.limit;
    if (limit != null) {
      sql.write(' LIMIT ? OFFSET ?');
      variables
        ..add(Variable.withInt(limit))
        ..add(Variable.withInt(query.offset));
    }
    return (sql: sql.toString(), variables: variables);
  }

  /// La página de resultados JUNTO con el mejor chunk de cada elemento, en UNA
  /// pasada por el índice de chunks —`null` si esta consulta no es de las que
  /// se resuelven así: ver [canMerge]—.
  ///
  /// Pedir los ids de la página y después, aparte, los chunks donde está lo que
  /// se encontró recorría el índice dos veces, y con una palabra frecuente cada
  /// pasada cuesta lo que cuestan las coincidencias. Acá los mejores chunks se
  /// piden una vez, se agrupan por elemento —la fila de menor `rank` de cada
  /// uno trae su `chunk_key`— y sirven a la vez para elegir y ordenar los
  /// elementos y para señalar dónde está lo encontrado.
  ///
  /// Con [everyWord], suma los elementos que tienen todas las palabras en
  /// fragmentos distintos; se deja para cuando la página no se llenó sin ellos.
  ({String sql, List<Variable<Object>> variables})? mergedIds({
    required bool everyWord,
  }) {
    final top = _topChunks;
    if (top == null) return null;
    final terms = everyWord ? _termMatches : const <String>[];

    const oneTerm =
        'SELECT c.item_id AS item_id FROM chunk_search '
        'JOIN chunks c ON c.row_key = chunk_search.rowid '
        'WHERE chunk_search MATCH ?';
    final everyBranch = terms.isEmpty
        ? ''
        : ' UNION ALL SELECT item_id, 0 AS t FROM ( '
              '${List.filled(terms.length, oneTerm).join(' INTERSECT ')})';

    final sql =
        'WITH best AS ( '
        'SELECT c.item_id AS item_id, top.rid AS chunk_key, '
        'MIN(top.s) AS s FROM ( '
        'SELECT chunk_search.rowid AS rid, chunk_search.rank AS s '
        'FROM chunk_search '
        'WHERE chunk_search MATCH ? AND $kChunkOutsideTrashSql '
        'ORDER BY chunk_search.rank LIMIT ?) top '
        'JOIN chunks c ON c.row_key = top.rid GROUP BY c.item_id) '
        'SELECT item.id AS id, best.chunk_key AS chunk_key FROM ( '
        'SELECT cand.item_id AS item_id, MAX(cand.t) AS t FROM ( '
        'SELECT item_search.item_id AS item_id, 1 AS t FROM item_search '
        'WHERE item_search MATCH ? '
        'UNION ALL SELECT best.item_id, 0 AS t FROM best$everyBranch '
        ') cand GROUP BY cand.item_id) cands '
        'LEFT JOIN best ON best.item_id = cands.item_id '
        'JOIN item ON item.id = cands.item_id '
        'WHERE $kActiveItemSql '
        'ORDER BY cands.t DESC, (best.s IS NULL), best.s LIMIT ? OFFSET ?';

    return (
      sql: sql,
      variables: [
        Variable.withString(_match),
        Variable.withInt(top),
        Variable.withString(_match),
        for (final term in terms) Variable.withString(term),
        Variable.withInt(query.limit!),
        Variable.withInt(query.offset),
      ],
    );
  }

  /// Cuántos elementos coinciden, sin paginar: "hay 340 resultados" es el
  /// total, no lo que entró en la página actual. Con una palabra que está en
  /// todas partes, el total es el de la ventana que se miró.
  ({String sql, List<Variable<Object>> variables}) count() => (
    sql: 'SELECT COUNT(*) AS n FROM $_from$_whereClause',
    variables: [..._fromArgs, ..._args],
  );

  static String _marks(int count) => List.filled(count, '?').join(', ');

  /// Con orden por relevancia, primero lo que coincide en el título, el
  /// subtítulo o el propio texto del usuario y después lo que solo lo
  /// menciona en el cuerpo de una fuente, cada grupo por la relevancia de su
  /// mejor chunk. Sin relevancia que medir —sin texto buscado, o con una
  /// palabra en todas partes— se cae en el orden por fecha de captura.
  static String _orderingFor(
    LibraryQuery query, {
    required bool ranked,
    required bool windowed,
  }) {
    final direction = query.descending ? 'DESC' : 'ASC';
    return switch (query.sortBy) {
      LibrarySort.relevance when ranked && !windowed =>
        'hits.t DESC, (hits.s IS NULL), hits.s',
      LibrarySort.relevance when ranked => 'hits.t DESC, $_capturedAtSql DESC',
      LibrarySort.relevance ||
      LibrarySort.capturedAt => '$_capturedAtSql $direction',
      LibrarySort.publishedAt => 'source.published_at $direction',
      LibrarySort.updatedAt => 'item.updated_at $direction',
      LibrarySort.title => 'item.title $direction',
    };
  }
}
