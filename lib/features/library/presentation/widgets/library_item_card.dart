import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/core/domain/entities/knowledge_item.dart';
import 'package:sinapsis/core/domain/entities/space.dart';
import 'package:sinapsis/core/error/failure_messages.dart';
import 'package:sinapsis/features/export/domain/entities/export_format.dart';
import 'package:sinapsis/features/export/domain/usecases/export_item_usecase.dart';
import 'package:sinapsis/features/export/presentation/providers/export_providers.dart';
import 'package:sinapsis/features/export/presentation/widgets/export_format_presentation.dart';
import 'package:sinapsis/features/library/presentation/providers/library_providers.dart';
import 'package:sinapsis/features/library/presentation/widgets/entity_presentation.dart';
import 'package:sinapsis/features/organize/presentation/providers/organize_providers.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// Una fila de la biblioteca.
///
/// Muestra cuatro cosas y en este orden de importancia: qué es (el ícono del
/// tipo de fuente), cómo se llama, de dónde salió y si le falta algo. Un
/// vistazo a la lista tiene que alcanzar para reconocer lo que uno busca.
///
/// Tarjeta propia y no `ListTile` a secas: una superficie con esquinas
/// redondeadas y aire alrededor separa visualmente cada elemento sin
/// necesitar una línea divisoria, y dan lugar a un ícono con más presencia
/// —el mismo criterio que el ícono de una página en Notion—.
class LibraryItemCard extends StatelessWidget {
  const LibraryItemCard({
    required this.item,
    required this.onTap,
    this.onLongPress,
    this.selectionMode = false,
    this.selected = false,
    this.onSelectedChanged,
    super.key,
  });

  final KnowledgeItem item;
  final VoidCallback onTap;

  /// Punto de entrada al modo de selección múltiple, en las listas donde
  /// existe. `null` en las que no lo ofrecen.
  final VoidCallback? onLongPress;

  /// Si la lista está mostrando casillas en vez de navegar al tocar.
  final bool selectionMode;
  final bool selected;
  final ValueChanged<bool>? onSelectedChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final stateLabel = item.processingState.label(l10n);

    return Material(
      color: selected
          ? colors.primaryContainer.withValues(alpha: 0.4)
          : colors.surfaceContainerLow,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        // En modo selección, tocar la fila alterna la casilla: es lo que
        // espera cualquiera que use Gmail o Fotos, y repetir el mismo gesto
        // en la casilla y en el resto de la fila evita que haya que
        // acertarle a un blanco chico.
        onTap: selectionMode ? () => onSelectedChanged?.call(!selected) : onTap,
        onLongPress: onLongPress,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: selected
                  ? colors.primary
                  : colors.outlineVariant.withValues(alpha: 0.6),
              width: selected ? 1.5 : 1,
            ),
          ),
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (selectionMode)
                Padding(
                  padding: const EdgeInsets.only(right: 4, top: 2),
                  child: Checkbox(
                    value: selected,
                    onChanged: (value) =>
                        onSelectedChanged?.call(value ?? false),
                  ),
                )
              else
                _IconBadge(icon: item.source.kind.icon),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            item.subtitle ?? item.source.kind.label(l10n),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: colors.onSurfaceVariant,
                            ),
                          ),
                        ),
                        if (stateLabel != null) ...[
                          const SizedBox(width: 8),
                          _StateBadge(
                            label: stateLabel,
                            color: item.processingState.color(colors)!,
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              // El menú se tapa a sí mismo en modo selección: ahí el gesto de
              // la fila entera ya es "elegir", y ofrecer de paso "eliminar"
              // o "exportar" invitaría a un toque accidental sobre un ítem
              // que se estaba por marcar, no por borrar.
              if (!selectionMode) _ItemMenuButton(item: item),
            ],
          ),
        ),
      ),
    );
  }
}

/// El menú de tres puntos de cada fila: eliminar, mover de espacio o
/// exportar, sin tener que abrir el detalle solo para eso.
class _ItemMenuButton extends ConsumerWidget {
  const _ItemMenuButton({required this.item});

  final KnowledgeItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;

