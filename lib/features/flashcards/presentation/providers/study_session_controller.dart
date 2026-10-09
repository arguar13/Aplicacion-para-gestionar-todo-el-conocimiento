import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/core/domain/entities/card_phase.dart';
import 'package:sinapsis/core/domain/entities/flashcard.dart';
import 'package:sinapsis/core/error/failures.dart';
import 'package:sinapsis/core/util/util_providers.dart';
import 'package:sinapsis/features/flashcards/domain/entities/review_grade.dart';
import 'package:sinapsis/features/flashcards/domain/entities/study_counts.dart';
import 'package:sinapsis/features/flashcards/domain/entities/study_limits.dart';
import 'package:sinapsis/features/flashcards/domain/entities/study_next.dart';
import 'package:sinapsis/features/flashcards/domain/entities/study_scope.dart';
import 'package:sinapsis/features/flashcards/presentation/providers/flashcard_providers.dart';
import 'package:sinapsis/features/flashcards/presentation/providers/study_limits_provider.dart';
import 'package:sinapsis/features/flashcards/presentation/providers/study_providers.dart';

/// Una respuesta dada en esta sesión: a qué tarjeta, con qué calificación y
/// cuánto se tardó en contestarla.
@immutable
class StudySessionAnswer {
  const StudySessionAnswer({
    required this.cardId,
    required this.grade,
    required this.took,
  });

  final String cardId;
  final ReviewGrade grade;
  final Duration took;
}

/// Cómo va una sesión de estudio (F31, ola 2): qué toca, cuánto queda y lo que
/// se hizo hasta ahora.
@immutable
class StudySessionState {
  const StudySessionState({
    this.next,
    this.counts,
    this.revealed = false,
    this.busy = false,
    this.answers = const [],
    this.shownAt,
    this.failure,
  });

  /// Qué sigue; `null` mientras carga la primera vez.
  final StudyNext? next;

  /// Cuánto hay para hoy en el recorte, con los límites de la sesión.
  final StudyCounts? counts;

  /// Si la tarjeta que se ve ya tiene la respuesta a la vista.
  final bool revealed;

  /// Si se está guardando una respuesta, deshaciéndola o recargando la cola:
  /// no se acepta otra acción hasta terminar.
  final bool busy;

  /// Lo contestado en esta sesión, de la más vieja a la más nueva, sin lo que
  /// se deshizo.
  final List<StudySessionAnswer> answers;

  /// Desde cuándo se ve la tarjeta de ahora: de ahí sale cuánto se tarda en
  /// contestarla.
  final DateTime? shownAt;

  /// Por qué no se pudo leer la cola, si falló. La pantalla lo dice y deja
  /// reintentar, en vez de fingir que no hay nada para repasar.
  final Failure? failure;

  /// La tarjeta que toca, o `null` si no hay ninguna a la vista.
  Flashcard? get card => switch (next) {
    StudyNextCard(:final card) => card,
    _ => null,
  };

  /// De qué cola sale la tarjeta que se ve.
  StudyQueueKind? get queue => switch (next) {
    StudyNextCard(:final queue) => queue,
    _ => null,
  };

  /// Cuántas respuestas lleva la sesión.
  int get answered => answers.length;

  /// Cuántas no fueron «De nuevo».
  int get correct => answers.where((a) => a.grade != ReviewGrade.again).length;

  /// Cuánto se tardó en total contestando.
  Duration get studied => answers.fold(Duration.zero, (sum, a) => sum + a.took);

  /// De 0 a 1: lo contestado sobre lo contestado más lo que falta. Una tarjeta
  /// que se olvida vuelve a contar como pendiente, así que puede retroceder un
  /// poco: dice la verdad de lo que falta, no de lo que se avanzó.
  double get progress {
    final remaining = counts?.total ?? 0;
    final total = answered + remaining;
    return total == 0 ? 0 : answered / total;
  }

