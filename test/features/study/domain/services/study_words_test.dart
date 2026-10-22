import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/features/study/domain/services/study_sentences.dart';
import 'package:sinapsis/features/study/domain/services/study_words.dart';

/// Las palabras de una oración y las palabras clave (F36).
void main() {
  const content =
      'La Revolución socio-económica de l’État cambió todo en 1848.';
  const sentence = StudySentence(0, content.length);

  String wordOf(StudyWord w) => content.substring(w.start, w.end);

  test('las palabras, con sus posiciones y plegadas', () {
    final words = studyWordsIn(content, 0, content.length);
    expect(words.map(wordOf), [
      'La',
      'Revolución',
      'socio-económica',
      'de',
      'l’État',
      'cambió',
      'todo',
      'en',
      '1848',
    ]);
    expect(words[1].folded, 'revolucion');
    expect(words[2].folded, 'socio-economica');
    expect(words[4].folded, "l'etat");
  });

  test('un guion al final no se pega a la palabra', () {
    const text = 'pre- y post-guerra';
    expect(studyWordsIn(text, 0, text.length).map((w) => w.folded), [
      'pre',
      'y',
      'post-guerra',
    ]);
  });

  test('«de», «la», una letra sola no dicen nada; un número sí', () {
    final words = {
      for (final w in studyWordsIn(content, 0, content.length))
        w.folded: w.meaningful,
    };
    expect(words['la'], isFalse);
    expect(words['de'], isFalse);
    expect(words['revolucion'], isTrue);
    expect(words['1848'], isTrue);
  });

  group('las palabras clave que propone la IA', () {
    test('sin mirar mayúsculas ni acentos, en el orden propuesto', () {
      final picked = pickKeywords(content, sentence, ['1848', 'REVOLUCION']);
      expect(picked.map(wordOf), ['1848', 'Revolución']);
    });

    test('una frase cuenta como sus palabras', () {
      final picked = pickKeywords(content, sentence, ['revolución cambió']);
      expect(picked.map(wordOf), ['Revolución', 'cambió']);
    });

    test('lo que no está en la oración y lo que no dice nada se descartan', () {
      final picked = pickKeywords(content, sentence, [
        'guerra',
        'de',
        'la',
        'todo',
      ]);
      expect(picked.map(wordOf), ['todo']);
    });

    test('sin repetir, y hasta 4', () {
      final picked = pickKeywords(content, sentence, [
        'todo',
        'todo',
        'revolución',
        'cambió',
        '1848',
        'socio-económica',
      ]);
      expect(picked.map(wordOf), ['todo', 'Revolución', 'cambió', '1848']);
    });

    test('una palabra repetida en la oración: la primera libre', () {
      const twice = 'Vapor y más vapor.';
      final picked = pickKeywords(twice, const StudySentence(0, 18), [
        'vapor',
        'vapor',
      ]);
      expect(picked.map((w) => w.start), [0, 12]);
    });

    test('solo dentro de la oración', () {
      const text = 'Primera con vapor. Segunda sin nada.';
      final second = splitStudySentences(text, markdown: false)[1];
      expect(pickKeywords(text, second, ['vapor']), isEmpty);
    });
  });

  test('la palabra que se toca', () {
    final word = studyWordAt(content, sentence, content.indexOf('olución'));
    expect(word == null ? null : wordOf(word), 'Revolución');
    expect(studyWordAt(content, sentence, content.indexOf(' todo')), isNull);
  });

  test('cómo se compara un texto suelto', () {
    expect(
      foldStudyWord('  ¡Revolución Industrial!  '),
      'revolucion industrial',
    );
  });
}
