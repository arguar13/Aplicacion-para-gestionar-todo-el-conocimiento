import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/core/domain/entities/knowledge_item.dart';
import 'package:sinapsis/core/domain/entities/tag.dart';
import 'package:sinapsis/features/library/presentation/providers/library_providers.dart';
import 'package:sinapsis/features/organize/presentation/providers/organize_providers.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// Las etiquetas de un elemento, con lo necesario para agregar y quitar.
///
/// Vive con el contrato mínimo posible —el elemento entero— porque agregar o
/// quitar una etiqueta no es una operación propia: es guardar el elemento de
/// nuevo con su lista de etiquetas cambiada, por el mismo camino que
/// cualquier otro cambio. No hay un "agregar etiqueta a un elemento" en el
/// repositorio, y no hace falta que lo haya.
class TagEditor extends ConsumerWidget {
  const TagEditor({required this.item, super.key});

  final KnowledgeItem item;

  Future<void> _save(WidgetRef ref, List<Tag> tags) {
    return ref.read(libraryRepositoryProvider).save(item.copyWith(tags: tags));
  }

  Future<void> _remove(WidgetRef ref, Tag tag) {
    final remaining = item.tags.where((t) => t.id != tag.id).toList();
    return _save(ref, remaining);
  }

  Future<void> _add(BuildContext context, WidgetRef ref) async {
    final name = await showDialog<String>(
      context: context,
      builder: (context) => _AddTagDialog(alreadyOn: item.tags),
    );
    if (name == null || !context.mounted) return;

    final result = await ref
        .read(organizeRepositoryProvider)
        .getOrCreateTag(name);

    final tag = result.getRight().toNullable();
    if (tag == null) return;

    // Puede que ya esté: quien escribe una etiqueta a mano puede tipear el
    // nombre exacto de una que el elemento ya tiene, sin haberla visto en
    // las sugerencias.
    if (item.tags.any((t) => t.id == tag.id)) return;

    await _save(ref, [...item.tags, tag]);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.detailTagsTitle,
          style: theme.textTheme.titleSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final tag in item.tags)
              InputChip(
                label: Text(tag.name),
                onDeleted: () => _remove(ref, tag),
                deleteIconColor: theme.colorScheme.onSurfaceVariant,
                deleteButtonTooltipMessage: l10n.detailRemoveTag(tag.name),
              ),
            ActionChip(
              avatar: const Icon(Icons.add, size: 18),
              label: Text(l10n.detailAddTag),
              onPressed: () => _add(context, ref),
            ),
          ],
        ),
      ],
    );
  }
}

/// El diálogo para elegir o escribir el nombre de una etiqueta nueva.
///
/// Devuelve el nombre, recortado, o `null` si se canceló. No devuelve un
/// [Tag] ya resuelto: encontrar o crear la etiqueta a partir del nombre es
/// trabajo del repositorio, y hacerlo acá duplicaría esa decisión —"sin
/// distinguir mayúsculas, y recortando espacios"— en dos lugares que podrían
/// terminar en desacuerdo.
class _AddTagDialog extends ConsumerStatefulWidget {
  const _AddTagDialog({required this.alreadyOn});

  /// Las que el elemento ya tiene, para no sugerirlas de nuevo.
  final List<Tag> alreadyOn;

  @override
  ConsumerState<_AddTagDialog> createState() => _AddTagDialogState();
}

class _AddTagDialogState extends ConsumerState<_AddTagDialog> {
  final _controller = TextEditingController();

  @override
  void initState() {
    super.initState();
    // Las sugerencias cambian con lo que se va escribiendo.
    _controller.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _confirm(String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return;

    Navigator.of(context).pop(trimmed);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final allTags = ref.watch(allTagsProvider).valueOrNull ?? const <Tag>[];
    final alreadyOnIds = widget.alreadyOn.map((t) => t.id).toSet();

    final typed = _controller.text.trim().toLowerCase();
    final suggestions = allTags
        .where((t) => !alreadyOnIds.contains(t.id))
        .where((t) => typed.isEmpty || t.name.toLowerCase().contains(typed))
        .take(8)
        .toList();

    return AlertDialog(
      title: Text(l10n.detailAddTag),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _controller,
              autofocus: true,
              decoration: InputDecoration(hintText: l10n.detailNewTagHint),
              onSubmitted: _confirm,
            ),
            if (suggestions.isNotEmpty) ...[
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final tag in suggestions)
                    ActionChip(
                      label: Text(tag.name),
                      onPressed: () => _confirm(tag.name),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.commonCancel),
        ),
        TextButton(
          onPressed: () => _confirm(_controller.text),
          child: Text(l10n.detailAddTag),
        ),
      ],
    );
  }
}
