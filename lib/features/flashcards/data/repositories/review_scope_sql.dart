import 'package:drift/drift.dart';
import 'package:sinapsis/features/flashcards/data/repositories/card_browser_sql.dart';
import 'package:sinapsis/features/flashcards/domain/entities/card_browser_query.dart';
import 'package:sinapsis/features/flashcards/domain/entities/review_activity.dart';
import 'package:sinapsis/features/flashcards/domain/entities/review_stats.dart';

/// Una consulta escrita a mano con sus parámetros, en el orden de sus `?`.
typedef ScopedQuery = ({String sql, List<Variable<Object>> variables});

/// El SQL de las estadísticas y del historial de repaso, acotado a un recorte
/// (F43, M16 y M17).
///
/// El recorte se resuelve UNA vez a sus elementos, y cada consulta lo lleva
/// como `f.item_id IN (…)`: SQLite busca las tarjetas por
/// `idx_flashcards_item` y, de cada una, sus repasos por
/// `idx_review_log_flashcard` (`flashcard_id`, `reviewed_at`). El `CROSS JOIN`
/// fija ese orden —de las tarjetas a sus repasos—, para que un recorte chico
/// nunca recorra el registro entero. Sin recorte se recorren las tarjetas, que
/// es lo que se está contando.
///
/// Los parámetros van en el orden en que aparecen los `?`, sin numerar: el
/// `WHERE` del recorte primero y lo que cada consulta sume después.
class ReviewScopeSql {
  ReviewScopeSql({this.itemIds}) {
    final ids = itemIds;
    if (ids == null) {
      where = 'i.deleted_at IS NULL';
      args = const [];
    } else {
      where = ids.isEmpty
          ? '0'
          : 'i.deleted_at IS NULL AND '
                'f.item_id IN (${List.filled(ids.length, '?').join(', ')})';
      args = [for (final id in ids) Variable.withString(id)];
    }
  }

  /// Los elementos del recorte; `null` = todos. Vacío = no entra nada.
  final List<String>? itemIds;

  late final String where;
  late final List<Variable<Object>> args;

  /// El tramo con el que se agrupan los repasos, en segundos: un cuarto de
  /// hora (ver `ReviewActivityBucket`). Las fechas se guardan en segundos.
  static const quarterSeconds = 900;

  /// Las tarjetas del recorte, unidas a su elemento (que tiene que estar
  /// vivo).
  static const cardsFrom = CardBrowserSql.from;

  /// Los repasos de las tarjetas del recorte.
  static const logsFrom =
      '$cardsFrom CROSS JOIN review_log rl ON rl.flashcard_id = f.id';

  /// La etapa del registro, como el índice de [ReviewLogStage]: lo de antes de
  /// v39 es todo `review` salvo la primera respuesta, que se marcó `newCard`.
  static final stageSql =
      'CASE '
      "WHEN rl.phase_before = 'newCard' THEN ${ReviewLogStage.newCard.index} "
      "WHEN rl.phase_before = 'learning' THEN ${ReviewLogStage.learning.index} "
      "WHEN rl.phase_before = 'relearning' "
      'THEN ${ReviewLogStage.relearning.index} '
      'WHEN rl.interval_before < $kMatureIntervalDays '
      'THEN ${ReviewLogStage.young.index} '
      'ELSE ${ReviewLogStage.mature.index} END';

  /// Un olvido: un «De nuevo» sobre un repaso en días, como en «Mis tarjetas».
  static const lapseSql =
      "CASE WHEN rl.grade = 'again' AND rl.phase_before = 'review' "
      'THEN 1 ELSE 0 END';

  /// Cuántas respuestas hubo en cada cuarto de hora, etapa y botón: de acá
  /// salen los repasos por día, los botones de cada período, las horas, la
  /// retención y el calendario, con una sola lectura del registro.
  ScopedQuery get activity => (
    sql:
        'SELECT rl.reviewed_at / $quarterSeconds AS q, $stageSql AS stage, '
        'rl.grade AS grade, COUNT(*) AS n $logsFrom WHERE $where '
        'GROUP BY q, stage, grade',
    variables: args,
  );

  /// Lo de hoy: cuántas tarjetas distintas, cuántas respuestas, cuántas no
  /// fueron «De nuevo» y cuántas nuevas, desde [dayStart].
  ScopedQuery today(DateTime dayStart) => (
    sql:
        'SELECT COUNT(DISTINCT rl.flashcard_id) AS cards, COUNT(*) AS answers, '
        "COALESCE(SUM(CASE WHEN rl.grade = 'again' THEN 0 ELSE 1 END), 0) "
        'AS correct, '
        "COALESCE(SUM(CASE WHEN rl.phase_before = 'newCard' THEN 1 ELSE 0 "
        'END), 0) AS new_cards '
        '$logsFrom WHERE $where AND rl.reviewed_at >= ?',
    variables: [...args, Variable.withDateTime(dayStart)],
  );

