import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/features/creations/infographic/domain/infographic_numbers.dart';

/// Los números tal como los escribe un texto (F43): el material está en
/// castellano —el punto separa los miles—, pero uno en inglés también se
/// entiende.
void main() {
  test('los números de un texto en castellano', () {
    expect(InfographicNumbers.parse('40 %'), 40);
    expect(InfographicNumbers.parse('40 años de travesía'), 40);
    expect(InfographicNumbers.parse('3.000.000'), 3000000);
    expect(InfographicNumbers.parse('1.500 personas'), 1500);
    expect(InfographicNumbers.parse('12,5%'), 12.5);
    expect(InfographicNumbers.parse('1.234,75'), 1234.75);
    expect(InfographicNumbers.parse('3 000 000'), 3000000);
    expect(InfographicNumbers.parse('x2'), 2);
    expect(InfographicNumbers.parse('-7 grados'), -7);
  });

  test('y en inglés', () {
    expect(InfographicNumbers.parse('1,234.5'), 1234.5);
    expect(InfographicNumbers.parse('2.5'), 2.5);
    expect(InfographicNumbers.parse('10,000'), 10000);
  });

  test('un número es un número, y lo que no trae ninguno es null', () {
    expect(InfographicNumbers.parse(7), 7);
    expect(InfographicNumbers.parse(2.25), 2.25);
    expect(InfographicNumbers.parse(double.nan), isNull);
    expect(InfographicNumbers.parse('mucho'), isNull);
    expect(InfographicNumbers.parse(null), isNull);
    expect(InfographicNumbers.parse(true), isNull);
  });

  test('dos números separados por un espacio no se juntan', () {
    expect(InfographicNumbers.parse('1 de cada 10'), 1);
    expect(InfographicNumbers.parse('7 10'), 7);
  });

  test('los porcentajes, entre 0 y 1', () {
    expect(InfographicNumbers.percentOf('40 %'), closeTo(0.4, 1e-9));
    expect(InfographicNumbers.percentOf('12,5%'), closeTo(0.125, 1e-9));
    expect(InfographicNumbers.percentOf('40'), isNull);
    expect(InfographicNumbers.percentOf('140 %'), isNull);
  });

  test('escribir un número como en castellano', () {
    expect(InfographicNumbers.format(3000000), '3.000.000');
    expect(InfographicNumbers.format(12.5), '12,5');
    expect(InfographicNumbers.format(0.25), '0,25');
    expect(InfographicNumbers.format(999), '999');
    expect(InfographicNumbers.format(-1500), '-1.500');
  });
}
