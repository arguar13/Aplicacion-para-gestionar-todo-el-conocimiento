import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/features/vocabulary/domain/entities/vocabulary_stats.dart';
import 'package:sinapsis/features/vocabulary/presentation/providers/vocabulary_providers.dart';
import 'package:sinapsis/features/vocabulary/presentation/widgets/candidate_group_card.dart';
import 'package:sinapsis/features/vocabulary/presentation/widgets/vocabulary_feedback.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// El mantenimiento del vocabulario controlado: qué valores se repiten, cuáles
/// se usan una sola vez, cuáles no se usan y qué categorías quedaron vacías.
///
/// Nada se cambia sin que quien mira lo decida, y toda operación se puede
/// deshacer —la última, mientras dure la sesión—.
class VocabularyScreen extends ConsumerWidget {
  const VocabularyScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final canUndo = ref.watch(vocabularyControllerProvider) != null;

    int count<T>(AsyncValue<List<T>> value) => value.valueOrNull?.length ?? 0;
    final candidates = count(ref.watch(mergeCandidateGroupsProvider));
    final singleUse = count(ref.watch(singleUseValuesProvider));
    final unused = count(ref.watch(unusedValuesProvider));
    final empty = count(ref.watch(orphanCategoriesProvider));

    return DefaultTabController(
      length: 4,
      child: Scaffold(
        appBar: AppBar(
          title: Text(l10n.vocabularyTitle),
          actions: [
            IconButton(
              tooltip: l10n.vocabularyUndoTooltip,
              icon: const Icon(Icons.undo),
              onPressed: canUndo
                  ? VocabularyFeedback.of(context, ref).undo
                  : null,
            ),
          ],
          bottom: TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: [
              Tab(text: l10n.vocabularyTabCandidates(candidates)),
              Tab(text: l10n.vocabularyTabSingleUse(singleUse)),
              Tab(text: l10n.vocabularyTabUnused(unused)),
              Tab(text: l10n.vocabularyTabEmptyCategories(empty)),
            ],
          ),
        ),
        body: const TabBarView(
          children: [
            _CandidatesTab(),
            _SingleUseTab(),
            _UnusedTab(),
            _EmptyCategoriesTab(),
          ],
        ),
      ),
    );
  }
}

/// Un mensaje centrado, para los estados vacíos y de error.
class _CenteredMessage extends StatelessWidget {
  const _CenteredMessage(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyLarge,
        ),
      ),
    );
  }
}

/// El cuerpo de una pestaña según el estado de su lista: carga, error, vacío o
/// la lista en sí.
class _AsyncList<T> extends StatelessWidget {
  const _AsyncList({
    required this.value,
    required this.emptyText,
    required this.builder,
  });

  final AsyncValue<List<T>> value;
  final String emptyText;
  final Widget Function(BuildContext context, List<T> items) builder;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return value.when(
      data: (items) =>
          items.isEmpty ? _CenteredMessage(emptyText) : builder(context, items),
      error: (_, _) => _CenteredMessage(l10n.vocabularyLoadError),
      loading: () => const Center(child: CircularProgressIndicator()),
    );
  }
}

class _CandidatesTab extends ConsumerWidget {
  const _CandidatesTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;

    return _AsyncList<MergeCandidateGroup>(
      value: ref.watch(mergeCandidateGroupsProvider),
      emptyText: l10n.vocabularyCandidatesEmpty,
      builder: (context, groups) => ListView.builder(
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: groups.length,
        itemBuilder: (context, index) {
          final group = groups[index];
          // La llave es su contenido: si el grupo cambia —se fusionó algo—,
          // la tarjeta arranca de cero en vez de arrastrar una selección que
          // ya no corresponde.
          return CandidateGroupCard(
            key: ValueKey(group.values.map((v) => v.id).join('|')),
            group: group,
          );
        },
      ),
    );
  }
}

class _SingleUseTab extends ConsumerWidget {
  const _SingleUseTab();

