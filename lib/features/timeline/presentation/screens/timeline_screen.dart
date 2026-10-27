import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:sinapsis/app/router/route_paths.dart';
import 'package:sinapsis/features/library/domain/entities/library_query.dart';
import 'package:sinapsis/features/timeline/domain/entities/timeline_event.dart';
import 'package:sinapsis/features/timeline/presentation/providers/timeline_providers.dart';
import 'package:sinapsis/features/timeline/presentation/widgets/timeline_ai_action.dart';
import 'package:sinapsis/features/timeline/presentation/widgets/timeline_ai_progress.dart';
import 'package:sinapsis/features/timeline/presentation/widgets/timeline_canvas.dart';
import 'package:sinapsis/features/timeline/presentation/widgets/timeline_event_bar.dart';
import 'package:sinapsis/features/timeline/presentation/widgets/timeline_filter_sheet.dart';
import 'package:sinapsis/features/timeline/presentation/widgets/timeline_scope_bar.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// Cuánto se espera después de la última tecla antes de buscar: cada consulta
/// vuelve a leer todos los hechos, y hacerlo por letra sería trabajo tirado.
const _searchDelay = Duration(milliseconds: 300);

/// La línea de tiempo (F9): los hechos con fecha de la bóveda sobre un eje
/// que se mueve y se acerca. Un destino de «Organizar», arriba del Atlas (F40).
///
/// Los eventos son las "Fecha del hecho" puestas en los elementos. Lo que se
/// sabe con menos precisión —un siglo, un "circa"— se ve distinto de una fecha
/// exacta, y tocar un hecho abre el elemento.
///
/// No recibe filtro: lo que se ve lo dice `timelineFilterProvider`, que es el
/// único dueño. La pantalla vive en una rama del shell, así que no se vuelve a
/// construir cuando otra pantalla —el Atlas, el detalle— la abre recortada a
/// algo; esas fijan el filtro antes de navegar y la pantalla lo muestra.
class TimelineScreen extends ConsumerStatefulWidget {
  const TimelineScreen({super.key});

  @override
  ConsumerState<TimelineScreen> createState() => _TimelineScreenState();
}

class _TimelineScreenState extends ConsumerState<TimelineScreen> {
  final _searchController = TextEditingController();
  Timer? _searchTimer;

  /// Lo último que llegó para mostrar, con la consulta a la que corresponde.
  ///
  /// Al cambiar el filtro, la consulta nueva tarda un instante en responder y,
  /// mientras, `timelineEventsProvider` no tiene valor. Sin esto, el lienzo se
  /// desarmaría y volvería a armarse con un giro de espera en el medio; así se
  /// queda donde está, y cuando llegan los hechos nuevos se mueve, animado,
  /// hasta encuadrarlos. El `frameKey` del lienzo es la consulta **de estos
  /// hechos** y no la del filtro actual: si no, encuadraría los viejos.
  ({LibraryQuery query, List<TimelineEvent> events})? _shown;

