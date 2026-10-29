import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/features/creations/flashcards/domain/flashcard_deck.dart';
import 'package:sinapsis/features/creations/flashcards/presentation/export/flashcard_deck_export.dart';
import 'package:sinapsis/features/creations/quiz/domain/quiz.dart';
import 'package:sinapsis/features/creations/quiz/presentation/export/quiz_export.dart';

const _deck = FlashcardDeck(
  title: 'Éxodo',
  cards: [
    DeckCard(
      id: 'c1',
      front: '¿Quién guía, «al pueblo»?',
      back: 'Moisés,\nel profeta.',
      hint: 'Empieza con M',
      flashcardId: 'f1',
    ),
    DeckCard(id: 'c2', front: '¿Qué se abre?', back: 'El mar\tRojo.'),
  ],
);

final _deckLabels = DeckExportLabels(
  question: 'Pregunta',
  answer: 'Respuesta',
  hint: (h) => 'Pista: $h',
  subtitle: (n) => '$n tarjetas',
  page: (p, n) => 'Página $p de $n',
);

const _quiz = Quiz(
  title: 'Éxodo',
  questions: [
    QuizQuestion(
      id: 'q1',
      type: QuizQuestionType.multiple,
      prompt: '¿Qué pasa?',
      options: [
        QuizOption(text: 'El mar se abre', correct: true, explanation: 'Sí.'),
        QuizOption(text: 'Llueve fuego', correct: false, explanation: 'No.'),
        QuizOption(text: 'Llegan al Sinaí', correct: true),
      ],
      explanation: 'Dos cosas.',
    ),
    QuizQuestion(
      id: 'q2',
      type: QuizQuestionType.fillBlank,
      prompt: 'Llegan al $kQuizBlank.',
      answer: 'Sinaí',
      alternatives: ['Horeb'],
    ),
  ],
);

final _quizLabels = QuizExportLabels(
  count: (n) => '$n preguntas',
  answers: 'Respuestas',
  allThatApply: '(todas las que correspondan)',
  why: 'Por qué',
  type: (t) => t.storageKey,
  page: (p, n) => 'Página $p de $n',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('el mazo', () {
    test('para Anki: el archivo de texto de siempre, con su mazo y sin '
        'romper filas', () {
      final text = utf8.decode(
        flashcardDeckAnkiText(
          _deck,
          title: 'Éxodo::Libro',
          createdAt: DateTime.utc(2026),
        ),
      );
      final lines = text.split('\n');
      expect(lines.first, '#separator:Tab');
      expect(lines, contains('#deck column:3'));
      expect(lines, hasLength(4 + 2));
      expect(
        lines[4],
        '¿Quién guía, «al pueblo»?\tMoisés,<br>el profeta.<br><br>Empieza '
        'con M\tSinapsis::Estudiar::Éxodo:Libro',
      );
      expect(lines[5], startsWith('¿Qué se abre?\tEl mar Rojo.\t'));
    });

    test('en Markdown: cada pregunta con su respuesta y su pista', () {
      final md = flashcardDeckMarkdown(
        _deck,
        title: 'Éxodo',
        labels: _deckLabels,
      );
      expect(md, startsWith('# Éxodo\n\n2 tarjetas'));
      expect(md, contains('## 1. ¿Quién guía, «al pueblo»?\n\nMoisés,'));
      expect(md, contains('> Pista: Empieza con M'));
      expect(md, contains('## 2. ¿Qué se abre?'));
    });

    test('en PDF, con la letra de la app', () async {
      final file = await flashcardDeckFile(
        _deck,
        format: DeckExportFormat.pdf,
        title: 'Éxodo / 1',
        labels: _deckLabels,
        createdAt: DateTime.utc(2026),
      );
      expect(file.fileName, endsWith('.pdf'));
      expect(file.fileName, isNot(contains('/')));
      expect(file.mimeType, 'application/pdf');
      expect(ascii.decode(file.bytes.sublist(0, 5)), '%PDF-');
      // La letra de la app viaja dentro del PDF: con la de fábrica, las
      // comillas latinas no se verían.
      expect(latin1.decode(file.bytes), contains('Inter'));
    });

    test('sin la letra, el PDF sale igual con la de fábrica', () async {
      final bytes = await flashcardDeckPdf(
        const FlashcardDeck(
          title: 'Plain',
          cards: [DeckCard(id: 'c1', front: 'Q', back: 'A')],
        ),
        title: 'Plain',
        labels: _deckLabels,
        bundle: _EmptyBundle(),
      );
      expect(ascii.decode(bytes.sublist(0, 5)), '%PDF-');
    });

    test('cada formato con su nombre y su tipo', () async {
      for (final (format, extension, mime) in [
        (DeckExportFormat.anki, 'tsv', 'text/tab-separated-values'),
        (DeckExportFormat.markdown, 'md', 'text/markdown'),
      ]) {
        final file = await flashcardDeckFile(
          _deck,
          format: format,
          title: 'Éxodo',
          labels: _deckLabels,
          createdAt: DateTime.utc(2026),
        );
        expect(file.fileName, 'Éxodo.$extension');
        expect(file.mimeType, mime);
      }
    });
  });

  group('el cuestionario', () {
    test('en Markdown: las preguntas con A–D y, al final, las respuestas con '
        'la explicación de cada opción', () {
      final md = quizMarkdown(_quiz, title: 'Éxodo', labels: _quizLabels);
      expect(md, contains('## 1. ¿Qué pasa? (todas las que correspondan)'));
      expect(md, contains('- A. El mar se abre'));
      expect(md, contains('- C. Llegan al Sinaí'));
      expect(md, contains('## 2. Llegan al ________.'));
      final answers = md.substring(md.indexOf('## Respuestas'));
      expect(
        answers,
        contains('**1.** A. El mar se abre · C. Llegan al Sinaí'),
      );
      expect(answers, contains('✓ A: Sí.'));
      expect(answers, contains('✗ B: No.'));
      expect(answers, contains('Por qué: Dos cosas.'));
      expect(answers, contains('**2.** Sinaí'));
      expect(answers, contains('  - Horeb'));
    });

    test('en PDF', () async {
      final file = await quizFile(
        _quiz,
        format: QuizExportFormat.pdf,
        title: 'Éxodo',
        labels: _quizLabels,
      );
      expect(file.fileName, 'Éxodo.pdf');
      expect(ascii.decode(file.bytes.sublist(0, 5)), '%PDF-');
    });
  });
}

class _EmptyBundle extends CachingAssetBundle {
  @override
  Future<ByteData> load(String key) =>
      Future.error(FlutterError('No está: $key'));
}
