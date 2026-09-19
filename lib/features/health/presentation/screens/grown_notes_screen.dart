import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:sinapsis/app/router/route_paths.dart';
import 'package:sinapsis/features/health/domain/entities/grown_note.dart';
import 'package:sinapsis/features/health/presentation/providers/health_providers.dart';
import 'package:sinapsis/features/library/presentation/widgets/entity_presentation.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// Las notas vivas que crecieron esta semana: con bloques o vínculos nuevos en
/// los últimos 7 días.
///
/// Es el punto de entrada natural a la sesión de consolidación: se abre cada
/// una, se reescribe como texto continuo y se marca madura. Las que más
/// crecieron van primero, y cada una dice cuánto creció y en qué etapa está.
class GrownNotesScreen extends ConsumerWidget {
  const GrownNotesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final notes = ref.watch(grownNotesProvider);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.grownNotesTitle)),
      body: notes.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => _CenteredMessage(l10n.grownNotesLoadError),
        data: (notes) => notes.isEmpty
            ? _CenteredMessage(l10n.grownNotesEmpty)
            : ListView.builder(
                itemCount: notes.length + 1,
                itemBuilder: (context, index) {
                  if (index == 0) return _Hint(l10n.grownNotesHint);
                  return _GrownNoteTile(note: notes[index - 1]);
                },
              ),
      ),
    );
  }
}

class _GrownNoteTile extends StatelessWidget {
  const _GrownNoteTile({required this.note});

  final GrownNote note;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final growth = [
      if (note.newBlocks > 0) l10n.grownNotesNewBlocks(note.newBlocks),
      if (note.newRelations > 0) l10n.grownNotesNewRelations(note.newRelations),
    ].join(' · ');

    return ListTile(
      title: Text(note.title, maxLines: 2, overflow: TextOverflow.ellipsis),
      subtitle: Text(growth),
      trailing: Text(
        note.maturity.label(l10n),
        style: theme.textTheme.labelMedium?.copyWith(
          color: note.maturity.color(theme.colorScheme),
        ),
      ),
      onTap: () => context.push(RoutePaths.itemDetail(note.itemId)),
    );
  }
}

class _Hint extends StatelessWidget {
  const _Hint(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline, size: 18, color: theme.colorScheme.outline),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CenteredMessage extends StatelessWidget {
  const _CenteredMessage(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(text, textAlign: TextAlign.center),
      ),
    );
  }
}
