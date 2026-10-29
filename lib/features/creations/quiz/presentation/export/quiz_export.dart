import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:sinapsis/core/storage/file_store.dart';
import 'package:sinapsis/features/creations/domain/entities/study_creation.dart';
import 'package:sinapsis/features/creations/flashcards/presentation/export/study_pdf.dart';
import 'package:sinapsis/features/creations/flashcards/presentation/widgets/study_viewer_parts.dart';
import 'package:sinapsis/features/creations/presentation/creation_presentation.dart';
import 'package:sinapsis/features/creations/presentation/kinds/creation_kind_spec.dart';
import 'package:sinapsis/features/creations/quiz/domain/quiz.dart';
import 'package:sinapsis/features/creations/quiz/presentation/widgets/quiz_parts.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// En qué se descarga un cuestionario.
enum QuizExportFormat { pdf, markdown }

/// «Descargar» del «Cuestionario» (F43, paso 8): pregunta el formato —PDF o
/// Markdown— y arma el archivo: las preguntas para responder y, al final, las
/// respuestas con su porqué. `null` si se cerró la hoja.
Future<CreationExportFile?> exportQuiz(
  BuildContext context,
  WidgetRef ref,
  StudyCreation creation,
) async {
  final l10n = AppLocalizations.of(context)!;
  final format = await showStudyExportChoices<QuizExportFormat>(
    context,
    title: l10n.f43QuizExportTitle,
    choices: [
      StudyExportChoice(
        value: QuizExportFormat.pdf,
        icon: Icons.picture_as_pdf_outlined,
        title: l10n.f43QuizExportPdf,
        subtitle: l10n.f43QuizExportPdfHint,
      ),
      StudyExportChoice(
        value: QuizExportFormat.markdown,
        icon: Icons.notes,
        title: l10n.f43QuizExportMarkdown,
        subtitle: l10n.f43QuizExportMarkdownHint,
      ),
    ],
  );
  if (format == null) return null;
  return quizFile(
    QuizJson.decode(creation.decodedContent),
    format: format,
    title: studyCreationTitle(l10n, creation),
    labels: QuizExportLabels.of(l10n),
  );
}

/// Los textos de los archivos del cuestionario, en el idioma de la app.
@immutable
class QuizExportLabels {
  const QuizExportLabels({
    required this.count,
    required this.answers,
    required this.allThatApply,
    required this.why,
    required this.type,
    required this.page,
  });

  factory QuizExportLabels.of(AppLocalizations l10n) => QuizExportLabels(
    count: l10n.f43QuizCount,
    answers: l10n.f43QuizAnswerKey,
    allThatApply: l10n.f43QuizAllThatApply,
    why: l10n.f43QuizExplanation,
    type: (type) => quizTypeLabel(l10n, type),
    page: l10n.f43QuizPdfPage,
  );

  final String Function(int count) count;
  final String answers;
  final String allThatApply;
  final String why;
  final String Function(QuizQuestionType type) type;
  final String Function(int page, int pages) page;
}

/// El archivo de [quiz] en [format], con [title] de nombre.
Future<CreationExportFile> quizFile(
  Quiz quiz, {
  required QuizExportFormat format,
  required String title,
  required QuizExportLabels labels,
  AssetBundle? bundle,
}) async {
  final name = sanitizeFileName(title.isEmpty ? 'Cuestionario' : title);
  return switch (format) {
    QuizExportFormat.markdown => CreationExportFile(
      fileName: '$name.md',
      bytes: Uint8List.fromList(
        utf8.encode(quizMarkdown(quiz, title: title, labels: labels)),
      ),
      mimeType: 'text/markdown',
    ),
    QuizExportFormat.pdf => CreationExportFile(
      fileName: '$name.pdf',
      bytes: await quizPdf(quiz, title: title, labels: labels, bundle: bundle),
      mimeType: 'application/pdf',
    ),
  };
}

/// La pregunta como se escribe en un archivo: el espacio de completar, como
/// una raya larga.
String _promptOf(QuizQuestion question) =>
    question.prompt.replaceAll(kQuizBlank, '________');

/// « (todas las que correspondan)» en una de selección múltiple.
String _applyOf(QuizQuestion question, QuizExportLabels labels) =>
    question.type == QuizQuestionType.multiple ? ' ${labels.allThatApply}' : '';

/// Lo que dice la clave de respuestas de [question].
List<String> _keyOf(QuizQuestion question) => question.type.hasOptions
    ? [
        for (final (i, option) in question.options.indexed)
          if (option.correct) '${quizLetter(i)}. ${option.text}',
      ]
    : [question.answer];

