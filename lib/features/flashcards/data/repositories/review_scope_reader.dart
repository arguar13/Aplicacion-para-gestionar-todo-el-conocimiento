import 'package:drift/drift.dart';
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/features/flashcards/data/repositories/review_scope_sql.dart';
import 'package:sinapsis/features/flashcards/domain/entities/review_activity.dart';
import 'package:sinapsis/features/flashcards/domain/entities/review_grade.dart';
import 'package:sinapsis/features/flashcards/domain/entities/study_scope.dart';
import 'package:sinapsis/features/flashcards/domain/services/study_scope_resolver.dart';

/// Lo que comparten las estadísticas y el historial de repaso (F43, M16 y
/// M17): el recorte resuelto una vez y la lectura agrupada del registro.
class ReviewScopeReader {
  const ReviewScopeReader({
    required AppDatabase database,
    required StudyScopeResolver resolver,
  }) : _db = database,
       _resolver = resolver;

  final AppDatabase _db;
  final StudyScopeResolver _resolver;

  /// Hasta cuántos elementos acepta un recorte: cada uno es un parámetro de la
  /// consulta (SQLite admite 32.766), igual que en la cola de estudio.
  static const maxScopeItems = 30000;

  /// Lo que leen las consultas: cualquier escritura acá puede cambiar un
  /// número.
  Set<TableInfo<dynamic, dynamic>> get reads => {
    _db.reviewLogs,
    _db.flashcards,
    _db.knowledgeEntries,
  };

  /// Lo que hay que mirar para que la pantalla se actualice sola: lo que se
  /// lee y aquello de lo que está hecho un recorte, como la cola de estudio.
  List<TableInfo<dynamic, dynamic>> get watched => [
    ...reads,
    _db.itemPropertyValues,
    _db.propertyValues,
    _db.spaces,
    _db.notebooks,
    _db.notebookItems,
  ];

  /// El SQL de [scope], con el recorte ya resuelto a sus elementos. Un recorte
  /// que ya no existe falla, como en la cola de estudio.
  Future<ReviewScopeSql> sqlFor(StudyScope scope) async {
    final resolved = await _resolver.itemIds(scope);
    final ids = resolved.getOrElse((failure) => throw StateError('$failure'));
    if (ids != null && ids.length > maxScopeItems) {
      throw StateError(
        'El recorte tiene ${ids.length} elementos y las estadísticas admiten '
        'hasta $maxScopeItems.',
      );
    }
    return ReviewScopeSql(itemIds: ids?.toList());
  }

  /// Corre [query] y trae sus filas.
  Future<List<QueryRow>> rows(ScopedQuery query) => _db
      .customSelect(query.sql, variables: query.variables, readsFrom: reads)
      .get();

  /// Las respuestas del recorte, agrupadas por cuarto de hora, etapa y botón.
  Future<List<ReviewActivityBucket>> activity(ReviewScopeSql sql) async {
    final grades = {for (final g in ReviewGrade.values) g.name: g};
    return [
      for (final row in await rows(sql.activity))
        if (grades[row.read<String>('grade')] case final grade?)
          ReviewActivityBucket(
            start: quarterStart(row.read<int>('q')),
            stage: ReviewLogStage.values[row.read<int>('stage')],
            grade: grade,
            count: row.read<int>('n'),
          ),
    ];
  }

  /// El cuarto de hora número [q] desde 1970, en la hora local.
  static DateTime quarterStart(int q) => DateTime.fromMillisecondsSinceEpoch(
    q * ReviewScopeSql.quarterSeconds * 1000,
  );
}
