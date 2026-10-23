import 'package:flutter/foundation.dart';
import 'package:sinapsis/features/study/domain/repositories/study_repository.dart';
import 'package:sinapsis/features/study/domain/services/study_marker.dart';
import 'package:sinapsis/features/study/domain/services/study_reply.dart';
import 'package:sinapsis/features/study/domain/services/study_sentences.dart';

/// Cómo va el análisis de un documento (F36): cuántas partes van y cuántas
/// son en total, y cuántas no se pudieron leer.
@immutable
class StudyProgress {
  const StudyProgress({
    required this.partsDone,
    required this.partsTotal,
    this.unreadParts = 0,
  });

  final int partsDone;

  /// Las que van más las que faltan, con el tamaño de parte de ahora: si una
  /// parte no entra entera, se achica y el total crece.
  final int partsTotal;

  /// Las partes en que el modelo no contestó en el formato, ni al
  /// reintentarlo: quedan analizadas sin nada marcado, para no trabarse en
  /// ellas.
  final int unreadParts;

  bool get finished => partsDone >= partsTotal;

  /// Cuánto va, de 0 a 100 (F39): las partes hechas sobre el total de ahora.
  /// Sin saber todavía cuántas son, 0.
  int get percent =>
      partsTotal <= 0 ? 0 : (partsDone * 100 ~/ partsTotal).clamp(0, 100);

  @override
  bool operator ==(Object other) =>
      other is StudyProgress &&
      other.partsDone == partsDone &&
      other.partsTotal == partsTotal &&
      other.unreadParts == unreadParts;

  @override
  int get hashCode => Object.hash(partsDone, partsTotal, unreadParts);

  @override
  String toString() => 'StudyProgress($partsDone/$partsTotal, $unreadParts)';
}

/// Lo que no se pudo guardar de una parte analizada.
class StudySaveException implements Exception {
  const StudySaveException(this.message);

  final String message;

  @override
  String toString() => 'StudySaveException: $message';
}

/// Analiza para estudiar lo que falta de un texto (F36): por partes, en orden
/// y desde donde quedó la vez anterior.
///
/// Cada parte se guarda al terminar (`StudyRepository.savePart`), así que lo
/// marcado aparece a medida que se analiza y, si se corta, no se pierde nada
/// de lo hecho. Una parte en que el modelo no contesta en el formato se
/// reintenta una vez; si tampoco, queda analizada sin marcas —para no volver
/// a gastar en ella cada vez— y se cuenta en [StudyProgress.unreadParts].
class AnalyzeForStudy {
  const AnalyzeForStudy({
    required StudyRepository repository,
    required StudyMarker marker,
  }) : _repository = repository,
       _marker = marker;

  final StudyRepository _repository;
  final StudyMarker _marker;

  /// Analiza el texto [content] de la forma [renditionId] y avisa cómo va
  /// después de cada parte. Entre parte y parte mira [shouldStop]: si dice
  /// que sí, termina ahí, con lo hecho guardado.
  Stream<StudyProgress> call({
    required String renditionId,
    required String content,
    required bool markdown,
    bool Function()? shouldStop,
  }) async* {
    final sentences = splitStudySentences(content, markdown: markdown);
    final study = await _repository.read(renditionId);
    if (study.complete) return;

    var next = sentences.indexWhere((s) => s.start >= study.analyzedUntil);
    if (next < 0) next = sentences.length;
    final budget = _marker.partCharBudget;
    var done = 0;
    var unread = 0;

    if (next == sentences.length) {
      // Nada más que analizar —un texto sin oraciones, o lo que faltaba se
      // fue al volver a extraer—: queda terminado.
      await _save(
        renditionId,
        content,
        start: study.analyzedUntil.clamp(0, content.length),
        end: study.analyzedUntil.clamp(0, content.length),
        marks: _nothing,
        completes: true,
      );
      yield const StudyProgress(partsDone: 0, partsTotal: 0);
      return;
    }

    // Antes de la primera parte, para que se vea cuántas son desde el
    // principio y no recién cuando termina una.
    yield StudyProgress(
      partsDone: 0,
      partsTotal: _partsLeft(sentences, next, budget),
    );

    while (next < sentences.length) {
      if (shouldStop?.call() ?? false) return;

      final end = studyPartEnd(sentences, next, charBudget: budget);
      final part = sentences.sublist(next, end);

      var outcome = await _marker.markPart(content: content, part: part);
      if (outcome.marks == null) {
        outcome = await _marker.markPart(
          content: content,
          part: part.sublist(0, outcome.analyzed.clamp(1, part.length)),
        );
      }
      final analyzed = outcome.analyzed.clamp(1, part.length);
      final marks = outcome.marks;
      if (marks == null) unread++;

      final last = next + analyzed;
      await _save(
        renditionId,
        content,
        start: sentences[next].start,
        end: sentences[last - 1].end,
        marks: marks ?? _nothing,
        completes: last == sentences.length,
      );
      done++;
      next = last;
      yield StudyProgress(
        partsDone: done,
        partsTotal: done + _partsLeft(sentences, next, budget),
        unreadParts: unread,
      );
    }
  }

  static const _nothing = StudyPartMarks(
    summary: [],
    synthesis: [],
    keywords: [],
  );

  Future<void> _save(
    String renditionId,
    String content, {
    required int start,
    required int end,
    required StudyPartMarks marks,
    required bool completes,
  }) async {
    final saved = await _repository.savePart(
      renditionId: renditionId,
      content: content,
      partStart: start,
      partEnd: end,
      marks: marks,
      completes: completes,
    );
    saved.fold(
      (failure) => throw StudySaveException(failure.toString()),
      (_) {},
    );
  }

  /// Cuántas partes quedan desde la oración [from], con [budget].
  static int _partsLeft(List<StudySentence> sentences, int from, int budget) {
    var parts = 0;
    var next = from;
    while (next < sentences.length) {
      next = studyPartEnd(sentences, next, charBudget: budget);
      parts++;
    }
    return parts;
  }
}
