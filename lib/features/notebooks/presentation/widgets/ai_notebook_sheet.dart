import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/features/library/presentation/widgets/entity_presentation.dart';
import 'package:sinapsis/features/notebooks/domain/entities/notebook.dart';
import 'package:sinapsis/features/notebooks/domain/services/notebook_candidates.dart';
import 'package:sinapsis/features/notebooks/presentation/providers/ai_notebook_controller.dart';
import 'package:sinapsis/features/notebooks/presentation/providers/notebook_providers.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// Abre «Crear con IA» (F30). Devuelve el cuaderno creado, o `null`.
Future<Notebook?> showAiNotebookSheet(BuildContext context) {
  return showModalBottomSheet<Notebook>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (context) => const AiNotebookSheet(),
  );
}

/// La hoja de «Crear con IA» (F30, decisión B): primero, de qué es el
/// cuaderno; después, lo que se encontró, marcado, para sacar lo que no va
/// —con la revisión de la IA llegando por tandas— y el nombre.
class AiNotebookSheet extends ConsumerStatefulWidget {
  const AiNotebookSheet({super.key});

  @override
  ConsumerState<AiNotebookSheet> createState() => _AiNotebookSheetState();
}

class _AiNotebookSheetState extends ConsumerState<AiNotebookSheet> {
  final _topic = TextEditingController();
  final _name = TextEditingController();
  var _creating = false;

  @override
  void dispose() {
    _topic.dispose();
    _name.dispose();
    super.dispose();
  }

  void _search() {
    final topic = _topic.text.trim();
    if (topic.isEmpty) return;
    FocusScope.of(context).unfocus();
    _name.text = notebookNameFrom(topic);
    ref.read(aiNotebookControllerProvider.notifier).search(topic);
  }

  Future<void> _create() async {
    setState(() => _creating = true);
    final notebook = await ref
        .read(aiNotebookControllerProvider.notifier)
        .create(_name.text.trim());
    if (!mounted) return;
    Navigator.of(context).pop(notebook);
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(aiNotebookControllerProvider);
    final keyboard = MediaQuery.viewInsetsOf(context).bottom;

    final Widget body;
    if (state == null) {
      body = _AskTopic(controller: _topic, onSearch: _search);
    } else if (state.searching) {
      body = _Searching(topic: state.topic);
    } else if (state.picks.isEmpty) {
      body = _NothingFound(
        topic: state.topic,
        onRetry: () =>
            ref.read(aiNotebookControllerProvider.notifier).restart(),
      );
    } else {
      body = _Proposal(
        state: state,
        name: _name,
        creating: _creating,
        onCreate: _create,
      );
    }

    return Padding(
      padding: EdgeInsets.only(bottom: keyboard),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.9,
        ),
        child: AnimatedSize(
          duration: const Duration(milliseconds: 200),
          alignment: Alignment.topCenter,
          child: body,
        ),
      ),
    );
  }
}

/// El encabezado de la hoja: el ✨ y el título.
class _Header extends StatelessWidget {
  const _Header({required this.title, this.onBack});

  final String title;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;
    return Row(
      children: [
        if (onBack != null)
          IconButton(
            key: const Key('ai-notebook-back'),
            icon: const Icon(Icons.arrow_back),
            tooltip: l10n.aiNotebookChangeSearch,
            onPressed: onBack,
          )
        else ...[
          Icon(Icons.auto_awesome, color: theme.colorScheme.primary),
          const SizedBox(width: 12),
        ],
        Expanded(child: Text(title, style: theme.textTheme.titleLarge)),
      ],
    );
  }
}

class _AskTopic extends ConsumerWidget {
  const _AskTopic({required this.controller, required this.onSearch});

  final TextEditingController controller;
  final VoidCallback onSearch;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    final models = ref.watch(notebookAiModelsProvider).valueOrNull;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Header(title: l10n.aiNotebookTitle),
          const SizedBox(height: 8),
          Text(
            l10n.aiNotebookIntro,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 20),
          TextField(
            key: const Key('ai-notebook-topic'),
            controller: controller,
            autofocus: true,
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              hintText: l10n.aiNotebookTopicHint,
              border: const OutlineInputBorder(),
            ),
            onSubmitted: (_) => onSearch(),
          ),
          if (models != null) ...[
            const SizedBox(height: 12),
            _ModelLine(
              on: models.sense,
              text: models.sense
                  ? l10n.aiNotebookSenseOn
                  : l10n.aiNotebookSenseOff,
              style: muted,
            ),
            const SizedBox(height: 4),
            _ModelLine(
              on: models.language,
              text: models.language
                  ? l10n.aiNotebookReviewOn
                  : l10n.aiNotebookReviewOff,
              style: muted,
            ),
          ],
          const SizedBox(height: 20),
          ValueListenableBuilder(
            valueListenable: controller,
            builder: (context, value, _) => FilledButton.icon(
              key: const Key('ai-notebook-search'),
              onPressed: value.text.trim().isEmpty ? null : onSearch,
              icon: const Icon(Icons.search),
              label: Text(l10n.aiNotebookSearch),
            ),
          ),
        ],
      ),
    );
  }
}

