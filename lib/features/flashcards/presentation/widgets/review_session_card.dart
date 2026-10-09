import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/core/domain/entities/flashcard.dart';
import 'package:sinapsis/core/domain/entities/flashcard_kind.dart';
import 'package:sinapsis/core/domain/entities/flashcard_option.dart';
import 'package:sinapsis/features/flashcards/domain/entities/review_grade.dart';
import 'package:sinapsis/features/flashcards/domain/services/cloze.dart';
import 'package:sinapsis/features/flashcards/domain/services/typed_answer.dart';
import 'package:sinapsis/features/flashcards/domain/services/typed_answer_alternatives.dart';
import 'package:sinapsis/features/flashcards/presentation/providers/flashcard_providers.dart';
import 'package:sinapsis/features/flashcards/presentation/widgets/multiple_choice_options.dart';
import 'package:sinapsis/features/flashcards/presentation/widgets/open_flashcard_source.dart';
import 'package:sinapsis/features/flashcards/presentation/widgets/review_card_faces.dart';
import 'package:sinapsis/features/flashcards/presentation/widgets/review_flip_card.dart';
import 'package:sinapsis/features/flashcards/presentation/widgets/review_grade_row.dart';
import 'package:sinapsis/features/flashcards/presentation/widgets/review_swipe_card.dart';
import 'package:sinapsis/features/narration/domain/read_aloud/readable_segments.dart';
import 'package:sinapsis/features/narration/presentation/read_aloud/readable_registry.dart';
import 'package:sinapsis/features/organize/presentation/widgets/highlightable_text.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// Lo que necesita una tarjeta en «Practicar igual» (F30): cuántas van de
/// cuántas, y pasar a la siguiente o terminar, en vez de calificarla.
typedef ReviewPractice = ({
  int done,
  int total,
  VoidCallback onNext,
  VoidCallback onStop,
});

/// Una tarjeta de la sesión de repaso y todo lo que se hace con ella: leer la
/// pregunta, dar vuelta la tarjeta, contestar y calificar.
///
/// La forma de la tarjeta (`FlashcardKind`) decide cómo se contesta:
///
/// - pregunta y respuesta, verdadero o falso: se da vuelta;
/// - opción múltiple: se toca una opción;
/// - huecos para completar: el hueco que se pregunta se ve como `[...]` y al
///   dar vuelta se resalta la respuesta;
/// - «escribí la respuesta»: se escribe, se compara y se muestra la diferencia.
///
/// La calificación es siempre la misma: cuánto costó recordar.
class ReviewSessionCard extends ConsumerStatefulWidget {
  const ReviewSessionCard({
    required this.card,
    required this.revealed,
    required this.grading,
    required this.onReveal,
    required this.onGrade,
    this.practice,
    super.key,
  });

  /// En «Practicar igual»: sin calificar.
  final ReviewPractice? practice;

  final Flashcard card;
  final bool revealed;
  final bool grading;
  final VoidCallback onReveal;
  final ValueChanged<ReviewGrade> onGrade;

  @override
  ConsumerState<ReviewSessionCard> createState() => _ReviewSessionCardState();
}

class _ReviewSessionCardState extends ConsumerState<ReviewSessionCard> {
  final _typed = TextEditingController();

  /// Lo que dio comparar lo escrito, ya comprobado.
  TypedAnswerResult? _result;

  Flashcard get _card => widget.card;

  @override
  void dispose() {
    _typed.dispose();
    super.dispose();
  }

  /// Compara lo escrito con la respuesta y da vuelta la tarjeta. Sin nada
  /// escrito también vale: dice que no se escribió nada y muestra la
  /// respuesta.
  void _check() {
    if (widget.revealed) return;
    // Las alternativas viajan en `back`, una por renglón (decisión 73): lo
    // correcto es la primera línea, y las demás también valen.
    final spec = TypedAnswerSpec.parse(_card.back);
    setState(() {
      _result = compareTypedAnswer(
        typed: _typed.text,
        correct: spec.answer,
        alternatives: spec.alternatives,
      );
    });
    widget.onReveal();
  }

