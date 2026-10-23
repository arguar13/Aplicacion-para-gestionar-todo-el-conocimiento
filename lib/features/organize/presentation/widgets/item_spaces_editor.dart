import 'package:flutter/foundation.dart' show setEquals;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/core/domain/entities/knowledge_item.dart';
import 'package:sinapsis/core/error/failure_messages.dart';
import 'package:sinapsis/features/library/presentation/providers/library_providers.dart';
import 'package:sinapsis/features/library/presentation/widgets/spaces_field.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// Los temas de un elemento ya guardado, en su detalle (F37): los mismos chips
/// y la misma hoja que el editor de notas, pero cada cambio se escribe al
/// momento, como las etiquetas de al lado.
///
/// No exige ninguno, a diferencia de la captura: lo que ya estaba sin tema se
/// ordena cuando la persona quiere —decisión C—, y forzarlo acá sería
/// obligarla a elegir para poder sacar uno.
class ItemSpacesEditor extends ConsumerWidget {
  const ItemSpacesEditor({required this.item, super.key});

  final KnowledgeItem item;

  Future<void> _set(
    BuildContext context,
    WidgetRef ref,
    Set<String> spaceIds,
  ) async {
    if (setEquals(spaceIds, item.spaceIds)) return;
    final l10n = AppLocalizations.of(context)!;
    final result = await ref
        .read(libraryRepositoryProvider)
        .setSpaces(itemIds: [item.id], spaceIds: spaceIds);
    if (!context.mounted) return;
    result.match(
      (failure) => ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(failure.localizedMessage(l10n)))),
      (_) {},
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.spacesLabel,
          style: theme.textTheme.titleSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 8),
        SpacesField.compact(
          spaceIds: item.spaceIds,
          onChanged: (spaceIds) => _set(context, ref, spaceIds),
        ),
      ],
    );
  }
}
