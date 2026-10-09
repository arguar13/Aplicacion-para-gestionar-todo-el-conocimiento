import 'package:drift/drift.dart';
import 'package:sinapsis/features/flashcards/domain/entities/card_browser_query.dart';
import 'package:sinapsis/features/flashcards/domain/services/card_text_search.dart';

/// El SQL de «Mis tarjetas» (F31, ola 2, decisión 72).
///
/// Escrito a mano, como el de la cola de estudio: los filtros de etapa son
/// condiciones sobre varias columnas y el orden por olvidos es un agregado. Un
/// único lugar arma el `WHERE`, para que contar, paginar, traer los ids y
/// rotular los filtros no puedan discrepar.
///
/// Los parámetros van en el orden en que aparecen los `?` (sin numerar): el
/// `WHERE` primero —[where] y [args]— y lo que cada consulta sume después.
class CardBrowserSql {
  CardBrowserSql({
    required this.query,
    required this.now,
    required this.dayEnd,
    this.itemIds,
    bool withStatus = true,
  }) {
    final clauses = <String>['i.deleted_at IS NULL'];
    final args = <Variable<Object>>[];

    final ids = itemIds;
    if (ids != null) {
      clauses.add(
        ids.isEmpty
            ? '0'
            : 'f.item_id IN (${List.filled(ids.length, '?').join(', ')})',
      );
      args.addAll(ids.map(Variable.withString));
    }

    final status = query.status;
    if (withStatus && status != null) {
      clauses.add(_statusSql(status));
      switch (status) {
        case CardBrowserStatus.buried:
          args.add(Variable.withDateTime(now));
        case CardBrowserStatus.due:
          args.add(Variable.withDateTime(dayEnd));
        case CardBrowserStatus.newCards ||
            CardBrowserStatus.learning ||
            CardBrowserStatus.young ||
            CardBrowserStatus.mature ||
            CardBrowserStatus.suspended:
          break;
      }
    }

    for (final pattern in cardSearchPatterns(query.text)) {
      clauses.add('(f.front GLOB ? OR f.back GLOB ?)');
      args
        ..add(Variable.withString(pattern))
        ..add(Variable.withString(pattern));
    }

    where = clauses.join(' AND ');
    this.args = args;
  }

  final CardBrowserQuery query;

  /// Ahora, para saber qué tarjetas están pospuestas.
  final DateTime now;

  /// Cuándo termina el día de estudio de hoy: lo que vence antes es «por
  /// repasar».
  final DateTime dayEnd;

  /// Los elementos del recorte; `null` = todos. Vacío = no entra nada.
  final List<String>? itemIds;

  late final String where;
  late final List<Variable<Object>> args;

  /// Una tarjeta que nunca se contestó: sin paso, sin intervalo, sin
  /// repeticiones. El espejo SQL de `Flashcard.phase == newCard` (el mismo de
  /// la cola de estudio; una prueba compara las dos contra la entidad).
  static const isNew =
      'f.learning_step IS NULL AND f.repetitions = 0 '
      'AND f.interval_days = 0 AND f.last_reviewed_at IS NULL';

  static String _statusSql(CardBrowserStatus status) => switch (status) {
    CardBrowserStatus.newCards => 'f.suspended = 0 AND ($isNew)',
    CardBrowserStatus.learning =>
      'f.suspended = 0 AND f.learning_step IS NOT NULL',
    CardBrowserStatus.young =>
      'f.suspended = 0 AND f.learning_step IS NULL AND NOT ($isNew) '
          'AND f.interval_days < $kMatureIntervalDays',
    CardBrowserStatus.mature =>
      'f.suspended = 0 AND f.learning_step IS NULL AND NOT ($isNew) '
          'AND f.interval_days >= $kMatureIntervalDays',
    CardBrowserStatus.suspended => 'f.suspended = 1',
    CardBrowserStatus.due =>
      'f.suspended = 0 AND NOT ($isNew) AND f.due_at < ?',
    CardBrowserStatus.buried =>
      'f.buried_until IS NOT NULL AND f.buried_until > ?',
  };

  /// Lo que viene después del `FROM` en toda consulta: las tarjetas unidas a su
  /// elemento (que tiene que estar vivo).
  static const from = 'FROM flashcards f JOIN item i ON i.id = f.item_id';

  /// Las veces que se olvidó cada tarjeta: un «De nuevo» sobre un repaso.
  /// Pre-v39, `phase_before` es `review` para todo salvo la primera respuesta.
  static const lapsesAggregate =
      'SELECT flashcard_id, COUNT(*) AS lapses FROM review_log '
      "WHERE grade = 'again' AND phase_before = 'review' "
      'GROUP BY flashcard_id';

  /// El `ORDER BY` completo: la columna pedida y el identificador, en el
  /// mismo sentido, para que el orden sea total.
  String get orderBy {
    final direction = query.descending ? 'DESC' : 'ASC';
    final column = switch (query.sort) {
      CardBrowserSort.due => 'f.due_at',
      CardBrowserSort.created => 'f.created_at',
      CardBrowserSort.ease => 'f.ease_factor',
      CardBrowserSort.interval => 'f.interval_days',
      CardBrowserSort.lapses => 'COALESCE(l.lapses, 0)',
    };
    return 'ORDER BY $column $direction, f.id $direction';
  }

  /// La unión con los olvidos, solo cuando se ordena por ellos: es un agregado
  /// sobre todo el historial y no se paga para ordenar por otra cosa.
  String get lapsesJoin => query.sort == CardBrowserSort.lapses
      ? 'LEFT JOIN ($lapsesAggregate) l ON l.flashcard_id = f.id'
      : '';
}
