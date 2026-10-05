import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/core/domain/entities/notebook_mode.dart';
import 'package:sinapsis/core/telemetry/telemetry_provider.dart';
import 'package:sinapsis/core/telemetry/telemetry_service.dart';
import 'package:sinapsis/features/chat/presentation/providers/chat_providers.dart';
import 'package:sinapsis/features/notebooks/domain/entities/notebook.dart';
import 'package:sinapsis/features/notebooks/domain/repositories/notebook_repository.dart';
import 'package:sinapsis/features/notebooks/domain/services/notebook_candidates.dart';
import 'package:sinapsis/features/notebooks/presentation/providers/notebook_providers.dart';

/// Un elemento propuesto, con si está marcado y qué dijo la IA.
@immutable
class AiNotebookPick {
  const AiNotebookPick({
    required this.candidate,
    required this.checked,
    this.fits,
  });

  final NotebookCandidate candidate;
  final bool checked;

  /// Lo que dijo la IA: `true` va, `false` no parece; `null` si no lo revisó
  /// (todavía, o porque no está el modelo).
  final bool? fits;

  AiNotebookPick copyWith({bool? checked, bool? Function()? fits}) =>
      AiNotebookPick(
        candidate: candidate,
        checked: checked ?? this.checked,
        fits: fits == null ? this.fits : fits(),
      );

  @override
  bool operator ==(Object other) =>
      other is AiNotebookPick &&
      other.candidate == candidate &&
      other.checked == checked &&
      other.fits == fits;

  @override
  int get hashCode => Object.hash(candidate, checked, fits);
}

/// Cómo va «Crear con IA» (F30): lo buscado, lo propuesto y la revisión.
@immutable
class AiNotebookState {
  const AiNotebookState({
    required this.topic,
    this.searching = false,
    this.picks = const [],
    this.senseSearch = SenseSearch.unavailable,
    this.toReview = 0,
    this.reviewed = 0,
    this.reviewFailed = false,
  });

  final String topic;
  final bool searching;
  final List<AiNotebookPick> picks;
  final SenseSearch senseSearch;

  /// Cuántos de los primeros revisa la IA: 0 sin el modelo de lenguaje.
  final int toReview;
  final int reviewed;

  /// Si la IA falló a mitad: lo no revisado queda como lo marcó la búsqueda.
  final bool reviewFailed;

  bool get reviewing => !searching && !reviewFailed && reviewed < toReview;

  int get checkedCount => picks.where((p) => p.checked).length;

  AiNotebookState copyWith({
    bool? searching,
    List<AiNotebookPick>? picks,
    SenseSearch? senseSearch,
    int? toReview,
    int? reviewed,
    bool? reviewFailed,
  }) => AiNotebookState(
    topic: topic,
    searching: searching ?? this.searching,
    picks: picks ?? this.picks,
    senseSearch: senseSearch ?? this.senseSearch,
    toReview: toReview ?? this.toReview,
    reviewed: reviewed ?? this.reviewed,
    reviewFailed: reviewFailed ?? this.reviewFailed,
  );
}

/// «Crear con IA» (F30, decisión B): la persona escribe de qué quiere el
/// cuaderno, se busca en su biblioteca ([NotebookCandidateFinder]) y se le
/// proponen los elementos ya marcados; destilda lo que no va y se crea un
/// cuaderno manual con los elegidos.
///
/// **La IA revisa por tandas** ([NotebookCandidateJudge]), si está el modelo
/// de lenguaje: los primeros [kNotebookJudgeMax], de a [kNotebookJudgeBatch].
/// La lista se muestra apenas termina la búsqueda —marcados los que encontró
/// por palabras o se parecen mucho por sentido— y cada tanda revisada
/// corrige las marcas, salvo las que la persona ya tocó: lo suyo manda. La
/// persona puede crear el cuaderno en cualquier momento; lo que falte
/// revisar ya no cambia nada.
class AiNotebookController extends StateNotifier<AiNotebookState?> {
  AiNotebookController({
    required NotebookCandidateFinder finder,
    required NotebookCandidateJudge judge,
    required Future<bool> Function() languageModelReady,
    required NotebookRepository notebooks,
    required TelemetryService telemetry,
  }) : _finder = finder,
       _judge = judge,
       _languageModelReady = languageModelReady,
       _notebooks = notebooks,
       _telemetry = telemetry,
       super(null);