  StudySessionState copyWith({
    StudyNext? next,
    bool clearNext = false,
    StudyCounts? counts,
    bool? revealed,
    bool? busy,
    List<StudySessionAnswer>? answers,
    DateTime? shownAt,
    Failure? failure,
    bool clearFailure = false,
  }) => StudySessionState(
    next: clearNext ? null : (next ?? this.next),
    counts: counts ?? this.counts,
    revealed: revealed ?? this.revealed,
    busy: busy ?? this.busy,
    answers: answers ?? this.answers,
    shownAt: shownAt ?? this.shownAt,
    failure: clearFailure ? null : (failure ?? this.failure),
  );
}

/// Una sesión de estudio sobre un recorte (F31, ola 2): lo que antes vivía en
/// el estado de la pantalla, aparte para poder probarlo sin dibujar nada.
///
/// El estado verdadero está en la base: tras cada respuesta se le vuelve a
/// preguntar a la cola (`StudyRepository.next`) qué toca. Acá solo vive lo que
/// la base no sabe: si la respuesta está a la vista, lo contestado en esta
/// sesión (para el resumen y para deshacer) y cuánto se amplió el límite.
class StudySessionController
    extends AutoDisposeFamilyNotifier<StudySessionState, StudyScope> {
  /// Cuánto se amplía el límite de hoy cada vez que se toca «Estudiar más hoy».
  static const moreNew = 10;
  static const moreReviews = 50;

  /// Lo más que cuenta una sola respuesta para el tiempo de la sesión: si se
  /// dejó el teléfono sobre la mesa, no se estudió dos horas.
  static const longestAnswer = Duration(minutes: 2);

  late DateTime _startedAt;
  var _alive = true;
  var _extraNew = 0;
  var _extraReviews = 0;
  var _learnAhead = Duration.zero;
  var _generation = 0;
  Timer? _wakeUp;

  @override
  StudySessionState build(StudyScope arg) {
    _startedAt = ref.read(clockProvider)();
    ref.onDispose(() {
      _alive = false;
      _wakeUp?.cancel();
    });
    // El despertador vive mientras alguien mira la sesión: al irse la pantalla
    // se apaga en el acto (no cuando el proveedor se descarta, un rato
    // después), y si vuelve a mirarse, se prende de nuevo.
    ref.onCancel(() => _wakeUp?.cancel());
    ref.onResume(() {
      final next = state.next;
      if (next is StudyNextWait) _wakeUpAt(next.until);
    });
    return const StudySessionState();
  }

  StudyScope get scope => arg;

  Future<void>? _started;

  /// Hace la primera lectura de la cola. Quien abre la sesión la llama una vez
  /// (volver a llamarla no repite nada): `build` no puede leer la base, porque
  /// el estado todavía no existe cuando termina.
  Future<void> start() => _started ??= load();

  /// Cuándo empezó la sesión: lo que se le pasa a `undoLastReview` para no
  /// deshacer lo de ayer.
  DateTime get startedAt => _startedAt;

  /// Los topes de hoy, con lo que se amplió en esta sesión.
  StudyLimits get _limits => ref
      .read(studyLimitsProvider)
      .extendedBy(newCards: _extraNew, reviews: _extraReviews);

  /// Le pregunta a la cola qué toca. Con [keepRevealed], si sigue siendo la
  /// misma tarjeta se queda con la respuesta a la vista (por ejemplo, tras
  /// editarla).
  Future<void> load({bool keepRevealed = false}) async {
    _wakeUp?.cancel();
    final generation = ++_generation;
    final limits = _limits;
    final learnAhead = _learnAhead;
    _learnAhead = Duration.zero;

    final repository = ref.read(studyRepositoryProvider);
    final next = await repository.next(
      scope,
      limits: limits,
      learnAhead: learnAhead,
    );
    final counts = await repository.counts(scope, limits: limits);
    // Una lectura más nueva ya está en camino o ya llegó: esta quedó vieja.
    if (!_alive || generation != _generation) return;

    final failure = next.getLeft().toNullable();
    if (failure != null) {
      state = state.copyWith(busy: false, failure: failure);
      return;
    }
    final fresh = next.getRight().toNullable()!;
    final sameCard =
        keepRevealed &&
        fresh is StudyNextCard &&
        state.card?.id == fresh.card.id;
    state = StudySessionState(
      next: fresh,
      counts: counts.getRight().toNullable() ?? state.counts,
      revealed: sameCard && state.revealed,
      answers: state.answers,
      shownAt: sameCard ? state.shownAt : ref.read(clockProvider)(),
    );
    if (fresh is StudyNextWait) _wakeUpAt(fresh.until);
  }

  /// Vuelve a preguntar cuando llega [until], que es cuando vuelve la próxima
  /// tarjeta en aprendizaje.
  void _wakeUpAt(DateTime until) {
    _wakeUp?.cancel();
    final wait = until.difference(ref.read(clockProvider)());
    _wakeUp = Timer(
      wait.isNegative ? Duration.zero : wait,
      () => unawaited(load()),
    );
  }

  /// Vuelve a leer solo cuánto hay, sin cambiar la tarjeta que se ve.
  Future<void> refreshCounts() async {
    final counts = await ref
        .read(studyRepositoryProvider)
        .counts(scope, limits: _limits);
    if (!_alive) return;
    final fresh = counts.getRight().toNullable();
    if (fresh != null) state = state.copyWith(counts: fresh);
  }

  /// Algo cambió en la base (la IA hizo tarjetas, se restauró un elemento,
  /// pasó el día): si no hay ninguna tarjeta a la vista se vuelve a preguntar,
  /// pero con una a la vista no se la cambia debajo de la persona.
  void onStudyDataChanged() {
    if (state.card == null && !state.busy) {
      unawaited(load());
    } else {
      unawaited(refreshCounts());
    }
  }

  /// Pone la respuesta a la vista.
  void reveal() {
    if (state.card == null || state.revealed) return;
    state = state.copyWith(revealed: true);
  }

  /// Califica la tarjeta que se ve. Devuelve por qué no se pudo guardar, o
  /// `null` si salió bien (o no había nada que calificar).
  Future<Failure?> grade(ReviewGrade grade) async {
    final card = state.card;
    if (card == null || state.busy || !state.revealed) return null;
    state = state.copyWith(busy: true);

    final now = ref.read(clockProvider)();
    final shownAt = state.shownAt ?? now;
    final elapsed = now.difference(shownAt);
    final took = elapsed.isNegative
        ? Duration.zero
        : (elapsed > longestAnswer ? longestAnswer : elapsed);

    final result = await ref
        .read(flashcardRepositoryProvider)
        .review(id: card.id, grade: grade);
    if (!_alive) return null;
    final failure = result.getLeft().toNullable();
    if (failure != null) {
      state = state.copyWith(busy: false);
      return failure;
    }
    state = state.copyWith(
      answers: [
        ...state.answers,
        StudySessionAnswer(cardId: card.id, grade: grade, took: took),
      ],
    );
    await load();
    return null;
  }

  /// Si hay una respuesta de esta sesión para deshacer.
  bool get canUndo => state.answers.isNotEmpty && !state.busy;

  /// Deshace la última respuesta de esta sesión: la tarjeta vuelve a como
  /// estaba y se muestra de nuevo, sin la respuesta a la vista. Devuelve por
  /// qué no se pudo, o `null`.
  Future<Failure?> undo() async {
    if (!canUndo) return null;
    state = state.copyWith(busy: true);
    final result = await ref
        .read(flashcardRepositoryProvider)
        .undoLastReview(since: _startedAt);
    if (!_alive) return null;
    final failure = result.getLeft().toNullable();
    if (failure != null) {
      state = state.copyWith(busy: false);
      return failure;
    }
    final card = result.getRight().toNullable()!;
    _wakeUp?.cancel();
    // Se invalida cualquier lectura en vuelo: mostraría lo de antes.
    _generation++;
    final answers = [...state.answers]..removeLast();
    state = StudySessionState(
      next: StudyNextCard(card: card, queue: _queueOf(card)),
      counts: state.counts,
      answers: answers,
      shownAt: ref.read(clockProvider)(),
    );
    await refreshCounts();
    return null;
  }

  /// «Estudiar más hoy»: amplía por hoy el límite y sigue.
  Future<void> studyMore() {
    _extraNew += moreNew;
    _extraReviews += moreReviews;
    return load();
  }

  /// «Seguir ahora»: trae ya la tarjeta que vuelve en unos minutos.
  Future<void> continueNow() {
    _learnAhead = const Duration(days: 1);
    return load();
  }

  /// Vuelve a intentar tras un fallo de lectura.
  Future<void> retry() {
    state = state.copyWith(clearFailure: true);
    return load();
  }

  /// Pausa la tarjeta que se ve y pasa a la siguiente. Devuelve el
  /// identificador pausado para poder reactivarla, o por qué no se pudo.
  Future<({String? id, Failure? failure})> suspendCurrent() async {
    final card = state.card;
    if (card == null || state.busy) return (id: null, failure: null);
    final result = await ref.read(flashcardRepositoryProvider).suspend([
      card.id,
    ]);
    return _leaveCurrent(card.id, result.getLeft().toNullable());
  }

  /// Pospone hasta mañana la tarjeta que se ve y pasa a la siguiente.
  Future<({String? id, Failure? failure})> buryCurrent() async {
    final card = state.card;
    if (card == null || state.busy) return (id: null, failure: null);
    final result = await ref
        .read(flashcardRepositoryProvider)
        .buryUntilTomorrow([card.id]);
    return _leaveCurrent(card.id, result.getLeft().toNullable());
  }

  /// Borra la tarjeta que se ve y pasa a la siguiente.
  Future<Failure?> deleteCurrent() async {
    final card = state.card;
    if (card == null || state.busy) return null;
    final result = await ref.read(flashcardRepositoryProvider).delete(card.id);
    final failure = result.getLeft().toNullable();
    if (failure != null) return failure;
    // Borrar la tarjeta se lleva su historial: «deshacer» ya no la alcanza,
    // y la próxima respuesta que deshace es la anterior de otra tarjeta. La
    // lista de la sesión tiene que seguir a la base.
    state = state.copyWith(
      answers: [
        for (final answer in state.answers)
          if (answer.cardId != card.id) answer,
      ],
    );
    await load();
    return null;
  }

  /// Cambia el texto de la tarjeta que se ve, sin cambiarla de lugar ni tapar
  /// su respuesta si ya estaba a la vista.
  Future<Failure?> editCurrent({
    required String front,
    required String back,
  }) async {
    final card = state.card;
    if (card == null || state.busy) return null;
    final result = await ref
        .read(flashcardRepositoryProvider)
        .update(id: card.id, front: front, back: back);
    final failure = result.getLeft().toNullable();
    if (failure != null) return failure;
    await load(keepRevealed: true);
    return null;
  }

  /// Reactiva una pausada o una pospuesta: vuelve a la cola, pero no
  /// reemplaza la tarjeta que se está viendo.
  Future<Failure?> restore(String id, {required bool wasSuspended}) async {
    final repository = ref.read(flashcardRepositoryProvider);
    final result = wasSuspended
        ? await repository.unsuspend([id])
        : await repository.unbury([id]);
    final failure = result.getLeft().toNullable();
    if (failure != null) return failure;
    onStudyDataChanged();
    return null;
  }

  Future<({String? id, Failure? failure})> _leaveCurrent(
    String id,
    Failure? failure,
  ) async {
    if (failure != null) return (id: null, failure: failure);
    await load();
    return (id: id, failure: null);
  }

  static StudyQueueKind _queueOf(Flashcard card) => switch (card.phase) {
    CardPhase.newCard => StudyQueueKind.newCard,
    CardPhase.learning || CardPhase.relearning => StudyQueueKind.learning,
    CardPhase.review => StudyQueueKind.review,
  };
}

/// La sesión de estudio de un recorte, mientras alguna pantalla la mira.
final studySessionProvider = NotifierProvider.autoDispose
    .family<StudySessionController, StudySessionState, StudyScope>(
      StudySessionController.new,
    );
