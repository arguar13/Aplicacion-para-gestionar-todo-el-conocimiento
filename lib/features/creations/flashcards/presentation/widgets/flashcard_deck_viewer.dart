import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/core/design/widgets/app_snack_bar.dart';
import 'package:sinapsis/core/domain/entities/flashcard.dart';
import 'package:sinapsis/core/domain/entities/habit_event_kind.dart';
import 'package:sinapsis/features/creations/domain/entities/creation_scope.dart';
import 'package:sinapsis/features/creations/domain/entities/study_creation.dart';
import 'package:sinapsis/features/creations/flashcards/domain/deck_round.dart';
import 'package:sinapsis/features/creations/flashcards/domain/flashcard_deck.dart';
import 'package:sinapsis/features/creations/flashcards/presentation/flashcards_kind.dart';
import 'package:sinapsis/features/creations/flashcards/presentation/widgets/study_viewer_parts.dart';
import 'package:sinapsis/features/creations/presentation/explain_in_chat_question.dart';
import 'package:sinapsis/features/creations/presentation/providers/creation_kinds.dart';
import 'package:sinapsis/features/creations/presentation/providers/creations_providers.dart';
import 'package:sinapsis/features/creations/presentation/repasar_navigation.dart';
import 'package:sinapsis/features/creations/presentation/widgets/creation_source_chips.dart';
import 'package:sinapsis/features/creations/presentation/widgets/explain_in_chat_button.dart';
import 'package:sinapsis/features/flashcards/domain/entities/review_grade.dart';
import 'package:sinapsis/features/flashcards/presentation/providers/flashcard_providers.dart';
import 'package:sinapsis/features/flashcards/presentation/widgets/open_flashcard_source.dart';
import 'package:sinapsis/features/flashcards/presentation/widgets/review_flip_card.dart';
import 'package:sinapsis/features/flashcards/presentation/widgets/review_grade_row.dart';
import 'package:sinapsis/features/flashcards/presentation/widgets/review_swipe_card.dart';
import 'package:sinapsis/features/habit/presentation/providers/habit_providers.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// El visor de «Tarjetas didácticas» (F43, M13, decisión M): el mazo se
/// **estudia como en Anki**, con la tarjeta y los cuatro botones de la sesión
/// de Repasar —sus mismas piezas: `ReviewFlipCard`, `ReviewSwipeCard` y
/// `ReviewGradeRow`—:
///
/// 1. se ve la pregunta y se piensa la respuesta (el recuerdo activo);
/// 2. «Mostrar respuesta», o tocar la tarjeta;
/// 3. De nuevo, Difícil, Bien o Fácil, con el intervalo de SM-2 debajo de
///    cada uno; también deslizando, igual que en Repasar.
///
/// Con «Sumar a mi repaso» prendido, cada calificación va **al calendario de
/// su tarjeta** —la del documento procesado (decisión F)— con el mismo
/// repositorio que la sesión de Repasar (`FlashcardRepository.review`), y
/// queda en el registro de repasos, que es de donde sale la racha. Apagado,
/// las tarjetas no tienen calendario: se califica **de práctica**, y lo dice.
/// «De nuevo» la vuelve a poner al final de la vuelta ([DeckRound]).
///
/// Arriba, «3 / 18» con su barra y barajar; al terminar, cuántas fueron a
/// cada botón, y la vuelta suma a la racha.
class FlashcardDeckViewer extends ConsumerStatefulWidget {
  const FlashcardDeckViewer({required this.creation, super.key});

  final StudyCreation creation;

  @override
  ConsumerState<FlashcardDeckViewer> createState() =>
      _FlashcardDeckViewerState();
}

class _FlashcardDeckViewerState extends ConsumerState<FlashcardDeckViewer> {
  late FlashcardDeck _deck = _decode(widget.creation);
  late DeckRound _round = DeckRound.start(_deck.cards.length);

  /// Mientras se guarda una calificación: no se acepta otra.
  var _grading = false;

  /// Mientras se suma o se saca del repaso: el interruptor espera.
  var _saving = false;

  static FlashcardDeck _decode(StudyCreation creation) =>
      FlashcardDeckJson.decode(creation.decodedContent);

