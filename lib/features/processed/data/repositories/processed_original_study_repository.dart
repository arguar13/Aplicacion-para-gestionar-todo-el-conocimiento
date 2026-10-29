import 'package:fpdart/fpdart.dart';
import 'package:sinapsis/core/domain/entities/study_mark_kind.dart';
import 'package:sinapsis/core/error/failures.dart';
import 'package:sinapsis/features/processed/domain/entities/processed_part.dart';
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
/// **En el original se marca** (F43, paso 15, decisión J). Elegir a mano una
/// oración o una palabra sobre la copia —tocándola en el visor, o desde los
/// botones de estudio— es elegirla en el procesado: la posición en el texto
/// de la fuente se lleva a la del texto propio del documento
/// (`ProcessedStudyLayout.ownOf`) y se guarda con [_study], el repositorio de
/// las claves `procesado:…` (decisión I), como cualquier marca del procesado.
/// Sacar una marca y borrar las de una clase, igual. Lo que no está en el
/// texto propio letra por letra —una página que se editó— no tiene dónde
/// guardarse, y falla diciéndolo.
///
/// El análisis con la IA no corre sobre esta clave sino sobre la del texto
/// propio (`processedStudyKeyFor`): lo que marca aparece acá solo, porque cada
/// marca del procesado lleva su lugar en la fuente. Por eso [savePart] y
/// [addAiKeywords] no se aceptan. Nada cae nunca en la fuente.
class ProcessedOriginalStudyRepository implements StudyRepository {
  const ProcessedOriginalStudyRepository(this._processed, this._study);

  final ProcessedRepository _processed;

  /// Donde se guarda lo estudiado del texto propio del procesado.
  final StudyRepository _study;

  static const _analyzedElsewhere = Failure.validation(
    message:
        'El original de un documento procesado se analiza por el texto '
        'propio del documento.',
  );

  static const _notOwnText = Failure.validation(
    message:
        'Esa parte del original no está en el texto del documento procesado.',
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
  }) async => left(_analyzedElsewhere);

  @override
  Future<Either<Failure, Unit>> addAiKeywords({
    required String renditionId,
    required String content,
    required List<StudyWord> words,
  }) async => left(_analyzedElsewhere);

  /// Lo elegido en `[start, end)` del original, guardado en el procesado: ver
  /// la clase.
  @override
  Future<Either<Failure, Unit>> addUserMark({
    required String renditionId,
    required String content,
    required StudyMarkKind kind,
    required int start,
    required int end,
  }) async {
    final documentId = processedDocumentOfOriginalStudyKey(renditionId);
    if (documentId == null) return left(_notOwnText);
    final marks = await _processed.watchOriginalMarks(documentId).first;
    if (marks == null) return left(_notOwnText);
    return (await _processed.studyTextOf(documentId)).match(
      (failure) async => left(failure),
      (own) async {
        final place = own?.layout.ownOf(
          ProcessedAnchor(renditionId: marks.sourceKey, start: start, end: end),
        );
        if (own == null || place == null) return left(_notOwnText);
        return _study.addUserMark(
          renditionId: own.key,
          content: own.content,
          kind: kind,
          start: place.start,
          end: place.end,
        );
      },
    );
  }

  /// Las marcas del original son partes del procesado, con su mismo id —con
  /// el prefijo del procesado, así el repositorio de la app las manda directo
  /// allá (`KeyedStudyRepository.removeMark`)—.
  @override
  Future<Either<Failure, Unit>> removeMark(String markId) => _study.removeMark(
    markId.startsWith(kProcessedStudyKeyPrefix)
        ? markId
        : '$kProcessedStudyKeyPrefix$markId',
  );

  @override
  Future<Either<Failure, Unit>> clearAi(String renditionId) {
    final documentId = processedDocumentOfOriginalStudyKey(renditionId);
    if (documentId == null) return Future.value(left(_notOwnText));
    return _study.clearAi(processedStudyKeyFor(documentId));
  }

  @override
  Future<Either<Failure, Unit>> clearKind(
    String renditionId,
    StudyMarkKind kind,
  ) {
    final documentId = processedDocumentOfOriginalStudyKey(renditionId);
    if (documentId == null) return Future.value(left(_notOwnText));
    return _study.clearKind(processedStudyKeyFor(documentId), kind);
  }
}
