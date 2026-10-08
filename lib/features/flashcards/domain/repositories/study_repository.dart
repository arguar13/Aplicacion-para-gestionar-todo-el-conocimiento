import 'package:fpdart/fpdart.dart';
import 'package:sinapsis/core/error/failures.dart';
import 'package:sinapsis/features/flashcards/domain/entities/study_counts.dart';
import 'package:sinapsis/features/flashcards/domain/entities/study_limits.dart';
import 'package:sinapsis/features/flashcards/domain/entities/study_next.dart';
import 'package:sinapsis/features/flashcards/domain/entities/study_scope.dart';

/// La cola de estudio (F31, decisión 69): qué tarjeta toca ahora y cuánto hay
/// para hoy.
///
/// ## El orden de la sesión
///
/// 1. Primero las que se aprenden o reaprenden y YA volvieron
///    (`dueAt <= ahora`), la que venció antes primero: son minutos, y
///    esperarlas las enfría.
/// 2. Después los repasos que vencen hoy (hasta el final del día de estudio,
///    ver `StudyDay`), el más atrasado primero, hasta el límite de repasos del
///    día.
/// 3. Al final las nuevas, en el orden en que se crearon, hasta el límite de
///    nuevas del día. (Anki por defecto las mezcla entre los repasos; acá van
///    después a propósito: un repaso atrasado nunca queda sin hacer por haber
///    entretenido la sesión con lo nuevo, y el límite de nuevas se puede
///    cumplir al final o dejar.)
/// 4. Si no queda nada más y hay tarjetas en aprendizaje que vuelven más tarde
///    hoy: las que están a menos de `learnAhead` se muestran ya; si no, la
///    sesión devuelve [StudyNextWait] con cuándo vuelven.
///
/// Quedan afuera las pausadas, las pospuestas hasta mañana, las de elementos en
/// la papelera y —para nuevas y repasos— las hermanas (mismo `group_id`) de una
/// tarjeta que ya se contestó hoy: una sola por grupo por día.
abstract interface class StudyRepository {
  /// Qué tarjeta toca en [scope], con los topes [limits] (los de fábrica o
  /// `studyLimitsProvider`; para «estudiar más hoy», `limits.extendedBy`).
  ///
  /// [learnAhead] es cuánto antes de su hora se trae una tarjeta en aprendizaje
  /// cuando no hay nada más: cero (por defecto) la deja esperar.
  Future<Either<Failure, StudyNext>> next(
    StudyScope scope, {
    required StudyLimits limits,
    Duration learnAhead = Duration.zero,
  });

  /// Cuánto hay para estudiar hoy en [scope], respetando [limits].
  Future<Either<Failure, StudyCounts>> counts(
    StudyScope scope, {
    required StudyLimits limits,
  });

  /// [counts], actualizándose solo ante cualquier cambio de tarjetas, repasos,
  /// elementos o de lo que compone un recorte. Lo que cambia con el reloj sin
  /// que nada se escriba —empieza otro día de estudio— no lo detecta el
  /// repositorio: lo avisa `StudyDayWatcher`, y `studyCountsProvider` vuelve a
  /// pedir el stream.
  Stream<StudyCounts> watchCounts(
    StudyScope scope, {
    required StudyLimits limits,
  });
}