/// El cuestionario en Markdown: las preguntas con sus opciones y, al final,
/// las respuestas con la explicación de cada opción.
String quizMarkdown(
  Quiz quiz, {
  required String title,
  required QuizExportLabels labels,
}) {
  final buffer = StringBuffer('# $title\n\n')
    ..writeln(labels.count(quiz.questions.length))
    ..writeln();
  for (final (n, question) in quiz.questions.indexed) {
    final apply = _applyOf(question, labels);
    buffer
      ..writeln('## ${n + 1}. ${_promptOf(question)}$apply')
      ..writeln()
      ..writeln('*${labels.type(question.type)}*')
      ..writeln();
    for (final (i, option) in question.options.indexed) {
      buffer.writeln('- ${quizLetter(i)}. ${option.text}');
    }
    if (question.options.isNotEmpty) buffer.writeln();
  }
  buffer
    ..writeln('---')
    ..writeln()
    ..writeln('## ${labels.answers}')
    ..writeln();
  for (final (n, question) in quiz.questions.indexed) {
    buffer.writeln('**${n + 1}.** ${_keyOf(question).join(' · ')}');
    for (final alternative in question.alternatives) {
      buffer.writeln('  - $alternative');
    }
    for (final (i, option) in question.options.indexed) {
      if (option.explanation.isEmpty) continue;
      final mark = option.correct ? '✓' : '✗';
      buffer.writeln('  - $mark ${quizLetter(i)}: ${option.explanation}');
    }
    if (question.explanation.isNotEmpty) {
      buffer.writeln('  - ${labels.why}: ${question.explanation}');
    }
    buffer.writeln();
  }
  return buffer.toString();
}

/// El cuestionario en PDF: para responder en papel, con las respuestas al
/// final.
Future<Uint8List> quizPdf(
  Quiz quiz, {
  required String title,
  required QuizExportLabels labels,
  AssetBundle? bundle,
}) => buildStudyPdf(
  title: title,
  subtitle: labels.count(quiz.questions.length),
  pageLabel: labels.page,
  bundle: bundle,
  build: () => [
    for (final (n, question) in quiz.questions.indexed) ...[
      pw.Text(
        labels.type(question.type).toUpperCase(),
        style: const pw.TextStyle(
          fontSize: 8,
          color: kStudyPdfMuted,
          letterSpacing: 0.8,
        ),
      ),
      pw.SizedBox(height: 2),
      pw.Text(
        '${n + 1}. ${_promptOf(question)}${_applyOf(question, labels)}',
        style: const pw.TextStyle(fontSize: 12.5, lineSpacing: 2),
      ),
      pw.SizedBox(height: 6),
      if (question.type.hasOptions)
        for (final (i, option) in question.options.indexed)
          pw.Padding(
            padding: const pw.EdgeInsets.only(left: 12, bottom: 3),
            child: pw.Text(
              '${quizLetter(i)}.  ${option.text}',
              style: const pw.TextStyle(fontSize: 11, lineSpacing: 2),
            ),
          )
      else
        pw.Container(
          height: question.type == QuizQuestionType.shortAnswer ? 54 : 22,
          decoration: const pw.BoxDecoration(
            border: pw.Border(
              bottom: pw.BorderSide(color: kStudyPdfLine, width: 0.8),
            ),
          ),
        ),
      pw.SizedBox(height: 14),
    ],
    pw.NewPage(),
    pw.Text(labels.answers, style: const pw.TextStyle(fontSize: 18)),
    pw.SizedBox(height: 10),
    for (final (n, question) in quiz.questions.indexed) ...[
      pw.Text(
        '${n + 1}. ${_keyOf(question).join(' · ')}',
        style: const pw.TextStyle(fontSize: 11.5, color: kStudyPdfGood),
      ),
      for (final (i, option) in question.options.indexed)
        if (option.explanation.isNotEmpty)
          pw.Padding(
            padding: const pw.EdgeInsets.only(left: 12, top: 2),
            child: pw.Text(
              '${quizLetter(i)}: ${option.explanation}',
              style: const pw.TextStyle(fontSize: 9.5, color: kStudyPdfMuted),
            ),
          ),
      if (question.explanation.isNotEmpty)
        pw.Padding(
          padding: const pw.EdgeInsets.only(left: 12, top: 2),
          child: pw.Text(
            '${labels.why}: ${question.explanation}',
            style: const pw.TextStyle(fontSize: 9.5, color: kStudyPdfMuted),
          ),
        ),
      pw.SizedBox(height: 8),
    ],
  ],
);
