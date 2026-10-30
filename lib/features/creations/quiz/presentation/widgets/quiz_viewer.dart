import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/core/domain/entities/habit_event_kind.dart';
import 'package:sinapsis/features/creations/design/creation_art.dart';
import 'package:sinapsis/features/creations/domain/entities/creation_scope.dart';
import 'package:sinapsis/features/creations/domain/entities/study_creation.dart';
import 'package:sinapsis/features/creations/domain/services/structured_writer.dart';
import 'package:sinapsis/features/creations/flashcards/presentation/widgets/study_viewer_parts.dart';
import 'package:sinapsis/features/creations/presentation/explain_in_chat_question.dart';
import 'package:sinapsis/features/creations/presentation/providers/creation_kinds.dart';
import 'package:sinapsis/features/creations/presentation/repasar_navigation.dart';
import 'package:sinapsis/features/creations/presentation/widgets/creation_source_chips.dart';
import 'package:sinapsis/features/creations/presentation/widgets/explain_in_chat_button.dart';
import 'package:sinapsis/features/creations/quiz/domain/quiz.dart';
import 'package:sinapsis/features/creations/quiz/domain/quiz_session.dart';
import 'package:sinapsis/features/creations/quiz/presentation/quiz_kind.dart';
import 'package:sinapsis/features/creations/quiz/presentation/widgets/quiz_parts.dart';
import 'package:sinapsis/features/flashcards/domain/services/typed_answer.dart';
import 'package:sinapsis/features/habit/presentation/providers/habit_providers.dart';
import 'package:sinapsis/features/transform/domain/entities/cancellation_signal.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// El visor del «Cuestionario» (F43, paso 8), con el diseño de las capturas
/// de NotebookLM (M15): arriba, «6 / 14» con ⋮ («Ver en la fuente» y
/// «Empezar de nuevo»); la pregunta en negrita y grande; cada opción en su
/// tarjeta, con «A.»; al responder, la correcta con borde verde y
/// «✓ ¡Exacto!» o la elegida con borde rojo y «No es esa», y **cada opción**
/// con su explicación debajo; «Explicar» debajo de las opciones, que lleva la
/// pregunta al chat (decisión L); abajo, fijos, Anterior y Siguiente; al
/// final, el puntaje y «Repetir solo las que fallé». Sin 👍 ni 👎 (decisión
/// I).
///
/// Los cuatro tipos:
///
/// - **Opción única**: tocar una opción ya responde.
/// - **Selección múltiple**: se tildan las que correspondan y «Comprobar».
/// - **Completar espacios**: se escribe lo que falta y se compara sin tildes
///   ni mayúsculas (la comparación del repaso, F31); un «casi» lo decide la
///   persona.
/// - **Respuesta breve**: con una IA lista, la IA dice si está bien y por qué
///   —se puede cancelar mientras revisa—; sin IA, o si no pudo, se muestra la
///   respuesta esperada y la persona se autocalifica.
///
/// Responder no toca ninguna tarjeta ni su calendario: terminar una vuelta
/// cuenta para la racha, como el quiz de siempre (F20).
class QuizViewer extends ConsumerStatefulWidget {
  const QuizViewer({required this.creation, super.key});

  final StudyCreation creation;

  @override
  ConsumerState<QuizViewer> createState() => _QuizViewerState();
}

class _QuizViewerState extends ConsumerState<QuizViewer> {
  late Quiz _quiz = QuizJson.decode(widget.creation.decodedContent);
  late QuizRun _run = QuizRun.start(_quiz);
  final _scroll = ScrollController();

  /// Lo que se va tildando en una de selección múltiple, antes de comprobar.
  final _picked = <String, Set<int>>{};

  /// Lo escrito en las de completar y respuesta breve.
  final _typed = <String, TextEditingController>{};

  /// Una de completar con un «casi», esperando que la persona decida.
  final _almost = <String, TypedAnswerResult>{};

  /// Una de respuesta breve que se califica a mano, y por qué.
  final _selfGrade = <String, _SelfGradeReason>{};

  /// La que la IA está revisando, y cómo cortarla.
  String? _gradingId;
  CancellationSignal? _grading;

