import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/features/citations/domain/entities/bibliography.dart';
import 'package:sinapsis/features/citations/domain/services/bibliography_builder.dart';
import 'package:sinapsis/features/citations/presentation/providers/citation_preferences.dart';
import 'package:sinapsis/features/export/domain/entities/export_format.dart';
import 'package:sinapsis/features/export/domain/services/bibliography_file_builder.dart';
import 'package:sinapsis/features/export/presentation/providers/export_providers.dart';
import 'package:sinapsis/features/export/presentation/widgets/export_format_presentation.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// Arma y guarda la bibliografía de [sources] (F15, D13): pregunta el
/// formato, la arma con el estilo y el idioma por defecto de Ajustes, y la
/// guarda donde el usuario elija.
///
/// Es el mismo camino desde los cuatro lugares donde aparece «Bibliografía»
/// —la selección de la Biblioteca, una rama del Atlas, un espacio y una
/// nota—: cada uno solo decide cuáles fuentes entran y con qué [suggestedName]
/// sugerir el archivo —el de la rama, el del espacio, el título de la nota, o
/// «Bibliografía» a secas para una selección, que no tiene un único nombre
/// propio—.
///
/// Sin fuentes que citar no pregunta nada: lo avisa y no hay nada más que
/// hacer.
Future<void> exportBibliography(
  BuildContext context,
  WidgetRef ref, {
  required List<BibliographySource> sources,
  required String suggestedName,
}) async {
  final l10n = AppLocalizations.of(context)!;
  final messenger = ScaffoldMessenger.of(context);

  if (sources.isEmpty) {
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(l10n.bibliographyExportEmpty)));
    return;
  }

  final format = await _chooseFormat(context, l10n);
  if (format == null || !context.mounted) return;

  final bibliography = buildBibliography(
    sources,
    style: ref.read(defaultCitationStyleProvider),
    language: ref.read(defaultCitationLanguageProvider),
  );

  try {
    final bytes = await buildBibliographyFile(bibliography, format);
    await ref
        .read(fileSaverProvider)
        .saveFile(
          fileName: suggestedBibliographyFileName(suggestedName, format),
          bytes: bytes,
        );
    // Ver `ExportItemUseCase`: ninguna plataforma distingue de verdad
    // "canceló el diálogo de guardado" de "lo guardó", así que las dos se
    // tratan igual y solo se avisa si algo salió mal de verdad.
    // ignore: avoid_catches_without_on_clauses
  } catch (e) {
    if (!context.mounted) return;
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(l10n.bibliographyExportFailed)));
  }
}

Future<ExportFormat?> _chooseFormat(
  BuildContext context,
  AppLocalizations l10n,
) {
  return showModalBottomSheet<ExportFormat>(
    context: context,
    showDragHandle: true,
    builder: (context) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            title: Text(l10n.bibliographyExportChooseFormat),
            dense: true,
          ),
          for (final format in bibliographyFormats)
            ListTile(
              key: Key('bibliography-export-format-${format.name}'),
              title: Text(format.label(l10n)),
              onTap: () => Navigator.of(context).pop(format),
            ),
        ],
      ),
    ),
  );
}
