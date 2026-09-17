import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/core/domain/entities/item_property.dart';
import 'package:sinapsis/core/domain/entities/knowledge_item.dart';
import 'package:sinapsis/core/domain/entities/property_definition.dart';
import 'package:sinapsis/core/domain/entities/property_value.dart';
import 'package:sinapsis/features/organize/presentation/providers/organize_providers.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// Las propiedades tipadas de un elemento —"Época: Siglo I a.C.", "Región:
/// Roma"—, agrupadas por categoría, con lo necesario para agregar y quitar.
///
/// Aparte de [TagEditor] a propósito: acá agregar o quitar un valor sí es
/// una operación propia del repositorio (`assignProperty`/
/// `removeItemProperty`), no "guardar el elemento de nuevo con la lista
/// cambiada" — ver la decisión 31 en docs/arquitectura.md sobre por qué. El
/// elemento se actualiza solo cuando cambia, porque ya llega desde un
/// stream que observa esas mismas tablas.
class PropertyEditor extends ConsumerWidget {
  const PropertyEditor({required this.item, super.key});

  final KnowledgeItem item;

  Future<void> _remove(WidgetRef ref, ItemProperty property) {
    return ref
        .read(organizeRepositoryProvider)
        .removeItemProperty(itemId: item.id, propertyValueId: property.valueId);
  }

  Future<void> _add(BuildContext context, WidgetRef ref) async {
    final picked = await showDialog<(String category, String value)>(
      context: context,
      builder: (context) => const _AddPropertyDialog(),
    );
    if (picked == null || !context.mounted) return;

    final (category, value) = picked;
    final organize = ref.read(organizeRepositoryProvider);

    final definitionResult = await organize.getOrCreatePropertyDefinition(
      category,
    );
    final definition = definitionResult.getRight().toNullable();
    if (definition == null) return;

    await organize.assignProperty(
      itemId: item.id,
      definitionId: definition.id,
      value: value,
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);

    // Agrupadas por categoría, y las categorías en el orden en que ya
    // vienen del repositorio —alfabético— porque `item.properties` no
    // promete ningún orden propio entre categorías distintas.
    final byDefinition = <String, List<ItemProperty>>{};
    for (final property in item.properties) {
      (byDefinition[property.definitionId] ??= []).add(property);
    }
    final definitionIds = byDefinition.keys.toList()
      ..sort(
        (a, b) => byDefinition[a]!.first.definitionName.toLowerCase().compareTo(
          byDefinition[b]!.first.definitionName.toLowerCase(),
        ),
      );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                l10n.detailPropertiesTitle,
                style: theme.textTheme.titleSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            ActionChip(
              avatar: const Icon(Icons.add, size: 18),
              label: Text(l10n.detailAddProperty),
              onPressed: () => _add(context, ref),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (definitionIds.isEmpty)
          Text(
            l10n.detailNoPropertiesYet,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          )
        else
          for (final definitionId in definitionIds) ...[
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                byDefinition[definitionId]!.first.definitionName,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  letterSpacing: 0.5,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final property in byDefinition[definitionId]!)
                    InputChip(
                      label: Text(property.value),
                      onDeleted: () => _remove(ref, property),
                      deleteIconColor: theme.colorScheme.onSurfaceVariant,
                      deleteButtonTooltipMessage: l10n.detailRemoveProperty(
                        property.value,
                      ),
                    ),
                ],
              ),
            ),
          ],
      ],
    );
  }
}

/// El diálogo para agregar una propiedad: categoría y valor, cada uno con
/// sus propias sugerencias mientras se escribe.
///
/// Devuelve `(categoría, valor)` ya recortados, o `null` si se canceló.
/// No devuelve nada ya resuelto contra la base —ni la `PropertyDefinition`
/// ni el `PropertyValue`—: encontrar o crear cada uno a partir del nombre
/// es trabajo del repositorio, igual que en `_AddTagDialog`.
class _AddPropertyDialog extends ConsumerStatefulWidget {
  const _AddPropertyDialog();

  @override
  ConsumerState<_AddPropertyDialog> createState() => _AddPropertyDialogState();
}

class _AddPropertyDialogState extends ConsumerState<_AddPropertyDialog> {
  final _categoryController = TextEditingController();
  final _valueController = TextEditingController();

  @override
  void initState() {
    super.initState();
    // Las sugerencias de las dos listas cambian con lo que se va
    // escribiendo en cada campo.
    _categoryController.addListener(() => setState(() {}));
    _valueController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _categoryController.dispose();
    _valueController.dispose();
    super.dispose();
  }

  void _confirm() {
    final category = _categoryController.text.trim();
    final value = _valueController.text.trim();
    if (category.isEmpty || value.isEmpty) return;

    Navigator.of(context).pop((category, value));
  }

  void _pickCategory(String name) {
    _categoryController.text = name;
    _categoryController.selection = TextSelection.collapsed(
      offset: name.length,
    );
  }

  void _pickValue(String value) {
    _valueController.text = value;
    _valueController.selection = TextSelection.collapsed(offset: value.length);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final definitions =
        ref.watch(allPropertyDefinitionsProvider).valueOrNull ??
        const <PropertyDefinition>[];

    final typedCategory = _categoryController.text.trim().toLowerCase();
    final categorySuggestions = definitions
        .where(
          (d) =>
              typedCategory.isEmpty ||
              d.name.toLowerCase().contains(typedCategory),
        )
        .take(6)
        .toList();

    // Las sugerencias de valor solo tienen sentido una vez que la
    // categoría escrita coincide exacto con una que ya existe: mientras
    // se está escribiendo una categoría nueva, no hay bajo qué categoría
    // buscar valores.
    final matchingDefinition = definitions
        .where((d) => d.name.toLowerCase() == typedCategory)
        .firstOrNull;
    final valueSuggestions = matchingDefinition == null
        ? const <PropertyValue>[]
        : ref
                  .watch(propertyValuesProvider(matchingDefinition.id))
                  .valueOrNull ??
              const <PropertyValue>[];
    final typedValue = _valueController.text.trim().toLowerCase();
    final filteredValueSuggestions = valueSuggestions
        .where(
          (v) =>
              typedValue.isEmpty || v.value.toLowerCase().contains(typedValue),
        )
        .take(6)
        .toList();

    return AlertDialog(
      title: Text(l10n.detailAddProperty),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _categoryController,
              autofocus: true,
              decoration: InputDecoration(
                hintText: l10n.detailPropertyCategoryHint,
              ),
            ),
            if (categorySuggestions.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final definition in categorySuggestions)
                    ActionChip(
                      label: Text(definition.name),
                      onPressed: () => _pickCategory(definition.name),
                    ),
                ],
              ),
            ],
            const SizedBox(height: 12),
            TextField(
              controller: _valueController,
              decoration: InputDecoration(
                hintText: l10n.detailPropertyValueHint,
              ),
              onSubmitted: (_) => _confirm(),
            ),
            if (filteredValueSuggestions.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final value in filteredValueSuggestions)
                    ActionChip(
                      label: Text(value.value),
                      onPressed: () => _pickValue(value.value),
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
        TextButton(onPressed: _confirm, child: Text(l10n.detailAddProperty)),
      ],
    );
  }
}