    return PopupMenuButton<_ItemMenuAction>(
      icon: const Icon(Icons.more_vert, size: 20),
      tooltip: l10n.libraryItemMenuTooltip,
      onSelected: (action) => _handle(context, ref, action),
      itemBuilder: (context) => [
        PopupMenuItem(
          value: const _MoveAction(),
          child: ListTile(
            leading: const Icon(Icons.drive_file_move_outline),
            title: Text(l10n.libraryItemMoveToSpace),
            contentPadding: EdgeInsets.zero,
          ),
        ),
        for (final format in ExportFormat.values)
          PopupMenuItem(
            value: _ExportAction(format),
            child: ListTile(
              leading: const Icon(Icons.ios_share_outlined),
              title: Text(l10n.libraryItemExportAs(format.label(l10n))),
              contentPadding: EdgeInsets.zero,
            ),
          ),
        const PopupMenuDivider(),
        PopupMenuItem(
          value: const _DeleteAction(),
          child: ListTile(
            leading: Icon(
              Icons.delete_outline,
              color: Theme.of(context).colorScheme.error,
            ),
            title: Text(
              l10n.detailDelete,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
            contentPadding: EdgeInsets.zero,
          ),
        ),
      ],
    );
  }

  Future<void> _handle(
    BuildContext context,
    WidgetRef ref,
    _ItemMenuAction action,
  ) async {
    switch (action) {
      case _DeleteAction():
        await _delete(context, ref);
      case _MoveAction():
        await _move(context, ref);
      case _ExportAction(:final format):
        await _export(context, ref, format);
    }
  }

  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context)!;

    // Mismo paso intermedio que el botón de eliminar del detalle: se lleva
    // el contenido, la procedencia y todo lo que tenga, sin papelera de la
    // que rescatarlo.
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        content: Text(l10n.detailDeleteConfirm),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n.commonCancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l10n.detailDelete),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;

    await ref.read(libraryRepositoryProvider).delete(item.id);
  }

  Future<void> _move(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context)!;
    final spaces = ref.read(allSpacesProvider).valueOrNull ?? const <Space>[];

    final chosen = await showModalBottomSheet<(bool, String?)>(
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
              onTap: () => Navigator.of(context).pop((true, null)),
            ),
            for (final space in spaces)
              ListTile(
                leading: const Icon(Icons.folder_outlined),
                title: Text(space.name),
                selected: item.spaceId == space.id,
                onTap: () => Navigator.of(context).pop((true, space.id)),
              ),
          ],
        ),
      ),
    );
    // A diferencia de un `String?` a secas, el booleano distingue "cerró sin
    // elegir" de "eligió sin clasificar": las dos vuelven `null` de
    // `Navigator.pop`, y acá sí importa no confundirlas —"sin clasificar" es
    // una fila más de la lista, y hay que poder elegirla sin que se lea como
    // un cierre accidental—.
    if (chosen == null || !context.mounted) return;

    final (_, spaceId) = chosen;
    if (spaceId == item.spaceId) return;

    final result = await ref
        .read(libraryRepositoryProvider)
        .assignSpace(itemId: item.id, spaceId: spaceId);
    if (!context.mounted) return;

    result.match(
      (failure) => ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(failure.localizedMessage(l10n)))),
      (_) {
        final spaceName =
            spaces.where((s) => s.id == spaceId).firstOrNull?.name ??
            l10n.detailSpaceNone;
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(content: Text(l10n.libraryItemMoved(spaceName))),
          );
      },
    );
  }

  Future<void> _export(
    BuildContext context,
    WidgetRef ref,
    ExportFormat format,
  ) async {
    final l10n = AppLocalizations.of(context)!;

    final result = await ref.read(exportItemUseCaseProvider)(
      ExportItemParams(item: item, format: format),
    );
    if (!context.mounted) return;

    result.match(
      (failure) => ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(failure.localizedMessage(l10n)))),
      (_) => ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(l10n.libraryItemExported))),
    );
  }
}

sealed class _ItemMenuAction {
  const _ItemMenuAction();
}

class _DeleteAction extends _ItemMenuAction {
  const _DeleteAction();
}

class _MoveAction extends _ItemMenuAction {
  const _MoveAction();
}

class _ExportAction extends _ItemMenuAction {
  const _ExportAction(this.format);

  final ExportFormat format;
}

/// El ícono del tipo de fuente, con más presencia que un ícono suelto: un
/// fondo circular tenue lo separa del texto y le da al ojo un punto de
/// anclaje fijo por el que reconocer la fila, aunque el título cambie de
/// largo entre una y otra.
class _IconBadge extends StatelessWidget {
  const _IconBadge({required this.icon});

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: colors.secondaryContainer,
        shape: BoxShape.circle,
      ),
      alignment: Alignment.center,
      child: Icon(icon, size: 20, color: colors.onSecondaryContainer),
    );
  }
}

/// La insignia de estado. Solo aparece cuando hay algo que decir — ver
/// `ProcessingStatePresentation.label`.
class _StateBadge extends StatelessWidget {
  const _StateBadge({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: theme.textTheme.labelSmall?.copyWith(color: color),
      ),
    );
  }
}
