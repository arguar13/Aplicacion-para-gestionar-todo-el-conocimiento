import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/features/reference/domain/services/bibtex/latex_accents.dart';

void main() {
  group('decodeLatexAccents', () {
    test('la letra sola, sin llaves', () {
      expect(decodeLatexAccents(r"Gonz\'alez"), 'González');
    });

    test('la letra entre llaves', () {
      expect(decodeLatexAccents(r"Gonz\'{a}lez"), 'González');
    });

    test('el comando entero entre llaves', () {
      expect(decodeLatexAccents(r"Gonz{\'a}lez"), 'González');
    });

    test('diéresis, circunflejo y tilde', () {
      expect(decodeLatexAccents(r'M\"uller'), 'Müller');
      expect(decodeLatexAccents(r'\^Ile-de-France'), 'Île-de-France');
      expect(decodeLatexAccents(r'espa\~nol'), 'español');
    });

    test('la cedilla, que solo se escribe entre llaves', () {
      expect(decodeLatexAccents(r'fran\c{c}ais'), 'français');
    });

    test('comandos sin parámetro: ß, æ, ø', () {
      expect(decodeLatexAccents(r'stra\ss e'), 'straße');
      expect(decodeLatexAccents(r'\AE sop'), 'Æsop');
      expect(decodeLatexAccents(r'S\o ren'), 'Søren');
    });

    test('un `~` suelto es el espacio irrompible: se vuelve un espacio', () {
      expect(decodeLatexAccents('Fig.~1'), 'Fig. 1');
    });

    test('los escapes de caracteres especiales', () {
      expect(decodeLatexAccents(r'AT\&T'), 'AT&T');
      expect(decodeLatexAccents(r'50\% de crecimiento'), '50% de crecimiento');
    });

    test('las llaves que protegen mayúsculas se quitan sin dejar rastro', () {
      expect(
        decodeLatexAccents('Fue en {P}arís, no en {L}ondres'),
        'Fue en París, no en Londres',
      );
    });

    test('texto ya en UTF-8 (BibLaTeX, Zotero) pasa sin tocar', () {
      expect(decodeLatexAccents('García Márquez'), 'García Márquez');
    });

    test('sin ningún acento, no cambia nada', () {
      expect(decodeLatexAccents('Plain ASCII Title'), 'Plain ASCII Title');
    });

    test('un comando sin mapeo deja la letra base, sin romper', () {
      expect(decodeLatexAccents(r"\'w"), 'w');
    });
  });
}
