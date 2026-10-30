import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/features/creations/domain/entities/creation_scope.dart';
import 'package:sinapsis/features/creations/presentation/providers/repasar_providers.dart';
import 'package:sinapsis/features/creations/presentation/widgets/creation_scope_picker.dart';
import 'package:sinapsis/features/flashcards/presentation/providers/review_stats_providers.dart';
import 'package:sinapsis/features/flashcards/presentation/widgets/review_stats_tab.dart';
import 'package:sinapsis/features/habit/presentation/providers/habit_providers.dart';
import 'package:sinapsis/features/habit/presentation/widgets/review_history_tab.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// Qué pestaña abre [ReviewStatsScreen].
enum ReviewStatsTab { stats, history }

/// Estadísticas e Historial (F43, M16 y M17): una sola pantalla con dos
/// pestañas, que antes eran dos pantallas que repetían partes.
///
/// Sigue al selector de Repasar (`repasarScopeProvider`): las estadísticas de
/// un libro son las de sus tarjetas. La píldora de arriba de cada pestaña lo
/// cambia, y el cambio vale también para Repasar, como si se lo hubiera
/// elegido allá.
///
/// Se llega desde los dos íconos de la barra de Repasar, cada uno a su
/// pestaña; las dos direcciones de antes (`/review/stats` y
/// `/review/history`) siguen andando y abren la suya.
class ReviewStatsScreen extends ConsumerWidget {
  const ReviewStatsScreen({this.initialTab = ReviewStatsTab.stats, super.key});

  final ReviewStatsTab initialTab;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    return DefaultTabController(
      length: ReviewStatsTab.values.length,
      initialIndex: initialTab.index,
      child: Scaffold(
        appBar: AppBar(
          title: Text(l10n.f43S20ScreenTitle),
          bottom: TabBar(
            tabs: [
              Tab(
                key: const Key('review-stats-tab-stats'),
                icon: const Icon(Icons.bar_chart_rounded),
                text: l10n.cardStatsTitle,
              ),
              Tab(
                key: const Key('review-stats-tab-history'),
                icon: const Icon(Icons.show_chart_rounded),
                text: l10n.f43S20HistoryTab,
              ),
            ],
          ),
        ),
        body: const TabBarView(children: [_StatsTab(), _HistoryTab()]),
      ),
    );
  }
}

/// La lista de una pestaña: la píldora del recorte arriba y lo demás debajo,
/// en una sola lista que se desplaza —con letra grande o en un teléfono chico,
/// nada queda fijo ocupando la pantalla— y centrada en una pantalla ancha.
class _TabList extends ConsumerWidget {
  const _TabList({required this.listKey, required this.child});

  final Key listKey;
  final Widget child;

  Future<void> _choose(
    BuildContext context,
    WidgetRef ref,
    CreationScope current,
  ) async {
    final chosen = await showCreationScopePicker(context, current: current);
    if (chosen == null || !context.mounted) return;
    chooseRepasarScope(ref, chosen);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scope = ref.watch(repasarScopeProvider);
    return SafeArea(
      top: false,
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 840),
          child: ListView(
            key: listKey,
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            children: [
              CreationScopePill(
                scope: scope,
                onTap: () => unawaited(_choose(context, ref, scope)),
              ),
              const SizedBox(height: 16),
              child,
            ],
          ),
        ),
      ),
    );
  }
}

class _Loading extends StatelessWidget {
  const _Loading();

  @override
  Widget build(BuildContext context) => const Padding(
    padding: EdgeInsets.all(32),
    child: Center(child: CircularProgressIndicator()),
  );
}

class _StatsTab extends ConsumerWidget {
  const _StatsTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final scope = ref.watch(repasarScopeProvider).studyScope;
    final stats = ref.watch(reviewStatsProvider(scope));
    // Un repaso más o un día nuevo vuelven a emitir sin pasar por
    // «cargando»: lo de antes queda a la vista y la pantalla no parpadea.
    final value = stats.valueOrNull;
    return _TabList(
      listKey: const Key('review-stats-list'),
      child: value != null
          ? ReviewStatsSections(stats: value)
          : stats.hasError
          ? Text(l10n.cardStatsLoadError, key: const Key('card-stats-error'))
          : const _Loading(),
    );
  }
}

class _HistoryTab extends ConsumerWidget {
  const _HistoryTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final scope = ref.watch(repasarScopeProvider).studyScope;
    final history = ref.watch(reviewHistoryProvider(scope));
    final value = history.valueOrNull;
    return _TabList(
      listKey: const Key('review-history-list'),
      child: value != null
          ? ReviewHistorySections(history: value)
          : history.hasError
          ? Text(
              l10n.reviewHistoryLoadError,
              key: const Key('review-history-error'),
            )
          : const _Loading(),
    );
  }
}