  final NotebookCandidateFinder _finder;
  final NotebookCandidateJudge _judge;
  final Future<bool> Function() _languageModelReady;
  final NotebookRepository _notebooks;
  final TelemetryService _telemetry;

  /// Qué búsqueda es la vigente: una nueva, crear o volver deja sin efecto lo
  /// que la anterior todavía esté revisando.
  var _serial = 0;

  /// Los que la persona marcó o desmarcó: la IA ya no los cambia.
  final _touched = <String>{};

  bool _current(int serial) => mounted && serial == _serial;

  /// Busca lo que podría ir en un cuaderno sobre [topic] y, si está el modelo
  /// de lenguaje, lo hace revisar.
  Future<void> search(String topic) async {
    final serial = ++_serial;
    _touched.clear();
    state = AiNotebookState(topic: topic.trim(), searching: true);

    final result = await _finder.find(topic.trim());
    if (!_current(serial)) return;
    final canReview =
        result.candidates.isNotEmpty && await _languageModelReady();
    if (!_current(serial)) return;

    state = state!.copyWith(
      searching: false,
      senseSearch: result.senseSearch,
      picks: [
        for (final candidate in result.candidates)
          AiNotebookPick(candidate: candidate, checked: candidate.likely),
      ],
      toReview: canReview
          ? math.min(kNotebookJudgeMax, result.candidates.length)
          : 0,
    );
    if (canReview) await _review(serial);
  }

  Future<void> _review(int serial) async {
    final toReview = state!.toReview;
    for (var start = 0; start < toReview; start += kNotebookJudgeBatch) {
      final end = math.min(start + kNotebookJudgeBatch, toReview);
      final batch = state!.picks.sublist(start, end);
      final Set<int>? picks;
      try {
        picks = await _judge.judgeNotebookCandidates(
          topic: state!.topic,
          candidates: [
            for (final pick in batch)
              (title: pick.candidate.title, excerpt: pick.candidate.excerpt),
          ],
        );
        // El modelo es de terceros y puede fallar de formas sin un tipo
        // propio: queda registrado, la pantalla lo dice y lo no revisado
        // queda como lo marcó la búsqueda.
        // ignore: avoid_catches_without_on_clauses
      } catch (error, stackTrace) {
        _telemetry.recordError(
          error,
          stackTrace,
          hint: 'AiNotebookController: revisar lo propuesto',
        );
        if (_current(serial)) state = state!.copyWith(reviewFailed: true);
        return;
      }
      if (!_current(serial)) return;

      final updated = [...state!.picks];
      if (picks != null) {
        for (var i = start; i < end; i++) {
          final fits = picks.contains(i - start);
          final pick = updated[i];
          updated[i] = pick.copyWith(
            fits: () => fits,
            checked: _touched.contains(pick.candidate.itemId) ? null : fits,
          );
        }
      }
      state = state!.copyWith(picks: updated, reviewed: end);
    }
  }

  /// Marca o desmarca [itemId]; desde ahí, la IA ya no lo cambia.
  void toggle(String itemId) {
    final current = state;
    if (current == null) return;
    _touched.add(itemId);
    state = current.copyWith(
      picks: [
        for (final pick in current.picks)
          if (pick.candidate.itemId == itemId)
            pick.copyWith(checked: !pick.checked)
          else
            pick,
      ],
    );
  }

  /// Vuelve a escribir de qué es: lo que se estaba revisando ya no cuenta.
  void restart() {
    _serial++;
    _touched.clear();
    state = null;
  }

  /// Crea el cuaderno manual [name] con los marcados, agregados de una vez.
  Future<Notebook> create(String name) async {
    _serial++;
    final ids = [
      for (final pick in state?.picks ?? const <AiNotebookPick>[])
        if (pick.checked) pick.candidate.itemId,
    ];
    final notebook = await _notebooks.create(
      name: name,
      mode: NotebookMode.manual,
    );
    await _notebooks.addItems(notebookId: notebook.id, itemIds: ids);
    return notebook;
  }
}

/// «Crear con IA» mientras su hoja está abierta (F30).
final aiNotebookControllerProvider =
    StateNotifierProvider.autoDispose<AiNotebookController, AiNotebookState?>(
      (ref) => AiNotebookController(
        finder: ref.watch(notebookCandidateFinderProvider),
        judge: ref.watch(notebookCandidateJudgeProvider),
        languageModelReady: () => ref.read(chatModelManagerProvider).isReady(),
        notebooks: ref.watch(notebookRepositoryProvider),
        telemetry: ref.watch(telemetryServiceProvider),
      ),
    );
