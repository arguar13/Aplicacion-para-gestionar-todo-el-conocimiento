import 'package:flutter/foundation.dart';
import 'package:sinapsis/core/domain/entities/highlight.dart';
import 'package:sinapsis/core/domain/entities/highlight_color.dart';
import 'package:sinapsis/core/domain/entities/highlight_style.dart';
import 'package:sinapsis/core/domain/entities/study_mark_kind.dart';
import 'package:sinapsis/features/export/domain/entities/document_mark.dart';
import 'package:sinapsis/features/export/domain/entities/marked_document_options.dart';
import 'package:sinapsis/features/study/domain/entities/document_study.dart';
import 'package:sinapsis/features/study/domain/services/study_layers.dart';

/// Los colores con que se marca el documento que se descarga (F38), en ARGB.
///
/// Son datos y no la paleta de la pantalla porque el dominio no conoce
/// Flutter: quien arma el caso de uso los saca de `StudyPalette` y de
/// `HighlightPalette`, en su tema claro —el papel es blanco, también si la
/// app está en modo oscuro—.
@immutable
class DocumentMarkColors {
  const DocumentMarkColors({
    required this.summary,
    required this.synthesis,
    required this.keyword,
    required this.highlights,
    required this.defaultHighlight,
    required this.underlines,
    required this.defaultUnderline,
  });

  final int summary;
  final int synthesis;
  final int keyword;

  /// El tono de cada color del resaltador a mano, de fondo.
  final Map<HighlightColor, int> highlights;

  /// El de un resaltado sin color elegido —todos los de antes de F38—: el de
  /// siempre, el que tiene en la pantalla con el tema claro.
  final int defaultHighlight;

  /// La línea de cada color, subrayado: más oscura que el tono, que como
  /// línea fina sobre el papel casi no se vería.
  final Map<HighlightColor, int> underlines;

  /// La de un subrayado sin color elegido.
  final int defaultUnderline;

  /// El color de un resaltado de [color] con [style].
  int highlightOf(
    HighlightColor? color, [
    HighlightStyle style = HighlightStyle.fill,
  ]) => switch (style) {
    HighlightStyle.fill =>
      color == null ? defaultHighlight : highlights[color] ?? defaultHighlight,
    HighlightStyle.underline =>
      color == null ? defaultUnderline : underlines[color] ?? defaultUnderline,
  };
}

/// Los tramos para marcar en el documento, en el orden de las capas (F38).
///
/// De abajo hacia arriba, porque un escritor deja ganar al que viene después
/// en la lista cuando dos se pisan:
///
/// 1. las oraciones del resumen y, encima, las de la síntesis;
/// 2. lo que la persona subrayó, el más reciente arriba;
/// 3. las palabras clave —igual que en la pantalla: el resaltador a mano
///    queda debajo de ellas—.
///
/// Las palabras clave son las de las oraciones que se marcan: con el resumen,
/// las de las oraciones del resumen; con la síntesis, las de la síntesis; con
/// solo las palabras clave, las de las dos (es lo que muestra el original con
/// ese botón prendido, ver `studyPaints`).
///
/// Un tramo que ya no cabe en [content] —un subrayado de un texto que se
/// volvió a extraer— no se puede ubicar y se deja afuera.
List<DocumentMark> buildDocumentMarks({
  required String content,
  required MarkedDocumentOptions options,
  required DocumentStudy study,
  required List<Highlight> highlights,
  required DocumentMarkColors colors,
}) {
  DocumentMark? fromStudy(StudyMark mark, int color) =>
      _fits(content, mark.start, mark.end)
      ? DocumentMark(
          start: mark.start,
          end: mark.end,
          excerpt: content.substring(mark.start, mark.end),
          color: color,
        )
      : null;

  final sentenceKinds = {
    if (options.summary) StudyMarkKind.summary,
    if (options.synthesis) StudyMarkKind.synthesis,
  };
  // Los resaltados de oraciones, una capa por tipo y no mezclados por
  // posición: la oración que está en el resumen y en la síntesis tiene las
  // dos marcas, y la de la síntesis tiene que quedar arriba.
  final sentences = [
    if (options.summary)
      for (final mark in studySentenceMarks(study, {StudyMarkKind.summary}))
        ?fromStudy(mark, colors.summary),
    if (options.synthesis)
      for (final mark in studySentenceMarks(study, {StudyMarkKind.synthesis}))
        ?fromStudy(mark, colors.synthesis),
  ];

  final mine = options.myHighlights
      ? ([...highlights]..sort(_oldestFirst))
            .where((h) => _fits(content, h.startOffset, h.endOffset))
            .map(
              (h) => DocumentMark(
                start: h.startOffset,
                end: h.endOffset,
                excerpt: h.excerpt,
                color: colors.highlightOf(h.color, h.style),
                style: h.style,
                note: h.note,
              ),
            )
            .toList()
      : const <DocumentMark>[];

  final keywords = options.keywords
      ? [
          for (final mark in studyKeywordMarksWithin(
            study,
            studySentenceMarks(
              study,
              sentenceKinds.isEmpty
                  ? const {StudyMarkKind.summary, StudyMarkKind.synthesis}
                  : sentenceKinds,
            ),
          ))
            ?fromStudy(mark, colors.keyword),
        ]
      : const <DocumentMark>[];

  return [...sentences, ...mine, ...keywords];
}

/// Qué de las cuatro cosas que se pueden marcar hay para marcar: un resumen
/// sin analizar, un documento sin palabras clave o sin subrayados no tiene
/// qué ofrecer.
MarkedDocumentOptions availableMarkedOptions({
  required String content,
  required DocumentStudy study,
  required List<Highlight> highlights,
}) {
  bool has(StudyMarkKind kind) =>
      study.of(kind).any((mark) => _fits(content, mark.start, mark.end));
  return MarkedDocumentOptions(
    summary: has(StudyMarkKind.summary),
    synthesis: has(StudyMarkKind.synthesis),
    keywords: has(StudyMarkKind.keyword),
    myHighlights: highlights.any(
      (h) => _fits(content, h.startOffset, h.endOffset),
    ),
  );
}

bool _fits(String content, int start, int end) =>
    start >= 0 && end > start && end <= content.length;

/// Por cuándo se hicieron, y a igual hora, por dónde empiezan: que el orden
/// no dependa de cómo los entregó la base.
int _oldestFirst(Highlight a, Highlight b) {
  final byTime = a.createdAt.compareTo(b.createdAt);
  return byTime != 0 ? byTime : a.startOffset.compareTo(b.startOffset);
}
