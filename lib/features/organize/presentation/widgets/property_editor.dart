import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/core/domain/entities/historical_date.dart';
import 'package:sinapsis/core/domain/entities/item_property.dart';
import 'package:sinapsis/core/domain/entities/knowledge_item.dart';
import 'package:sinapsis/core/domain/entities/property_definition.dart';
import 'package:sinapsis/core/domain/entities/property_value.dart';
import 'package:sinapsis/core/domain/entities/property_value_type.dart';
import 'package:sinapsis/core/error/failure_messages.dart';
import 'package:sinapsis/core/error/failures.dart';
import 'package:sinapsis/features/organize/domain/repositories/organize_repository.dart';
import 'package:sinapsis/features/organize/presentation/providers/organize_providers.dart';
import 'package:sinapsis/features/organize/presentation/widgets/historical_date_form.dart';
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
    final picked = await showDialog<_PickedProperty>(
      context: context,
      builder: (context) => const _AddPropertyDialog(),
    );
    if (picked == null || !context.mounted) return;

    final organize = ref.read(organizeRepositoryProvider);
    final failure = await switch (picked) {
      _PickedText(:final category, :final value) => _assignText(
        organize,
        category: category,
        value: value,
      ),
      _PickedDate(:final definition, :final date) => _assignDate(
        organize,
        definition: definition,
        date: date,
      ),
    };

    if (failure == null || !context.mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            failure.localizedMessage(AppLocalizations.of(context)!),
          ),
        ),
      );
  }

  /// Un valor de texto bajo [category], que se crea si hace falta. Devuelve el
  /// fallo, o `null` si salió bien.
  Future<Failure?> _assignText(
    OrganizeRepository organize, {
    required String category,
    required String value,
  }) async {
    final definitionResult = await organize.getOrCreatePropertyDefinition(
      category,
    );
    final definition = definitionResult.getRight().toNullable();
    if (definition == null) return definitionResult.getLeft().toNullable();

    final assigned = await organize.assignProperty(
      itemId: item.id,
      definitionId: definition.id,
      value: value,
    );
    return assigned.getLeft().toNullable();
  }

  /// Una fecha histórica bajo [definition]. El valor lleva la fecha completa
  /// —año astronómico, rango, precisión, "circa"—, no solo su texto: eso es lo
  /// que la línea de tiempo lee. Devuelve el fallo, o `null` si salió bien.
  Future<Failure?> _assignDate(
    OrganizeRepository organize, {
    required PropertyDefinition definition,
    required HistoricalDate date,
  }) async {
    final valueResult = await organize.getOrCreateHistoricalPropertyValue(
      definitionId: definition.id,
      date: date,
    );
    final propertyValue = valueResult.getRight().toNullable();
    if (propertyValue == null) return valueResult.getLeft().toNullable();

    final assigned = await organize.assignProperty(
      itemId: item.id,
      definitionId: definition.id,
      value: propertyValue.value,
    );
    return assigned.getLeft().toNullable();
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

/// Lo que eligió el usuario en el diálogo de agregar una propiedad.
sealed class _PickedProperty {
  const _PickedProperty();
}

/// Una categoría y un valor de texto, ya recortados. Ni la categoría ni el
/// valor están resueltos contra la base: encontrar o crear cada uno a partir
/// del nombre es trabajo del repositorio, igual que en `_AddTagDialog`.
final class _PickedText extends _PickedProperty {
  const _PickedText(this.category, this.value);

  final String category;
  final String value;
}

/// Una fecha para una categoría de tipo fecha. La categoría sí viene
/// resuelta: el diálogo ya la necesitó para saber que era de fecha.
final class _PickedDate extends _PickedProperty {
  const _PickedDate(this.definition, this.date);

  final PropertyDefinition definition;
  final HistoricalDate date;
}

/// El diálogo para agregar una propiedad: categoría y valor, cada uno con
/// sus propias sugerencias mientras se escribe.
///
/// Si la categoría escrita es una que ya existe y es de tipo fecha —"Fecha
/// del hecho"—, el valor no es un texto libre sino un formulario de fecha:
/// un texto suelto quedaría sin año ni precisión, y la línea de tiempo no
/// tendría cómo ubicarlo.
///
/// Devuelve un [_PickedProperty], o `null` si se canceló.
class _AddPropertyDialog extends ConsumerStatefulWidget {
  const _AddPropertyDialog();

  @override
  ConsumerState<_AddPropertyDialog> createState() => _AddPropertyDialogState();
}

class _AddPropertyDialogState extends ConsumerState<_AddPropertyDialog> {
  final _categoryController = TextEditingController();
  final _valueController = TextEditingController();
  final _dateController = HistoricalDateController();

  @override
  void initState() {
    super.initState();
    // Las sugerencias de las dos listas cambian con lo que se va
    // escribiendo en cada campo.
    _categoryController.addListener(() => setState(() {}));
    _valueController.addListener(() => setState(() {}));
    _dateController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _categoryController.dispose();
    _valueController.dispose();
    _dateController.dispose();
    super.dispose();
  }

  /// La categoría escrita, si coincide exacto con una que ya existe.
  PropertyDefinition? _matchingDefinition(
    List<PropertyDefinition> definitions,
  ) {
    final typed = _categoryController.text.trim().toLowerCase();
    return definitions.where((d) => d.name.toLowerCase() == typed).firstOrNull;
  }

  void _confirm() {
    final definitions =
        ref.read(allPropertyDefinitionsProvider).valueOrNull ??
        const <PropertyDefinition>[];
    final matching = _matchingDefinition(definitions);

    if (matching != null && matching.type == PropertyValueType.date) {
      final date = _dateController.date;
      if (date == null) return;
      Navigator.of(context).pop(_PickedDate(matching, date));
      return;
    }

    final category = _categoryController.text.trim();
    final value = _valueController.text.trim();
    if (category.isEmpty || value.isEmpty) return;

    Navigator.of(context).pop(_PickedText(category, value));
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
    final matchingDefinition = _matchingDefinition(definitions);
    final isDateCategory = matchingDefinition?.type == PropertyValueType.date;
    final valueSuggestions = matchingDefinition == null || isDateCategory
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
      // El formulario de fecha es más alto que un campo de texto: en una
      // pantalla baja tiene que poder desplazarse.
      scrollable: true,
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
            if (isDateCategory)
              HistoricalDateForm(controller: _dateController)
            else
              TextField(
                controller: _valueController,
                decoration: InputDecoration(
                  hintText: l10n.detailPropertyValueHint,
                ),
                onSubmitted: (_) => _confirm(),
              ),
            if (!isDateCategory && filteredValueSuggestions.isNotEmpty) ...[
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
        TextButton(
          // Con una fecha a medio escribir no hay nada que confirmar; con
          // texto, confirmar en blanco simplemente no cierra el diálogo.
          onPressed: isDateCategory && _dateController.date == null
              ? null
              : _confirm,
          child: Text(l10n.detailAddProperty),
        ),
      ],
    );
  }
}
