import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/features/vault/domain/entities/pin_policy.dart';

void main() {
  group('isValid', () {
    test('rechaza una clave más corta que el mínimo', () {
      expect(PinPolicy.isValid('12345'), isFalse);
      expect(PinPolicy.isValid(''), isFalse);
    });

    test('acepta una clave de exactamente el mínimo', () {
      expect(PinPolicy.isValid('1' * PinPolicy.minLength), isTrue);
    });

    test('acepta una frase larga: más entropía, no menos', () {
      // El campo ofrece teclado numérico, pero nada obliga a usar solo
      // dígitos — y quien quiera una frase como clave debería poder.
      expect(PinPolicy.isValid('mi frase secreta bien larga'), isTrue);
    });

    test('rechaza algo absurdamente largo: un pegado accidental no debería '
        'terminar derivándose', () {
      expect(PinPolicy.isValid('x' * (PinPolicy.maxLength + 1)), isFalse);
    });
  });

  group('lockoutFor', () {
    test('la primera tanda impone la espera más corta', () {
      expect(PinPolicy.lockoutFor(0), PinPolicy.lockoutDurations.first);
    });

    test('las esperas crecen tanda a tanda', () {
      for (var i = 1; i < PinPolicy.lockoutDurations.length; i++) {
        expect(
          PinPolicy.lockoutFor(i),
          greaterThan(PinPolicy.lockoutFor(i - 1)),
        );
      }
    });

    test('se estanca en la más larga en vez de crecer sin fin', () {
      expect(
        PinPolicy.lockoutFor(PinPolicy.lockoutDurations.length),
        PinPolicy.lockoutDurations.last,
      );
      expect(PinPolicy.lockoutFor(1000), PinPolicy.lockoutDurations.last);
    });

    test('edge case: una tanda negativa no impone espera alguna', () {
      expect(PinPolicy.lockoutFor(-1), Duration.zero);
    });
  });
}
