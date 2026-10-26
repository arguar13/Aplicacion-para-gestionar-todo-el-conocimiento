import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/features/timeline/domain/services/roman_numerals.dart';

/// Los números romanos de los siglos (F40): solo los canónicos.
void main() {
  group('parseRoman', () {
    test('los canónicos, en mayúscula o minúscula', () {
      const cases = {
        'I': 1,
        'II': 2,
        'III': 3,
        'IV': 4,
        'V': 5,
        'VI': 6,
        'VIII': 8,
        'IX': 9,
        'X': 10,
        'XIV': 14,
        'XIX': 19,
        'XX': 20,
        'XXI': 21,
        'XL': 40,
        'XLIX': 49,
        'L': 50,
        'XC': 90,
        'C': 100,
        'CD': 400,
        'D': 500,
        'CM': 900,
        'M': 1000,
        'MCMXCIV': 1994,
        'MMXXIV': 2024,
        'MMMCMXCIX': 3999,
      };
      cases.forEach((text, value) {
        expect(parseRoman(text), value, reason: text);
        expect(parseRoman(text.toLowerCase()), value, reason: text);
      });
    });

    test('lo que se parece pero no es canónico no se lee', () {
      for (final text in [
        'IIII',
        'VV',
        'VX',
        'IC',
        'IL',
        'XM',
        'MIM',
        'IIX',
        'XXXX',
        'VIIII',
        'LC',
        'DM',
        'CCCC',
        'IXI',
        'IVI',
        'MMMM',
        'XIIII',
      ]) {
        expect(parseRoman(text), isNull, reason: text);
      }
    });

    test('lo que no son romanos no se lee', () {
      for (final text in ['', ' ', 'A', 'XIA', '12', 'X I', 'XIX ', '-X']) {
        expect(parseRoman(text), isNull, reason: '«$text»');
      }
    });
  });

  group('romanOf', () {
    test('escribe los canónicos', () {
      expect(romanOf(1), 'I');
      expect(romanOf(4), 'IV');
      expect(romanOf(9), 'IX');
      expect(romanOf(14), 'XIV');
      expect(romanOf(19), 'XIX');
      expect(romanOf(40), 'XL');
      expect(romanOf(90), 'XC');
      expect(romanOf(400), 'CD');
      expect(romanOf(1994), 'MCMXCIV');
      expect(romanOf(3999), 'MMMCMXCIX');
    });

    test('es el inverso de parseRoman en todo su rango', () {
      for (var n = 1; n < 4000; n++) {
        expect(parseRoman(romanOf(n)), n);
      }
    });

    test('no hay romanos para el cero ni para 4000', () {
      expect(() => romanOf(0), throwsA(isA<AssertionError>()));
      expect(() => romanOf(4000), throwsA(isA<AssertionError>()));
      expect(() => romanOf(-1), throwsA(isA<AssertionError>()));
    });
  });
}
