import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/features/study/domain/services/study_fallback_keywords.dart';
import 'package:sinapsis/features/study/domain/services/study_sentences.dart';
import 'package:sinapsis/features/study/domain/services/study_words.dart';

/// El respaldo local de las palabras clave: que **toda** oración con contenido
/// tenga las suyas, sin IA.
void main() {
  // El comienzo de un libro de Project Gutenberg y su índice, como los
  // reportó el dueño: las oraciones de la licencia, que el modelo salteaba, y
  // las líneas del índice, sin punto final.
  const gutenberg = '''
The Project Gutenberg eBook of Don Quijote

This eBook is for the use of anyone anywhere in the United States and most other parts of the world at no cost and with almost no restrictions whatsoever. You may copy it, give it away or re-use it under the terms of the Project Gutenberg License included with this eBook or online at www.gutenberg.org. If you are not located in the United States, you will have to check the laws of the country where you are located before using this eBook.

## ÍNDICE

1. Que trata de la condición y ejercicio del famoso hidalgo D. Quijote de la Mancha
2. Que trata de la primera salida que de su tierra hizo el ingenioso Don Quijote
3. Donde se cuenta la graciosa manera que tuvo don Quijote en armarse caballero
''';

  List<StudySentence> split(String content) =>
      splitStudySentences(content, markdown: true);

  List<String> keywordsOf(String content, StudySentence sentence) {
    final stats = StudyWordStats.of(content);
    return [
      for (final w in fallbackKeywordsFor(content, sentence, stats))
        content.substring(w.start, w.end),
    ];
  }

  String textOf(String content, StudySentence s) =>
      content.substring(s.start, s.end);

  group('la oración con contenido', () {
    test('toda oración con una palabra que dice algo tiene al menos una y '
        'hasta cuatro, y son palabras de la oración, en su lugar', () {
      final stats = StudyWordStats.of(gutenberg);
      final sentences = split(gutenberg);
      expect(sentences.length, 8);

      for (final sentence in sentences) {
        final words = fallbackKeywordsFor(gutenberg, sentence, stats);
        expect(words, isNotEmpty, reason: textOf(gutenberg, sentence));
        expect(words.length, lessThanOrEqualTo(kMaxKeywordsPerSentence));
        for (final word in words) {
          expect(word.start, greaterThanOrEqualTo(sentence.start));
          expect(word.end, lessThanOrEqualTo(sentence.end));
          expect(word.meaningful, isTrue);
          // La palabra es la del texto, no una versión plegada.
          expect(
            foldStudyWord(gutenberg.substring(word.start, word.end)),
            word.folded,
          );
        }
        // En el orden del texto, sin repetir lugar.
        expect(
          words.map((w) => w.start).toList(),
          orderedEquals([...words.map((w) => w.start)]..sort()),
        );
        expect(words.map((w) => w.start).toSet().length, words.length);
      }
    });

    test('elige lo que dice algo y no las palabras vacías de castellano ni '
        'de inglés', () {
      final license = split(gutenberg)[2]; // «You may copy it, …»
      final picked = keywordsOf(gutenberg, license);
      const empty = {'You', 'may', 'it', 'or', 'the', 'with', 'this', 'at'};
      expect(picked.where(empty.contains), isEmpty, reason: '$picked');
      expect(picked, isNotEmpty);

      final item = split(gutenberg).last;
      final words = keywordsOf(gutenberg, item);
      expect(
        words.where(const {'Donde', 'se', 'que', 'en', 'la'}.contains),
        isEmpty,
      );
    });

    test('prefiere lo raro del documento a lo que está en todas partes', () {
      const content =
          'El vapor movía el telar. El vapor movía la fábrica. '
          'El vapor movía el tren. El vapor movía el barco con sus calderas.';
      // «calderas» aparece una sola vez: es lo que distingue a la última.
      final last = split(content).last;
      expect(keywordsOf(content, last), contains('calderas'));
    });

    test('un nombre propio en medio de la oración le gana a una palabra '
        'común de la misma largura', () {
      // Tres palabras con algo para decir: se elige una, y «conversamos» es
      // más larga.
      const content = 'Ayer conversamos con Cervantes.';
      expect(keywordsOf(content, split(content).single), ['Cervantes']);
    });

    test('las oraciones largas llevan más palabras que las cortas', () {
      const short = 'Llueve fuerte.';
      const long =
          'Las fábricas textiles inglesas adoptaron rápidamente máquinas '
          'hiladoras, telares mecánicos, locomotoras, canales, minas profundas '
          'y puertos enormes durante aquellas décadas turbulentas.';
      expect(keywordsOf(short, split(short).single).length, 1);
      expect(
        keywordsOf(long, split(long).single).length,
        kMaxKeywordsPerSentence,
      );
    });

    test('los números y los romanos son el último recurso', () {
      const content = 'Capítulo II\n\nEn 1492 llegaron.\n\nXIV 1492';
      final sentences = split(content);
      expect(keywordsOf(content, sentences[0]), ['Capítulo']);
      expect(keywordsOf(content, sentences[1]), ['llegaron']);
      // Sin otra cosa, un número o un romano igual cuenta: hay que marcar algo.
      expect(keywordsOf(content, sentences[2]), isNotEmpty);
    });

    test('si solo tiene palabras vacías que el programa deja pasar, igual '
        'marca una', () {
      const content = 'You may.';
      expect(keywordsOf(content, split(content).single), hasLength(1));
    });

    test('una oración de artículos y preposiciones no tiene contenido: no '
        'se le inventa nada', () {
      const content = 'Es de él.';
      expect(keywordsOf(content, split(content).single), isEmpty);
    });

    test('la mayúscula con que empieza la oración no hace nombre propio', () {
      const content = 'Pasamos conversando largamente.';
      expect(keywordsOf(content, split(content).single), ['conversando']);
    });

    test('una palabra repetida en la oración cuenta una vez', () {
      const content =
          'telar telar telar fábrica fábrica fábrica vapor vapor vapor molino.';
      final picked = keywordsOf(content, split(content).single);
      expect(picked.toSet().length, picked.length, reason: '$picked');
      expect(picked, hasLength(2));
    });

    test('un número no le gana a una palabra, aunque sea lo más raro del '
        'documento', () {
      const content = 'Sol luz sol luz sol luz sol luz. Sol luz 1492.';
      expect(keywordsOf(content, split(content).last), isNot(contains('1492')));
    });

    test('lo raro del documento le gana a lo largo pero común', () {
      const content =
          'Maquinarias maquinarias maquinarias maquinarias maquinarias '
          'funcionaban. Zinc maquinarias.';
      expect(keywordsOf(content, split(content).last), ['Zinc']);
    });

    test('una palabra vacía, aunque sea larga y única, no le gana a una '
        'común del tema', () {
      const content = 'sol sol sol sol sol. Whatsoever sol.';
      expect(keywordsOf(content, split(content).last), ['sol']);
    });

    test('los números no inflan cuántas palabras se eligen', () {
      const content = 'Sol 1492 1493 1494 1495 1496.';
      expect(keywordsOf(content, split(content).single), ['Sol']);
    });

    test('a igual puntaje, la que está primero en la oración', () {
      const content = 'casa mesa luna.';
      expect(keywordsOf(content, split(content).single), ['casa']);
    });

    test('es determinista: la misma oración da siempre las mismas', () {
      final sentence = split(gutenberg)[1];
      expect(keywordsOf(gutenberg, sentence), keywordsOf(gutenberg, sentence));
    });

    test('las acentuadas y las mayúsculas se pliegan: «Él» y «ÍNDICE»', () {
      const content = 'ÍNDICE';
      expect(keywordsOf(content, split(content).single), ['ÍNDICE']);
    });
  });

  group('lo que falta', () {
    test('solo las oraciones sin ninguna palabra clave reciben las suyas', () {
      final sentences = split(gutenberg);
      final stats = StudyWordStats.of(gutenberg);
      // La licencia ya tiene sus cuatro del modelo; lo demás, no.
      final model = [
        (
          gutenberg.indexOf('eBook is'),
          gutenberg.indexOf('eBook is') + 'eBook'.length,
        ),
        (
          gutenberg.indexOf('United States and'),
          gutenberg.indexOf('United States and') + 'United'.length,
        ),
      ];

      final filled = missingKeywords(
        content: gutenberg,
        sentences: sentences,
        keywordRanges: model,
        stats: stats,
      );

      final covered = sentences[1];
      expect(
        filled.where((w) => w.start >= covered.start && w.end <= covered.end),
        isEmpty,
        reason: 'la oración del modelo no se toca',
      );
      for (final sentence in sentences) {
        final has =
            filled.any(
              (w) => w.start >= sentence.start && w.end <= sentence.end,
            ) ||
            model.any((r) => r.$1 >= sentence.start && r.$2 <= sentence.end);
        expect(has, isTrue, reason: textOf(gutenberg, sentence));
      }
    });

    test('una palabra clave de la oración de al lado no la cubre', () {
      const content = 'Primera oración larga. Segunda oración larga.';
      final sentences = split(content);
      const first = (0, 7);
      final filled = missingKeywords(
        content: content,
        sentences: sentences,
        keywordRanges: [first],
        stats: StudyWordStats.of(content),
      );
      expect(filled, isNotEmpty);
      expect(filled.every((w) => w.start >= sentences[1].start), isTrue);
    });

    test('una palabra que cruza el borde de la oración no la cubre', () {
      const content = 'Primera oración larga. Segunda oración larga.';
      final sentences = split(content);
      final filled = missingKeywords(
        content: content,
        sentences: sentences,
        keywordRanges: [(sentences[0].end - 3, sentences[1].start + 3)],
        stats: StudyWordStats.of(content),
      );
      // Ni la de una ni la de la otra: las dos reciben las suyas.
      expect(filled.any((w) => w.end <= sentences[0].end), isTrue);
      expect(filled.any((w) => w.start >= sentences[1].start), isTrue);
    });

    test('con todas cubiertas no agrega nada, y el orden de los rangos '
        'da igual', () {
      const content = 'Primera oración larga. Segunda oración larga.';
      final sentences = split(content);
      final filled = missingKeywords(
        content: content,
        sentences: sentences,
        keywordRanges: [
          (sentences[1].start, sentences[1].start + 3),
          (sentences[0].start, sentences[0].start + 3),
        ],
        stats: StudyWordStats.of(content),
      );
      expect(filled, isEmpty);
    });
  });

  test('un libro entero: ninguna oración con contenido queda sin palabras', () {
    final buffer = StringBuffer('# Libro\n\n');
    const topics = ['vapor', 'telar', 'Inglaterra', 'canales', 'locomotora'];
    for (var i = 0; i < 400; i++) {
      final topic = topics[i % topics.length];
      buffer
        ..writeln(
          'En el capítulo $i, ${topics[(i + 2) % 5]} y $topic aparecen junto '
          'a la vieja ciudad. Luego, nadie pudo decir si el $topic era '
          'realmente tan importante como se creía.',
        )
        ..writeln()
        ..writeln('Capítulo $i')
        ..writeln('Que trata de ${topics[(i + 1) % 5]} y de la ciudad')
        ..writeln();
    }
    final content = buffer.toString();
    final sentences = split(content);
    final stats = StudyWordStats.of(content);

    final filled = missingKeywords(
      content: content,
      sentences: sentences,
      keywordRanges: const [],
      stats: stats,
    );

    var withContent = 0;
    for (final sentence in sentences) {
      final words = studyWordsIn(content, sentence.start, sentence.end);
      final inside = filled
          .where((w) => w.start >= sentence.start && w.end <= sentence.end)
          .length;
      if (words.any((w) => w.meaningful)) {
        withContent++;
        expect(inside, inInclusiveRange(1, kMaxKeywordsPerSentence));
      }
    }
    expect(withContent, greaterThan(1000));
  });
}
