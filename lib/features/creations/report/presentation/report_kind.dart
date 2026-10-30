import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/features/creations/domain/entities/study_creation_kind.dart';
import 'package:sinapsis/features/creations/domain/services/creation_generator.dart';
import 'package:sinapsis/features/creations/presentation/kinds/creation_kind_spec.dart';
import 'package:sinapsis/features/creations/presentation/kinds/default_creation_kinds.dart';
import 'package:sinapsis/features/creations/report/domain/report_generator.dart';
import 'package:sinapsis/features/creations/report/domain/report_template.dart';
import 'package:sinapsis/features/creations/report/presentation/export/report_export.dart';
import 'package:sinapsis/features/creations/report/presentation/widgets/report_index_sheet.dart';
import 'package:sinapsis/features/creations/report/presentation/widgets/report_template_picker.dart';
import 'package:sinapsis/features/creations/report/presentation/widgets/report_view.dart';
import 'package:sinapsis/features/reading/presentation/frame/reading_contents_sheet.dart';
import 'package:sinapsis/features/reading/presentation/frame/reading_frame.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// Los informes en Repasar (F43, paso 10): la hoja con el formato y las
/// plantillas como tarjetas (`ReportTemplatePicker`, con la propia escrita
/// con ✎), lo que se estima que escribe cada plantilla en cada formato, el
/// visor con sus secciones que se pliegan y sus preguntas —en el marco de
/// lectura (F47, paso 1), con el índice en «Contenido»—, y el PDF o el
/// Markdown para descargar desde ⋮.
///
/// Arranca del de fábrica: su tarjeta, su color y el segmentado del formato
/// quedan como están; la plantilla y su texto propio pasan a dibujarse a mano.
final reportKindSpecProvider = Provider<CreationKindSpec>(
  (ref) => buildReportKindSpec(),
);

/// El de [reportKindSpecProvider], armado.
CreationKindSpec buildReportKindSpec() {
  final base = defaultCreationKindSpec(StudyCreationKind.report);
  return base.copyWith(
    options: [
      for (final option in base.options)
        if (option.key == CreationOptionValues.format) option,
    ],
    optionsBuilder: (context, options) => ReportTemplatePicker(
      key: const Key('report-options'),
      options: options,
    ),
    extraDefaults: const {
      CreationOptionValues.template: CreationOptionValues.learningSummary,
      CreationOptionValues.customTemplate: '',
    },
    expectedOutputTokens: reportOutputTokens,
    viewerBuilder: (context, creation) =>
        ReportView(key: ValueKey('report-${creation.id}'), creation: creation),
    // En el marco de lectura (F47, paso 1): el índice va en «Contenido» y la
    // descarga —el PDF para leer o imprimir, o el Markdown— en ⋮.
    reader: CreationReaderSpec(
      bodyShowsTitle: true,
      contents: (context, creation) => [
        ReadingContentsSection(
          key: const Key('report-contents'),
          title: AppLocalizations.of(context)!.f47P1ReportIndex,
          entries: [
            ReadingOutlineEntry(
              key: const Key('report-action-index'),
              label: AppLocalizations.of(context)!.f43ReportIndexTooltip,
              onSelected: () => unawaited(showReportIndex(context, creation)),
            ),
          ],
        ),
      ],
    ),
    exporter: exportReport,
  );
}

/// Quien genera los informes: una línea en `creationGeneratorsProvider`.
final reportGeneratorProvider = Provider<CreationGenerator>(
  (ref) => const ReportGenerator(),
);
