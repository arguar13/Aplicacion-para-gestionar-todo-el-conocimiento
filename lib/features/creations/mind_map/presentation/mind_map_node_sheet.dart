import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/features/creations/design/creation_controls.dart';
import 'package:sinapsis/features/creations/domain/entities/creation_scope_summary.dart';
import 'package:sinapsis/features/creations/domain/entities/study_creation.dart';
import 'package:sinapsis/features/creations/mind_map/domain/mind_map.dart';
import 'package:sinapsis/features/creations/mind_map/presentation/mind_map_actions.dart';
import 'package:sinapsis/features/creations/presentation/providers/repasar_providers.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// La hoja de una idea del mapa, al tocarla: su nombre entero, dónde está
/// dentro del mapa, su nota, de qué documento sale con su pasaje, y las dos
/// cosas que se pueden hacer —«Preguntarle al chat sobre esto» y «Ver en el
/// documento»—.
///
/// [ref] es el del visor, que sigue abierto cuando la hoja ya se cerró: lo
/// que se hace después lo usa.
Future<void> showMindMapNodeSheet(
  BuildContext context,
  WidgetRef ref, {
  required StudyCreation creation,
  required MindMap map,
  required MindMapNode node,
  required Color accent,
}) {
  // Lo que se hace sale de la pantalla del visor, no de la hoja: la hoja se
  // cierra antes.
  final host = context;
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (sheet) => MindMapNodeSheet(
      creation: creation,
      map: map,
      node: node,
      accent: accent,
      onAsk: (documentTitle) {
        Navigator.of(sheet).pop();
        askMindMapNodeInChat(
          host,
          creation,
          map,
          node,
          documentTitle: documentTitle,
        );
      },
      onOpenDocument: () {
        Navigator.of(sheet).pop();
        unawaited(openMindMapNodeInDocument(host, ref, creation, node));
      },
    ),
  );
}

class MindMapNodeSheet extends ConsumerWidget {
  const MindMapNodeSheet({
    required this.creation,
    required this.map,
    required this.node,
    required this.accent,
    required this.onAsk,
    required this.onOpenDocument,
    super.key,
  });

  final StudyCreation creation;
  final MindMap map;
  final MindMapNode node;
  final Color accent;

  /// «Preguntarle al chat», con el título del documento si se sabe.
  final void Function(String? documentTitle) onAsk;
  final VoidCallback onOpenDocument;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final path = map.pathTo(node.id);
    final above = path.length > 1
        ? path.sublist(0, path.length - 1).map((n) => n.label).join(' › ')
        : null;
    final documentId = mindMapNodeDocument(creation, node);
    final sources =
        ref
            .watch(
              creationSourcesProvider(CreationSourceIds(creation.sourceIds)),
            )
            .valueOrNull ??
        const <CreationSource>[];
    var documentTitle = node.source?.documentTitle;
    for (final source in sources) {
      if (source.documentId == documentId && source.title.isNotEmpty) {
        documentTitle = source.title;
      }
    }
    final quote = node.source?.quote;

    return SingleChildScrollView(
      key: ValueKey('mind-map-sheet-${node.id}'),
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Semantics(
                  header: true,
                  child: Text(node.label, style: theme.textTheme.titleLarge),
                ),
              ),
              const SizedBox(width: 12),
              CreationCloseButton(
                tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
          if (above != null) ...[
            const SizedBox(height: 6),
            Text(
              l10n.f43MindInside(above),
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ],
          if (node.note != null) ...[
            const SizedBox(height: 16),
            Text(node.note!, style: theme.textTheme.bodyLarge),
          ],
          if (documentTitle != null || quote != null) ...[
            const SizedBox(height: 16),
            _Passage(title: documentTitle, quote: quote, accent: accent),
          ],
          const SizedBox(height: 24),
          FilledButton.icon(
            key: const Key('mind-map-ask-chat'),
            onPressed: () => onAsk(documentTitle),
            icon: const Icon(Icons.forum_outlined),
            label: Text(l10n.f43MindAskChat),
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(52),
            ),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            key: const Key('mind-map-see-document'),
            onPressed: onOpenDocument,
            icon: Icon(
              documentId == null
                  ? Icons.source_outlined
                  : Icons.menu_book_outlined,
            ),
            label: Text(
              documentId == null
                  ? l10n.f43MindSeeSources
                  : l10n.f43MindSeeInDocument,
            ),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(52),
            ),
          ),
        ],
      ),
    );
  }
}

/// De qué documento sale la idea y, si la IA lo dio, su pasaje, con una
/// barra del color del mapa al costado, como una cita.
class _Passage extends StatelessWidget {
  const _Passage({
    required this.title,
    required this.quote,
    required this.accent,
  });

  final String? title;
  final String? quote;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      key: const Key('mind-map-passage'),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(16),
      ),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (title != null)
            Row(
              children: [
                Icon(Icons.description_outlined, size: 18, color: accent),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    l10n.f43MindFrom(title!),
                    style: theme.textTheme.labelLarge,
                  ),
                ),
              ],
            ),
          if (quote != null) ...[
            if (title != null) const SizedBox(height: 10),
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    width: 3,
                    decoration: BoxDecoration(
                      color: accent,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      '«$quote»',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontStyle: FontStyle.italic,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
