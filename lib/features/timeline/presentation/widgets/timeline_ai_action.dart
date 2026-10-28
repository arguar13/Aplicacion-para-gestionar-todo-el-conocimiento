import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/core/domain/entities/processing_state.dart';
import 'package:sinapsis/core/error/failure_messages.dart';
import 'package:sinapsis/features/ai_organize/presentation/widgets/ai_organize_now.dart';
import 'package:sinapsis/features/library/domain/entities/library_query.dart';
import 'package:sinapsis/features/library/presentation/providers/library_providers.dart';
import 'package:sinapsis/features/timeline/domain/entities/timeline_filter.dart';
import 'package:sinapsis/features/timeline/presentation/providers/timeline_providers.dart';
import 'package:sinapsis/features/timeline/presentation/widgets/timeline_ai_sheet.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// «Organizar con IA» en la barra de la línea de tiempo (F40): elige qué
/// recorre la IA —todo, un tema o un documento— y lo pone en la cola de la IA
/// para que busque sus fechas.
///
/// Si la línea ya está recortada a algo, la hoja arranca con eso elegido. El
/// avance se ve en la propia línea (`TimelineAiProgress`) y los hechos nuevos
/// aparecen solos; sin modelo, o con la IA en pausa, el aviso dice qué falta,
/// igual que las otras acciones de la IA.
class TimelineAiAction extends ConsumerWidget {
  const TimelineAiAction({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    return IconButton(
      key: const Key('timeline-ai-action'),
      tooltip: l10n.timelineAiAction,
      icon: const Icon(Icons.auto_awesome_outlined),
      onPressed: () => _organize(context, ref),
    );
  }

  Future<void> _organize(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context)!;
    final messenger = ScaffoldMessenger.of(context);
    final choice = await showTimelineAiSheet(
      context,
      initial: ref.read(timelineFilterProvider).scope,
    );
    if (choice == null || !context.mounted) return;

    final scope = choice.scope;
    // Lo que recorre es siempre lo que está listo de ese recorte —también un
    // documento elegido—: un texto a medio procesar va a cambiar.
    final found = await ref
        .read(libraryRepositoryProvider)
        .matchingIds(_queryOf(scope));
    if (!context.mounted) return;
    final failure = found.getLeft().toNullable();
    if (failure != null) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(failure.localizedMessage(l10n))));
      return;
    }
    final itemIds = found.getRight().toNullable() ?? const <String>[];

    if (itemIds.isEmpty) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(l10n.timelineAiNothing)));
      return;
    }
    await findDatesNowWithAi(
      context,
      ref,
      itemIds: itemIds,
      seeItemId: scope?.kind == TimelineScopeKind.document ? scope!.id : null,
    );
  }

  /// Lo que recorre la IA para [scope]: los documentos procesados listos de
  /// ese recorte —o todos—, que son de lo que se arma la línea de tiempo (F41,
  /// paso 6). Es la consulta de la línea de tiempo sin su búsqueda ni su panel:
  /// lo que se recorre es el tema o la rama, no lo que estaba buscado.
  static LibraryQuery _queryOf(TimelineScope? scope) =>
      TimelineFilter(scope: scope).query.copyWith(
        processingStates: {ProcessingState.ready},
        scope: LibraryScope.processed,
      );
}
