import 'package:flutter/material.dart';
import 'package:sinapsis/features/creations/report/domain/report.dart';
import 'package:sinapsis/features/creations/report/domain/report_markdown.dart';
import 'package:sinapsis/features/creations/report/domain/report_template.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// Los nombres de las plantillas y los formatos de un informe, y los textos
/// fijos de lo que se exporta, en el idioma de la app.
extension ReportLabels on AppLocalizations {
  String reportTemplateName(ReportTemplate template) => switch (template) {
    ReportTemplate.learningSummary => f43StudioOptLearningSummary,
    ReportTemplate.studyGuide => f43StudioOptStudyGuide,
    ReportTemplate.briefing => f43StudioOptBriefing,
    ReportTemplate.glossary => f43StudioOptGlossary,
    ReportTemplate.custom => f43ReportCustomLabel,
  };

  String reportTemplateHint(ReportTemplate template) => switch (template) {
    ReportTemplate.learningSummary => f43ReportTemplateLearningHint,
    ReportTemplate.studyGuide => f43ReportTemplateStudyGuideHint,
    ReportTemplate.briefing => f43ReportTemplateBriefingHint,
    ReportTemplate.glossary => f43ReportTemplateGlossaryHint,
    ReportTemplate.custom => f43ReportTemplateCustomHint,
  };

  String reportFormatName(ReportFormat format) => switch (format) {
    ReportFormat.interactive => f43StudioOptInteractive,
    ReportFormat.document => f43StudioOptDocument,
  };

  /// «Guía de estudio · Interactivo».
  String reportKicker(ReportTemplate template, ReportFormat format) =>
      f43ReportKicker(reportTemplateName(template), reportFormatName(format));

  /// El título de la sección [index] (desde 0) de [report].
  String reportSectionTitle(Report report, int index) {
    final title = report.sections[index].title.trim();
    return title.isEmpty ? f43ReportUntitledSection(index + 1) : title;
  }

  /// Los textos de lo exportado: arriba, la plantilla y el formato; abajo,
  /// las fuentes ([sourceTitles]) y el número de página.
  ReportExportLabels reportExportLabels({
    required ReportTemplate template,
    required ReportFormat format,
    List<String> sourceTitles = const [],
  }) => ReportExportLabels(
    kicker: reportKicker(template, format),
    untitledSection: f43ReportUntitledSection,
    questions: f43ReportQuestionsTitle,
    answerKey: f43ReportAnswerKey,
    sources: sourceTitles.isEmpty
        ? ''
        : f43ReportSourcesLine(sourceTitles.join(', ')),
    page: f43ReportPage,
  );
}

/// El ícono de cada plantilla, en su tarjeta.
IconData reportTemplateIcon(ReportTemplate template) => switch (template) {
  ReportTemplate.learningSummary => Icons.lightbulb_outline,
  ReportTemplate.studyGuide => Icons.school_outlined,
  ReportTemplate.briefing => Icons.article_outlined,
  ReportTemplate.glossary => Icons.sort_by_alpha,
  ReportTemplate.custom => Icons.edit_outlined,
};
