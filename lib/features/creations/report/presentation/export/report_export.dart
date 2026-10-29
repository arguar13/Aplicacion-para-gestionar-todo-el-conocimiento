import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/core/storage/file_store.dart';
import 'package:sinapsis/features/creations/design/creation_controls.dart';
import 'package:sinapsis/features/creations/domain/entities/study_creation.dart';
import 'package:sinapsis/features/creations/presentation/creation_presentation.dart';
import 'package:sinapsis/features/creations/presentation/kinds/creation_kind_spec.dart';
import 'package:sinapsis/features/creations/presentation/providers/repasar_providers.dart';
import 'package:sinapsis/features/creations/report/domain/report_json.dart';
import 'package:sinapsis/features/creations/report/domain/report_keywords.dart';
import 'package:sinapsis/features/creations/report/domain/report_markdown.dart';
import 'package:sinapsis/features/creations/report/domain/report_template.dart';
import 'package:sinapsis/features/creations/report/presentation/export/report_pdf_exporter.dart';
import 'package:sinapsis/features/creations/report/presentation/providers/report_providers.dart';
import 'package:sinapsis/features/creations/report/presentation/report_labels.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// En qué se descarga un informe.
enum ReportFileFormat { pdf, markdown }

/// Pregunta en qué descargar un informe: PDF —para leer o imprimir, con el
/// rosa— o Markdown —para Obsidian u otro editor, con la negrita—. `null` si
/// se cerró sin elegir.
Future<ReportFileFormat?> askReportFileFormat(BuildContext context) =>
    showModalBottomSheet<ReportFileFormat>(
      context: context,
      showDragHandle: true,
      useSafeArea: true,
      builder: (context) {
        final l10n = AppLocalizations.of(context)!;
        return SingleChildScrollView(
          key: const Key('report-export-sheet'),
          padding: const EdgeInsets.fromLTRB(8, 0, 8, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 4, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        l10n.f43ReportDownload,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ),
                    CreationCloseButton(tooltip: l10n.f43StudioClose),
                  ],
                ),
              ),
              ListTile(
                key: const Key('report-export-pdf'),
                leading: const Icon(Icons.picture_as_pdf_outlined),
                title: Text(l10n.f43ReportExportPdf),
                subtitle: Text(l10n.f43ReportExportPdfHint),
                onTap: () => Navigator.of(context).pop(ReportFileFormat.pdf),
              ),
              ListTile(
                key: const Key('report-export-markdown'),
                leading: const Icon(Icons.notes),
                title: Text(l10n.f43ReportExportMarkdown),
                subtitle: Text(l10n.f43ReportExportMarkdownHint),
                onTap: () =>
                    Navigator.of(context).pop(ReportFileFormat.markdown),
              ),
            ],
          ),
        );
      },
    );

/// Quien arma el PDF de los informes: el de verdad, o uno de prueba.
final reportPdfExporterProvider = Provider<ReportPdfExporter>(
  (ref) => const ReportPdfExporter(),
);

/// El archivo de un informe para «Descargar» y «Compartir»
/// (`CreationKindSpec.exporter`): pregunta en qué formato y lo arma con las
/// palabras clave que se ven en el visor —si está abierto y se apagaron, no
/// van—.
Future<CreationExportFile?> exportReport(
  BuildContext context,
  WidgetRef ref,
  StudyCreation creation,
) async {
  final l10n = AppLocalizations.of(context)!;
  final format = await askReportFileFormat(context);
  if (format == null) return null;
  return buildReportFile(ref, l10n, creation, format);
}

/// El archivo de [creation] en [format], sin preguntar.
Future<CreationExportFile> buildReportFile(
  WidgetRef ref,
  AppLocalizations l10n,
  StudyCreation creation,
  ReportFileFormat format,
) async {
  final report = ReportJson.decode(creation.content);
  final template = ReportTemplate.of(creation.options);
  final reportFormat = ReportFormat.of(creation.options);
  final sources = CreationSourceIds(creation.sourceIds);

  final byDefault = ref.read(reportKeywordsShownByDefaultProvider(sources));
  final shown =
      ref.read(reportReadingProvider(creation.id)).keywords ?? byDefault;
  var keywords = ReportKeywords.empty;
  if (shown) {
    final fromSources = await _settled(
      ref,
      reportSourceKeywordsProvider(sources).future,
    );
    keywords = ReportKeywords(
      fromSources.isNotEmpty ? fromSources : report.keywords,
    );
  }
  final described = await _settled(
    ref,
    creationSourcesProvider(sources).future,
  );
  final labels = l10n.reportExportLabels(
    template: template,
    format: reportFormat,
    sourceTitles: [
      for (final source in described)
        if (source.isLive) source.title,
    ],
  );
  final interactive = reportFormat == ReportFormat.interactive;
  final name = sanitizeFileName(
    report.title.isNotEmpty ? report.title : studyCreationTitle(l10n, creation),
  );
  switch (format) {
    case ReportFileFormat.pdf:
      final bytes = await ref
          .read(reportPdfExporterProvider)
          .export(
            report: report,
            keywords: keywords,
            interactive: interactive,
            labels: labels,
          );
      return CreationExportFile(
        fileName: '$name.pdf',
        bytes: bytes,
        mimeType: 'application/pdf',
      );
    case ReportFileFormat.markdown:
      final text = reportToMarkdown(
        report,
        keywords: keywords,
        interactive: interactive,
        labels: labels,
      );
      return CreationExportFile(
        fileName: '$name.md',
        bytes: utf8.encode(text),
        mimeType: 'text/markdown',
      );
  }
}

/// Lo que da [future] —de un proveedor que se descarta solo—, escuchándolo
/// mientras tanto: leído sin escuchar, se descartaría antes de terminar.
Future<T> _settled<T>(
  WidgetRef ref,
  ProviderListenable<Future<T>> future,
) async {
  final subscription = ref.listenManual(future, (_, _) {});
  try {
    return await subscription.read();
  } finally {
    subscription.close();
  }
}
