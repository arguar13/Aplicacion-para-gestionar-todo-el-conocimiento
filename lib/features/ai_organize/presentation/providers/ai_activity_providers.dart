import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fpdart/fpdart.dart';
import 'package:sinapsis/core/database/database_provider.dart';
import 'package:sinapsis/core/domain/entities/suggestion.dart';
import 'package:sinapsis/core/error/failures.dart';
import 'package:sinapsis/core/telemetry/telemetry_provider.dart';
import 'package:sinapsis/features/ai_organize/domain/entities/ai_run.dart';
import 'package:sinapsis/features/ai_organize/domain/repositories/ai_run_repository.dart';
import 'package:sinapsis/features/ai_organize/presentation/providers/ai_organize_providers.dart';
import 'package:sinapsis/features/ai_organize/presentation/providers/ai_organize_settings_notifier.dart';
import 'package:sinapsis/features/ai_review/data/repositories/pending_review_repository_impl.dart';
import 'package:sinapsis/features/ai_review/domain/entities/pending_review_item.dart';
import 'package:sinapsis/features/ai_review/domain/repositories/pending_review_repository.dart';
import 'package:sinapsis/features/flashcards/presentation/providers/flashcard_providers.dart';
import 'package:sinapsis/features/library/presentation/providers/library_providers.dart';
import 'package:sinapsis/features/organize/presentation/providers/organize_providers.dart';
import 'package:sinapsis/features/suggestions/presentation/providers/suggestion_providers.dart';

// ---------------------------------------------------------------------------
// «Para revisar» (F27): lo dudoso que la IA no aplicó.
// ---------------------------------------------------------------------------

final pendingReviewRepositoryProvider = Provider<PendingReviewRepository>((
  ref,
) {
  return PendingReviewRepositoryImpl(
    database: ref.watch(appDatabaseProvider),
    telemetry: ref.watch(telemetryServiceProvider),
  );
});

/// Los elementos con algo para revisar, el más reciente primero. Es solo el
/// índice: lo que se ve de cada uno sale de [itemReviewSuggestionsProvider],
/// que se abre únicamente para las tarjetas que están en pantalla.
final pendingReviewItemsProvider =
    StreamProvider.autoDispose<List<PendingReviewItem>>((ref) {
      return ref
          .watch(pendingReviewRepositoryProvider)
          .watchItemsWithPendingReview();
    });

/// Cuántas sugerencias hay para revisar en toda la bóveda: el número que
/// acompaña a «Lo que hizo la IA» en Ajustes.
final pendingReviewCountProvider = StreamProvider.autoDispose<int>((ref) {
  return ref.watch(pendingReviewRepositoryProvider).watchPendingReviewCount();
});

/// Si [suggestion] se revisa en «Para revisar»: todo menos un duplicado, que
/// tiene su pantalla porque fusionar borra un elemento.
bool isReviewableSuggestion(Suggestion suggestion) =>
    suggestion is! DuplicateSuggestionEntry;

/// Las sugerencias pendientes de un elemento que van a «Para revisar».
final itemReviewSuggestionsProvider = Provider.autoDispose
    .family<AsyncValue<List<Suggestion>>, String>((ref, itemId) {
      return ref
          .watch(pendingSuggestionsProvider(itemId))
          .whenData(
            (all) => [
              for (final suggestion in all)
                if (isReviewableSuggestion(suggestion)) suggestion,
            ],
          );
    });

// ---------------------------------------------------------------------------
// Lo que la IA hizo en UN elemento: la línea del detalle.
// ---------------------------------------------------------------------------

/// Cuántas pasadas de un elemento se leen para su línea: un elemento tiene
/// una o dos —la cola no lo vuelve a organizar después de que se deshizo—;
/// el tope solo evita que un error ajeno la vuelva cara.
const _itemRunsLimit = 100;

/// Las pasadas de la IA sobre `itemId`, de la más nueva a la más vieja.
///
/// Las pasadas no son una consulta que se mire sola —se leen de a páginas—,
/// así que esto se vuelve a leer cuando cambia algo que las cuenta: la cola
/// (terminó una pasada), los vínculos y las tarjetas del elemento (alguien
/// borró o adoptó uno) y el elemento mismo (sus temas y propiedades). Una
/// falla deja la línea sin mostrarse: no es motivo para trabar el detalle.
final aiItemRunsProvider = FutureProvider.autoDispose
    .family<List<AiRun>, String>((ref, itemId) async {
      ref
        ..watch(aiOrganizeStatusProvider)
        ..watch(itemRelationsProvider(itemId))
        ..watch(itemFlashcardsProvider(itemId))
        ..watch(libraryItemProvider(itemId));
      final result = await ref
          .watch(aiRunRepositoryProvider)
          .listRuns(itemId: itemId, limit: _itemRunsLimit);
      return result.getOrElse((_) => const []);
    });

/// Lo que dice la línea «La IA organizó esto» de un elemento.
@immutable
class AiItemSummary {
  const AiItemSummary({
    this.remaining = const AiRunTally(),
    this.reviewCount = 0,
  });

  /// Lo que sigue siendo de la IA, sumando las pasadas que siguen en pie: lo
  /// que la persona adoptó o borró ya no cuenta.
  final AiRunTally remaining;

  /// Cuántas sugerencias del elemento esperan en «Para revisar».
  final int reviewCount;

