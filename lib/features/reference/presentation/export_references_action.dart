import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/core/storage/file_store.dart';
import 'package:sinapsis/features/export/presentation/providers/export_providers.dart';
import 'package:sinapsis/features/reference/domain/entities/reference_file_format.dart';
import 'package:sinapsis/features/reference/presentation/providers/reference_providers.dart';
import 'package:sinapsis/features/reference/presentation/reference_file_format_presentation.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// Arma y guarda un `.bib` o un `.ris` con la referencia de [itemIds] (F15,
/// D15): pregunta el formato y guarda donde el usuario elija —mismo molde
/// que `exportBibliography`, con las entradas enteras en vez de formateadas
/// en un estilo—.
///
/// Sin ninguna fuente entre lo elegido, no pregunta nada: lo avisa y no hay
/// nada más que hacer.
Future<void> exportReferences(
  BuildContext context,
  WidgetRef ref, {
  required List<String> itemIds,
}) async {
  final l10n = AppLocalizations.of(context)!;
  final messenger = ScaffoldMessenger.of(context);

  final format = await _chooseFormat(context, l10n);
  if (format == null || !context.mounted) return;

  final content = await ref.read(exportReferencesUseCaseProvider)(
    itemIds,
    format,
  );
  if (content == null) {
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(l10n.exportReferencesEmpty)));
    return;
  }

  try {
    await ref
        .read(fileSaverProvider)
        .saveFile(
          fileName:
              '${sanitizeFileName(l10n.exportReferencesFileName)}'
              '${format.fileExtension}',
          bytes: utf8.encode(content),
        );
    // Ver `exportBibliography`: ninguna plataforma distingue de verdad
    // "canceló el diálogo de guardado" de "lo guardó".
    // ignore: avoid_catches_without_on_clauses
  } catch (e) {
    if (!context.mounted) return;
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(l10n.exportReferencesFailed)));
  }
}

Future<ReferenceFileFormat?> _chooseFormat(
  BuildContext context,
  AppLocalizations l10n,
) {
  return showModalBottomSheet<ReferenceFileFormat>(
    context: context,
    showDragHandle: true,
    builder: (context) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(title: Text(l10n.exportReferencesChooseFormat), dense: true),
          for (final format in ReferenceFileFormat.values)
            ListTile(
              key: Key('reference-export-format-${format.name}'),
              title: Text(format.label(l10n)),
              onTap: () => Navigator.of(context).pop(format),
            ),
        ],
      ),
    ),
  );
}
