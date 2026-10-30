import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/features/creations/presentation/explain_in_chat_question.dart';
import 'package:sinapsis/l10n/generated/app_localizations_en.dart';
import 'package:sinapsis/l10n/generated/app_localizations_es.dart';

/// La pregunta de «Explicar» (F43, M15): antes de responder no dice cuál es
/// la correcta; después, por qué es esa y por qué la elegida no; con la
/// fuente, su título y su pasaje.
void main() {
  final es = AppLocalizationsEs();
  final en = AppLocalizationsEn();

  const options = [
    ExplainOption(text: 'Aarón'),
    ExplainOption(text: 'Moisés', correct: true),
    ExplainOption(text: 'Faraón'),
  ];

  List<ExplainOption> choose(Set<int> chosen) => [
    for (final (i, o) in options.indexed)
      ExplainOption(
        text: o.text,
        correct: o.correct,
        chosen: chosen.contains(i),
      ),
  ];

  group('antes de responder', () {
    test('explica la pregunta sin decir cuál es la correcta', () {
      final question = explainInChatQuestion(
        es,
        ExplainSubject(question: '¿Quién guía al pueblo?', options: choose({})),
      );

      expect(
        question,
        '${es.f43S19AskBefore}\n'
        '\n'
        'Pregunta: ¿Quién guía al pueblo?\n'
        'Opciones:\n'
        'A. Aarón\n'
        'B. Moisés\n'
        'C. Faraón',
      );
    });

    test('aunque le llegue la respuesta, no la usa', () {
      final question = explainInChatQuestion(
        es,
        const ExplainSubject(
          question: 'El pueblo llega al monte _____.',
          answer: 'Sinaí',
          typed: 'Horeb',
          typedCorrect: false,
        ),
      );

      expect(question, startsWith(es.f43S19AskBefore));
      expect(question, isNot(contains('Sinaí')));
      expect(question, isNot(contains('Horeb')));
      expect(question, isNot(contains('Respuesta:')));
    });

    test('una tarjeta sin dar vuelta no lleva su dorso', () {
      final question = explainInChatQuestion(
        es,
        const ExplainSubject(question: '¿Qué se abre?', answer: 'El mar.'),
      );
      expect(question, isNot(contains('El mar.')));
    });
  });

  group('después de responder', () {
    test('con la equivocada: por qué la correcta es esa y la elegida no', () {
      final question = explainInChatQuestion(
        es,
        ExplainSubject(
          question: '¿Quién guía al pueblo?',
          options: choose({0}),
          answered: true,
        ),
      );

      expect(
        question.split('\n').first,
        es.f43S19AskChoiceWrong('«A. Aarón»', '«B. Moisés»'),
      );
      expect(question, contains('Opciones:\nA. Aarón\nB. Moisés\nC. Faraón'));
    });

    test('con la correcta: por qué es esa y por qué las otras no', () {
      final question = explainInChatQuestion(
        es,
        ExplainSubject(
          question: '¿Quién guía al pueblo?',
          options: choose({1}),
          answered: true,
        ),
      );
      expect(
        question.split('\n').first,
        es.f43S19AskChoiceRight('«B. Moisés»'),
      );
    });

    test('selección múltiple: todas las elegidas y todas las correctas', () {
      final question = explainInChatQuestion(
        es,
        const ExplainSubject(
          question: '¿Qué pasa en el camino?',
          options: [
            ExplainOption(text: 'El mar se abre', correct: true, chosen: true),
            ExplainOption(text: 'Llueve fuego'),
            ExplainOption(text: 'Llegan al Sinaí', correct: true),
          ],
          answered: true,
        ),
      );
      expect(
        question.split('\n').first,
        es.f43S19AskChoiceWrong(
          '«A. El mar se abre»',
          '«A. El mar se abre» y «C. Llegan al Sinaí»',
        ),
      );
    });

    test('a la vista sin haber elegido: dice la correcta', () {
      final question = explainInChatQuestion(
        es,
        ExplainSubject(
          question: '¿Quién?',
          options: choose({}),
          answered: true,
        ),
      );
      expect(
        question.split('\n').first,
        es.f43S19AskChoiceShown('«B. Moisés»'),
      );
    });

    test('escrita: lo escrito, si estaba bien, y la respuesta', () {
      ExplainSubject typed({bool? correct}) => ExplainSubject(
        question: 'El pueblo llega al monte _____.',
        answer: 'Sinaí',
        typed: 'Horeb',
        typedCorrect: correct,
        answered: true,
      );

      final wrong = explainInChatQuestion(es, typed(correct: false));
      expect(wrong.split('\n').first, es.f43S19AskTypedWrong('«Horeb»'));
      expect(wrong, contains('Respuesta: Sinaí'));
      expect(
        explainInChatQuestion(es, typed(correct: true)).split('\n').first,
        es.f43S19AskTypedRight('«Horeb»'),
      );
      expect(
        explainInChatQuestion(es, typed()).split('\n').first,
        es.f43S19AskTyped('«Horeb»'),
      );
    });

    test('una tarjeta dada vuelta: la pregunta y la respuesta', () {
      final question = explainInChatQuestion(
        es,
        const ExplainSubject(
          question: '¿Qué se abre?',
          answer: 'El mar.',
          answered: true,
        ),
      );
      expect(
        question,
        '${es.f43S19AskCard}\n'
        '\n'
        'Pregunta: ¿Qué se abre?\n'
        'Respuesta: El mar.',
      );
    });
  });

  test('con la fuente: su título y su pasaje, al final', () {
    final question = explainInChatQuestion(
      es,
      const ExplainSubject(
        question: '¿Qué se abre?',
        answer: 'El mar.',
        answered: true,
      ).withSource(title: 'Éxodo', passage: 'Y el mar se abrió.'),
    );
    expect(
      question,
      endsWith(
        'Respuesta: El mar.\n'
        '\n'
        'Fuente: Éxodo\n'
        'Pasaje de la fuente: «Y el mar se abrió.»',
      ),
    );
  });

  test('los saltos de línea de una pregunta no rompen los renglones', () {
    final question = explainInChatQuestion(
      es,
      const ExplainSubject(question: '¿Quién\n  guía?\n'),
    );
    expect(question, endsWith('Pregunta: ¿Quién guía?'));
  });

  test('en inglés, con sus comillas', () {
    final question = explainInChatQuestion(
      en,
      ExplainSubject(question: 'Who?', options: choose({0}), answered: true),
    );
    expect(
      question.split('\n').first,
      en.f43S19AskChoiceWrong('“A. Aarón”', '“B. Moisés”'),
    );
    expect(question, contains('Question: Who?'));
  });

  group('el pasaje', () {
    test('el tramo, en una línea', () {
      expect(
        explainPassage('Una fuente\n\nCon un texto.', 4, 20),
        'fuente Con un t',
      );
    });

    test('fuera del texto, nada', () {
      expect(explainPassage('corto', 10, 20), '');
      expect(explainPassage('corto', 3, 2), '');
      expect(explainPassage('corto', -1, 2), '');
    });

    test('uno largo se corta en una palabra entera, con «…»', () {
      final text = List.filled(400, 'palabra').join(' ');
      final passage = explainPassage(text, 0, text.length);
      expect(passage.length, lessThanOrEqualTo(kExplainPassageChars + 1));
      expect(passage, endsWith('palabra…'));
    });
  });
}
