import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/core/design/widgets/empty_state_view.dart';
import 'package:sinapsis/core/domain/entities/flashcard.dart';
import 'package:sinapsis/core/domain/entities/flashcard_kind.dart';
import 'package:sinapsis/core/error/failure_messages.dart';
import 'package:sinapsis/core/error/failures.dart';
import 'package:sinapsis/core/util/util_providers.dart';
import 'package:sinapsis/features/flashcards/domain/entities/review_grade.dart';
import 'package:sinapsis/features/flashcards/domain/entities/study_next.dart';
import 'package:sinapsis/features/flashcards/domain/entities/study_scope.dart';
import 'package:sinapsis/features/flashcards/presentation/providers/flashcard_providers.dart';
import 'package:sinapsis/features/flashcards/presentation/providers/study_providers.dart';
import 'package:sinapsis/features/flashcards/presentation/providers/study_session_controller.dart';
import 'package:sinapsis/features/flashcards/presentation/widgets/review_card_menu.dart';
import 'package:sinapsis/features/flashcards/presentation/widgets/review_empty_state.dart';
import 'package:sinapsis/features/flashcards/presentation/widgets/review_session_card.dart';
import 'package:sinapsis/features/flashcards/presentation/widgets/review_session_progress.dart';
import 'package:sinapsis/features/flashcards/presentation/widgets/review_session_summary.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// Repasar las tarjetas que ya tocan, de a una: se lee la pregunta, se
/// intenta responder de memoria, se toca para revelar la respuesta, y se
/// califica qué tan bien salió. Esa calificación es lo único que decide
/// cuándo vuelve a aparecer (algoritmo SM-2, ver `scheduleNext`).
///
/// Qué toca lo decide la cola de estudio (`StudyRepository`) para [scope], y
/// el estado de la sesión vive en `StudySessionController`: esta pantalla lo
/// dibuja y le avisa lo que la persona hace.
class ReviewScreen extends ConsumerStatefulWidget {
  const ReviewScreen({
    this.scope = const StudyScope.all(),
    this.startInPractice = false,
    super.key,
  });

  /// Qué se estudia.
  final StudyScope scope;

  /// Empezar directamente en «Practicar igual» (F30): repasar todas las
  /// tarjetas aunque no les toque, sin tocar su calendario.
  final bool startInPractice;

  @override
  ConsumerState<ReviewScreen> createState() => _ReviewScreenState();
}

class _ReviewScreenState extends ConsumerState<ReviewScreen> {
  /// «Practicar igual» (F30): las tarjetas que se están practicando sin que
  /// les toque, y cuál va. `null` fuera de la práctica.
  List<Flashcard>? _practice;
  var _practiceIndex = 0;
  var _practiceRevealed = false;

  /// Quien recibe el teclado de la sesión (espacio, 1 a 4, Z).
  final _keys = FocusNode(debugLabel: 'Sesión de repaso');

  StudySessionController get _session =>
      ref.read(studySessionProvider(widget.scope).notifier);

  @override
  void dispose() {
    _keys.dispose();
    super.dispose();
  }

  /// Si lo que tiene el foco es un campo de texto: ahí se escribe, y las
  /// teclas de la sesión (un «1», un espacio, una «z») son letras.
  bool get _typing {
    final focused = FocusManager.instance.primaryFocus?.context;
    return focused != null &&
        (focused.widget is EditableText ||
            focused.findAncestorWidgetOfExactType<EditableText>() != null);
  }

