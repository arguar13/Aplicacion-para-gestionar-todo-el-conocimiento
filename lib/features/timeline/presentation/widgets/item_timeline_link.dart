import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/features/library/domain/entities/library_query.dart';
import 'package:sinapsis/features/timeline/domain/entities/timeline_filter.dart';
import 'package:sinapsis/features/timeline/presentation/providers/timeline_providers.dart';
import 'package:sinapsis/features/timeline/presentation/timeline_navigation.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// «Ver en la línea de tiempo», en el detalle de un elemento que tiene fechas
/// (F40): abre la línea de tiempo recortada a ese documento.
///
/// Pregunta a la propia línea de tiempo si el elemento tiene hechos, con la
/// misma consulta que la biblioteca entiende para «solo estos elementos», y no
/// mira las propiedades del elemento: así vale igual para una «Fecha del
/// hecho» y para los hechos fechados dentro del documento que se sumen, y no
/// ofrece abrir una línea vacía por una propiedad sin fecha. Sin hechos no
/// dibuja nada.
class ItemTimelineLink extends ConsumerWidget {
  const ItemTimelineLink({
    required this.itemId,
    required this.title,
    super.key,
  });

  final String itemId;

  /// El título del elemento: rotula el chip del recorte.
  final String title;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hasEvents =
        ref
            .watch(timelineEventsProvider(LibraryQuery(ids: {itemId})))
            .valueOrNull
            ?.isNotEmpty ??
        false;
    if (!hasEvents) return const SizedBox.shrink();

    final l10n = AppLocalizations.of(context)!;
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Align(
        alignment: AlignmentDirectional.centerStart,
        child: ActionChip(
          key: const ValueKey('item-timeline-link'),
          avatar: const Icon(Icons.timeline, size: 18),
          label: Text(l10n.detailOpenTimeline),
          onPressed: () => showInTimeline(
            context,
            ref,
            TimelineScope.document(itemId: itemId, label: title),
          ),
        ),
      ),
    );
  }
}
