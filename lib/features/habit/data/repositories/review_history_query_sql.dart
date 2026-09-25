import 'package:drift/drift.dart';
import 'package:sinapsis/core/database/active_entries.dart';
import 'package:sinapsis/core/database/app_database.dart';

/// Lo que la consulta de tarjetas difíciles lee: cualquier escritura en
/// estas tablas puede cambiar el resultado. `knowledgeEntries` es `item`
/// —el filtro de la papelera lee su columna—.
List<TableInfo<dynamic, dynamic>> reviewHistoryTables(AppDatabase db) => [
  db.reviewLogs,
  db.flashcards,
  db.knowledgeEntries,
];

/// Cuántas tarjetas trae «tarjetas difíciles», ya recortado. Decisión
/// propia: diez alcanza para señalar un patrón sin abrumar la pantalla.
const kHardestCardsLimit = 10;

/// Por debajo de esto no cuenta: una tarjeta repasada una sola vez y
/// calificada `again` tendría 100 % de "again" sin decir nada real.
/// Decisión propia, mismo espíritu que `kMinSourcesForCompleteBranch` en
/// `complete_topic_branch.dart` —un piso bajo para que un caso mínimo no
/// trivialice el criterio—.
const kHardestCardsMinReviews = 3;

/// Las tarjetas con mayor proporción de `again` entre sus repasos (F17,
/// D8), de toda la historia —no solo la ventana de las últimas semanas
/// que usa la curva de retención: una tarjeta que costó hace meses y no
/// se volvió a repasar sigue siendo información real sobre qué cuesta—.
///
/// `GROUP BY`/`HAVING`/un `ORDER BY` sobre una proporción calculada no
/// tienen una forma limpia en el constructor tipado de drift: se escribe
/// a mano, mismo criterio que `atlas_query_sql.dart`. Variables: `?1` el
/// piso de repasos, `?2` el tope de filas.
///
/// Deja afuera las tarjetas de un elemento en la papelera
/// ([kActiveItemSql]): una tarjeta que ya no se puede repasar no tiene
/// sentido señalarla como "la más difícil".
const kHardestCardsSql =
    '''
SELECT f.id AS flashcard_id,
       f.front AS front,
       COUNT(*) AS total,
       SUM(CASE WHEN rl.grade = 'again' THEN 1 ELSE 0 END) AS again_count
FROM review_log rl
JOIN flashcards f ON f.id = rl.flashcard_id
JOIN item ON item.id = f.item_id
WHERE $kActiveItemSql
GROUP BY f.id
HAVING total >= ?1
ORDER BY (again_count * 1.0 / total) DESC, total DESC
LIMIT ?2
''';
