import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/domain/entities/content_block.dart';
import 'package:sinapsis/core/domain/services/inline_link_parser.dart';

void main() {
  group('extractInlineLinks', () {
    test('devuelve los títulos como se escribieron, recortados', () {
      final links = extractInlineLinks('Ver [[  Roma antigua ]] y [[Egipto]].');

      expect(links.map((l) => l.title), ['Roma antigua', 'Egipto']);
      expect(links.map((l) => l.normalizedTitle), ['roma antigua', 'egipto']);
    });

    test('el mismo destino escrito distinto cuenta una sola vez', () {
      final links = extractInlineLinks('[[Roma]] y [[roma]] y [[ ROMA ]]');

      expect(links, hasLength(1));
      // Se queda con la primera forma en que apareció.
      expect(links.single.title, 'Roma');
    });

    test('un enlace vacío o de puros espacios no es un enlace', () {
      expect(extractInlineLinks('[[]]'), isEmpty);
      expect(extractInlineLinks('[[   ]]'), isEmpty);
    });

    test('un enlace vacío no se engancha con el siguiente a través de los '
        'cierres', () {
      final links = extractInlineLinks('[[]] y luego [[Roma]]');

      expect(links.map((l) => l.title), ['Roma']);
    });

    test('un corchete suelto dentro del título se conserva', () {
      final links = extractInlineLinks('[[Ley 1] de Indias]]');

      expect(links.single.title, 'Ley 1] de Indias');
    });

    test('un texto sin enlaces no devuelve nada', () {
      expect(extractInlineLinks('nada [entre] corchetes simples'), isEmpty);
    });

    test('no se parte por acentos ni se pliegan: la regla es recorte y '
        'minúsculas', () {
      final links = extractInlineLinks('[[Canción]] y [[Cancion]]');

      expect(links.map((l) => l.normalizedTitle), ['canción', 'cancion']);
    });

    test('un título con caracteres de otro alfabeto se conserva', () {
      final links = extractInlineLinks('[[Москва]]');

      expect(links.single.title, 'Москва');
      expect(links.single.normalizedTitle, 'москва');
    });
  });

  group('extractInlineLinksFromBlocks', () {
    test('junta los enlaces de todos los bloques sin repetir destino', () {
      final links = extractInlineLinksFromBlocks(const [
        ContentBlock.paragraph(text: 'Empieza en [[Roma]].'),
        ContentBlock.bulletItem(text: 'Sigue con [[Egipto]] y [[roma]]'),
        ContentBlock.quote(text: 'Cita: [[Grecia]]'),
      ]);

      expect(links.map((l) => l.title), ['Roma', 'Egipto', 'Grecia']);
    });

    test('sin bloques no hay enlaces', () {
      expect(extractInlineLinksFromBlocks(const []), isEmpty);
    });
  });

  test('normalizeLinkTitle recorta y baja a minúsculas', () {
    expect(normalizeLinkTitle('  Roma ANTIGUA '), 'roma antigua');
  });
}
