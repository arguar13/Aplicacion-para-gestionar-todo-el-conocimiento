import 'package:fpdart/fpdart.dart';
import 'package:sinapsis/core/domain/entities/study_mark_kind.dart';
import 'package:sinapsis/core/error/failures.dart';
import 'package:sinapsis/features/study/domain/entities/document_study.dart';
import 'package:sinapsis/features/study/domain/services/study_reply.dart';

/// Dónde se guarda lo estudiado de cada texto (F36): las marcas y hasta dónde
/// se analizó (`study_marks`, `study_analyses`).
abstract interface class StudyRepository {
  /// Lo estudiado del texto de la forma [renditionId], y cada cambio.
  Stream<DocumentStudy> watch(String renditionId);

  /// Lo estudiado ahora, de una vez.
  Future<DocumentStudy> read(String renditionId);

  /// Guarda una parte analizada, `[partStart, partEnd)` de [content]: lo que
  /// la IA había marcado ahí se reemplaza por [marks] —lo que eligió la
  /// persona queda—, y el análisis llega hasta [partEnd]; con [completes],
  /// terminó.
  ///
  /// Va junto o no va: si el análisis se corta a mitad de una parte, al
  /// retomarla se rehace entera, sin duplicar nada.
  Future<Either<Failure, Unit>> savePart({
    required String renditionId,
    required String content,
    required int partStart,
    required int partEnd,
    required StudyPartMarks marks,
    required bool completes,
  });

  /// Agrega `[start, end)` de [content] como [kind] elegido por la persona
  /// (F36, F39): una oración del resumen o de la síntesis, o una palabra
  /// clave. Si ya estaba, no la duplica.
  Future<Either<Failure, Unit>> addUserMark({
    required String renditionId,
    required String content,
    required StudyMarkKind kind,
    required int start,
    required int end,
  });

  /// Saca la marca [markId], la haya puesto la IA o la persona.
  Future<Either<Failure, Unit>> removeMark(String markId);

  /// Borra lo que hizo la IA en el texto, para volver a analizarlo: sus
  /// marcas y hasta dónde llegó. Lo que eligió la persona queda (F39,
  /// decisión A).
  Future<Either<Failure, Unit>> clearAi(String renditionId);
}
