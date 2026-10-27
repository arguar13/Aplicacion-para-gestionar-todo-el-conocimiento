import 'package:fpdart/fpdart.dart';
import 'package:sinapsis/core/domain/entities/study_mark_kind.dart';
import 'package:sinapsis/core/error/failures.dart';
import 'package:sinapsis/features/study/domain/entities/document_study.dart';
import 'package:sinapsis/features/study/domain/repositories/study_repository.dart';
import 'package:sinapsis/features/study/domain/services/study_reply.dart';
import 'package:sinapsis/features/study/domain/services/study_words.dart';

/// Un [StudyRepository] que reparte cada pedido según la clave del texto
/// (`renditionId`) y el id de la marca: lo que empieza con uno de los prefijos
/// de `byPrefix` va a ese repositorio; lo demás, a `fallback`.
///
/// Es la costura que deja que la máquina de estudiar de siempre (F36, F39)
/// estudie también lo que no es una forma de la Biblioteca —el texto propio de
/// un documento procesado (F41, decisión I), con su clave `procesado:…`— sin
/// enterarse: la tarjeta, el análisis por partes, el respaldo de las palabras
/// clave y «Elegir a mano» hablan con un solo repositorio, y cada texto guarda
/// lo suyo donde le corresponde.
class KeyedStudyRepository implements StudyRepository {
  const KeyedStudyRepository({
    required StudyRepository fallback,
    required Map<String, StudyRepository> byPrefix,
  }) : _fallback = fallback,
       _byPrefix = byPrefix;

  final StudyRepository _fallback;
  final Map<String, StudyRepository> _byPrefix;

  StudyRepository _for(String key) {
    for (final MapEntry(key: prefix, value: repository) in _byPrefix.entries) {
      if (key.startsWith(prefix)) return repository;
    }
    return _fallback;
  }

  @override
  Stream<DocumentStudy> watch(String renditionId) =>
      _for(renditionId).watch(renditionId);

  @override
  Future<DocumentStudy> read(String renditionId) =>
      _for(renditionId).read(renditionId);

  @override
  Future<Either<Failure, Unit>> savePart({
    required String renditionId,
    required String content,
    required int partStart,
    required int partEnd,
    required StudyPartMarks marks,
    required bool completes,
  }) => _for(renditionId).savePart(
    renditionId: renditionId,
    content: content,
    partStart: partStart,
    partEnd: partEnd,
    marks: marks,
    completes: completes,
  );

  @override
  Future<Either<Failure, Unit>> addAiKeywords({
    required String renditionId,
    required String content,
    required List<StudyWord> words,
  }) => _for(
    renditionId,
  ).addAiKeywords(renditionId: renditionId, content: content, words: words);

  @override
  Future<Either<Failure, Unit>> addUserMark({
    required String renditionId,
    required String content,
    required StudyMarkKind kind,
    required int start,
    required int end,
  }) => _for(renditionId).addUserMark(
    renditionId: renditionId,
    content: content,
    kind: kind,
    start: start,
    end: end,
  );

  /// Una marca va al repositorio cuyo prefijo lleva su id: las de un texto que
  /// no es de la Biblioteca lo llevan (`kProcessedStudyMarkPrefix`).
  @override
  Future<Either<Failure, Unit>> removeMark(String markId) =>
      _for(markId).removeMark(markId);

  @override
  Future<Either<Failure, Unit>> clearAi(String renditionId) =>
      _for(renditionId).clearAi(renditionId);
}