  /// Los atajos de teclado de la compu: espacio da vuelta la tarjeta, 1 a 4
  /// califican («De nuevo», «Difícil», «Bien», «Fácil») y Z deshace.
  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent || _typing) return KeyEventResult.ignored;
    final keyboard = HardwareKeyboard.instance;
    final key = event.logicalKey;
    final session = ref.read(studySessionProvider(widget.scope));
    final practicing = _practice != null;

    // Deshacer: Z, o Control+Z / Cmd+Z.
    if (key == LogicalKeyboardKey.keyZ &&
        !keyboard.isAltPressed &&
        !practicing) {
      if (_session.canUndo) unawaited(_undo());
      return KeyEventResult.handled;
    }
    // Con otro modificador (Ctrl+1 cambia de pestaña en un navegador), no.
    if (keyboard.isControlPressed ||
        keyboard.isAltPressed ||
        keyboard.isMetaPressed) {
      return KeyEventResult.ignored;
    }

    final grade = switch (key) {
      LogicalKeyboardKey.digit1 ||
      LogicalKeyboardKey.numpad1 => ReviewGrade.again,
      LogicalKeyboardKey.digit2 ||
      LogicalKeyboardKey.numpad2 => ReviewGrade.hard,
      LogicalKeyboardKey.digit3 ||
      LogicalKeyboardKey.numpad3 => ReviewGrade.good,
      LogicalKeyboardKey.digit4 ||
      LogicalKeyboardKey.numpad4 => ReviewGrade.easy,
      _ => null,
    };
    if (grade != null) {
      if (!practicing && session.card != null && session.revealed) {
        unawaited(_grade(grade));
      }
      return KeyEventResult.handled;
    }

    if (key == LogicalKeyboardKey.space) {
      if (practicing) {
        _practiceRevealed ? _nextPractice() : _revealPractice();
      } else {
        final card = session.card;
        // De opción múltiple se contesta tocando una opción, y «escribí la
        // respuesta» se contesta escribiendo.
        if (card != null &&
            !session.revealed &&
            card.kind != FlashcardKind.multipleChoice &&
            card.kind != FlashcardKind.typedAnswer) {
          _session.reveal();
        }
      }
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _revealPractice() => setState(() => _practiceRevealed = true);

  @override
  void initState() {
    super.initState();
    unawaited(_session.start());
    if (widget.startInPractice) unawaited(_startPractice());
  }

  /// Practica todas las tarjetas, aunque no les toque: la que vence antes,
  /// primero. No califica: el calendario de cada una (SM-2) no cambia.
  Future<void> _startPractice() async {
    final all = await ref.read(flashcardRepositoryProvider).getAll();
    if (!mounted) return;
    final cards = all.getOrElse((_) => const <Flashcard>[]).toList()
      ..sort((a, b) => a.dueAt.compareTo(b.dueAt));
    if (cards.isEmpty) return;
    setState(() {
      _practice = cards;
      _practiceIndex = 0;
      _practiceRevealed = false;
    });
  }

  void _nextPractice() {
    final cards = _practice!;
    if (_practiceIndex + 1 >= cards.length) {
      _stopPractice();
    } else {
      setState(() {
        _practiceRevealed = false;
        _practiceIndex++;
      });
    }
  }

  /// Termina de practicar. Una pantalla que se abrió solo para practicar se
  /// cierra y vuelve a la entrada; si no, sigue la sesión de siempre.
  void _stopPractice() {
    setState(() {
      _practice = null;
      _practiceRevealed = false;
    });
    if (widget.startInPractice) _finish();
  }

  void _showFailure(Failure failure) {
    final l10n = AppLocalizations.of(context)!;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(failure.localizedMessage(l10n))));
  }

  Future<void> _grade(ReviewGrade grade) async {
    final failure = await _session.grade(grade);
    if (failure != null && mounted) _showFailure(failure);
  }

  Future<void> _undo() async {
    final failure = await _session.undo();
    if (failure != null && mounted) _showFailure(failure);
  }

  /// Cierra la sesión.
  void _finish() => unawaited(Navigator.of(context).maybePop());

  /// Lo que muestra la sesión según lo que dice la cola.
  Widget _body(AppLocalizations l10n, StudySessionState session) {
    final practice = _practice;
    if (practice != null) {
      return ReviewSessionCard(
        key: ValueKey('practice-${practice[_practiceIndex].id}'),
        card: practice[_practiceIndex],
        revealed: _practiceRevealed,
        grading: false,
        practice: (
          done: _practiceIndex,
          total: practice.length,
          onNext: _nextPractice,
          onStop: _stopPractice,
        ),
        onReveal: _revealPractice,
        onGrade: (_) {},
      );
    }

    final next = session.next;
    if (next == null) {
      final failure = session.failure;
      if (failure == null) return const CircularProgressIndicator();
      return EmptyStateView(
        key: const Key('review-load-failed'),
        icon: Icons.error_outline,
        title: l10n.reviewSessionLoadFailed,
        message: failure.localizedMessage(l10n),
        actionLabel: l10n.reviewSessionRetry,
        onAction: () => unawaited(_session.retry()),
      );
    }
    switch (next) {
      case StudyNextCard(:final card):
        return ReviewSessionCard(
          // La misma tarjeta vuelve en un minuto: otra clave, otro estado.
          key: ValueKey(
            '${card.id}:${card.lastReviewedAt?.millisecondsSinceEpoch}',
          ),
          card: card,
          revealed: session.revealed,
          grading: session.busy,
          onReveal: _session.reveal,
          onGrade: (grade) => unawaited(_grade(grade)),
        );
      case StudyNextWait(:final until, :final learningLeft):
        if (session.answered > 0) return _summary(session);
        final wait = until.difference(ref.read(clockProvider)());
        final minutes = (wait.inSeconds / 60).ceil().clamp(1, 24 * 60);
        return EmptyStateView(
          key: const Key('review-waiting'),
          icon: Icons.hourglass_bottom,
          title: l10n.reviewWaitTitle,
          message: l10n.reviewWaitMessage(learningLeft, minutes),
          actionLabel: l10n.reviewWaitNow,
          onAction: () => unawaited(_session.continueNow()),
        );
      case StudyNextDone(
        :final hitLimit,
        :final newBeyondLimit,
        :final reviewsBeyondLimit,
      ):
        if (session.answered > 0) return _summary(session);
        if (hitLimit) {
          return EmptyStateView(
            key: const Key('review-limit-reached'),
            icon: Icons.flag_outlined,
            title: l10n.reviewLimitTitle,
            message: l10n.reviewLimitMessage(
              newBeyondLimit,
              reviewsBeyondLimit,
            ),
            actionLabel: l10n.reviewLimitMore,
            onAction: () => unawaited(_session.studyMore()),
          );
        }
        // F30: si está vacío, dice por qué.
        return ReviewEmptyState(onPractice: () => unawaited(_startPractice()));
    }
  }

  Widget _summary(StudySessionState session) => ReviewSessionSummary(
    session: session,
    onFinish: _finish,
    onUndo: () => unawaited(_undo()),
    onStudyMore: () => unawaited(_session.studyMore()),
    onContinueNow: () => unawaited(_session.continueNow()),
  );

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final session = ref.watch(studySessionProvider(widget.scope));
    // Si no hay ninguna tarjeta a la vista y algo cambia (la IA hizo tarjetas,
    // se restauró un elemento, pasó el día), se vuelve a preguntar.
    ref.listen(studyCountsProvider(widget.scope), (previous, current) {
      if (_practice == null) _session.onStudyDataChanged();
    });
    final inSession = _practice == null && session.card != null;

    return Focus(
      focusNode: _keys,
      autofocus: true,
      onKeyEvent: _onKey,
      child: Scaffold(
        appBar: AppBar(
          title: Text(l10n.reviewTitle),
          actions: [
            if (_practice == null)
              IconButton(
                key: const Key('review-undo'),
                icon: const Icon(Icons.undo),
                tooltip: l10n.reviewSessionUndoTooltip,
                onPressed: _session.canUndo ? () => unawaited(_undo()) : null,
              ),
            if (inSession)
              ReviewCardMenu(scope: widget.scope, card: session.card!),
          ],
        ),
        body: SafeArea(
          child: Column(
            children: [
              if (inSession)
                Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 480),
                    child: ReviewSessionProgress(session: session),
                  ),
                ),
              Expanded(
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 480),
                    child: _body(l10n, session),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