  @override
  void didUpdateWidget(QuizViewer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.creation.content == widget.creation.content) return;
    // Otro contenido —se volvió a generar—: otra vuelta desde el principio.
    _restart(QuizJson.decode(widget.creation.decodedContent));
  }

  @override
  void dispose() {
    _grading?.cancel();
    _scroll.dispose();
    for (final controller in _typed.values) {
      controller.dispose();
    }
    super.dispose();
  }

  TextEditingController _controllerOf(String id) =>
      _typed[id] ??= TextEditingController();

  void _forget(Iterable<String> ids) {
    for (final id in ids) {
      _picked.remove(id);
      _typed.remove(id)?.dispose();
      _almost.remove(id);
      _selfGrade.remove(id);
    }
  }

  void _restart(Quiz quiz) {
    _stopGrading();
    setState(() {
      _forget(_quiz.questions.map((q) => q.id));
      _quiz = quiz;
      _run = QuizRun.start(quiz);
    });
    _toTop();
  }

  void _retryMissed() {
    _stopGrading();
    final missed = _run.missed;
    setState(() {
      _forget(missed.map((q) => q.id));
      _run = _run.retryMissed();
    });
    _toTop();
  }

  void _toTop() {
    if (_scroll.hasClients) _scroll.jumpTo(0);
  }

  void _stopGrading() {
    _grading?.cancel();
    _grading = null;
    _gradingId = null;
  }

  void _go(QuizRun Function(QuizRun run) move) {
    _stopGrading();
    final next = move(_run);
    if (next.finished && !_run.finished) {
      // Terminar una vuelta cuenta para la racha, una vez, como el quiz de
      // siempre (F20): no por pregunta.
      unawaited(
        ref.read(habitEventRecorderProvider).record(HabitEventKind.quiz),
      );
    }
    setState(() => _run = next);
    _toTop();
  }

  void _answer(QuizAnswer answer) => setState(() => _run = _run.answer(answer));

  // --- Opciones ------------------------------------------------------------

  void _tapOption(QuizQuestion question, int index) {
    if (_run.currentAnswer != null) return;
    if (question.type == QuizQuestionType.single) {
      _answer(
        QuizChoiceAnswer(
          chosen: {index},
          verdict: gradeQuizChoice(question, {index}),
        ),
      );
      return;
    }
    setState(() {
      final picked = _picked[question.id] ??= {};
      if (!picked.remove(index)) picked.add(index);
    });
  }

  void _checkChoices(QuizQuestion question) {
    final chosen = {...?_picked[question.id]};
    if (chosen.isEmpty) return;
    _answer(
      QuizChoiceAnswer(
        chosen: chosen,
        verdict: gradeQuizChoice(question, chosen),
      ),
    );
  }

  // --- Escritas -------------------------------------------------------------

  void _checkBlank(QuizQuestion question) {
    final typed = _controllerOf(question.id).text;
    final graded = gradeQuizBlank(question, typed);
    final verdict = graded.verdict;
    if (verdict == null) {
      setState(() => _almost[question.id] = graded.comparison);
      return;
    }
    _answer(
      QuizTypedAnswer(
        typed: typed,
        verdict: verdict,
        comparison: graded.comparison,
      ),
    );
  }

  void _decideAlmost(QuizQuestion question, {required bool right}) {
    final comparison = _almost.remove(question.id);
    _answer(
      QuizTypedAnswer(
        typed: _controllerOf(question.id).text,
        verdict: right ? QuizVerdict.correct : QuizVerdict.wrong,
        comparison: comparison,
        by: QuizGrader.self,
      ),
    );
  }

  Future<void> _checkShort(QuizQuestion question) async {
    final typed = _controllerOf(question.id).text;
    if (typed.trim().isEmpty) return;
    final grader = ref.read(quizAnswerGraderProvider);
    final signal = CancellationSignal();
    setState(() {
      _grading = signal;
      _gradingId = question.id;
    });
    if (!await grader.isAvailable()) {
      if (!mounted || signal.isCancelled) return;
      setState(() {
        _stopGrading();
        _selfGrade[question.id] = _SelfGradeReason.noAi;
      });
      return;
    }
    try {
      final grade = await grader.grade(
        question: question,
        typed: typed,
        languageCode: widget.creation.languageCode,
        cancellation: signal,
      );
      if (!mounted || signal.isCancelled) return;
      _stopGrading();
      _answer(
        QuizTypedAnswer(
          typed: typed,
          verdict: grade.correct ? QuizVerdict.correct : QuizVerdict.wrong,
          reason: grade.reason,
          by: QuizGrader.ai,
        ),
      );
    } on CreationCancelledException {
      // Lo cortó la persona: lo califica ella.
      if (!mounted) return;
      if (_run.current.id == question.id) {
        setState(() => _selfGrade[question.id] = _SelfGradeReason.cancelled);
      }
      // El modelo es de terceros y falla de formas sin tipo propio: cualquier
      // cosa que no sea cancelar deja calificarla a mano, nunca se cae.
      // ignore: avoid_catches_without_on_clauses
    } catch (_) {
      if (!mounted || signal.isCancelled) return;
      setState(() {
        _stopGrading();
        _selfGrade[question.id] = _SelfGradeReason.failed;
      });
    }
  }

  void _cancelGrading() {
    final id = _gradingId;
    _grading?.cancel();
    setState(() {
      _grading = null;
      _gradingId = null;
      if (id != null) _selfGrade[id] = _SelfGradeReason.cancelled;
    });
  }

  void _selfGradeShort(QuizQuestion question, {required bool right}) {
    _selfGrade.remove(question.id);
    _answer(
      QuizTypedAnswer(
        typed: _controllerOf(question.id).text,
        verdict: right ? QuizVerdict.correct : QuizVerdict.wrong,
        by: QuizGrader.self,
      ),
    );
  }

  // --- Fuente y «Explicar» --------------------------------------------------

  /// El documento del que sale [question]: el que dijo la IA o, si el
  /// cuestionario se hizo de uno solo, ese.
  String? _documentOf(QuizQuestion question) {
    final sources = widget.creation.sourceIds;
    return question.documentId ?? (sources.length == 1 ? sources.single : null);
  }

  /// «Ver en la fuente»: el documento procesado de la pregunta; si no se
  /// sabe cuál, las fuentes del cuestionario.
  void _openSource(QuizQuestion question) {
    final documentId = _documentOf(question);
    if (documentId != null) {
      openProcessedSource(context, documentId);
    } else {
      unawaited(showCreationSources(context, widget.creation));
    }
  }

  /// Lo que «Explicar» le lleva al chat sobre [question], tal como está
  /// ahora: antes de responder, la pregunta y sus opciones; después, también
  /// lo elegido o lo escrito y cuál es la respuesta.
  ExplainSubject _explainSubject(QuizQuestion question) {
    final answer = _run.answers[question.id];
    final chosen = switch (answer) {
      QuizChoiceAnswer(:final chosen) => chosen,
      _ => const <int>{},
    };
    return ExplainSubject(
      question: question.prompt,
      options: [
        if (question.type.hasOptions)
          for (final (i, option) in question.options.indexed)
            ExplainOption(
              text: option.text,
              correct: option.correct,
              chosen: chosen.contains(i),
            ),
      ],
      answer: question.type.isTyped ? question.answer : null,
      typed: answer is QuizTypedAnswer ? answer.typed : null,
      typedCorrect: answer is QuizTypedAnswer ? answer.isCorrect : null,
      answered: answer != null,
    );
  }

  Widget _explain(QuizQuestion question) {
    final scope = widget.creation.scope;
    return Center(
      child: ExplainInChatButton(
        key: const Key('quiz-explain'),
        subject: () => _explainSubject(question),
        sourceItemId: _documentOf(question),
        notebookId: scope is NotebookScope ? scope.notebookId : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final quiz = _quiz;
    if (quiz.isEmpty) {
      return Center(
        key: const Key('quiz-viewer-empty'),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(l10n.f43QuizEmpty, textAlign: TextAlign.center),
        ),
      );
    }
    final accent = ref
        .watch(creationKindRegistryProvider)
        .of(widget.creation.kind)
        .accent
        .of(context);
    final failure = quiz.illustrationFailure;
    final wantsImages = studyCreationWantsImages(widget.creation);

    if (_run.finished) {
      return QuizScoreView(
        key: const Key('quiz-score'),
        correct: _run.correct,
        total: _run.total,
        missed: _run.missed.length,
        accent: accent,
        onRetryMissed: _retryMissed,
        onRestart: () => _restart(_quiz),
      );
    }

    final question = _run.current;
    final answer = _run.currentAnswer;
    return Column(
      key: const Key('quiz-viewer'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (wantsImages && failure != null)
          StudyIllustrationNotice(
            failure: failure,
            account: quiz.illustrationAccount,
            message: l10n.f43QuizIllustrationsMissing,
          ),
        QuizHeader(
          index: _run.index,
          total: _run.total,
          type: question.type,
          accent: accent,
          retry: _run.retry,
          menu: _QuizMenu(
            onViewSource: () => _openSource(question),
            onRestart: () => _restart(_quiz),
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            key: const Key('quiz-scroll'),
            controller: _scroll,
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 640),
                child: Column(
                  key: ValueKey('quiz-question-${question.id}'),
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    QuizPrompt(question: question, accent: accent),
                    if (wantsImages || question.illustrationRef != null) ...[
                      const SizedBox(height: 16),
                      Center(
                        child: StudyItemPicture(
                          reference: question.illustrationRef,
                          icon: question.icon,
                          seed: _quiz.questions.indexOf(question),
                          accent: accent,
                          style: CreationArtStyle.paper,
                          semanticLabel: l10n.f43QuizPictureSemantics,
                        ),
                      ),
                    ],
                    const SizedBox(height: 16),
                    ..._body(context, question, answer, accent),
                  ],
                ),
              ),
            ),
          ),
        ),
        QuizNavigation(
          canGoBack: !_run.isFirst,
          isLast: _run.isLast,
          onPrevious: () => _go((run) => run.previous()),
          onNext: () => _go((run) => run.next()),
        ),
      ],
    );
  }

  List<Widget> _body(
    BuildContext context,
    QuizQuestion question,
    QuizAnswer? answer,
    Color accent,
  ) {
    final l10n = AppLocalizations.of(context)!;
    switch (question.type) {
      case QuizQuestionType.single || QuizQuestionType.multiple:
        final multiple = question.type == QuizQuestionType.multiple;
        final chosen = switch (answer) {
          QuizChoiceAnswer(:final chosen) => chosen,
          _ => _picked[question.id] ?? const <int>{},
        };
        return [
          QuizInstruction(
            multiple ? l10n.f43QuizChooseAll : l10n.f43QuizChooseOne,
          ),
          const SizedBox(height: 10),
          for (final (i, option) in question.options.indexed)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: QuizOptionTile(
                key: Key('quiz-option-$i'),
                index: i,
                option: option,
                multiple: multiple,
                selected: chosen.contains(i),
                answered: answer != null,
                accent: accent,
                onTap: answer == null ? () => _tapOption(question, i) : null,
              ),
            ),
          if (multiple && answer == null) ...[
            const SizedBox(height: 4),
            FilledButton(
              key: const Key('quiz-check'),
              style: quizWideButtonStyle(),
              onPressed: chosen.isEmpty ? null : () => _checkChoices(question),
              child: Text(l10n.f43QuizCheck),
            ),
            const SizedBox(height: 10),
          ],
          // El veredicto va en las tarjetas de las opciones; debajo de ellas,
          // «Explicar» y, ya respondida, el porqué de la pregunta.
          const SizedBox(height: 4),
          _explain(question),
          if (answer != null && question.explanation.isNotEmpty) ...[
            const SizedBox(height: 16),
            QuizExplanation(text: question.explanation),
          ],
        ];
      case QuizQuestionType.fillBlank:
        final almost = _almost[question.id];
        return [
          QuizInstruction(l10n.f43QuizFillHint),
          const SizedBox(height: 10),
          QuizTypedField(
            controller: _controllerOf(question.id),
            hint: l10n.f43QuizFillHint,
            enabled: answer == null && almost == null,
            onSubmitted: () => _checkBlank(question),
          ),
          const SizedBox(height: 12),
          if (answer == null && almost == null)
            ListenableBuilder(
              listenable: _controllerOf(question.id),
              builder: (context, _) => FilledButton(
                key: const Key('quiz-check'),
                style: quizWideButtonStyle(),
                onPressed: _controllerOf(question.id).text.trim().isEmpty
                    ? null
                    : () => _checkBlank(question),
                child: Text(l10n.f43QuizCheck),
              ),
            ),
          if (almost != null) ...[
            QuizVerdictBanner(
              correct: null,
              title: l10n.f43QuizAlmost,
              detail: l10n.f43QuizAlmostHint,
            ),
            const SizedBox(height: 12),
            QuizTypedComparison(result: almost),
            const SizedBox(height: 12),
            QuizSelfGradeRow(
              onRight: () => _decideAlmost(question, right: true),
              onWrong: () => _decideAlmost(question, right: false),
            ),
          ],
          if (answer case final QuizTypedAnswer typed) ...[
            QuizVerdictBanner(
              correct: typed.isCorrect,
              title: typed.isCorrect ? l10n.f43QuizExact : l10n.f43QuizNotQuite,
              detail: typed.by == QuizGrader.self
                  ? (typed.isCorrect
                        ? l10n.f43QuizSelfRight
                        : l10n.f43QuizSelfWrong)
                  : null,
            ),
            const SizedBox(height: 12),
            if (typed.comparison case final comparison?
                when !comparison.isMatch)
              QuizTypedComparison(result: comparison)
            else
              QuizExpectedAnswer(answer: question.answer),
            if (question.explanation.isNotEmpty) ...[
              const SizedBox(height: 12),
              QuizExplanation(text: question.explanation),
            ],
          ],
          const SizedBox(height: 16),
          _explain(question),
        ];
      case QuizQuestionType.shortAnswer:
        final grading = _gradingId == question.id;
        final self = _selfGrade[question.id];
        return [
          QuizInstruction(l10n.f43QuizShortHint),
          const SizedBox(height: 10),
          QuizTypedField(
            controller: _controllerOf(question.id),
            hint: l10n.f43QuizShortHint,
            enabled: answer == null && !grading && self == null,
            multiline: true,
            onSubmitted: () => unawaited(_checkShort(question)),
          ),
          const SizedBox(height: 12),
          if (answer == null && !grading && self == null)
            ListenableBuilder(
              listenable: _controllerOf(question.id),
              builder: (context, _) => FilledButton(
                key: const Key('quiz-check'),
                style: quizWideButtonStyle(),
                onPressed: _controllerOf(question.id).text.trim().isEmpty
                    ? null
                    : () => unawaited(_checkShort(question)),
                child: Text(l10n.f43QuizCheck),
              ),
            ),
          if (grading) QuizGradingCard(onCancel: _cancelGrading),
          if (self != null) ...[
            QuizVerdictBanner(
              correct: null,
              title: switch (self) {
                _SelfGradeReason.noAi => l10n.f43QuizNoAi,
                _SelfGradeReason.failed => l10n.f43QuizGradeFailed,
                _SelfGradeReason.cancelled => l10n.f43QuizSelfGradePrompt,
              },
              detail: self == _SelfGradeReason.cancelled
                  ? null
                  : l10n.f43QuizSelfGradePrompt,
            ),
            const SizedBox(height: 12),
            QuizExpectedAnswer(answer: question.answer),
            const SizedBox(height: 12),
            QuizSelfGradeRow(
              onRight: () => _selfGradeShort(question, right: true),
              onWrong: () => _selfGradeShort(question, right: false),
            ),
          ],
          if (answer case final QuizTypedAnswer typed) ...[
            QuizVerdictBanner(
              correct: typed.isCorrect,
              title: typed.isCorrect ? l10n.f43QuizExact : l10n.f43QuizNotQuite,
              detail: switch (typed.by) {
                QuizGrader.ai =>
                  typed.isCorrect ? l10n.f43QuizAiRight : l10n.f43QuizAiWrong,
                QuizGrader.self =>
                  typed.isCorrect
                      ? l10n.f43QuizSelfRight
                      : l10n.f43QuizSelfWrong,
                QuizGrader.comparison => null,
              },
              reason: typed.reason,
            ),
            const SizedBox(height: 12),
            QuizExpectedAnswer(answer: question.answer),
            if (question.explanation.isNotEmpty) ...[
              const SizedBox(height: 12),
              QuizExplanation(text: question.explanation),
            ],
          ],
          if (!grading) ...[const SizedBox(height: 16), _explain(question)],
        ];
    }
  }
}

/// El ⋮ de arriba: «Ver en la fuente» y «Empezar de nuevo».
class _QuizMenu extends StatelessWidget {
  const _QuizMenu({required this.onViewSource, required this.onRestart});

  final VoidCallback onViewSource;
  final VoidCallback onRestart;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return PopupMenuButton<VoidCallback>(
      key: const Key('quiz-menu'),
      tooltip: l10n.f43S19QuizMenu,
      icon: const Icon(Icons.more_vert),
      onSelected: (action) => action(),
      itemBuilder: (context) => [
        PopupMenuItem(
          key: const Key('quiz-menu-source'),
          value: onViewSource,
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.menu_book_outlined),
            title: Text(l10n.flashcardsViewSource),
          ),
        ),
        PopupMenuItem(
          key: const Key('quiz-menu-restart'),
          value: onRestart,
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.restart_alt),
            title: Text(l10n.f43QuizRestart),
          ),
        ),
      ],
    );
  }
}

/// Por qué una respuesta breve se califica a mano.
enum _SelfGradeReason { noAi, failed, cancelled }