/// Una línea de qué puede hacer la búsqueda con los modelos que hay.
class _ModelLine extends StatelessWidget {
  const _ModelLine({required this.on, required this.text, this.style});

  final bool on;
  final String text;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          on ? Icons.check_circle_outline : Icons.info_outline,
          size: 16,
          color: on ? scheme.primary : scheme.onSurfaceVariant,
        ),
        const SizedBox(width: 8),
        Expanded(child: Text(text, style: style)),
      ],
    );
  }
}

class _Searching extends StatelessWidget {
  const _Searching({required this.topic});

  final String topic;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Header(title: topic),
          const SizedBox(height: 24),
          const LinearProgressIndicator(),
          const SizedBox(height: 12),
          Text(
            l10n.aiNotebookSearching,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _NothingFound extends StatelessWidget {
  const _NothingFound({required this.topic, required this.onRetry});

  final String topic;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.search_off_outlined,
            size: 40,
            color: theme.colorScheme.outline,
          ),
          const SizedBox(height: 12),
          Text(
            l10n.aiNotebookNothing(topic),
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyLarge,
          ),
          const SizedBox(height: 16),
          OutlinedButton(
            key: const Key('ai-notebook-retry'),
            onPressed: onRetry,
            child: Text(l10n.aiNotebookTryOther),
          ),
        ],
      ),
    );
  }
}

class _Proposal extends ConsumerWidget {
  const _Proposal({
    required this.state,
    required this.name,
    required this.creating,
    required this.onCreate,
  });

  final AiNotebookState state;
  final TextEditingController name;
  final bool creating;
  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final controller = ref.read(aiNotebookControllerProvider.notifier);
    final count = state.checkedCount;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 24, 0),
          child: _Header(
            title: l10n.aiNotebookFound(state.picks.length),
            onBack: controller.restart,
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 4),
          child: TextField(
            key: const Key('ai-notebook-name'),
            controller: name,
            decoration: InputDecoration(
              labelText: l10n.aiNotebookNameLabel,
              border: const OutlineInputBorder(),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 8),
          child: _ReviewStatus(state: state),
        ),
        Flexible(
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: state.picks.length,
            itemBuilder: (context, index) => _PickTile(
              pick: state.picks[index],
              onToggle: () =>
                  controller.toggle(state.picks[index].candidate.itemId),
            ),
          ),
        ),
        const Divider(height: 1),
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 16),
          child: ValueListenableBuilder(
            valueListenable: name,
            builder: (context, value, _) => FilledButton.icon(
              key: const Key('ai-notebook-create'),
              onPressed: creating || count == 0 || value.text.trim().isEmpty
                  ? null
                  : onCreate,
              icon: const Icon(Icons.auto_stories_outlined),
              label: Text(l10n.aiNotebookCreate(count)),
            ),
          ),
        ),
      ],
    );
  }
}

/// Cómo se buscó y en qué anda la revisión de la IA.
class _ReviewStatus extends StatelessWidget {
  const _ReviewStatus({required this.state});

  final AiNotebookState state;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: scheme.onSurfaceVariant,
    );

    final review = switch (state) {
      AiNotebookState(reviewing: true) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LinearProgressIndicator(
            value: state.toReview == 0 ? null : state.reviewed / state.toReview,
          ),
          const SizedBox(height: 6),
          Text(
            l10n.aiNotebookReviewing(state.reviewed, state.toReview),
            style: muted,
          ),
        ],
      ),
      AiNotebookState(reviewFailed: true) => Text(
        l10n.aiNotebookReviewFailed,
        style: muted?.copyWith(color: scheme.error),
      ),
      AiNotebookState(toReview: > 0) => Text(
        l10n.aiNotebookReviewed,
        style: muted,
      ),
      _ => Text(l10n.aiNotebookNotReviewed, style: muted),
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        review,
        if (state.senseSearch == SenseSearch.failed) ...[
          const SizedBox(height: 4),
          Text(l10n.aiNotebookSenseFailed, style: muted),
        ],
      ],
    );
  }
}

class _PickTile extends StatelessWidget {
  const _PickTile({required this.pick, required this.onToggle});

  final AiNotebookPick pick;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final candidate = pick.candidate;
    final fits = pick.fits;

    return CheckboxListTile(
      key: Key('ai-notebook-pick-${candidate.itemId}'),
      value: pick.checked,
      onChanged: (_) => onToggle(),
      secondary: Icon(candidate.kind.icon),
      contentPadding: const EdgeInsets.symmetric(horizontal: 24),
      title: Text(
        candidate.title,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (candidate.excerpt.isNotEmpty)
            Text(
              candidate.excerpt,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          if (fits != null) ...[
            const SizedBox(height: 4),
            Row(
              children: [
                Icon(
                  fits ? Icons.auto_awesome : Icons.remove_circle_outline,
                  size: 14,
                  color: fits ? scheme.primary : scheme.onSurfaceVariant,
                ),
                const SizedBox(width: 4),
                Flexible(
                  child: Text(
                    fits ? l10n.aiNotebookFits : l10n.aiNotebookDoesNotFit,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: fits ? scheme.primary : scheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
