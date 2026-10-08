import 'package:drift/drift.dart';

/// El SQL de la cola de estudio (F31, decisión 69).
///
/// Escrito a mano y no con el constructor de Drift porque el filtro combina
/// varias cosas —etapa de la tarjeta, hermanas contestadas hoy, papelera,
/// recorte— y porque los conteos se resuelven en UNA pasada con `CASE`. Un
/// único lugar arma los filtros, para que "qué tarjeta toca" y "cuántas hay"
/// no puedan discrepar.
///
/// Los parámetros van numerados y se comparten: `?1` es ahora, `?2` el comienzo
/// del día de estudio, `?3` su fin, y desde `?4` los elementos del recorte.
class StudyQueueSql {
  StudyQueueSql({
    required this.now,
    required this.dayStart,
    required this.dayEnd,
    this.itemIds,
  });

  final DateTime now;
  final DateTime dayStart;
  final DateTime dayEnd;

  /// Los elementos del recorte; `null` = todos.
  final List<String>? itemIds;

  /// Los valores de `?1` a `?3` y desde `?4`, en ese orden.
  List<Variable<Object>> get _all => [
    Variable.withDateTime(now),
    Variable.withDateTime(dayStart),
    Variable.withDateTime(dayEnd),
    for (final id in itemIds ?? const <String>[]) Variable.withString(id),
  ];

  /// Los parámetros que [sql] usa, y ni uno más: SQLite exige que se pase
  /// exactamente hasta el índice más alto que aparece en la sentencia.
  List<Variable<Object>> bind(String sql) {
    var highest = 0;
    for (final match in RegExp(r'\?(\d+)').allMatches(sql)) {
      final index = int.parse(match.group(1)!);
      if (index > highest) highest = index;
    }
    return _all.take(highest).toList();
  }

  /// Una tarjeta que nunca se contestó: sin paso, sin intervalo, sin
  /// repeticiones. El espejo SQL de `Flashcard.phase == newCard`.
  static const _isNew =
      'f.learning_step IS NULL AND f.repetitions = 0 '
      'AND f.interval_days = 0 AND f.last_reviewed_at IS NULL';

  /// Lo que tiene que cumplir cualquier tarjeta para entrar en una sesión: no
  /// pausada, no pospuesta, de un elemento vivo y dentro del recorte.
  String get _eligible {
    final ids = itemIds;
    final marks = [for (var n = 0; n < (ids?.length ?? 0); n++) '?${4 + n}'];
    final inScope = ids == null
        ? ''
        : ' AND f.item_id IN (${marks.join(', ')})';
    return 'f.suspended = 0 '
        'AND (f.buried_until IS NULL OR f.buried_until <= ?1) '
        'AND f.item_id NOT IN '
        '(SELECT i.id FROM item i WHERE i.deleted_at IS NOT NULL)'
        '$inScope';
  }

  /// Ninguna hermana (mismo grupo) se contestó hoy: una por grupo por día.
  static const _noSiblingToday =
      '(f.group_id IS NULL OR NOT EXISTS ( '
      'SELECT 1 FROM flashcards s '
      'JOIN review_log r ON r.flashcard_id = s.id '
      'WHERE s.group_id = f.group_id AND s.id <> f.id '
      'AND r.reviewed_at >= ?2 AND r.reviewed_at < ?3))';

  /// La que se aprende o reaprende y ya volvió, la que venció antes primero.
  String get learningDue =>
      'SELECT f.* FROM flashcards f WHERE $_eligible '
      'AND f.learning_step IS NOT NULL AND f.due_at <= ?1 '
      'ORDER BY f.due_at, f.id LIMIT 1';

  /// El repaso en días que vence hoy, el más atrasado primero.
  String get reviewDue =>
      'SELECT f.* FROM flashcards f WHERE $_eligible '
      'AND f.learning_step IS NULL AND NOT ($_isNew) AND f.due_at < ?3 '
      'AND $_noSiblingToday '
      'ORDER BY f.due_at, f.id LIMIT 1';

  /// La nueva que sigue, en el orden en que se crearon.
  String get newDue =>
      'SELECT f.* FROM flashcards f WHERE $_eligible '
      'AND $_isNew AND f.due_at < ?3 AND $_noSiblingToday '
      'ORDER BY f.created_at, f.id LIMIT 1';

  /// La primera tarjeta en aprendizaje que vuelve más tarde hoy.
  String get learningLater =>
      'SELECT f.* FROM flashcards f WHERE $_eligible '
      'AND f.learning_step IS NOT NULL AND f.due_at > ?1 AND f.due_at < ?3 '
      'ORDER BY f.due_at, f.id LIMIT 1';

  /// Cuántas hay de cada una, sin límites: en aprendizaje que vuelven hoy,
  /// nuevas y repasos que vencen hoy, y cuántas en aprendizaje vuelven después
  /// de ahora.
  String get counts =>
      'SELECT '
      'COALESCE(SUM(CASE WHEN f.learning_step IS NOT NULL '
      'AND f.due_at < ?3 THEN 1 ELSE 0 END), 0) AS learning, '
      'MIN(CASE WHEN f.learning_step IS NOT NULL AND f.due_at < ?3 '
      'THEN f.due_at END) AS next_learning_due, '
      'COALESCE(SUM(CASE WHEN f.learning_step IS NOT NULL '
      'AND f.due_at > ?1 AND f.due_at < ?3 THEN 1 ELSE 0 END), 0) '
      'AS learning_later, '
      'COALESCE(SUM(CASE WHEN $_isNew AND f.due_at < ?3 '
      'AND $_noSiblingToday THEN 1 ELSE 0 END), 0) AS new_available, '
      'COALESCE(SUM(CASE WHEN f.learning_step IS NULL AND NOT ($_isNew) '
      'AND f.due_at < ?3 AND $_noSiblingToday THEN 1 ELSE 0 END), 0) '
      'AS reviews_available '
      'FROM flashcards f WHERE $_eligible';

  /// Lo que ya se hizo hoy, en toda la bóveda: los límites son globales.
  static const doneToday =
      'SELECT '
      "COALESCE(SUM(CASE WHEN phase_before = 'newCard' THEN 1 ELSE 0 END), 0) "
      'AS new_done, '
      "COALESCE(SUM(CASE WHEN phase_before = 'review' THEN 1 ELSE 0 END), 0) "
      'AS reviews_done '
      'FROM review_log WHERE reviewed_at >= ?2 AND reviewed_at < ?3';
}
