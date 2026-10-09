import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/features/flashcards/domain/services/card_text_search.dart';

void main() {
  group('cardSearchPatterns', () {
    test('sin texto no hay nada que buscar', () {
      expect(cardSearchPatterns(''), isEmpty);
      expect(cardSearchPatterns('   \n\t '), isEmpty);
    });

    test('una palabra es un patrón; dos, dos', () {
      expect(cardSearchPatterns('roma'), hasLength(1));
      expect(cardSearchPatterns('  roma   imperio '), hasLength(2));
    });

    test('cada letra admite sus mayúsculas y sus acentos', () {
      final pattern = cardSearchPatterns('a').single;
      expect(pattern, startsWith('*['));
      for (final form in ['a', 'A', 'á', 'Á', 'à', 'ä', 'â']) {
        expect(pattern, contains(form));
      }
      // «á» busca igual que «a».
      expect(cardSearchPatterns('á'), cardSearchPatterns('a'));
      expect(cardSearchPatterns('ÁLVARO'), cardSearchPatterns('alvaro'));
    });

    test('la ñ no se confunde con la n', () {
      expect(cardSearchPatterns('ñ'), isNot(cardSearchPatterns('n')));
      expect(cardSearchPatterns('ñ').single, contains('Ñ'));
      expect(cardSearchPatterns('n').single, isNot(contains('ñ')));
    });

    test('los comodines de GLOB se escapan', () {
      expect(cardSearchPatterns('*').single, '*[*]*');
      expect(cardSearchPatterns('?').single, '*[?]*');
      expect(cardSearchPatterns('[').single, '*[[]*');
    });

    test('una letra sin variantes se parea con su mayúscula y minúscula', () {
      expect(cardSearchPatterns('z').single, '*[zZ]*');
      expect(cardSearchPatterns('7').single, '*7*');
    });

    test('toma como mucho $kMaxSearchTerms palabras', () {
      final many = List.generate(20, (n) => 'p$n').join(' ');
      expect(cardSearchPatterns(many), hasLength(kMaxSearchTerms));
    });
  });
}
