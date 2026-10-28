import 'package:fpdart/fpdart.dart';
import 'package:sinapsis/core/domain/entities/flashcard.dart';
import 'package:sinapsis/core/domain/entities/knowledge_item.dart';
import 'package:sinapsis/core/error/failures.dart';
import 'package:sinapsis/features/flashcards/domain/entities/flashcard_option_draft.dart';
import 'package:sinapsis/features/flashcards/domain/repositories/flashcard_repository.dart';
import 'package:sinapsis/features/flashcards/domain/services/distractor_sourcer.dart';
import 'package:sinapsis/features/flashcards/domain/services/flashcard_generator.dart';
import 'package:sinapsis/features/flashcards/domain/services/quiz_question_generator.dart';
import 'package:sinapsis/features/flashcards/domain/services/source_quote_locator.dart';
import 'package:sinapsis/features/library/domain/repositories/library_repository.dart';
import 'package:sinapsis/features/processed/domain/repositories/processed_repository.dart';
import 'package:sinapsis/features/processed/domain/services/processed_card_text.dart';
import 'package:sinapsis/features/reading/domain/extractable_text.dart';

/// Una pregunta de quiz generada y YA LISTA para guardarse —anclada de
/// verdad, nunca una sugerencia a medias—, pendiente solo de que la persona
/// la revise (F20, «revisión obligatoria antes»).
///
/// Lo que trae es todo real: [correctSourceCharStart]/
/// [correctSourceCharEnd] son del texto de [correctSourceItemId], no del modelo
/// —`GenerateQuizUseCase.generate` ya descartó cualquier pregunta cuya cita
/// no se pudo anclar—, y [distractors] ya vienen de `DistractorSourcer`, con
/// su propio chunk real cada uno.
class QuizQuestionResult {
  const QuizQuestionResult({
    required this.question,
    required this.correctAnswer,
    required this.correctSourceItemId,
    required this.correctSourceCharStart,
    required this.correctSourceCharEnd,
    required this.distractors,
  });

  final String question;
  final String correctAnswer;

  /// De dónde sale la respuesta correcta: el elemento mismo, o —en un
  /// documento procesado (F41, decisión K)— la fuente de la Biblioteca, en el
  /// pasaje que el procesado copió de ella.
  final String correctSourceItemId;
  final int correctSourceCharStart;
  final int correctSourceCharEnd;

  /// Nunca vacío —`generate` descarta la pregunta si no encontró ningún
  /// distractor real—. Con uno solo, la pregunta queda con dos opciones en
  /// total: el equivalente práctico de verdadero/falso, con la MISMA forma
  /// de tarjeta que una de más opciones (ver el doc comment de `generate`).
  final List<DistractorCandidate> distractors;
}

/// Genera preguntas de quiz de opción múltiple y las guarda, en dos pasos
/// separados a propósito —no es un `UseCase` de una sola llamada—: [generate]
/// solo sugiere, como cualquier generador de este proyecto; [save] es lo que
/// de verdad escribe, y solo debería llamarse con lo que la persona ya
/// confirmó en la pantalla de revisión (F20, commit siguiente). Nunca hay un
/// camino que guarde sin pasar por una revisión.
class GenerateQuizUseCase {
  const GenerateQuizUseCase({
    required LibraryRepository library,
    required FlashcardRepository flashcards,
    required QuizQuestionGenerator generator,
    required DistractorSourcer distractorSourcer,
    required ProcessedRepository processed,
  }) : _library = library,
       _flashcards = flashcards,
       _generator = generator,
       _distractorSourcer = distractorSourcer,
       _processed = processed;

  final LibraryRepository _library;
  final FlashcardRepository _flashcards;
  final QuizQuestionGenerator _generator;
  final DistractorSourcer _distractorSourcer;
  final ProcessedRepository _processed;

  /// Mínimo de distractores reales para que una pregunta se ofrezca: uno
  /// solo alcanza —ver el doc comment de [QuizQuestionResult.distractors]—,
  /// cero no: sin ningún material real con qué armar una opción incorrecta
  /// no hay pregunta de opción múltiple posible, y no se inventa ninguna.
  static const _minDistractors = 1;