  @override
  void dispose() {
    _searchTimer?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged(String text) {
    // Redibuja el botón de borrar del campo.
    setState(() {});
    _searchTimer?.cancel();
    _searchTimer = Timer(
      _searchDelay,
      () => ref.read(timelineFilterProvider.notifier).search(text),
    );
  }

  void _clearSearch() {
    _searchTimer?.cancel();
    _searchController.clear();
    ref.read(timelineFilterProvider.notifier).search('');
    setState(() {});
  }

  void _clearAll() {
    _searchTimer?.cancel();
    _searchController.clear();
    ref.read(timelineFilterProvider.notifier).clear();
    setState(() {});
  }

  /// El filtro cambió de búsqueda desde afuera —otra pantalla abrió la línea
  /// recortada a algo, y eso borra lo que se había buscado—: el campo tiene que
  /// decir lo mismo que el filtro. Lo que se escribe acá llega al filtro por su
  /// propio camino y cae en el mismo texto, así que no lo pisa.
  void _syncSearchField(String? searchText) {
    final text = searchText ?? '';
    if (text == _searchController.text.trim()) return;
    _searchTimer?.cancel();
    setState(() => _searchController.text = text);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final filter = ref.watch(timelineFilterProvider);
    ref.listen(
      timelineFilterProvider.select((f) => f.searchText),
      (_, next) => _syncSearchField(next),
    );
    final query = filter.query;
    final events = ref.watch(timelineEventsProvider(query));
    if (events.valueOrNull case final loaded?) {
      _shown = (query: query, events: loaded);
    }
    final shown = _shown;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.timelineTitle),
        actions: [
          const TimelineAiAction(),
          IconButton(
            tooltip: l10n.timelineFiltersTooltip,
            icon: Badge(
              isLabelVisible: filter.panelCount > 0,
              label: Text('${filter.panelCount}'),
              child: const Icon(Icons.filter_list),
            ),
            onPressed: () => showTimelineFilters(context),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: TextField(
              controller: _searchController,
              onChanged: _onSearchChanged,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: l10n.timelineSearchHint,
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchController.text.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: _clearSearch,
                      ),
                isDense: true,
                border: const OutlineInputBorder(
                  borderRadius: BorderRadius.all(Radius.circular(28)),
                ),
              ),
            ),
          ),
          const TimelineScopeBar(),
          const TimelineAiProgress(),
          Expanded(
            child: switch (events) {
              AsyncError() when shown == null => _LoadError(
                onRetry: () => ref.invalidate(timelineEventsProvider(query)),
              ),
              _ when shown == null => const Center(
                child: CircularProgressIndicator(),
              ),
              _ when shown.events.isEmpty => _Empty(
                filtered: filter.activeCount > 0,
                onClearFilters: _clearAll,
              ),
              _ => Column(
                children: [
                  Expanded(
                    child: TimelineCanvas(
                      events: shown.events,
                      // Otra consulta: el eje se encuadra de nuevo sobre lo
                      // que quedó.
                      frameKey: shown.query,
                      onOpen: (event) =>
                          context.push(RoutePaths.itemDetail(event.itemId)),
                    ),
                  ),
                  _Legend(count: shown.events.length),
                ],
              ),
            },
          ),
        ],
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.filtered, required this.onClearFilters});

  final bool filtered;
  final VoidCallback onClearFilters;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.timeline,
              size: 48,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 16),
            Text(
              filtered ? l10n.timelineNoResults : l10n.timelineEmptyTitle,
              style: theme.textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            if (filtered)
              TextButton(
                onPressed: onClearFilters,
                child: Text(l10n.timelineFilterClear),
              )
            else
              Text(
                l10n.timelineEmptyHint,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
          ],
        ),
      ),
    );
  }
}

class _LoadError extends StatelessWidget {
  const _LoadError({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(l10n.timelineLoadError),
          TextButton(onPressed: onRetry, child: Text(l10n.loadErrorRetry)),
        ],
      ),
    );
  }
}

/// La leyenda de cómo se dibuja la imprecisión, con la misma pintura que las
/// barras del eje, y cuántos hechos hay.
class _Legend extends StatelessWidget {
  const _Legend({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final color = theme.colorScheme.primary;
    final textStyle = theme.textTheme.labelSmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );

    Widget sample(TimelineBarStyle style, String label, {double fuzz = 0}) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 44,
            height: kTimelineBarHeight,
            child: CustomPaint(
              painter: TimelineBarSamplePainter(
                style: style,
                color: color,
                fuzzPx: fuzz,
                corePx: 44 - fuzz * 2,
              ),
            ),
          ),
          const SizedBox(width: 6),
          Text(label, style: textStyle),
        ],
      );
    }

    return Material(
      color: theme.colorScheme.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Wrap(
          spacing: 16,
          runSpacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(l10n.timelineEventCount(count), style: textStyle),
            sample(TimelineBarStyle.exact, l10n.timelineLegendExact),
            sample(
              TimelineBarStyle.approximate,
              l10n.timelineLegendCirca,
              fuzz: 10,
            ),
            sample(TimelineBarStyle.period, l10n.timelineLegendPeriod),
          ],
        ),
      ),
    );
  }
}
