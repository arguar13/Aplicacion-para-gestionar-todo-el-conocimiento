import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:sinapsis/app/router/route_paths.dart';
import 'package:sinapsis/core/util/format_clock.dart';
import 'package:sinapsis/features/citations/domain/entities/citation_source.dart';
import 'package:sinapsis/features/citations/presentation/fragment_citation.dart';
import 'package:sinapsis/features/library/presentation/widgets/entity_presentation.dart';
import 'package:sinapsis/features/notes/domain/entities/cited_source.dart';
import 'package:sinapsis/features/notes/presentation/providers/note_sources_providers.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// Las fuentes que cita una nota, con dónde: en el detalle de una nota, de
/// dónde sale lo que dice.
///
/// Una fuente aparece por dos caminos que pueden darse a la vez: la nota la
/// cita ella misma, o enlaza notas atómicas que salieron de ella. Con lo
/// segundo, cada fragmento dice qué nota lo usa y —si la fuente tiene marcas de
/// tiempo o páginas— en qué minuto o página está, y lleva a ese lugar exacto de
/// la fuente.
///
/// No dibuja nada si la nota no cita ninguna: una sección vacía es ruido en
/// cada nota del usuario.
class CitedSourcesSection extends ConsumerWidget {
  const CitedSourcesSection({required this.noteId, super.key});

  final String noteId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sources = ref.watch(citedSourcesProvider(noteId)).valueOrNull;
    if (sources == null || sources.isEmpty) return const SizedBox.shrink();

    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${l10n.citedSourcesTitle} (${sources.length})',
            style: theme.textTheme.titleSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 4),
          for (final source in sources) _CitedSourceTile(source: source),
        ],
      ),
    );
  }
}

class _CitedSourceTile extends StatelessWidget {
  const _CitedSourceTile({required this.source});

  final CitedSource source;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    final how = [
      if (source.isDirect) l10n.citedSourceDirect,
      if (source.fragments.isNotEmpty)
        l10n.citedSourceViaNotes(source.fragments.length),
    ].join(' · ');

    final title = Text(source.title);
    final subtitle = Text(how);
    final leading = Icon(source.sourceKind.icon);

    // Sin fragmentos no hay nada que desplegar: la fila lleva a la fuente.
    if (source.fragments.isEmpty) {
      return ListTile(
        contentPadding: EdgeInsets.zero,
        leading: leading,
        title: title,
        subtitle: subtitle,
        onTap: () => context.push(RoutePaths.itemDetail(source.sourceId)),
      );
    }

    return ExpansionTile(
      tilePadding: EdgeInsets.zero,
      childrenPadding: const EdgeInsets.only(left: 16),
      shape: const Border(),
      collapsedShape: const Border(),
      leading: leading,
      title: title,
      subtitle: subtitle,
      children: [
        ListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.open_in_new, size: 18),
          title: Text(source.title),
          onTap: () => context.push(RoutePaths.itemDetail(source.sourceId)),
        ),
        for (final fragment in source.fragments)
          _FragmentTile(sourceId: source.sourceId, fragment: fragment),
      ],
    );
  }
}

class _FragmentTile extends ConsumerWidget {
  const _FragmentTile({required this.sourceId, required this.fragment});

  final String sourceId;
  final CitedFragment fragment;

  /// Dónde de la fuente está el fragmento, para citarlo: la página o, si no
  /// hay, el minuto.
  CitationLocator? get _locator {
    final page = fragment.pageNumber;
    if (page != null) return CitationLocator.page('$page');
    final startMs = fragment.startMs;
    if (startMs != null) return CitationLocator.time(formatClock(startMs));
    return null;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final start = fragment.start;
    final end = fragment.end;

    final place = [
      if (fragment.startMs != null)
        l10n.citedFragmentTime(formatClock(fragment.startMs!)),
      if (fragment.pageNumber != null)
        l10n.citedFragmentPage(fragment.pageNumber!),
    ].join(' · ');

    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      leading: const Icon(Icons.content_cut, size: 18),
      title: Text(fragment.noteTitle),
      subtitle: place.isEmpty ? null : Text(place),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            key: const Key('cite-fragment'),
            icon: const Icon(Icons.format_quote),
            tooltip: l10n.citedFragmentCiteTooltip,
            onPressed: () => copyFragmentCitation(
              context,
              ref,
              sourceId: sourceId,
              locator: _locator,
            ),
          ),
          if (start != null && end != null)
            IconButton(
              icon: const Icon(Icons.my_location),
              tooltip: l10n.relationViewInSource,
              onPressed: () => context.push(
                RoutePaths.reading(sourceId, start: start, end: end),
              ),
            ),
        ],
      ),
      onTap: () => context.push(RoutePaths.itemDetail(fragment.noteId)),
    );
  }
}
