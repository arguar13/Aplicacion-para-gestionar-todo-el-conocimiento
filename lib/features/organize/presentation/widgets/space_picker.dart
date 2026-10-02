import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/core/domain/entities/knowledge_item.dart';
import 'package:sinapsis/core/domain/entities/space.dart';
import 'package:sinapsis/features/library/presentation/providers/library_providers.dart';
import 'package:sinapsis/features/library/presentation/widgets/space_picker_sheet.dart';
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
          onPressed: () => _choose(context, ref),
        ),
      ],
    );
  }

  /// Con la misma hoja que la captura y "mover a tema" —ver
  /// `showSpacePickerSheet`—, que distingue "eligió sin clasificar" de
  /// "cerró sin elegir": antes, con una hoja propia que devolvía el `id` a
  /// secas, las dos llegaban como `null` y elegir "sin clasificar" no hacía
  /// nada.
  Future<void> _choose(BuildContext context, WidgetRef ref) async {
    final chosen = await showSpacePickerSheet(
      context,
      selectedSpaceId: item.spaceId,
    );
    if (chosen == null) return;

    final (space,) = chosen;
    if (space?.id == item.spaceId) return;

    await ref
        .read(libraryRepositoryProvider)
        .assignSpace(itemId: item.id, spaceId: space?.id);
  }
}
