import 'package:drift/drift.dart' show Variable;
import 'package:sinapsis/core/database/active_entries.dart';
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/features/library/data/repositories/library_query_sql.dart';

/// Cuántos `row_key` hacia atrás se mira en el primer intento: cuatro ventanas
/// de chunks. Una palabra que pide ventana está, por definición, en muchos
/// chunks, y con una de cada cuatro filas que coincidan ya alcanza.
const _kFirstSpan = kSearchWindowChunks * 4;

/// Cuánto crece el tramo en cada intento siguiente.
const _kSpanGrowth = 4;

/// Desde qué `row_key` —sin incluirlo— hay que buscar para que la ventana de
/// los [kSearchWindowChunks] chunks más recientes que coinciden con [match]
/// quede completa. Ver [kSearchWindowSql] para por qué la búsqueda necesita una
/// cota en vez de pedirle al índice que ordene.
///
/// Prueba tramos cada vez más largos hacia atrás desde el último chunk y se
/// queda con el primero que ya junta coincidencias para llenar la ventana. Cada
/// prueba recorre hacia adelante, como mucho, una ventana de coincidencias:
/// unos milisegundos, y una palabra que está en tantos chunks como para pedir
/// ventana casi siempre se resuelve en la primera o la segunda. Si ni la
/// bóveda entera las junta, la cota deja pasar todo: la ventana es lo que
/// haya, que es lo que devolvía ordenar de más nuevo a más viejo.
///
/// Las coincidencias se cuentan con el mismo filtro de la papelera que la
/// consulta que después usa la cota: si no, unos cuantos chunks borrados
/// harían pasar por completa una ventana que no lo está.
Future<int> searchWindowFloor(AppDatabase db, String match) async {
  // Cada extremo en su propia subconsulta: SQLite lee el primero y el último
  // de un árbol solo si es UN mínimo o UN máximo; pedidos juntos recorre la
  // tabla entera —30 ms con 314.000 chunks—.
  final range = await db
      .customSelect(
        'SELECT (SELECT MIN(row_key) FROM chunks) AS first, '
        '(SELECT MAX(row_key) FROM chunks) AS last',
      )
      .getSingle();
  final first = range.readNullable<int>('first');
  final last = range.readNullable<int>('last');
  // Sin chunks no hay ventana que armar: cualquier cota sirve.
  if (first == null || last == null) return 0;

  var span = _kFirstSpan;
  while (true) {
    final floor = last - span;
    // El tramo ya cubre todos los chunks: `rowid > first - 1` los deja pasar.
    if (floor < first) return first - 1;

    final probe = await db
        .customSelect(
          'SELECT COUNT(*) AS n FROM ( '
          'SELECT chunk_search.rowid FROM chunk_search '
          'WHERE chunk_search MATCH ? AND chunk_search.rowid > ? '
          'AND $kChunkOutsideTrashSql LIMIT ?)',
          variables: [
            Variable.withString(match),
            Variable.withInt(floor),
            Variable.withInt(kSearchWindowChunks),
          ],
        )
        .getSingle();
    if (probe.read<int>('n') >= kSearchWindowChunks) return floor;
    span *= _kSpanGrowth;
  }
}