  /// Con la respuesta a la vista: calificarla, o —practicando— seguir.
  Widget _answered() {
    final current = widget.practice;
    return current == null
        ? ReviewGradeRow(
            card: _card,
            grading: widget.grading,
            onGrade: widget.onGrade,
          )
        : _PracticeRow(onNext: current.onNext, onStop: current.onStop);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final card = _card;
    final revealed = widget.revealed;
    final practice = widget.practice;
    final kind = card.kind;
    final isMultipleChoice = kind == FlashcardKind.multipleChoice;
    final isTyped = kind == FlashcardKind.typedAnswer;
    // back queda vacío en una tarjeta de opción múltiple
    // (FlashcardRepositoryImpl.createMultipleChoice): la respuesta sale de
    // sus opciones, no de acá.
    final showsBack = revealed && !isMultipleChoice;
    final frontKey = 'card:${card.id}:front';
    final backKey = 'card:${card.id}:back';

    // Una tarjeta de huecos dice el hueco que tapa; si el texto no lo tiene
    // (se editó mal desde otro lado) se muestra tal cual, sin romperse.
    final cloze = kind == FlashcardKind.cloze ? parseCloze(card.front) : null;
    final clozeNumber = card.clozeIndex;
    final clozeCard =
        cloze != null &&
            clozeNumber != null &&
            cloze.numbers.contains(clozeNumber)
        ? (
            question: cloze.questionSegmentsFor(clozeNumber),
            answer: cloze.answerSegmentsFor(clozeNumber),
            total: cloze.numbers.length,
          )
        : null;

    String join(List<ClozeSegment> segments) =>
        segments.map((s) => s.text).join();
    final spokenFront = clozeCard == null
        ? card.front
        : join(clozeCard.question);
    final spokenBack = clozeCard == null
        ? (isTyped ? TypedAnswerSpec.parse(card.back).answer : card.back)
        : [
            join(clozeCard.answer),
            if (card.back.trim().isNotEmpty) card.back,
          ].join('. ');

    // Lo que se lee en voz alta (F25): la pregunta y, ya revelada, la
    // respuesta. Revelarla es otro texto —otro `id`—: el lector vuelve a
    // empezar por la pregunta en vez de seguir donde terminó. Dos textos
    // cortos: armarlos acá cuesta nada, y esto se reconstruye solo al
    // revelar o al pasar de tarjeta.
    final readable = documentFrom(
      showsBack ? 'review:${card.id}:answer' : 'review:${card.id}',
      l10n.reviewTitle,
      [
        (
          sourceKey: frontKey,
          text: spokenFront,
          markdown: false,
          transcript: false,
        ),
        if (showsBack)
          (
            sourceKey: backKey,
            text: spokenBack,
            markdown: false,
            transcript: false,
          ),
      ],
    );

    Widget question() => ReadAloudText(
      card.front,
      sourceKey: frontKey,
      textAlign: TextAlign.center,
      style: theme.textTheme.titleLarge,
    );

    final Widget front;
    final Widget back;
    if (clozeCard != null) {
      Widget badge() => clozeCard.total > 1
          ? Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(
                l10n.reviewSessionClozeBadge(clozeNumber!, clozeCard.total),
                style: theme.textTheme.labelMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            )
          : const SizedBox.shrink();
      front = Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          badge(),
          ReviewClozeText(
            key: const Key('review-cloze-question'),
            segments: clozeCard.question,
          ),
        ],
      );
      back = Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          badge(),
          ReviewClozeText(
            key: const Key('review-cloze-answer'),
            segments: clozeCard.answer,
          ),
          if (card.back.trim().isNotEmpty) ...[
            const SizedBox(height: 16),
            const Divider(),
            const SizedBox(height: 16),
            Text(
              card.back,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyLarge,
            ),
          ],
        ],
      );
    } else {
      front = question();
      back = Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          question(),
          const SizedBox(height: 16),
          const Divider(),
          const SizedBox(height: 16),
          if (isTyped && _result != null)
            ReviewTypedResult(result: _result!)
          else
            ReadAloudText(
              isTyped ? TypedAnswerSpec.parse(card.back).answer : card.back,
              sourceKey: backKey,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyLarge,
            ),
        ],
      );
    }

    return ReadableRegion(
      document: readable,
      child: Padding(
        padding: const EdgeInsets.all(24),
        // De opción múltiple, la pregunta + hasta cuatro opciones + los
        // cuatro botones de calificar a la vez pueden pasarse de la altura
        // disponible en una pantalla chica —a diferencia de la tarjeta
        // simple, que nunca mostraba las dos cosas juntas—. Se desplaza en
        // vez de recortarse.
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (practice != null) ...[
                Text(
                  l10n.reviewPracticeProgress(
                    practice.done + 1,
                    practice.total,
                  ),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 24),
              ],
              ReviewSwipeCard(
                key: const Key('review-card'),
                // Se desliza para calificar una vez dada la vuelta, y no
                // practicando (ahí no se califica).
                enabled: revealed && !widget.grading && practice == null,
                onSwiped: widget.onGrade,
                child: ReviewFlipCard(
                  // De opción múltiple no se da vuelta: la respuesta son sus
                  // opciones, más abajo.
                  showBack: showsBack,
                  // De opción múltiple no se "revela" tocando la caja: se
                  // contesta tocando una opción. La de «escribí la
                  // respuesta» tampoco: se contesta escribiendo.
                  onTap: (revealed || isMultipleChoice || isTyped)
                      ? null
                      : widget.onReveal,
                  front: front,
                  back: back,
                ),
              ),
              if (revealed && practice == null) ...[
                const SizedBox(height: 12),
                Text(
                  l10n.reviewSessionSwipeHint,
                  key: const Key('review-swipe-hint'),
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
              const SizedBox(height: 24),
              // Con la respuesta a la vista, se puede ir a ver de dónde salió
              // —de opción múltiple, cada opción ya trae la suya propia más
              // abajo, `card.hasSourceRange` es siempre falso para esta
              // forma—.
              if (revealed && card.hasSourceRange) ...[
                TextButton.icon(
                  icon: const Icon(Icons.menu_book_outlined, size: 18),
                  label: Text(l10n.flashcardsViewSource),
                  onPressed: () => openFlashcardSource(context, card),
                ),
                const SizedBox(height: 8),
              ],
              if (isMultipleChoice) ...[
                // Montado siempre, contestada o no —así conserva su propio
                // estado de qué se tocó al revelar, en vez de perderlo
                // cuando `revealed` cambia y esta sección se arma de
                // nuevo—: las opciones, ya coloreadas, se quedan a la vista
                // mientras se califica.
                _MultipleChoiceAnswer(
                  // Con clave: lo que se muestra antes de estas opciones
                  // cambia al revelar (la pista de deslizar, el enlace a la
                  // fuente), y sin ella perderían lo que se tocó.
                  key: ValueKey('options:${card.id}'),
                  flashcardId: card.id,
                  onAnswered: (_) => widget.onReveal(),
                ),
                if (revealed) ...[const SizedBox(height: 16), _answered()],
              ] else if (revealed)
                _answered()
              else if (isTyped)
                _TypedAnswerInput(controller: _typed, onCheck: _check)
              else
                FilledButton.tonal(
                  key: const Key('review-show-answer'),
                  style: reviewWideButtonStyle(),
                  onPressed: widget.onReveal,
                  child: Text(l10n.reviewShowAnswer),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// El campo donde se escribe la respuesta, y el botón que la compara.
class _TypedAnswerInput extends StatelessWidget {
  const _TypedAnswerInput({required this.controller, required this.onCheck});

  final TextEditingController controller;
  final VoidCallback onCheck;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Column(
      children: [
        TextField(
          key: const Key('review-typed-field'),
          controller: controller,
          autofocus: true,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => onCheck(),
          decoration: InputDecoration(
            hintText: l10n.reviewSessionTypedHint,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
          ),
        ),
        const SizedBox(height: 12),
        FilledButton.tonal(
          key: const Key('review-typed-check'),
          style: reviewWideButtonStyle(),
          onPressed: onCheck,
          child: Text(l10n.reviewSessionTypedCheck),
        ),
      ],
    );
  }
}

/// En «Practicar igual» (F30): la siguiente, o terminar. No califica: el
/// calendario de la tarjeta no cambia.
class _PracticeRow extends StatelessWidget {
  const _PracticeRow({required this.onNext, required this.onStop});

  final VoidCallback onNext;
  final VoidCallback onStop;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Row(
      children: [
        Expanded(
          child: OutlinedButton(
            key: const Key('practice-stop'),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(kReviewButtonHeight),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
            onPressed: onStop,
            child: Text(l10n.reviewPracticeStop),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: FilledButton.tonal(
            key: const Key('practice-next'),
            style: reviewWideButtonStyle(),
            onPressed: onNext,
            child: Text(l10n.reviewPracticeNext),
          ),
        ),
      ],
    );
  }
}

/// Trae las opciones de [flashcardId] y las muestra con
/// [MultipleChoiceOptions] apenas están listas —sin spinner propio: la
/// tarjeta ya se ve, solo faltan sus opciones un instante—.
class _MultipleChoiceAnswer extends ConsumerWidget {
  const _MultipleChoiceAnswer({
    required this.flashcardId,
    required this.onAnswered,
    super.key,
  });

  final String flashcardId;
  final ValueChanged<FlashcardOption> onAnswered;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final options = ref.watch(flashcardOptionsProvider(flashcardId));
    return options.when(
      loading: () => const SizedBox.shrink(),
      error: (error, stackTrace) => const SizedBox.shrink(),
      data: (options) =>
          MultipleChoiceOptions(options: options, onAnswered: onAnswered),
    );
  }
}
