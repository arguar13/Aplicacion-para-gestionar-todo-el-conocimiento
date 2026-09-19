import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/features/vocabulary/domain/entities/vocabulary_stats.dart';
import 'package:sinapsis/features/vocabulary/presentation/providers/vocabulary_providers.dart';
import 'package:sinapsis/features/vocabulary/presentation/widgets/vocabulary_feedback.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// Abre el detalle de un valor: su nombre y cuánto se usa, con lo necesario
/// para renombrarlo y para ver, agregar y quitar sus alias.
Future<void> openVocabularyValue(
  BuildContext context, {
  required String definitionId,
  required String valueId,
}) {
  return Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (context) =>
          VocabularyValueScreen(definitionId: definitionId, valueId: valueId),
    ),
  );
}

/// Un valor del vocabulario en detalle.
///
/// Es una PÁGINA y no una hoja modal a propósito: cada cosa que se hace acá
/// —agregar o quitar un alias, renombrar— avisa con un `SnackBar` que trae su
/// "Deshacer", y la barrera de una hoja modal tapa el aviso de la pantalla de
/// abajo: no se podría tocar, y caducaría antes de que se cerrara la hoja.
class VocabularyValueScreen extends ConsumerStatefulWidget {
  const VocabularyValueScreen({
    required this.definitionId,
    required this.valueId,
    super.key,
  });

  final String definitionId;
  final String valueId;

  @override
  ConsumerState<VocabularyValueScreen> createState() =>
      _VocabularyValueScreenState();
}

class _VocabularyValueScreenState extends ConsumerState<VocabularyValueScreen> {
  final TextEditingController _alias = TextEditingController();

  @override
  void dispose() {
    _alias.dispose();
    super.dispose();
  }

  Future<void> _rename(VocabularyValueStat value) async {
    final feedback = VocabularyFeedback.of(context, ref);
    final controller = ref.read(vocabularyControllerProvider.notifier);
    final label = await askNewValueName(context, value.label);
    if (label == null) return;

    feedback.report(await controller.rename(id: value.id, label: label));
  }

  Future<void> _addAlias() async {
    final feedback = VocabularyFeedback.of(context, ref);
    final controller = ref.read(vocabularyControllerProvider.notifier);
    final text = _alias.text;
    if (text.trim().isEmpty) return;

    final result = await controller.addAlias(
      valueId: widget.valueId,
      alias: text,
    );
    // El campo se vacía solo si el alias se agregó: uno que falló —porque ya
    // existe— se deja para corregirlo.
    if (mounted && result.isRight()) _alias.clear();
    feedback.report(result);
  }

  Future<void> _removeAlias(VocabularyAlias alias) async {
    final feedback = VocabularyFeedback.of(context, ref);
    final controller = ref.read(vocabularyControllerProvider.notifier);

    feedback.report(await controller.removeAlias(alias.id));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final canUndo = ref.watch(vocabularyControllerProvider) != null;

    final value = ref
        .watch(categoryValuesProvider(widget.definitionId))
        .valueOrNull
        ?.where((v) => v.id == widget.valueId)
        .firstOrNull;
    final aliases = ref.watch(valueAliasesProvider(widget.valueId));

    return Scaffold(
      appBar: AppBar(
        title: Text(value?.label ?? l10n.vocabularyTitle),
        actions: [
          if (value != null)
            IconButton(
              tooltip: l10n.commonRename,
              icon: const Icon(Icons.edit_outlined),
              onPressed: () => _rename(value),
            ),
          IconButton(
            tooltip: l10n.vocabularyUndoTooltip,
            icon: const Icon(Icons.undo),
            onPressed: canUndo
                ? VocabularyFeedback.of(context, ref).undo
                : null,
          ),
        ],
      ),
      body: value == null
          // El valor se fusionó o se borró mientras esta página estaba
          // abierta: ya no hay nada que mostrar.
          ? const SizedBox.shrink()
          : ListView(
              padding: const EdgeInsets.all(20),
              children: [
                Text(
                  l10n.vocabularyUsage(value.usage),
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  l10n.vocabularyAliasesTitle,
                  style: theme.textTheme.titleSmall,
                ),
                const SizedBox(height: 8),
                switch (aliases) {
                  AsyncData(:final value) when value.isEmpty => Text(
                    l10n.vocabularyAliasesEmpty,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  AsyncData(:final value) => Wrap(
                    spacing: 8,
                    children: [
                      for (final alias in value)
                        InputChip(
                          label: Text(alias.alias),
                          deleteButtonTooltipMessage: l10n
                              .vocabularyRemoveAliasTooltip(alias.alias),
                          onDeleted: () => _removeAlias(alias),
                        ),
                    ],
                  ),
                  _ => const SizedBox.shrink(),
                },
                const SizedBox(height: 16),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _alias,
                        decoration: InputDecoration(
                          labelText: l10n.vocabularyAddAliasLabel,
                        ),
                        onSubmitted: (_) => _addAlias(),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: FilledButton.tonal(
                        onPressed: _addAlias,
                        child: Text(l10n.vocabularyAddAliasAction),
                      ),
                    ),
                  ],
                ),
              ],
            ),
    );
  }
}
