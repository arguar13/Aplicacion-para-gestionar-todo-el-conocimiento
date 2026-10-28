import 'package:fpdart/fpdart.dart';
import 'package:sinapsis/core/domain/entities/study_mark_kind.dart';
import 'package:sinapsis/core/error/failures.dart';
import 'package:sinapsis/features/processed/domain/repositories/processed_repository.dart';
import 'package:sinapsis/features/processed/domain/services/processed_identity.dart';
import 'package:sinapsis/features/study/domain/entities/document_study.dart';
import 'package:sinapsis/features/study/domain/repositories/study_repository.dart';
import 'package:sinapsis/features/study/domain/services/study_reply.dart';
import 'package:sinapsis/features/study/domain/services/study_words.dart';

/// Lo estudiado de la copia del original de un documento procesado (F41,
/// decisión H), por su clave `procesado-original:…`: lo elegido del procesado
/// —su resumen, su síntesis y sus palabras clave—, como marcas de estudiar
/// (`ProcessedRepository.watchOriginalMarks`).
///
/// Así los visores de siempre pintan la copia con los colores de estudiar sin
/// saber de Procesado: la miran como cualquier texto, por su clave, y lo que
/// ven no se mezcla con lo estudiado de la fuente.
///
/// **Solo se lee.** Lo marcado sobre la copia sale de las secciones del
/// procesado: se cambia en ellas —editando, quitando, volviendo a triar—, no
/// sobre la copia. Cualquier escritura falla diciéndolo, y nada cae en la
/// fuente.
class ProcessedOriginalStudyRepository implements StudyRepository {
  const ProcessedOriginalStudyRepository(this._processed);

  final ProcessedRepository _processed;

  static const _readOnly = Failure.validation(
    message:
        'Lo marcado sobre la copia del original sale del documento '
        'procesado: se cambia en sus secciones.',
  );

  @override
  Stream<DocumentStudy> watch(String renditionId) {
    final documentId = processedDocumentOfOriginalStudyKey(renditionId);
    if (documentId == null) return Stream.value(DocumentStudy.notStarted);
    return _processed
        .watchOriginalMarks(documentId)
        .map((marks) => marks?.study ?? DocumentStudy.notStarted);
  }

  @override
  Future<DocumentStudy> read(String renditionId) => watch(renditionId).first;

  @override
  Future<Either<Failure, Unit>> savePart({
    required String renditionId,
    required String content,
    required int partStart,
    required int partEnd,
    required StudyPartMarks marks,
    required bool completes,
  }) async => left(_readOnly);

  @override
  Future<Either<Failure, Unit>> addAiKeywords({
    required String renditionId,
    required String content,
    required List<StudyWord> words,
  }) async => left(_readOnly);

  @override
  Future<Either<Failure, Unit>> addUserMark({
    required String renditionId,
    required String content,
    required StudyMarkKind kind,
    required int start,
    required int end,
  }) async => left(_readOnly);

  @override
  Future<Either<Failure, Unit>> removeMark(String markId) async =>
      left(_readOnly);

  @override
  Future<Either<Failure, Unit>> clearAi(String renditionId) async =>
      left(_readOnly);
}