  @override
  void didUpdateWidget(FlashcardDeckViewer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.creation.content == widget.creation.content) return;
    final deck = _decode(widget.creation);
    // Lo que cambia sin volver a generar (sumar o sacar del repaso) conserva
    // la vuelta; un mazo distinto empieza otra.
    final sameCards = deck.cards.length == _deck.cards.length;
    setState(() {
      _deck = deck;
      if (!sameCards) _round = DeckRound.start(deck.cards.length);
    });
  }

  /// La tarjeta de repaso de [card], si tiene calendario: la del documento,
  /// sumada y no pausada. `loading` mientras todavía no se leyó.
  ({Flashcard? card, bool loading}) _scheduled(DeckCard card) {
    final id = card.flashcardId;
    final documentId = card.documentId;
    if (!_deck.inReview || id == null || documentId == null) {
      return (card: null, loading: false);
    }
    final cards = ref.watch(itemFlashcardsProvider(documentId));
    final found = cards.valueOrNull
        ?.where((f) => f.id == id && !f.suspended)
        .firstOrNull;
    return (card: found, loading: !cards.hasValue);
  }

  void _reveal() => setState(() => _round = _round.reveal());

  Future<void> _grade(ReviewGrade grade, Flashcard? scheduled) async {
    if (_grading || !_round.revealed || _round.finished) return;
    if (scheduled != null) {
      final l10n = AppLocalizations.of(context)!;
      final messenger = ScaffoldMessenger.of(context);
      setState(() => _grading = true);
      final result = await ref
          .read(flashcardRepositoryProvider)
          .review(id: scheduled.id, grade: grade);
      if (!mounted) return;
      if (result.isLeft()) {
        setState(() => _grading = false);
        messenger
          ..hideCurrentSnackBar()
          ..showSnackBar(
            AppSnackBar(content: Text(l10n.f43S19DeckGradeFailed)),
          );
        return;
      }
    }
    final next = _round.grade(grade, practice: scheduled == null);
    setState(() {
      _grading = false;
      _round = next;
    });
    if (next.finished && next.practiced > 0) {
      // Lo calificado de verdad ya está en el registro de repasos, de donde
      // sale la racha; lo de práctica no deja rastro ahí: terminar la vuelta
      // cuenta una vez, como el cuestionario y la sesión de quiz (F20).
      unawaited(
        ref.read(habitEventRecorderProvider).record(HabitEventKind.quiz),
      );
    }
  }

  void _toggleShuffle() => setState(() => _round = _round.toggleShuffle());

  void _restart(DeckRound round) => setState(() => _round = round);

  Future<void> _setInReview(bool value) async {
    final l10n = AppLocalizations.of(context)!;
    final messenger = ScaffoldMessenger.of(context);
    final review = ref.read(deckReviewProvider);
    final repository = ref.read(studyCreationRepositoryProvider);
    setState(() => _saving = true);
    final changed = value
        ? await review.add(
            _deck,
            fallbackDocument: widget.creation.sourceIds.firstOrNull,
          )
        : await review.remove(_deck);
    final saved = await changed.match(
      (_) async => false,
      (deck) async => (await repository.amend(
        widget.creation.id,
        content: FlashcardDeckJson.encodeString(deck),
      )).isRight(),
    );
    if (!mounted) return;
    setState(() => _saving = false);
    if (!saved) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(AppSnackBar(content: Text(l10n.f43CardsInReviewFailed)));
    }
  }

  /// «Ver en la fuente»: el fragmento del que salió, si su tarjeta lo sabe;
  /// si no, el documento procesado; si tampoco, las fuentes de la creación.
  void _openSource(DeckCard card, Flashcard? scheduled) {
    if (scheduled != null && scheduled.hasSourceRange) {
      openFlashcardSource(context, scheduled);
      return;
    }
    final documentId = card.documentId ?? _singleSource;
    if (documentId != null) {
      openProcessedSource(context, documentId);
      return;
    }
    unawaited(showCreationSources(context, widget.creation));
  }

  String? get _singleSource {
    final sources = widget.creation.sourceIds;
    return sources.length == 1 ? sources.single : null;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final deck = _deck;
    if (deck.isEmpty) {
      return Center(
        key: const Key('deck-viewer-empty'),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(l10n.f43CardsEmpty, textAlign: TextAlign.center),
        ),
      );
    }
    final accent = ref
        .watch(creationKindRegistryProvider)
        .of(widget.creation.kind)
        .accent
        .of(context);
    final failure = deck.illustrationFailure;
    final notice = studyCreationWantsImages(widget.creation) && failure != null
        ? StudyIllustrationNotice(
            failure: failure,
            account: deck.illustrationAccount,
            message: l10n.f43CardsIllustrationsMissing,
          )
        : null;
    final review = _ReviewSwitch(
      inReview: deck.inReview,
      saving: _saving,
      onChanged: (value) => unawaited(_setInReview(value)),
    );

    final round = _round;
    if (round.finished) {
      return Column(
        key: const Key('deck-viewer'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: _DeckRoundSummary(
              round: round,
              accent: accent,
              onRestart: () => _restart(DeckRound.start(deck.cards.length)),
              onForgotten: () => _restart(DeckRound.only(round.forgotten)),
            ),
          ),
          review,
        ],
      );
    }

    final card = deck.cards[round.current];
    final scheduled = _scheduled(card);
    final practice = !scheduled.loading && scheduled.card == null;
    final busy = _grading || scheduled.loading;
    final header = _DeckHeader(
      index: round.done,
      total: round.total,
      accent: accent,
      shuffled: round.shuffled,
      onShuffle: round.queue.length > 1 ? _toggleShuffle : null,
    );
    final scope = widget.creation.scope;
    final turn = _DeckTurn(
      // Cada respuesta es otro turno: la tarjeta arranca del frente, en su
      // lugar, y sin la pista a la vista.
      key: ValueKey('deck-turn-${round.done}'),
      card: card,
      number: round.done + 1,
      total: round.total,
      revealed: round.revealed,
      swipeEnabled: round.revealed && !busy,
      onReveal: _reveal,
      onGrade: (grade) => unawaited(_grade(grade, scheduled.card)),
      picture:
          studyCreationWantsImages(widget.creation) ||
              card.illustrationRef != null
          ? StudyItemPicture(
              reference: card.illustrationRef,
              icon: card.icon,
              seed: round.current,
              accent: accent,
              semanticLabel: l10n.f43CardsPictureSemantics,
            )
          : null,
      onViewSource: () => _openSource(card, scheduled.card),
      explain: ExplainInChatButton(
        key: const Key('deck-explain'),
        subject: () => ExplainSubject(
          question: card.front,
          answer: card.back,
          answered: true,
        ),
        sourceItemId:
            scheduled.card?.itemId ?? card.documentId ?? _singleSource,
        passageStart: scheduled.card?.sourceCharStart,
        passageEnd: scheduled.card?.sourceCharEnd,
        notebookId: scope is NotebookScope ? scope.notebookId : null,
      ),
    );
    final answer = _DeckAnswerBar(
      revealed: round.revealed,
      practice: practice,
      onReveal: _reveal,
      grades: switch (scheduled.card) {
        final Flashcard scheduledCard => ReviewGradeRow(
          card: scheduledCard,
          grading: busy,
          onGrade: (grade) => unawaited(_grade(grade, scheduledCard)),
        ),
        null => ReviewGradeRow.practice(
          grading: busy,
          onGrade: (grade) => unawaited(_grade(grade, null)),
        ),
      },
    );

    return LayoutBuilder(
      key: const Key('deck-viewer'),
      builder: (context, constraints) {
        // Con la letra grande o una pantalla baja, lo de arriba y lo de abajo
        // no dejan lugar para la tarjeta: todo se desplaza junto.
        final scale = MediaQuery.textScalerOf(context).scale(1);
        final tight = constraints.maxHeight < 520 * scale.clamp(1, 3);
        if (!tight) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ?notice,
              header,
              Expanded(
                child: LayoutBuilder(
                  builder: (context, area) => SingleChildScrollView(
                    key: const Key('deck-card-area'),
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        minHeight: math.max(0, area.maxHeight - 24),
                      ),
                      child: Center(child: turn),
                    ),
                  ),
                ),
              ),
              answer,
              review,
            ],
          );
        }
        return SingleChildScrollView(
          key: const Key('deck-viewer-scroll'),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ?notice,
              header,
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: turn,
              ),
              answer,
              review,
            ],
          ),
        );
      },
    );
  }
}