  Future<void> _rename(
    BuildContext context,
    WidgetRef ref,
    VocabularyValueStat value,
  ) async {
    final feedback = VocabularyFeedback.of(context, ref);
    final controller = ref.read(vocabularyControllerProvider.notifier);
    final label = await askNewValueName(context, value.label);
    if (label == null) return;

    feedback.report(await controller.rename(id: value.id, label: label));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;

    return _AsyncList<VocabularyValueStat>(
      value: ref.watch(singleUseValuesProvider),
      emptyText: l10n.vocabularySingleUseEmpty,
      builder: (context, values) => ListView.builder(
        itemCount: values.length,
        itemBuilder: (context, index) {
          final value = values[index];
          return ListTile(
            title: Text(value.label),
            subtitle: Text(
              [
                value.definitionName,
                if (value.aliasCount > 0)
                  l10n.vocabularyAliasCount(value.aliasCount),
              ].join(' · '),
            ),
            trailing: IconButton(
              tooltip: l10n.commonRename,
              icon: const Icon(Icons.edit_outlined),
              onPressed: () => _rename(context, ref, value),
            ),
          );
        },
      ),
    );
  }
}

class _UnusedTab extends ConsumerStatefulWidget {
  const _UnusedTab();

  @override
  ConsumerState<_UnusedTab> createState() => _UnusedTabState();
}

class _UnusedTabState extends ConsumerState<_UnusedTab> {
  final Set<String> _selected = {};

  /// Borra [ids]: lo que se ve marcado, no el conjunto crudo, que puede
  /// arrastrar ids de valores que ya dejaron de estar sin uso.
  Future<void> _delete(List<String> ids) async {
    final l10n = AppLocalizations.of(context)!;
    final feedback = VocabularyFeedback.of(context, ref);
    final controller = ref.read(vocabularyControllerProvider.notifier);
    final confirmed = await confirmVocabularyAction(
      context,
      title: l10n.vocabularyDeleteConfirmTitle,
      body: l10n.vocabularyDeleteConfirmBody(ids.length),
      confirmLabel: l10n.commonDelete,
    );
    if (!confirmed) return;

    final result = await controller.deleteUnused(ids);
    if (mounted && result.isRight()) setState(_selected.clear);
    feedback.report(result);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final async = ref.watch(unusedValuesProvider);

    // Lo marcado que ya no existe —se borró, o dejó de estar sin uso— se
    // olvida solo: no se puede pedir borrar algo que ya no está en la lista.
    final present = async.valueOrNull?.map((v) => v.id).toSet() ?? const {};
    final selected = _selected.intersection(present);

    return _AsyncList<VocabularyValueStat>(
      value: async,
      emptyText: l10n.vocabularyUnusedEmpty,
      builder: (context, values) => Column(
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: TextButton(
                onPressed: () => setState(() {
                  _selected
                    ..clear()
                    ..addAll(values.map((v) => v.id));
                }),
                child: Text(l10n.vocabularySelectAll),
              ),
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: values.length,
              itemBuilder: (context, index) {
                final value = values[index];
                return CheckboxListTile(
                  value: selected.contains(value.id),
                  onChanged: (checked) => setState(() {
                    if (checked ?? false) {
                      _selected.add(value.id);
                    } else {
                      _selected.remove(value.id);
                    }
                  }),
                  title: Text(value.label),
                  subtitle: Text(value.definitionName),
                );
              },
            ),
          ),
          if (selected.isNotEmpty)
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton.tonal(
                    onPressed: () => _delete(selected.toList()),
                    child: Text(l10n.vocabularyDeleteAction(selected.length)),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _EmptyCategoriesTab extends ConsumerWidget {
  const _EmptyCategoriesTab();

  Future<void> _delete(
    BuildContext context,
    WidgetRef ref,
    VocabularyCategoryStat category,
  ) async {
    final l10n = AppLocalizations.of(context)!;
    final feedback = VocabularyFeedback.of(context, ref);
    final controller = ref.read(vocabularyControllerProvider.notifier);
    final confirmed = await confirmVocabularyAction(
      context,
      title: l10n.vocabularyDeleteCategoryConfirmTitle,
      body: l10n.vocabularyDeleteCategoryConfirmBody(category.name),
      confirmLabel: l10n.commonDelete,
    );
    if (!confirmed) return;

    feedback.report(await controller.deleteCategories([category.id]));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;

    return _AsyncList<VocabularyCategoryStat>(
      value: ref.watch(orphanCategoriesProvider),
      emptyText: l10n.vocabularyEmptyCategoriesEmpty,
      builder: (context, categories) => ListView.builder(
        itemCount: categories.length,
        itemBuilder: (context, index) {
          final category = categories[index];
          return ListTile(
            title: Text(category.name),
            trailing: IconButton(
              tooltip: l10n.vocabularyDeleteCategoryTooltip(category.name),
              icon: const Icon(Icons.delete_outline),
              onPressed: () => _delete(context, ref, category),
            ),
          );
        },
      ),
    );
  }
}
