import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/features/library/domain/entities/library_query.dart';
import 'package:sinapsis/features/processed/presentation/providers/processed_providers.dart';
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
///
/// La línea de tiempo se arma con lo procesado (F41, paso 6): desde una fuente
/// lleva a las fechas de su documento procesado, si lo tiene. Las que la fuente
/// ya tenía siguen guardadas en ella, pero no están en la línea. Que la fuente
/// todavía no se procesó lo dice el «Mapa» del detalle, con el camino a
/// triarla: acá no se repite.
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
    final processed = ref.watch(processedDocumentForSourceProvider(itemId));
    // Hasta saber si es una fuente con su procesado, nada: no se ofrece abrir
    // una línea que después resulta ser otra.
    if (!processed.hasValue) return const SizedBox.shrink();
    final document = processed.value;
    final targetId = document?.id ?? itemId;
    final label = document?.title ?? title;

    final hasEvents =
        ref
            .watch(
              timelineEventsProvider(
                LibraryQuery(ids: {targetId}, scope: LibraryScope.processed),
              ),
            )
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
            TimelineScope.document(itemId: targetId, label: label),
          ),
        ),
      ),
    );
  }
}