  /// Las tarjetas en repaso —no nuevas, sin paso de aprendizaje, no
  /// pausadas— por tramo del intervalo y facilidad en por ciento: los
  /// intervalos y la facilidad, en una sola lectura.
  ///
  /// La facilidad se redondea en la base (`ROUND(ease * 100)`): 2,5 − 1,3 no
  /// da justo 1,2 en coma flotante, y agrupar por el real partiría un mismo
  /// valor en dos.
  ScopedQuery get cardShape {
    final band = [
      for (final range in IntervalRange.values)
        if (range.to != null)
          'WHEN f.interval_days <= ${range.to} THEN ${range.index}',
    ].join(' ');
    return (
      sql:
          'SELECT CASE $band ELSE ${IntervalRange.longer.index} END AS band, '
          'CAST(ROUND(f.ease_factor * 100) AS INTEGER) AS ease, '
          'COUNT(*) AS n $cardsFrom WHERE $where AND f.suspended = 0 '
          'AND f.learning_step IS NULL AND NOT (${CardBrowserSql.isNew}) '
          'GROUP BY band, ease',
      variables: args,
    );
  }

  /// Cuántas tarjetas se agregaron en cada cuarto de hora.
  ScopedQuery get added => (
    sql:
        'SELECT f.created_at / $quarterSeconds AS q, COUNT(*) AS n '
        '$cardsFrom WHERE $where GROUP BY q',
    variables: args,
  );

  /// Cuántas vencen en cada uno de los días que terminan en [ends], desde
  /// [today] (el principio del día de estudio de hoy); `-1` es lo atrasado.
  ///
  /// Cuenta lo programado —no lo nuevo, que no tiene fecha— y no pausado. Una
  /// tarjeta pospuesta cuenta el día en que vuelve, no el que tenía.
  ScopedQuery forecast({
    required DateTime today,
    required DateTime now,
    required List<DateTime> ends,
  }) {
    final whens = [
      'WHEN eff < ? THEN -1',
      for (var k = 0; k < ends.length; k++) 'WHEN eff < ? THEN $k',
    ].join(' ');
    return (
      sql:
          'SELECT CASE $whens END AS bucket, COUNT(*) AS n FROM ( '
          'SELECT CASE WHEN f.buried_until IS NOT NULL '
          'AND f.buried_until > ? AND f.buried_until > f.due_at '
          'THEN f.buried_until ELSE f.due_at END AS eff '
          '$cardsFrom WHERE $where AND f.suspended = 0 '
          'AND NOT (${CardBrowserSql.isNew}) '
          ') WHERE eff < ? GROUP BY bucket',
      variables: [
        Variable.withDateTime(today),
        for (final end in ends) Variable.withDateTime(end),
        Variable.withDateTime(now),
        ...args,
        Variable.withDateTime(ends.last),
      ],
    );
  }

  /// Las tarjetas que de verdad cuestan (F43, M16): al menos un «De nuevo» y
  /// [minReviews] repasos, de la que más se olvidó a la que menos —a igual
  /// cantidad de olvidos, la de más «De nuevo» entre sus repasos—, hasta
  /// [limit].
  ///
  /// El «al menos un De nuevo» es el arreglo de raíz: sin él, con menos de
  /// [limit] tarjetas olvidadas, la lista se completaba con tarjetas que nunca
  /// fallaron, y aparecía una «difícil» con 0 % «de nuevo».
  ScopedQuery difficult({required int minReviews, required int limit}) => (
    sql:
        'SELECT f.id AS flashcard_id, f.front AS front, f.back AS back, '
        'f.item_id AS item_id, f.source_char_start AS source_start, '
        'f.source_char_end AS source_end, COUNT(*) AS total, '
        "SUM(CASE WHEN rl.grade = 'again' THEN 1 ELSE 0 END) AS again_count, "
        'SUM($lapseSql) AS lapses '
        '$logsFrom WHERE $where GROUP BY f.id '
        'HAVING again_count >= 1 AND total >= ? '
        'ORDER BY lapses DESC, again_count * 1.0 / total DESC, total DESC, '
        'f.id LIMIT ?',
    variables: [...args, Variable.withInt(minReviews), Variable.withInt(limit)],
  );
}
