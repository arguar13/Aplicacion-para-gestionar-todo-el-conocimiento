import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/core/domain/entities/note_template.dart';
import 'package:sinapsis/features/blocks/presentation/providers/note_template_providers.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// La hoja de «elegir plantilla» al crear una nota (F16): «Nota en blanco»
/// o una de las plantillas guardadas.
///
/// Devuelve la plantilla elegida —`(null,)` para «nota en blanco»—, o
/// `null` a secas si se cerró sin elegir nada: mismo criterio que
/// `showSpacePickerSheet`, porque acá también hace falta distinguir «elegí
/// que no hay plantilla» de «me arrepentí de elegir»; lo segundo no debe
/// abrir el editor.
Future<(NoteTemplate?,)?> showTemplatePickerSheet(
  BuildContext context,
  WidgetRef ref,
) {
  final l10n = AppLocalizations.of(context)!;
  final templates = ref.read(noteTemplatesProvider).valueOrNull ?? const [];

  return showModalBottomSheet<(NoteTemplate?,)>(
    context: context,
    showDragHandle: true,
    builder: (context) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.notes),
            title: Text(l10n.blocksNewBlank),
            onTap: () => Navigator.of(context).pop((null,)),
          ),
          for (final template in templates)
            ListTile(
              leading: const Icon(Icons.bookmark_outline),
              title: Text(template.name),
              onTap: () => Navigator.of(context).pop((template,)),
            ),
        ],
      ),
    ),
  );
}