/// «3 / 20», la barra de avance y barajar.
class _DeckHeader extends StatelessWidget {
  const _DeckHeader({
    required this.index,
    required this.total,
    required this.accent,
    required this.shuffled,
    required this.onShuffle,
  });

  final int index;
  final int total;
  final Color accent;
  final bool shuffled;
  final VoidCallback? onShuffle;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 8, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Semantics(
                  liveRegion: true,
                  label: l10n.f43CardsProgressSemantics(index + 1, total),
                  excludeSemantics: true,
                  child: Text(
                    l10n.f43CardsProgress(index + 1, total),
                    key: const Key('deck-progress'),
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
              ),
              IconButton(
                key: const Key('deck-shuffle'),
                tooltip: shuffled
                    ? l10n.f43CardsUnshuffle
                    : l10n.f43CardsShuffle,
                isSelected: shuffled,
                onPressed: onShuffle,
                icon: const Icon(Icons.shuffle),
                selectedIcon: Icon(Icons.shuffle_on_outlined, color: accent),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: total == 0 ? 0 : index / total,
                minHeight: 4,
                color: accent,
                backgroundColor: scheme.surfaceContainerHighest,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Un turno: la tarjeta de Repasar, que se da vuelta al mostrar la respuesta
/// y, dada vuelta, se desliza para calificarla; debajo, la pista para
/// deslizar, «Ver en la fuente» y «Explicar».
class _DeckTurn extends StatefulWidget {
  const _DeckTurn({
    required this.card,
    required this.number,
    required this.total,
    required this.revealed,
    required this.swipeEnabled,
    required this.onReveal,
    required this.onGrade,
    required this.picture,
    required this.onViewSource,
    required this.explain,
    super.key,
  });

  final DeckCard card;
  final int number;
  final int total;
  final bool revealed;
  final bool swipeEnabled;
  final VoidCallback onReveal;
  final ValueChanged<ReviewGrade> onGrade;
  final Widget? picture;
  final VoidCallback onViewSource;
  final Widget explain;

  @override
  State<_DeckTurn> createState() => _DeckTurnState();
}

class _DeckTurnState extends State<_DeckTurn> {
  var _showHint = false;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final card = widget.card;
    final revealed = widget.revealed;

    Widget label(String text) => Text(
      text.toUpperCase(),
      style: theme.textTheme.labelSmall?.copyWith(
        color: scheme.onSurfaceVariant,
        letterSpacing: 1.2,
        fontWeight: FontWeight.w600,
      ),
    );

    final front = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (widget.picture case final picture?) ...[
          picture,
          const SizedBox(height: 16),
        ],
        label(l10n.f43CardsQuestion),
        const SizedBox(height: 10),
        Text(
          card.front,
          key: const Key('deck-card-front'),
          textAlign: TextAlign.center,
          style: theme.textTheme.titleLarge,
        ),
        if (card.hint.isNotEmpty) ...[
          const SizedBox(height: 12),
          if (_showHint)
            Text(
              l10n.f43CardsHint(card.hint),
              key: const Key('deck-card-hint'),
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: scheme.onSurfaceVariant,
                fontStyle: FontStyle.italic,
              ),
            )
          else
            TextButton.icon(
              key: const Key('deck-show-hint'),
              onPressed: () => setState(() => _showHint = true),
              icon: const Icon(Icons.lightbulb_outline, size: 18),
              label: Text(l10n.f43CardsShowHint),
            ),
        ],
      ],
    );
    // Como en Repasar: dada vuelta, la pregunta sigue arriba y la respuesta
    // debajo de la raya.
    final back = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          card.front,
          textAlign: TextAlign.center,
          style: theme.textTheme.titleMedium?.copyWith(
            color: scheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 16),
        const Divider(),
        const SizedBox(height: 16),
        label(l10n.f43CardsAnswer),
        const SizedBox(height: 10),
        Text(
          card.back,
          key: const Key('deck-card-back'),
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyLarge?.copyWith(fontSize: 18),
        ),
      ],
    );

    final side = revealed ? l10n.f43CardsAnswer : l10n.f43CardsQuestion;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 560),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ReviewSwipeCard(
            key: const Key('deck-swipe'),
            enabled: widget.swipeEnabled,
            onSwiped: widget.onGrade,
            child: Semantics(
              button: !revealed,
              label: [
                l10n.f43CardsCardSemantics(
                  widget.number,
                  widget.total,
                  side,
                  revealed ? '${card.front}. ${card.back}' : card.front,
                ),
                if (!revealed && _showHint) l10n.f43CardsHint(card.hint),
              ].join('. '),
              // Lo de adentro va en la etiqueta: la pista, como acción.
              customSemanticsActions: {
                if (!revealed && card.hint.isNotEmpty && !_showHint)
                  CustomSemanticsAction(label: l10n.f43CardsShowHint): () =>
                      setState(() => _showHint = true),
              },
              onTap: revealed ? null : widget.onReveal,
              onTapHint: revealed ? null : l10n.reviewShowAnswer,
              excludeSemantics: true,
              child: ReviewFlipCard(
                key: const Key('deck-card'),
                showBack: revealed,
                onTap: revealed ? null : widget.onReveal,
                front: front,
                back: back,
              ),
            ),
          ),
          if (revealed) ...[
            const SizedBox(height: 12),
            Text(
              l10n.reviewSessionSwipeHint,
              key: const Key('deck-swipe-hint'),
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              alignment: WrapAlignment.center,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 8,
              runSpacing: 8,
              children: [
                TextButton.icon(
                  key: const Key('deck-view-source'),
                  icon: const Icon(Icons.menu_book_outlined, size: 18),
                  label: Text(l10n.flashcardsViewSource),
                  onPressed: widget.onViewSource,
                ),
                widget.explain,
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// Abajo, fijo: «Mostrar respuesta» y, con la respuesta a la vista, los
/// cuatro botones —de práctica, con su aviso, si no hay calendario—.
class _DeckAnswerBar extends StatelessWidget {
  const _DeckAnswerBar({
    required this.revealed,
    required this.practice,
    required this.onReveal,
    required this.grades,
  });

  final bool revealed;
  final bool practice;
  final VoidCallback onReveal;
  final Widget grades;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: !revealed
              ? FilledButton.tonal(
                  key: const Key('deck-show-answer'),
                  style: reviewWideButtonStyle(),
                  onPressed: onReveal,
                  child: Text(l10n.reviewShowAnswer),
                )
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (practice) ...[
                      Semantics(
                        liveRegion: true,
                        child: Row(
                          key: const Key('deck-practice-note'),
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Padding(
                              padding: const EdgeInsets.only(top: 1),
                              child: Icon(
                                Icons.fitness_center,
                                size: 16,
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                l10n.f43S19DeckPracticeNote,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: scheme.onSurfaceVariant,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 8),
                    ],
                    grades,
                  ],
                ),
        ),
      ),
    );
  }
}

