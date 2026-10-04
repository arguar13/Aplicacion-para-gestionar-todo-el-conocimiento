import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fpdart/fpdart.dart';
import 'package:go_router/go_router.dart';
import 'package:sinapsis/app/router/route_paths.dart';
import 'package:sinapsis/core/error/failure_messages.dart';
import 'package:sinapsis/core/error/failures.dart';
import 'package:sinapsis/features/ai_organize/presentation/providers/ai_organize_queue_providers.dart';
import 'package:sinapsis/features/flashcards/domain/repositories/flashcard_coverage_reader.dart';
import 'package:sinapsis/features/flashcards/presentation/providers/ai_flashcards_providers.dart';
import 'package:sinapsis/features/notebooks/presentation/providers/notebook_providers.dart';
import 'package:sinapsis/features/organize/presentation/providers/organize_providers.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// Abre la hoja de «Crear tarjetas con IA» (F30): para qué elementos, cuántos
/// entran y cuántos ya tienen tarjetas, y el botón que se las pide a la cola
/// de la IA.
Future<void> showAiFlashcardsSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (context) => const AiFlashcardsSheet(),
  );
}

/// La hoja de «Crear tarjetas con IA» (F30).
///
/// Se elige el alcance —toda la biblioteca, un tema, una etiqueta o un
/// cuaderno— y la hoja cuenta, de ahí, cuántos elementos tienen texto y
/// cuántos ya tienen tarjetas. Por defecto se piden solo los que no tienen
/// ninguna: no se duplica nada. «También los que ya tienen» les hace otra
/// tanda, sin repetir preguntas.
///
/// Pedirlas no espera nada: la cola de la IA las hace en segundo plano, con
/// su notificación, y Repasar muestra cómo va.
class AiFlashcardsSheet extends ConsumerStatefulWidget {
  const AiFlashcardsSheet({super.key});

  @override
  ConsumerState<AiFlashcardsSheet> createState() => _AiFlashcardsSheetState();
}

class _AiFlashcardsSheetState extends ConsumerState<AiFlashcardsSheet> {
  var _kind = AiFlashcardsScopeKind.library;

  /// Lo elegido en cada tipo: cambiar de tipo y volver no lo pierde.
  final _chosen = <AiFlashcardsScopeKind, String>{};
  var _alsoWithCards = false;

  AiFlashcardsScope? get _scope {
    if (_kind == AiFlashcardsScopeKind.library) {
      return const AiFlashcardsScope.library();
    }
    final id = _chosen[_kind];
    return id == null ? null : AiFlashcardsScope(_kind, id);
  }

  void _start(FlashcardCoverage coverage) {
    final l10n = AppLocalizations.of(context)!;
    final ids = _alsoWithCards ? coverage.eligible : coverage.withoutCards;
    ref
        .read(aiOrganizeQueueProvider)
        .makeFlashcards(ids, anotherBatch: _alsoWithCards);
    final messenger = ScaffoldMessenger.of(context);
    Navigator.of(context).pop();
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(l10n.reviewAiStarted)));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final scope = _scope;
    final coverage = scope == null
        ? null
        : ref.watch(aiFlashcardsCoverageProvider(scope));
    final modelReady = ref.watch(languageModelReadyProvider).valueOrNull;

    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.85,
      ),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(Icons.auto_awesome, color: scheme.primary),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      l10n.reviewAiSheetTitle,
                      style: theme.textTheme.titleLarge,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                l10n.reviewAiSheetIntro,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 20),
              Text(l10n.reviewAiScopeTitle, style: theme.textTheme.labelLarge),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  for (final kind in AiFlashcardsScopeKind.values)
                    ChoiceChip(
                      key: Key('ai-cards-scope-${kind.name}'),
                      label: Text(_kindLabel(l10n, kind)),
                      avatar: Icon(_kindIcon(kind), size: 18),
                      showCheckmark: false,
                      selected: _kind == kind,
                      onSelected: (_) => setState(() => _kind = kind),
                    ),
                ],
              ),
              AnimatedSize(
                duration: const Duration(milliseconds: 200),
                alignment: Alignment.topCenter,
                child: _kind == AiFlashcardsScopeKind.library
                    ? const SizedBox(width: double.infinity)
                    : Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: _ScopePicker(
                          kind: _kind,
                          selected: _chosen[_kind],
                          onSelected: (id) =>
                              setState(() => _chosen[_kind] = id),
                        ),
                      ),
              ),
              const SizedBox(height: 16),
              _CoverageLine(coverage: coverage),
              const SizedBox(height: 8),
              SwitchListTile(
                key: const Key('ai-cards-also-with-cards'),
                contentPadding: EdgeInsets.zero,
                title: Text(l10n.reviewAiAlsoWithCards),
                subtitle: Text(l10n.reviewAiAlsoWithCardsHint),
                value: _alsoWithCards,
                onChanged: (value) => setState(() => _alsoWithCards = value),
              ),
              if (modelReady == false) ...[
                const SizedBox(height: 8),
                _ModelMissing(l10n: l10n),
              ],
              const SizedBox(height: 16),
              _StartButton(
                coverage: coverage?.valueOrNull?.getRight().toNullable(),
                alsoWithCards: _alsoWithCards,
                enabled: modelReady ?? false,
                onStart: _start,
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _kindLabel(AppLocalizations l10n, AiFlashcardsScopeKind kind) =>
      switch (kind) {
        AiFlashcardsScopeKind.library => l10n.reviewAiScopeLibrary,
        AiFlashcardsScopeKind.space => l10n.reviewAiScopeSpace,
        AiFlashcardsScopeKind.tag => l10n.reviewAiScopeTag,
        AiFlashcardsScopeKind.notebook => l10n.reviewAiScopeNotebook,
      };

  static IconData _kindIcon(AiFlashcardsScopeKind kind) => switch (kind) {
    AiFlashcardsScopeKind.library => Icons.local_library_outlined,
    AiFlashcardsScopeKind.space => Icons.folder_outlined,
    AiFlashcardsScopeKind.tag => Icons.label_outline,
    AiFlashcardsScopeKind.notebook => Icons.menu_book_outlined,
  };
}

