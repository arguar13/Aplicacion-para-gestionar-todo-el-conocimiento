import 'package:fpdart/fpdart.dart';
import 'package:sinapsis/core/error/failures.dart';
import 'package:sinapsis/features/study/domain/entities/document_study.dart';
import 'package:sinapsis/features/study/domain/services/study_reply.dart';
import 'package:sinapsis/features/study/domain/services/study_words.dart';

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

  /// Agrega [word] de [content] como palabra clave elegida por la persona.
  Future<Either<Failure, Unit>> addKeyword({
    required String renditionId,
    required String content,
    required StudyWord word,
  });

  /// Saca la palabra clave [markId], la haya puesto la IA o la persona.
  Future<Either<Failure, Unit>> removeKeyword(String markId);

  /// Borra todo lo estudiado del texto, para volver a analizarlo.
  Future<Either<Failure, Unit>> clear(String renditionId);
}
