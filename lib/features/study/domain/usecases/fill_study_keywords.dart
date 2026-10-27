import 'package:flutter/foundation.dart';
import 'package:sinapsis/core/domain/entities/study_mark_kind.dart';
import 'package:sinapsis/features/study/domain/repositories/study_repository.dart';
import 'package:sinapsis/features/study/domain/services/study_fallback_keywords.dart';
import 'package:sinapsis/features/study/domain/services/study_sentences.dart';
import 'package:sinapsis/features/study/domain/services/study_words.dart';
import 'package:sinapsis/features/study/domain/usecases/analyze_for_study.dart';

/// Lo que hay que mirar para completar las palabras clave de un texto: se
/// manda tal cual a otro hilo, así que solo lleva datos.
@immutable
class StudyFillJob {
  const StudyFillJob({
    required this.content,
    required this.markdown,
    required this.keywordRanges,
    required this.until,
  });

  final String content;
  final bool markdown;

  /// Los `[start, end)` de las palabras clave que ya hay, de la IA o de la
  /// persona.
  final List<(int, int)> keywordRanges;

  /// Hasta dónde llega lo analizado: las oraciones que empiezan antes.
  final int until;
}

/// Las palabras clave que le faltan a lo analizado de [job]: parte el texto
/// en oraciones, cuenta las palabras del documento y le pone el respaldo
/// local a cada oración con contenido que no tiene ninguna.
///
/// Función de nivel superior y sin estado: corre igual en este hilo o en otro.
List<StudyWord> missingKeywordsOfText(StudyFillJob job) {
  final sentences = [
    for (final sentence in splitStudySentences(
      job.content,
      markdown: job.markdown,
    ))
      if (sentence.start < job.until) sentence,
  ];
  if (sentences.isEmpty) return const [];
  return missingKeywords(
    content: job.content,
    sentences: sentences,
    keywordRanges: job.keywordRanges,
    stats: StudyWordStats.of(job.content),
  );
}

/// Quien corre [missingKeywordsOfText]: en la app, en otro hilo —un libro
/// entero son muchos caracteres para partir y contar en el de la pantalla—.
typedef StudyFillRunner = Future<List<StudyWord>> Function(StudyFillJob job);

/// Completa las palabras clave de un texto ya analizado (sin IA, sin red): a
/// cada oración con contenido que quedó sin ninguna le pone las que elige el
/// respaldo local.
///
/// Los textos analizados antes de que el análisis garantizara las palabras de
/// **todas** las oraciones —y los que perdieron palabras al volver a extraer
/// el texto o al restaurarse— quedan completos sin volver a pagar la IA. Es
/// idempotente: sobre un texto completo no agrega nada.
///
/// Mira hasta donde se analizó (`DocumentStudy.analyzedUntil`; todo, si
/// terminó): lo que falta analizar lo completa el propio análisis. Cuenta como
/// palabra clave de una oración la que eligió la persona.
class FillStudyKeywords {
  const FillStudyKeywords({
    required StudyRepository repository,
    StudyFillRunner? runner,
  }) : _repository = repository,
       _runner = runner ?? _inline;

  final StudyRepository _repository;
  final StudyFillRunner _runner;

  static Future<List<StudyWord>> _inline(StudyFillJob job) async =>
      missingKeywordsOfText(job);

  /// Completa [content] de la forma [renditionId]; devuelve cuántas palabras
  /// agregó. Un texto sin analizar no tiene nada que completar.
  Future<int> call({
    required String renditionId,
    required String content,
    required bool markdown,
  }) async {
    final study = await _repository.read(renditionId);
    if (!study.started) return 0;

    final missing = await _runner(
      StudyFillJob(
        content: content,
        markdown: markdown,
        keywordRanges: [
          for (final mark in study.of(StudyMarkKind.keyword))
            (mark.start, mark.end),
        ],
        until: study.complete ? content.length : study.analyzedUntil,
      ),
    );
    if (missing.isEmpty) return 0;

    final saved = await _repository.addAiKeywords(
      renditionId: renditionId,
      content: content,
      words: missing,
    );
    return saved.fold(
      (failure) => throw StudySaveException(failure.toString()),
      (_) => missing.length,
    );
  }
}
