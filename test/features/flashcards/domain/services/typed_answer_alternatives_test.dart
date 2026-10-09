import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/features/flashcards/domain/services/cloze.dart';
import 'package:sinapsis/features/flashcards/domain/services/cloze_generator.dart';
import 'package:sinapsis/features/flashcards/domain/services/typed_answer.dart';
import 'package:sinapsis/features/flashcards/domain/services/typed_answer_alternatives.dart';

class _FakeClozes implements ClozeGenerator {
  _FakeClozes(this.drafts);

  final List<ClozeDraft> drafts;
  String? lastContent;
  int? lastCount;

  @override
  Future<List<ClozeDraft>> generateClozes({
    required String content,
    int count = 5,
  }) async {
    lastContent = content;
    lastCount = count;
    return drafts;
  }
}

void main() {
  group('TypedAnswerSpec', () {
    test('una sola línea es la respuesta, sin alternativas', () {
      final spec = TypedAnswerSpec.parse('Roma');
      expect(spec.answer, 'Roma');
      expect(spec.alternatives, isEmpty);
      expect(spec.encoded, 'Roma');
    });

    test('la primera línea es la respuesta y el resto, alternativas', () {
      final spec = TypedAnswerSpec.parse('Roma\nRoma antigua\n  La Urbe  ');
      expect(spec.answer, 'Roma');
      expect(spec.alternatives, ['Roma antigua', 'La Urbe']);
      expect(spec.encoded, 'Roma\nRoma antigua\nLa Urbe');
    });

    test('ignora renglones vacíos y los saltos de línea de Windows', () {
      final spec = TypedAnswerSpec.parse('\r\nRoma\r\n\r\nUrbe\r\n');
      expect(spec.answer, 'Roma');
      expect(spec.alternatives, ['Urbe']);
    });

    test('una alternativa que repite la respuesta o a otra se descarta', () {
      final spec = TypedAnswerSpec.of('Roma', const [
        'roma',
        'Urbe',
        'URBE',
        '  ',
      ]);
      expect(spec.alternatives, ['Urbe']);
    });

    test('un texto vacío es una respuesta vacía', () {
      expect(TypedAnswerSpec.parse('  \n ').answer, '');
      expect(TypedAnswerSpec.parse('').alternatives, isEmpty);
    });

    test('se puede comparar con las alternativas ya separadas', () {
      final spec = TypedAnswerSpec.parse('Roma\nRoma antigua');
      final result = compareTypedAnswer(
        typed: 'roma antigua',
        correct: spec.answer,
        alternatives: spec.alternatives,
      );
      expect(result.verdict, TypedAnswerVerdict.match);
    });
  });

  group('ClozeAsFlashcardGenerator', () {
    test(
      'la frase con huecos va en el frente, vacío el dorso, y la cita',
      () async {
        final fake = _FakeClozes(const [
          ClozeDraft(text: 'El {{c1::Imperio}} cayó', quote: 'El Imperio cayó'),
          ClozeDraft(text: 'Sin cita {{c1::x}}'),
        ]);
        final drafts = await ClozeAsFlashcardGenerator(
          fake,
        ).generate(content: 'texto', count: 3);

        expect(fake.lastContent, 'texto');
        expect(fake.lastCount, 3);
        expect(drafts, hasLength(2));
        expect(drafts[0].front, 'El {{c1::Imperio}} cayó');
        expect(drafts[0].back, isEmpty);
        expect(drafts[0].quote, 'El Imperio cayó');
        expect(drafts[1].quote, isNull);
      },
    );
  });
}
