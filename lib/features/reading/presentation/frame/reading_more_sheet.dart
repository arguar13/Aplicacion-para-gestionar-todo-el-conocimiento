import 'dart:async';

import 'package:flutter/material.dart';
import 'package:sinapsis/features/reading/presentation/frame/reading_contents_sheet.dart';
import 'package:sinapsis/features/reading/presentation/frame/reading_frame.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// Una opción de ⋮ del marco de lectura.
@immutable
class ReadingMenuEntry {
  const ReadingMenuEntry({
    required this.icon,
    required this.label,
    required this.onSelected,
    this.detail,
    this.destructive = false,
    this.key,
  });

  final IconData icon;
  final String label;

  /// Para qué sirve, en chico.
  final String? detail;

  /// Lo que hace, ya cerrada la hoja. `null`: se ve apagada, y [detail] dice
  /// por qué.
  final VoidCallback? onSelected;

  /// Lo que se borra: en rojo.
  final bool destructive;

  final Key? key;
}

/// Un grupo de opciones de ⋮, separado del siguiente por una línea.
@immutable
class ReadingMenuGroup {
  const ReadingMenuGroup(this.entries);

  final List<ReadingMenuEntry> entries;
}

/// Abre ⋮ del marco de lectura (F47, paso 1, captura 6): una hoja con todo
/// lo demás.
///
/// - **Arriba**, la miniatura, el título con ✎ para cambiarle el nombre —si
///   se puede— y el tipo.
/// - **Después, en grupos**, lo que cada lector ofrece —en Procesado,
///   «Descargar con lo marcado» y «Editar el texto»; en lo creado, exportar,
///   los detalles y volver a crear—, y al final, en rojo, **lo que se borra**:
///   la copia, la creación o el documento procesado, nunca la fuente de la
///   Biblioteca.
Future<void> showReadingMore(
  BuildContext context, {
  required ReadingDocumentInfo info,
  required List<ReadingMenuGroup> groups,
}) {
  final still = MediaQuery.disableAnimationsOf(context);
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    sheetAnimationStyle: still ? AnimationStyle.noAnimation : null,
    builder: (_) => ReadingMoreSheet(
      info: info,
      groups: [
        for (final group in groups)
          if (group.entries.isNotEmpty) group,
      ],
      host: context,
    ),
  );
}

/// Lo de adentro de ⋮.
class ReadingMoreSheet extends StatelessWidget {
  const ReadingMoreSheet({
    required this.info,
    required this.groups,
    required this.host,
    super.key,
  });

  final ReadingDocumentInfo info;
  final List<ReadingMenuGroup> groups;

  /// El marco que abrió la hoja: lo que se hace después de cerrarla —abrir un
  /// diálogo, otra pantalla— se hace desde ahí.
  final BuildContext host;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final rename = info.onRename;

    return ListView(
      key: const Key('reading-more-sheet'),
      shrinkWrap: true,
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 0, 4, 12),
          child: Row(
            children: [
              SizedBox.square(
                dimension: 56,
                child:
                    info.thumbnail ??
                    DecoratedBox(
                      decoration: BoxDecoration(
                        color: scheme.secondaryContainer,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Icon(
                        info.kindIcon,
                        color: scheme.onSecondaryContainer,
                      ),
                    ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      info.title,
                      key: const Key('reading-more-title'),
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      info.kindLabel,
                      key: const Key('reading-more-kind'),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              if (rename != null)
                IconButton(
                  key: const Key('reading-more-rename'),
                  tooltip: l10n.f47P1MoreRename,
                  icon: const Icon(Icons.edit_outlined),
                  onPressed: () =>
                      closeReadingSheet(context, () => unawaited(rename(host))),
                ),
            ],
          ),
        ),
        for (final (index, group) in groups.indexed) ...[
          if (index > 0) const Divider(height: 16, indent: 8, endIndent: 8),
          for (final entry in group.entries)
            _EntryTile(
              entry: entry,
              onTap: switch (entry.onSelected) {
                final selected? => () => closeReadingSheet(context, selected),
                null => null,
              },
            ),
        ],
      ],
    );
  }
}

class _EntryTile extends StatelessWidget {
  const _EntryTile({required this.entry, required this.onTap});

  final ReadingMenuEntry entry;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = entry.destructive ? scheme.error : null;
    return ListTile(
      key: entry.key,
      enabled: onTap != null,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      leading: Icon(entry.icon, color: color),
      title: Text(entry.label, style: TextStyle(color: color)),
      subtitle: entry.detail == null ? null : Text(entry.detail!),
      onTap: onTap,
    );
  }
}