/// Al terminar la vuelta: cuántas fueron a cada botón, si quedó en el
/// calendario o fue de práctica, la racha, y otra vuelta —entera, o solo con
/// las de «De nuevo»—.
class _DeckRoundSummary extends ConsumerWidget {
  const _DeckRoundSummary({
    required this.round,
    required this.accent,
    required this.onRestart,
    required this.onForgotten,
  });

  final DeckRound round;
  final Color accent;
  final VoidCallback onRestart;
  final VoidCallback onForgotten;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final tally = round.tally;
    final forgotten = round.forgotten.length;
    final practiced = round.practiced;
    final streak = ref.watch(currentStreakProvider).valueOrNull;
    final note = practiced == 0
        ? l10n.f43S19DeckDoneScheduled
        : practiced == round.done
        ? l10n.f43S19DeckDonePractice
        : l10n.f43S19DeckDoneMixed;
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(26),
    );

    return Center(
      child: SingleChildScrollView(
        key: const Key('deck-summary'),
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Icon(Icons.celebration_outlined, size: 52, color: accent),
              const SizedBox(height: 14),
              Text(
                l10n.f43S19DeckDoneTitle,
                textAlign: TextAlign.center,
                style: theme.textTheme.titleLarge,
              ),
              const SizedBox(height: 4),
              Text(
                '${l10n.f43CardsCount(round.size)} · '
                '${l10n.f43S19DeckDoneAnswers(round.done)}',
                key: const Key('deck-summary-count'),
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 20),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final grade in ReviewGrade.values)
                    _GradeTally(
                      key: Key('deck-tally-${grade.name}'),
                      grade: grade,
                      count: tally[grade]!,
                    ),
                ],
              ),
              const SizedBox(height: 16),
              Text(
                note,
                key: const Key('deck-summary-note'),
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
              if (streak != null && streak.days > 0) ...[
                const SizedBox(height: 12),
                Row(
                  key: const Key('deck-summary-streak'),
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.local_fire_department,
                      size: 20,
                      color: scheme.tertiary,
                    ),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        '${l10n.reviewSessionStatStreak}: '
                        '${l10n.reviewSessionStreakDays(streak.days)}',
                        style: theme.textTheme.titleSmall,
                      ),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 24),
              if (forgotten > 0) ...[
                FilledButton.icon(
                  key: const Key('deck-again-only'),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(52),
                    shape: shape,
                  ),
                  onPressed: onForgotten,
                  icon: const Icon(Icons.replay),
                  label: Text(
                    l10n.f43S19DeckAgainOnly(forgotten),
                    textAlign: TextAlign.center,
                  ),
                ),
                const SizedBox(height: 10),
              ],
              OutlinedButton.icon(
                key: const Key('deck-restart'),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(52),
                  shape: shape,
                ),
                onPressed: onRestart,
                icon: const Icon(Icons.restart_alt),
                label: Text(
                  l10n.f43S19DeckRestart,
                  textAlign: TextAlign.center,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Cuántas fueron a un botón, con su color y su ícono.
class _GradeTally extends StatelessWidget {
  const _GradeTally({required this.grade, required this.count, super.key});

  final ReviewGrade grade;
  final int count;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final (background, foreground) = reviewGradeColors(
      theme.colorScheme,
      grade,
    );
    final name = reviewGradeLabel(l10n, grade);
    return Semantics(
      label: l10n.f43S19DeckGradeTally(name, count),
      excludeSemantics: true,
      child: Container(
        constraints: const BoxConstraints(minWidth: 84),
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(reviewGradeIcon(grade), size: 16, color: foreground),
                const SizedBox(width: 4),
                Text(
                  '$count',
                  key: const Key('deck-tally-count'),
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: foreground,
                    fontWeight: FontWeight.w700,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              name,
              style: theme.textTheme.labelMedium?.copyWith(color: foreground),
            ),
          ],
        ),
      ),
    );
  }
}

/// «Sumar a mi repaso»: prendido, las tarjetas están en «Para hoy» y cada
/// calificación va a su calendario; apagado, se califican de práctica.
class _ReviewSwitch extends StatelessWidget {
  const _ReviewSwitch({
    required this.inReview,
    required this.saving,
    required this.onChanged,
  });

  final bool inReview;
  final bool saving;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        child: Material(
          color: scheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(20),
          clipBehavior: Clip.antiAlias,
          child: SwitchListTile(
            key: const Key('deck-in-review'),
            value: inReview,
            onChanged: saving ? null : onChanged,
            secondary: saving
                ? SizedBox.square(
                    dimension: 24,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      // Sin animaciones, la rueda queda quieta.
                      value: MediaQuery.disableAnimationsOf(context)
                          ? 0.66
                          : null,
                    ),
                  )
                : Icon(
                    inReview ? Icons.event_available : Icons.event_busy,
                    color: inReview ? scheme.primary : scheme.onSurfaceVariant,
                  ),
            title: Text(l10n.f43CardsInReview),
            subtitle: Text(
              inReview ? l10n.f43CardsInReviewOn : l10n.f43S19DeckInReviewOff,
            ),
          ),
        ),
      ),
    );
  }
}