  /// La línea aparece solo si la IA hizo algo que siga en pie, o dejó algo
  /// para revisar.
  bool get isVisible => !remaining.isEmpty || reviewCount > 0;
}

final aiItemSummaryProvider = Provider.autoDispose
    .family<AiItemSummary, String>((ref, itemId) {
      final runs = ref.watch(aiItemRunsProvider(itemId)).valueOrNull;
      final review = ref.watch(itemReviewSuggestionsProvider(itemId));
      return AiItemSummary(
        remaining: [
          for (final run in runs ?? const <AiRun>[])
            if (!run.isUndone) run.remaining,
        ].fold(const AiRunTally(), (sum, tally) => sum + tally),
        reviewCount: review.valueOrNull?.length ?? 0,
      );
    });

// ---------------------------------------------------------------------------
// La actividad: las pasadas de toda la bóveda (o de un elemento), de a páginas.
// ---------------------------------------------------------------------------

/// Lo que la actividad tiene leído hasta ahora.
@immutable
class AiActivityState {
  const AiActivityState({
    this.runs = const [],
    this.loading = true,
    this.hasMore = true,
    this.failure,
  });

  /// Las pasadas leídas, de la más nueva a la más vieja.
  final List<AiRun> runs;

  /// Si hay una lectura en curso: la primera o la página siguiente.
  final bool loading;

  /// Si la última página vino llena: puede haber más.
  final bool hasMore;

  /// Por qué falló la última lectura, si falló.
  final Failure? failure;

  bool get isFirstLoad => loading && runs.isEmpty;

  AiActivityState copyWith({
    List<AiRun>? runs,
    bool? loading,
    bool? hasMore,
    Failure? Function()? failure,
  }) => AiActivityState(
    runs: runs ?? this.runs,
    loading: loading ?? this.loading,
    hasMore: hasMore ?? this.hasMore,
    failure: failure != null ? failure() : this.failure,
  );
}

/// Las pasadas de la IA de a páginas, para «Lo que hizo la IA» (F27).
///
/// Cada operación espera a la anterior: una página que llega después de
/// releer todo —por un deshacer, o porque la cola terminó otra pasada— se
/// pegaría corrida. Igual, una pasada nueva puede correr la ventana entre dos
/// páginas; por eso al pegar se descartan las que ya estaban.
class AiActivityController extends StateNotifier<AiActivityState> {
  AiActivityController({
    required AiRunRepository repository,
    this.itemId,
    this.pageSize = 30,
  }) : _repository = repository,
       super(const AiActivityState()) {
    unawaited(loadMore());
  }

  final AiRunRepository _repository;

  /// Solo las pasadas de este elemento, o `null` para todas.
  final String? itemId;
  final int pageSize;

  Future<void> _last = Future.value();

  Future<void> _enqueue(Future<void> Function() operation) =>
      _last = _last.then((_) => mounted ? operation() : null);

  /// La página siguiente, si puede haber más.
  Future<void> loadMore() => _enqueue(() async {
    if (!state.hasMore && state.runs.isNotEmpty) return;
    state = state.copyWith(loading: true, failure: () => null);
    final result = await _repository.listRuns(
      itemId: itemId,
      limit: pageSize,
      offset: state.runs.length,
    );
    if (!mounted) return;
    state = result.match(
      (failure) => state.copyWith(loading: false, failure: () => failure),
      (page) {
        final known = {for (final run in state.runs) run.id};
        return state.copyWith(
          runs: [
            ...state.runs,
            for (final run in page)
              if (!known.contains(run.id)) run,
          ],
          loading: false,
          hasMore: page.length == pageSize,
        );
      },
    );
  });

  /// Vuelve a leer todo lo que ya se mostraba, en una sola consulta: después
  /// de deshacer, o cuando la cola terminó una pasada.
  Future<void> refresh() => _enqueue(() async {
    final limit = math.max(state.runs.length, pageSize);
    final result = await _repository.listRuns(itemId: itemId, limit: limit);
    if (!mounted) return;
    state = result.match(
      (failure) => state.copyWith(loading: false, failure: () => failure),
      (runs) => state.copyWith(
        runs: runs,
        loading: false,
        hasMore: runs.length == limit,
        failure: () => null,
      ),
    );
  });

  /// Deshace la pasada [runId] y vuelve a leer, para que se vea deshecha.
  Future<Either<Failure, AiRunTally>> undoRun(String runId) async {
    final result = await _repository.undoRun(runId);
    await refresh();
    return result;
  }

  /// Deshace todo lo de [targetItemId] y vuelve a leer.
  Future<Either<Failure, AiRunTally>> undoItem(String targetItemId) async {
    final result = await _repository.undoItem(targetItemId);
    await refresh();
    return result;
  }
}

/// La actividad, de toda la bóveda (`null`) o de un elemento.
///
/// Se vuelve a leer cada vez que la cola cambia de estado: es cuando una
/// pasada empieza o termina.
final aiActivityControllerProvider = StateNotifierProvider.autoDispose
    .family<AiActivityController, AiActivityState, String?>((ref, itemId) {
      final controller = AiActivityController(
        repository: ref.watch(aiRunRepositoryProvider),
        itemId: itemId,
      );
      ref.listen(aiOrganizeStatusProvider, (_, _) {
        unawaited(controller.refresh());
      });
      return controller;
    });