  /// Hasta [count] preguntas de [item], cada una ya anclada y con sus
  /// distractores reales. Nunca guarda nada.
  ///
  /// Por pregunta: se descarta si la cita de la respuesta correcta no se
  /// pudo anclar al texto real (`locateQuote`, «mejor ninguno que uno
  /// equivocado», mismo criterio que una tarjeta común) —una opción
  /// correcta sin chunk real rompería el invariante de que NINGUNA opción de
  /// un quiz existe sin uno—; también se descarta si `DistractorSourcer` no
  /// encontró ningún material real para un distractor. Nunca degrada a
  /// `FlashcardKind.trueFalse`: esa forma necesita una afirmación redactada
  /// a mano, no una pregunta con su respuesta —convertir una en la otra
  /// necesitaría inventar el lado falso, exactamente el material que
  /// [DistractorSourcer] ya no encontró—; con un solo distractor real, la
  /// pregunta se ofrece como opción múltiple de dos opciones en vez de un
  /// tipo de tarjeta aparte.
  ///
  /// De un documento procesado (F41, decisión K), el quiz sale del mismo
  /// texto que sus tarjetas (`readProcessedCardText`), y cada respuesta se
  /// ancla en la fuente, en el pasaje que el procesado copió de ella
  /// (`ProcessedCardText.sourceAnchorOf`): lo que la persona escribió o editó
  /// no está en la fuente, así que una pregunta cuya respuesta sale de ahí se
  /// descarta, por la misma regla. Los distractores salen de otros elementos
  /// que no sean esa fuente. Si su texto no se puede leer, se dice: no se cae
  /// al de la fuente.
  Future<Either<Failure, List<QuizQuestionResult>>> generate({
    required KnowledgeItem item,
    int count = 5,
  }) async {
    final read = await readProcessedCardText(_processed, item.id);
    if (read.getLeft().toNullable() case final failure?) return left(failure);
    final processed = read.getRight().toNullable();
    final String? sourceItemId;
    if (processed == null) {
      sourceItemId = item.id;
    } else {
      try {
        sourceItemId = (await _processed.watchDocument(item.id).first)
            ?.summary
            .sourceItemId;
        // La consulta ya registró su fallo (`watchQuery`).
      } on Object {
        return left(
          const Failure.unexpected(message: 'No se pudo leer el documento.'),
        );
      }
    }
    final sourceText = processed != null
        ? processed.content
        : (extractableRendition(item)?.content ?? item.searchableText).trim();
    if (sourceText.trim().isEmpty) {
      return left(
        const Failure.validation(
          message: 'Este elemento no tiene texto del que generar un quiz.',
        ),
      );
    }

    final List<FlashcardDraft> drafts;
    try {
      drafts = await _generator.generateQuizQuestions(
        content: sourceText,
        count: count,
      );
      // El modelo es de terceros (flutter_gemma); puede fallar de formas sin
      // un tipo propio en Dart, mismo criterio que el resto de los
      // generadores de este proyecto.
      // ignore: avoid_catches_without_on_clauses
    } catch (e) {
      return left(Failure.unexpected(message: e.toString()));
    }

    final results = <QuizQuestionResult>[];
    for (final draft in drafts) {
      final located = locateQuote(sourceText, draft.quote);
      if (located == null || sourceItemId == null) continue;
      final range = processed == null
          ? (start: located.start, end: located.end)
          : switch (processed.sourceAnchorOf(located.start, located.end)) {
              null => null,
              final anchor => (start: anchor.start, end: anchor.end),
            };
      if (range == null) continue;

      final distractors = await _distractorSourcer.sourceDistractors(
        seedItemId: sourceItemId,
        excludeContent: draft.back,
      );
      if (distractors.length < _minDistractors) continue;

      results.add(
        QuizQuestionResult(
          question: draft.front,
          correctAnswer: draft.back,
          correctSourceItemId: sourceItemId,
          correctSourceCharStart: range.start,
          correctSourceCharEnd: range.end,
          distractors: distractors,
        ),
      );
    }
    return right(results);
  }

  /// Guarda [confirmed] —lo que la persona ya revisó y aceptó— para
  /// [itemId], todo en UNA transacción (F20, decisión D): o quedan todas las
  /// preguntas con sus opciones, o ninguna. Distinto del bucle de guardados
  /// sueltos que usa hoy la revisión de tarjetas comunes: acá una falla a
  /// mitad de camino no puede dejar un quiz a medias guardado.
  Future<Either<Failure, List<Flashcard>>> save({
    required String itemId,
    required List<QuizQuestionResult> confirmed,
  }) async {
    if (confirmed.isEmpty) return right(const []);

    try {
      return await _library.runInTransaction<Either<Failure, List<Flashcard>>>(
        () async {
          final saved = <Flashcard>[];
          for (final result in confirmed) {
            final options = [
              FlashcardOptionDraft(
                content: result.correctAnswer,
                isCorrect: true,
                sourceItemId: result.correctSourceItemId,
                sourceCharStart: result.correctSourceCharStart,
                sourceCharEnd: result.correctSourceCharEnd,
              ),
              for (final distractor in result.distractors)
                FlashcardOptionDraft(
                  content: distractor.content,
                  isCorrect: false,
                  sourceItemId: distractor.itemId,
                  sourceCharStart: distractor.sourceCharStart,
                  sourceCharEnd: distractor.sourceCharEnd,
                ),
            ];

            final created = await _flashcards.createMultipleChoice(
              itemId: itemId,
              front: result.question,
              options: options,
            );
            final failure = created.getLeft().toNullable();
            // `runInTransaction` —como cualquier transacción de drift— solo
            // revierte lo ya escrito si el cuerpo LANZA; devolver un
            // `Either.left` sin lanzar termina la función con normalidad y
            // deja committeado lo que ya se había guardado en este bucle,
            // rompiendo el «todo o nada» de la decisión D. `_SaveFailure` es
            // el lanzamiento que fuerza la reversión real; se atrapa afuera
            // de la transacción y se vuelve a convertir en el `Either` de
            // siempre.
            if (failure != null) throw _SaveFailure(failure);
            saved.add(created.getRight().toNullable()!);
          }
          return right(saved);
        },
      );
    } on _SaveFailure catch (e) {
      return left(e.failure);
    }
  }
}

/// Ver el comentario en `GenerateQuizUseCase.save`.
class _SaveFailure implements Exception {
  const _SaveFailure(this.failure);

  final Failure failure;
}
