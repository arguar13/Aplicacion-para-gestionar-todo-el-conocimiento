import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/domain/entities/ai_certainty.dart';
import 'package:sinapsis/features/ai_organize/domain/services/map_note_intro.dart';
import 'package:sinapsis/features/ai_organize/domain/services/topic_parent_chooser.dart';

/// Lo que el Atlas de la IA (F27) le pide al modelo y cómo lee lo que
/// contesta: sin modelo, porque lo que puede fallar es el formato de un texto.
void main() {
  group('bajo qué tema va uno suelto', () {
    test('lee el número y la certeza, en la primera línea que entiende', () {
      expect(
        parseTopicParentChoice(
          'Veamos.\nPADRE: 2 | alta\nPADRE: 1 | media',
          candidateCount: 3,
        ),
        const TopicParentChoice(index: 1, certainty: AiCertainty.high),
      );
      expect(
        parseTopicParentChoice('padre: 3', candidateCount: 3),
        const TopicParentChoice(index: 2),
      );
    });

    test('«ninguno», un número fuera de la lista o nada legible no eligen '
        'ninguno: nunca se adivina', () {
      for (final raw in [
        'PADRE: ninguno',
        'PADRE: 4 | alta',
        'PADRE: 0 | alta',
        'Creo que el segundo.',
        '',
      ]) {
        expect(
          parseTopicParentChoice(raw, candidateCount: 3),
          isNull,
          reason: raw,
        );
      }
    });
  });

  group('la introducción de una nota mapa', () {
    test('el pedido lleva el tema y cada elemento con su fragmento, y nunca '
        'pasa del tope', () {
      final entries = [
        for (var i = 0; i < 200; i++)
          MapIntroEntry(title: 'Elemento $i', excerpt: 'palabra ' * 100),
      ];

      final prompt = buildMapIntroPrompt(topic: 'Roma', entries: entries);

      expect(prompt, startsWith('Tema: Roma\n\nElementos:\n- Elemento 0: '));
      expect(prompt.length, lessThanOrEqualTo(kMapIntroPromptChars));
      // Cada fragmento, cortado en una palabra entera.
      expect(prompt.split('\n')[3], endsWith('palabra…'));
      expect(
        prompt.split('\n')[3].length,
        lessThan(kMapIntroExcerptChars + 20),
      );
    });

    test('un elemento sin texto va solo con su título', () {
      expect(
        buildMapIntroPrompt(
          topic: 'Roma',
          entries: const [MapIntroEntry(title: 'Las\nlegiones')],
        ),
        'Tema: Roma\n\nElementos:\n- Las legiones',
      );
    });

    test('se limpia: sin corchetes ni marcas, en un párrafo', () {
      expect(
        cleanMapIntro('## Intro\n\nEl tema reúne **todo** sobre [[Roma]].\n'),
        'Intro El tema reúne todo sobre Roma.',
      );
      expect(cleanMapIntro('   '), isEmpty);
    });

    test('lo que pasa del tope se corta en la última oración entera', () {
      final long = '${'Una oración corta. ' * 40}Sin final';

      final clean = cleanMapIntro(long, maxChars: 100);

      expect(clean.length, lessThanOrEqualTo(100));
      expect(clean, endsWith('corta.'));
      // Sin ninguna oración entera, en una palabra.
      expect(
        cleanMapIntro('palabra ' * 50, maxChars: 30),
        'palabra palabra palabra…',
      );
    });
  });
}
