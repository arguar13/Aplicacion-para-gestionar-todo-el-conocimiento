import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/core/domain/entities/topic_dimension.dart';
import 'package:sinapsis/core/error/failure_messages.dart';
import 'package:sinapsis/core/util/util_providers.dart';
import 'package:sinapsis/features/ai_organize/presentation/widgets/ai_organize_now.dart';
import 'package:sinapsis/features/creations/domain/entities/creation_scope.dart';
import 'package:sinapsis/features/creations/presentation/repasar_navigation.dart';
import 'package:sinapsis/features/graph/presentation/widgets/ai_suggest_relations_dialog.dart';
import 'package:sinapsis/features/library/domain/entities/library_query.dart';
import 'package:sinapsis/features/library/presentation/providers/library_providers.dart';
import 'package:sinapsis/features/map/domain/entities/knowledge_map_state.dart';
import 'package:sinapsis/features/map/domain/entities/map_dashboard.dart';
import 'package:sinapsis/features/map/domain/entities/topic_items.dart';
import 'package:sinapsis/features/map/domain/services/board_facts.dart';
import 'package:sinapsis/features/map/domain/services/board_insights.dart';
import 'package:sinapsis/features/map/presentation/providers/board_providers.dart';
import 'package:sinapsis/features/map/presentation/providers/map_canvas_request.dart';
import 'package:sinapsis/features/map/presentation/widgets/map_board_target.dart';
import 'package:sinapsis/features/map/presentation/widgets/map_board_view.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// El Resumen del Mapa con lo que necesita de afuera (F44, paso 3): lee lo que
/// cuenta además del grafo de temas y resuelve sus salidas —«Estudiar»,
/// «Sugerir vínculos», «Organizar con IA»— para que [MapBoardView] solo
/// dibuje.
///
/// Lo que se toca y lleva al Mapa (decisión D) va al lienzo por su canal de
/// pedidos ([canvasRequestFor] en `mapCanvasRequestProvider`): el lienzo lo
/// atiende y la pantalla pasa a la pestaña Mapa.
class MapBoardPane extends ConsumerStatefulWidget {
  const MapBoardPane({
    required this.snapshot,
    required this.dimension,
    required this.dashboard,
    required this.onOpenItem,
    required this.onOpenTension,
    super.key,
  });

  final KnowledgeMapSnapshot snapshot;
  final TopicDimension dimension;
  final MapDashboard? dashboard;
  final void Function(String itemId) onOpenItem;
  final VoidCallback onOpenTension;

  @override
  ConsumerState<MapBoardPane> createState() => _MapBoardPaneState();
}

class _MapBoardPaneState extends ConsumerState<MapBoardPane> {
  /// El último cálculo y con qué se hizo: solo se rehace si cambió algo de lo
  /// que lo arma —el mapa, los documentos o las tarjetas—, no en cada
  /// reconstrucción de la pantalla.
  BoardInsights? _insights;
  Object? _inputs;

  BoardInsights? _insightsFor(
    BoardFacts? facts,
    Map<String, BoardCardFact>? cards,
  ) {
    if (facts == null || cards == null) return _insights;
    final inputs = (widget.snapshot, facts, cards);
    if (inputs == _inputs) return _insights;
    _inputs = inputs;
    return _insights = buildBoardInsights(
      graph: widget.snapshot.graph,
      detection: widget.snapshot.detection,
      facts: facts,
      cards: cards,
      now: ref.read(clockProvider)(),
    );
  }

  /// Lleva al lienzo lo que se tocó en el Resumen.
  void _showInMap(MapBoardTarget target) =>
      ref.read(mapCanvasRequestProvider.notifier).state = canvasRequestFor(
        target,
      );

  /// Abre Repasar con [valueId] en el selector: un tema de F37 es un espacio;
  /// un valor del vocabulario, con sus ramas.
  void _study(String valueId) => openRepasarWith(
    context,
    widget.dimension.isSpaces
        ? CreationScope.space(valueId)
        : CreationScope.topic(valueId),
  );

  /// «Sugerir vínculos» entre lo suelto: se elige de cuál partir y la IA
  /// propone con cuáles de los otros unirlo; nada se vincula sin confirmar.
  Future<void> _suggestLinks(List<String> itemIds) async {
    final l10n = AppLocalizations.of(context)!;
    final messenger = ScaffoldMessenger.of(context);
    final loaded = await ref
        .read(libraryRepositoryProvider)
        .list(
          LibraryQuery(
            ids: itemIds.take(kMaxGraphItems).toSet(),
            scope: LibraryScope.processed,
          ),
        );
    if (!mounted) return;
    final failure = loaded.getLeft().toNullable();
    if (failure != null) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(failure.localizedMessage(l10n))));
      return;
    }
    await showAiSuggestRelationsDialog(
      context,
      ref,
      items: loaded.getRight().toNullable() ?? const [],
      // Son sueltos: no tienen vínculos que descontar.
      links: const [],
    );
  }

  @override
  Widget build(BuildContext context) {
    final request = widget.snapshot.request;
    final facts = ref.watch(boardFactsProvider(request)).valueOrNull;
    final cards = ref.watch(boardCardsProvider).valueOrNull;

    return MapBoardView(
      snapshot: widget.snapshot,
      dimension: widget.dimension,
      dashboard: widget.dashboard,
      insights: _insightsFor(facts, cards),
      onShowInMap: _showInMap,
      onOpenItem: widget.onOpenItem,
      onOpenTension: widget.onOpenTension,
      onStudyTopic: _study,
      onSuggestLinks: (ids) => unawaited(_suggestLinks(ids)),
      onOrganize: (ids) =>
          unawaited(organizeAllNowWithAi(context, ref, itemIds: ids)),
    );
  }
}

/// El pedido al lienzo de lo que se tocó en el Resumen:
///
/// - un documento: lo vinculado, con él en foco —lo mismo que «Ver en el
///   Mapa»—;
/// - un tema: los temas de su comunidad, con él resaltado;
/// - las comunidades y los temas: esa altura entera;
/// - los documentos: su altura —sin un tema que abrir, lo vinculado—;
/// - los vínculos: lo vinculado, sin foco.
MapCanvasRequest canvasRequestFor(MapBoardTarget target) => switch (target) {
  MapBoardItem(:final itemId) => MapShowLinks(focusId: itemId),
  MapBoardTopic(:final valueId) => MapShowTopic(valueId),
  MapBoardLevel(figure: MapBoardFigure.communities) => const MapShowAltitude(
    MapAltitude.communities,
  ),
  MapBoardLevel(figure: MapBoardFigure.topics) => const MapShowAltitude(
    MapAltitude.topics,
  ),
  MapBoardLevel(figure: MapBoardFigure.documents) => const MapShowAltitude(
    MapAltitude.documents,
  ),
  MapBoardLevel(figure: MapBoardFigure.links) => const MapShowLinks(),
};
