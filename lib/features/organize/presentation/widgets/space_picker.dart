import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/core/domain/entities/knowledge_item.dart';
import 'package:sinapsis/core/domain/entities/space.dart';
import 'package:sinapsis/features/library/presentation/providers/library_providers.dart';
import 'package:sinapsis/features/organize/presentation/providers/organize_providers.dart';
import 'package:sinapsis/features/organize/presentation/widgets/tag_editor.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// A qué espacio pertenece un elemento, con lo necesario para cambiarlo.
///
/// Aparte de [TagEditor] a propósito: un elemento pertenece a lo sumo a un
/// espacio, así que esto no acumula ni quita de una lista — reemplaza un
/// único valor, más parecido a mover un archivo de carpeta que a etiquetarlo.
class SpacePicker extends ConsumerWidget {
  const SpacePicker({required this.item, super.key});

  final KnowledgeItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final spaces = ref.watch(allSpacesProvider).valueOrNull ?? const <Space>[];
    final current = spaces.where((s) => s.id == item.spaceId).firstOrNull;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.detailSpaceLabel,
          style: theme.textTheme.titleSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 8),
        ActionChip(
          avatar: Icon(
            current == null ? Icons.folder_off_outlined : Icons.folder_outlined,
            size: 18,
          ),
          label: Text(current?.name ?? l10n.detailSpaceNone),
          onPressed: () => _choose(context, ref, spaces),
        ),
      ],
    );
  }

  Future<void> _choose(
    BuildContext context,
    WidgetRef ref,
    List<Space> spaces,
  ) async {
    final l10n = AppLocalizations.of(context)!;

    final chosen = await showModalBottomSheet<String?>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(title: Text(l10n.detailSpaceChoose), dense: true),
            ListTile(
              leading: const Icon(Icons.folder_off_outlined),
              title: Text(l10n.detailSpaceNone),
              selected: item.spaceId == null,
              onTap: () => Navigator.of(context).pop(),
            ),
            for (final space in spaces)
              ListTile(
                leading: const Icon(Icons.folder_outlined),
                title: Text(space.name),
                selected: item.spaceId == space.id,
                onTap: () => Navigator.of(context).pop(space.id),
              ),
          ],
        ),
      ),
    );

    // `showModalBottomSheet` devuelve `null` tanto si se eligió "sin
    // clasificar" como si se cerró sin elegir nada: no hay forma de
    // distinguirlas con el tipo de retorno de Navigator.pop. Como mover a
    // "sin clasificar" es una acción explícita en la lista (con su propio
    // ListTile), y cerrar sin elegir es la interacción por defecto de un
    // bottom sheet, se prioriza no tocar nada — perder el gesto de "cerrar
    // sin elegir" pesa más que ganar el de "elegir explícitamente sin
    // clasificar", que de todas formas ya es el estado más común.
    if (chosen == item.spaceId) return;

    await ref
        .read(libraryRepositoryProvider)
        .assignSpace(itemId: item.id, spaceId: chosen);
  }
}
