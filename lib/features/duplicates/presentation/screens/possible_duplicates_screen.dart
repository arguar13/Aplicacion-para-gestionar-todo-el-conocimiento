import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/core/domain/entities/suggestion.dart';
import 'package:sinapsis/core/error/failure_messages.dart';
import 'package:sinapsis/features/library/presentation/providers/library_providers.dart';
import 'package:sinapsis/features/suggestions/presentation/providers/suggestion_providers.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// Lo que el generador de duplicados (F7) encontró parecido a algo que
/// ya existe, en toda la bóveda —no un elemento puntual—, con su
/// propia confirmación explícita por fila antes de fusionar nada:
/// fusionar borra un elemento, y eso pide más que un casillero en el
/// diálogo genérico de revisión de sugerencias (D4).
class PossibleDuplicatesScreen extends ConsumerWidget {
  const PossibleDuplicatesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final suggestions = ref.watch(pendingDuplicateSuggestionsProvider);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.duplicatesTitle)),
      body: switch (suggestions) {
        AsyncData(:final value) =>
          value.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      l10n.duplicatesEmpty,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyLarge,
                    ),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  itemCount: value.length,
                  itemBuilder: (context, index) => _DuplicateCard(
                    suggestion: value[index] as DuplicateSuggestionEntry,
                  ),
                ),
        AsyncError(:final error) => Center(child: Text('$error')),
        _ => const Center(child: CircularProgressIndicator()),
      },
    );
  }
}

/// Un posible duplicado, con los dos títulos a la vista —cuál se
/// conserva y cuál se descartaría— antes de que quien mira decida.
class _DuplicateCard extends ConsumerWidget {
  const _DuplicateCard({required this.suggestion});

  final DuplicateSuggestionEntry suggestion;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final target = ref
        .watch(libraryItemProvider(suggestion.targetItemId))
        .valueOrNull;
    // El elemento que se conserva puede haber desaparecido —se borró a
    // mano mientras tanto—: sin él no hay nada coherente que mostrar en
    // esta fila todavía, así que se espera al próximo cambio en vez de
    // mostrar un título en blanco.
    if (target == null) return const SizedBox.shrink();

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _ItemRow(
              icon: Icons.check_circle_outline,
              color: theme.colorScheme.primary,
              label: l10n.duplicatesKeepLabel,
              title: target.title,
            ),
            const SizedBox(height: 8),
            _ItemRow(
              icon: Icons.delete_outline,
              color: theme.colorScheme.error,
              label: l10n.duplicatesDiscardLabel,
              title: suggestion.duplicateItemTitle,
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => _discard(context, ref),
                  child: Text(l10n.duplicatesDiscardAction),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: () => _confirmAndMerge(context, ref, target.title),
                  child: Text(l10n.duplicatesMergeAction),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmAndMerge(
    BuildContext context,
    WidgetRef ref,
    String keepTitle,
  ) async {
    final l10n = AppLocalizations.of(context)!;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.duplicatesMergeConfirmTitle),
        content: Text(
          l10n.duplicatesMergeConfirmBody(
            suggestion.duplicateItemTitle,
            keepTitle,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n.commonCancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l10n.duplicatesMergeAction),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;

    final result = await ref
        .read(suggestionRepositoryProvider)
        .accept(suggestion.id);
    if (!context.mounted) return;

    final failure = result.getLeft().toNullable();
    if (failure != null) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(failure.localizedMessage(l10n))));
    }
  }

  Future<void> _discard(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context)!;

    final result = await ref
        .read(suggestionRepositoryProvider)
        .reject(suggestion.id);
    if (!context.mounted) return;

    result.match(
      (failure) => ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(failure.localizedMessage(l10n)))),
      (_) => ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(l10n.duplicatesDiscarded))),
    );
  }
}

class _ItemRow extends StatelessWidget {
  const _ItemRow({
    required this.icon,
    required this.color,
    required this.label,
    required this.title,
  });

  final IconData icon;
  final Color color;
  final String label;
  final String title;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: theme.textTheme.labelSmall?.copyWith(color: color),
              ),
              Text(title, style: theme.textTheme.bodyMedium),
            ],
          ),
        ),
      ],
    );
  }
}
