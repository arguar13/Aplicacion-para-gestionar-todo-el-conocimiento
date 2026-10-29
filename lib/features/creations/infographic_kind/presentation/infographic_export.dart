import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/core/storage/file_store.dart';
import 'package:sinapsis/features/creations/design/creation_controls.dart';
import 'package:sinapsis/features/creations/domain/entities/study_creation.dart';
import 'package:sinapsis/features/creations/infographic/domain/infographic_design.dart';
import 'package:sinapsis/features/creations/infographic/presentation/export/infographic_exporter.dart';
import 'package:sinapsis/features/creations/infographic_kind/domain/infographic_content.dart';
import 'package:sinapsis/features/creations/infographic_kind/domain/infographic_options.dart';
import 'package:sinapsis/features/creations/infographic_kind/presentation/infographic_kind_providers.dart';
import 'package:sinapsis/features/creations/presentation/creation_presentation.dart';
import 'package:sinapsis/features/creations/presentation/kinds/creation_kind_spec.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// Cómo se guarda una infografía: la imagen o el PDF.
enum InfographicFileFormat { png, pdf }

/// El archivo de una infografía en [format] (F43: «PNG en alta resolución, o
/// PDF»): la misma lámina de la pantalla, con su diseño de ahora y sus
/// ilustraciones, dibujada fuera de ella (`InfographicExporter`). El PNG va
/// al doble de la lámina.
Future<CreationExportFile> exportInfographic(
  WidgetRef ref,
  StudyCreation creation, {
  required InfographicFileFormat format,
  required String title,
  InfographicDesign? design,
}) async {
  final content = InfographicContent.decode(creation.content);
  final chosen = design ?? infographicDesignOf(creation.options);
  final illustrations = await loadInfographicResolver(
    ref.read(infographicIllustrationStoreProvider),
    content.sheet,
  );
  const exporter = InfographicExporter();
  final name = sanitizeFileName(title);
  return switch (format) {
    InfographicFileFormat.png => CreationExportFile(
      fileName: '$name.png',
      bytes: await exporter.toPng(
        sheet: content.sheet,
        design: chosen,
        illustrations: illustrations,
      ),
      mimeType: 'image/png',
    ),
    InfographicFileFormat.pdf => CreationExportFile(
      fileName: '$name.pdf',
      bytes: await exporter.toPdf(
        sheet: content.sheet,
        design: chosen,
        illustrations: illustrations,
      ),
      mimeType: 'application/pdf',
    ),
  };
}

/// El `exporter` de la infografía para «Compartir» y «Descargar» en «Lo
/// creado»: pregunta si va como imagen o como PDF, y la arma con su diseño
/// guardado. `null` si se cierra sin elegir.
Future<CreationExportFile?> infographicExporter(
  BuildContext context,
  WidgetRef ref,
  StudyCreation creation,
) async {
  final l10n = AppLocalizations.of(context)!;
  final title = studyCreationTitle(l10n, creation);
  final format = await showModalBottomSheet<InfographicFileFormat>(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (context) => const InfographicFormatSheet(),
  );
  if (format == null) return null;
  return exportInfographic(ref, creation, format: format, title: title);
}

/// La hoja chica para elegir cómo se guarda: imagen o PDF.
class InfographicFormatSheet extends StatelessWidget {
  const InfographicFormatSheet({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    Widget option({
      required InfographicFileFormat format,
      required IconData icon,
      required String title,
      required String detail,
    }) => Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Material(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(20),
        clipBehavior: Clip.antiAlias,
        child: ListTile(
          key: ValueKey('infographic-format-${format.name}'),
          contentPadding: const EdgeInsets.fromLTRB(16, 6, 12, 6),
          leading: Icon(icon, color: scheme.primary),
          title: Text(title),
          subtitle: Text(detail),
          trailing: Icon(Icons.chevron_right, color: scheme.onSurfaceVariant),
          onTap: () => Navigator.of(context).pop(format),
        ),
      ),
    );
    return Material(
      color: scheme.surfaceContainerLow,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      l10n.f43IgFormatTitle,
                      style: theme.textTheme.titleLarge,
                    ),
                  ),
                  CreationCloseButton(tooltip: l10n.f43InfoDesignClose),
                ],
              ),
              option(
                format: InfographicFileFormat.png,
                icon: Icons.image_outlined,
                title: l10n.f43IgFormatPng,
                detail: l10n.f43IgFormatPngDetail,
              ),
              option(
                format: InfographicFileFormat.pdf,
                icon: Icons.picture_as_pdf_outlined,
                title: l10n.f43IgFormatPdf,
                detail: l10n.f43IgFormatPdfDetail,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
