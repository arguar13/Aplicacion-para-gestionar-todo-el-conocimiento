import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/domain/services/dedup_fingerprint.dart';

void main() {
  group('normalizeForDedup', () {
    test('mayúsculas, puntuación y espacios de más no cambian el '
        'resultado', () {
      final withFormat = normalizeForDedup('¡Hola, MUNDO!!  ¿Cómo estás?');
      final plain = normalizeForDedup('hola mundo cómo estás');

      expect(withFormat, plain);
    });

    test('colapsa varios espacios seguidos en uno solo', () {
      expect(
        normalizeForDedup('una   frase    con   espacios'),
        'una frase con espacios',
      );
    });

    test('preserva letras acentuadas y la eñe', () {
      expect(normalizeForDedup('Año Difícil'), 'año difícil');
    });

    test('texto vacío normaliza a vacío', () {
      expect(normalizeForDedup(''), '');
    });
  });

  group('contentHashOf', () {
    test('dos textos que normalizan igual dan el mismo hash', () {
      final a = contentHashOf(normalizeForDedup('¡Hola, MUNDO!!'));
      final b = contentHashOf(normalizeForDedup('hola   mundo'));

      expect(a, b);
    });

    test('dos textos distintos dan hashes distintos', () {
      final a = contentHashOf(normalizeForDedup('un texto'));
      final b = contentHashOf(normalizeForDedup('otro texto'));

      expect(a, isNot(b));
    });
  });

  group('simhashOf / hammingDistance', () {
    test('dos textos idénticos dan la misma huella, distancia 0', () {
      const text = 'el gato subió al techo y miró las estrellas';
      final a = simhashOf(normalizeForDedup(text));
      final b = simhashOf(normalizeForDedup(text));

      expect(hammingDistance(a, b), 0);
    });

    test('un texto y un recorte claro suyo quedan más cerca entre sí que '
        'de un texto sin relación —el caso "reel recorta video largo"', () {
      const original =
          'el gato subió al techo y miró las estrellas durante toda la '
          'noche mientras el perro dormía tranquilo en el jardín de la '
          'casa vieja cerca del río';
      const clip =
          'el gato subió al techo y miró las estrellas durante toda la '
          'noche mientras el perro dormía tranquilo en el jardín';
      const unrelated =
          'las finanzas públicas del país mejoraron este trimestre '
          'gracias a una reforma fiscal profunda y bien planificada por '
          'el nuevo gobierno electo';

      final originalHash = simhashOf(normalizeForDedup(original));
      final clipHash = simhashOf(normalizeForDedup(clip));
      final unrelatedHash = simhashOf(normalizeForDedup(unrelated));

      final distanceToClip = hammingDistance(originalHash, clipHash);
      final distanceToUnrelated = hammingDistance(originalHash, unrelatedHash);

      expect(distanceToClip, lessThan(distanceToUnrelated));
    });

    test('dos textos sin ninguna relación quedan lejos', () {
      const a = 'el gato subió al techo y miró las estrellas';
      const b = 'las finanzas públicas del país mejoraron este trimestre';

      final distance = hammingDistance(
        simhashOf(normalizeForDedup(a)),
        simhashOf(normalizeForDedup(b)),
      );

      expect(distance, greaterThan(10));
    });

    test('texto vacío no revienta: huella de puros ceros', () {
      final hash = simhashOf('');

      expect(hash, '0' * 16);
    });

    test('menos de tres palabras no revienta —todo el texto es un solo '
        'shingle', () {
      final hash = simhashOf(normalizeForDedup('dos palabras'));

      expect(hash.length, 16);
    });

    test('la huella siempre tiene el largo en hex que corresponde a los '
        'bits pedidos', () {
      final hash = simhashOf(normalizeForDedup('un texto cualquiera'));

      expect(hash.length, 16);
    });
  });
}