/// Cuál tema, etiqueta o cuaderno: la lista de los que hay, o que todavía no
/// hay ninguno.
class _ScopePicker extends ConsumerWidget {
  const _ScopePicker({
    required this.kind,
    required this.selected,
    required this.onSelected,
  });

  final AiFlashcardsScopeKind kind;
  final String? selected;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final options = switch (kind) {
      AiFlashcardsScopeKind.space =>
        ref
            .watch(allSpacesProvider)
            .whenData((all) => [for (final s in all) (id: s.id, name: s.name)]),
      AiFlashcardsScopeKind.tag =>
        ref
            .watch(allTagsProvider)
            .whenData((all) => [for (final t in all) (id: t.id, name: t.name)]),
      AiFlashcardsScopeKind.notebook =>
        ref
            .watch(notebooksProvider)
            .whenData((all) => [for (final n in all) (id: n.id, name: n.name)]),
      AiFlashcardsScopeKind.library => const AsyncValue.data(
        <({String id, String name})>[],
      ),
    };
    final list = options.valueOrNull;
    if (list == null) return const LinearProgressIndicator();
    if (list.isEmpty) {
      return Text(
        l10n.reviewAiNothingToPick,
        style: theme.textTheme.bodyMedium?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      );
    }
    final sorted = [...list]
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return DropdownMenu<String>(
      key: Key('ai-cards-pick-${kind.name}'),
      expandedInsets: EdgeInsets.zero,
      initialSelection: selected,
      hintText: switch (kind) {
        AiFlashcardsScopeKind.space => l10n.reviewAiPickSpace,
        AiFlashcardsScopeKind.tag => l10n.reviewAiPickTag,
        _ => l10n.reviewAiPickNotebook,
      },
      onSelected: (id) {
        if (id != null) onSelected(id);
      },
      dropdownMenuEntries: [
        for (final option in sorted)
          DropdownMenuEntry(value: option.id, label: option.name),
      ],
    );
  }
}

/// Cuántos entran y cuántos ya tienen tarjetas, o por qué no se pudo contar.
class _CoverageLine extends StatelessWidget {
  const _CoverageLine({required this.coverage});

  /// `null` mientras no se eligió de cuál tema, etiqueta o cuaderno.
  final AsyncValue<Either<Failure, FlashcardCoverage>>? coverage;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final value = coverage;
    final error = theme.textTheme.bodyMedium?.copyWith(color: scheme.error);

    final child = switch (value) {
      null => const SizedBox(height: 40, key: ValueKey('none')),
      AsyncValue(hasValue: false, hasError: false) => const Padding(
        key: ValueKey('loading'),
        padding: EdgeInsets.symmetric(vertical: 18),
        child: LinearProgressIndicator(),
      ),
      AsyncValue(hasError: true) => Text(
        l10n.reviewAiCoverageFailed,
        key: const ValueKey('error'),
        style: error,
      ),
      AsyncValue(:final value) => value!.match(
        (failure) => Text(
          failure.localizedMessage(l10n),
          key: const ValueKey('failure'),
          style: error,
        ),
        (coverage) => _CoverageCounts(coverage: coverage),
      ),
    };
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 200),
      child: child,
    );
  }
}

/// Los dos números, en una tarjeta tranquila.
class _CoverageCounts extends StatelessWidget {
  const _CoverageCounts({required this.coverage});

  final FlashcardCoverage coverage;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      key: const Key('ai-cards-coverage'),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(Icons.style_outlined, color: scheme.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.reviewAiCoverage(coverage.eligible.length),
                  style: theme.textTheme.bodyLarge,
                ),
                if (coverage.eligible.isNotEmpty)
                  Text(
                    l10n.reviewAiCoverageWithCards(coverage.withCards.length),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Falta bajar el modelo de lenguaje: sin él no hay tarjetas, y se ofrece
/// bajarlo.
class _ModelMissing extends StatelessWidget {
  const _ModelMissing({required this.l10n});

  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 8, 8, 8),
      decoration: BoxDecoration(
        color: scheme.errorContainer.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(Icons.download_for_offline_outlined, color: scheme.error),
          const SizedBox(width: 12),
          Expanded(child: Text(l10n.flashcardsModelMissing)),
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              context.push(RoutePaths.chatModel);
            },
            child: Text(l10n.flashcardsDownloadModel),
          ),
        ],
      ),
    );
  }
}

/// «Crear tarjetas de N elementos»: los que no tienen, o todos con «también
/// los que ya tienen». Sin ninguno, o sin el modelo, no se puede.
class _StartButton extends StatelessWidget {
  const _StartButton({
    required this.coverage,
    required this.alsoWithCards,
    required this.enabled,
    required this.onStart,
  });

  final FlashcardCoverage? coverage;
  final bool alsoWithCards;
  final bool enabled;
  final ValueChanged<FlashcardCoverage> onStart;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final current = coverage;
    final count = current == null
        ? 0
        : (alsoWithCards
              ? current.eligible.length
              : current.withoutCards.length);
    return FilledButton.icon(
      key: const Key('ai-cards-start'),
      onPressed: enabled && current != null && count > 0
          ? () => onStart(current)
          : null,
      icon: const Icon(Icons.auto_awesome),
      label: Text(l10n.reviewAiStart(count)),
    );
  }
}
