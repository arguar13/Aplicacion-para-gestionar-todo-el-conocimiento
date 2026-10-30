import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/features/processed/domain/services/text_tidier.dart';
import 'package:sinapsis/features/processed/domain/services/tidy_check.dart';

/// La comprobación de lo que ordenó la IA (F45, decisión B): cada palabra de
/// la extracción, en su orden, y ninguna de más. Lo único que puede cambiar es
/// cómo está escrito el texto —renglones, párrafos, mayúsculas, puntuación,
/// palabras partidas con guion, encabezados y pies repetidos—, nunca lo que
/// dice.
void main() {
  TidyProblem? problemOf(
    String extracted,
    String tidied, {
    TidyMargins margins = TidyMargins.none,
  }) => checkTidiedText(extracted, tidied, margins: margins).problem;

  void faithful(
    String extracted,
    String tidied, {
    TidyMargins margins = TidyMargins.none,
  }) => expect(
    checkTidiedText(extracted, tidied, margins: margins),
    TidyCheck.faithful,
  );

  group('lo que la IA puede arreglar', () {
    test('une los renglones cortados de una columna en un párrafo', () {
      faithful(
        'La república romana\ncayó cuando César\ncruzó el Rubicón.\n'
            'El Senado lo declaró\nenemigo público.',
        'La república romana cayó cuando César cruzó el Rubicón. El Senado '
            'lo declaró enemigo público.',
      );
    });

    test('deja un título solo en su renglón, en otras mayúsculas', () {
      faithful(
        'CAPÍTULO PRIMERO La caída Roma cayó en 476.',
        'Capítulo primero\n\nLa caída\n\nRoma cayó en 476.',
      );
    });

    test('cambia la puntuación y los espacios sin tocar las palabras', () {
      faithful('Roma , cayó ;en 476 .', 'Roma cayó en 476.');
    });

    test('junta una palabra partida con guion al final del renglón', () {
      faithful(
        'El imperio se exten-\ndió por el Medite-\r\nrráneo.',
        'El imperio se extendió por el Mediterráneo.',
      );
    });

    test('o la deja partida como estaba', () {
      faithful('se exten-\ndió', 'se exten-dió');
      faithful('se exten-\ndió', 'se exten- dió');
    });

    test('junta lo partido en más de dos renglones', () {
      faithful('anti-\nconstitucio-\nnalmente', 'anticonstitucionalmente');
    });

    test('el guion blando no cuenta: es invisible', () {
      faithful('Medi\u00ADterráneo', 'Mediterráneo');
    });

    test('un acento escrito aparte es el mismo que el compuesto, y una '
        'ligadura son sus letras', () {
      faithful('Camio\u0301n y n\u0303andu\u0301', 'Camión y ñandú');
      faithful('el \uFB01nal de la \uFB02ota', 'el final de la flota');
    });

    test('saca los números de página sueltos, también sin márgenes', () {
      faithful(
        'Roma cayó.\n12\nLos bárbaros entraron.\n- 13 -\nFin.\nPágina 14 '
            'de 300\nxii',
        'Roma cayó. Los bárbaros entraron. Fin.',
      );
    });

    test('saca un encabezado que se repite en todo el documento', () {
      const extracted =
          'Historia de Roma\nRoma cayó.\nHistoria de Roma\nLos bárbaros '
          'entraron.\nHistoria de Roma\nFin.';
      faithful(
        extracted,
        'Roma cayó. Los bárbaros entraron. Fin.',
        margins: TidyMargins.of(extracted),
      );
    });

    test('y el que lleva el número de página en una punta', () {
      const extracted =
          'Historia de Roma 13\nRoma cayó.\n14 Historia de Roma\nLos '
          'bárbaros entraron.\nHistoria de Roma 15\nFin.';
      faithful(
        extracted,
        'Roma cayó. Los bárbaros entraron. Fin.',
        margins: TidyMargins.of(extracted),
      );
    });

    test('puede sacar unos encabezados y dejar otros', () {
      const extracted =
          'Historia de Roma\nRoma cayó.\nHistoria de Roma\nFin.\n'
          'Historia de Roma';
      faithful(
        extracted,
        'Historia de Roma\n\nRoma cayó. Fin.',
        margins: TidyMargins.of(extracted),
      );
    });

    test('un encabezado que también es parte del texto no se confunde', () {
      // «Roma» es un encabezado y también la primera palabra de una
      // oración: se puede sacar el encabezado y dejar la oración.
      const extracted = 'Roma\nRoma cayó.\nRoma\nRoma resistió.\nRoma\nFin.';
      faithful(
        extracted,
        'Roma cayó. Roma resistió. Fin.',
        margins: TidyMargins.of(extracted),
      );
    });

    test('nada cambia: también es fiel', () {
      faithful('Roma cayó en 476.', 'Roma cayó en 476.');
    });
  });

  group('lo que no se queda', () {
    test('una palabra inventada', () {
      expect(
        problemOf('Roma cayó en 476.', 'Roma cayó finalmente en 476.'),
        TidyProblem.invented,
      );
    });

    test('un comentario antes del texto', () {
      expect(
        problemOf(
          'Roma cayó en 476 tras siglos de crisis.',
          'Aquí está el texto ordenado:\n\nRoma cayó en 476 tras siglos de '
              'crisis.',
        ),
        TidyProblem.invented,
      );
    });

    test('una oración repetida', () {
      expect(
        problemOf('Roma cayó. Fin.', 'Roma cayó. Roma cayó. Fin.'),
        TidyProblem.invented,
      );
    });

    test('una palabra corregida: un acento que no estaba', () {
      expect(
        problemOf('esta es la casa', 'está es la casa'),
        TidyProblem.invented,
      );
    });

    test('la traducción', () {
      expect(
        problemOf(
          'La república romana cayó cuando César cruzó el Rubicón.',
          'The Roman republic fell when Caesar crossed the Rubicon.',
        ),
        TidyProblem.rewritten,
      );
    });

    test('un resumen con palabras propias', () {
      expect(
        problemOf(
          'La república romana cayó cuando César cruzó el Rubicón con sus '
              'legiones y el Senado lo declaró enemigo público.',
          'César terminó con la república.',
        ),
        TidyProblem.invented,
      );
    });

    test('un resumen hecho de oraciones copiadas', () {
      expect(
        problemOf(
          'Roma nació. Roma creció mucho durante siglos. Roma cayó.',
          'Roma nació. Roma cayó.',
        ),
        TidyProblem.missing,
      );
    });

    test('un recorte: le falta el final', () {
      expect(
        problemOf(
          'Roma cayó en 476. Los bárbaros entraron. El imperio terminó.',
          'Roma cayó en 476. Los bárbaros entraron.',
        ),
        TidyProblem.missing,
      );
    });

    test('un recorte en el medio', () {
      expect(
        problemOf('Roma cayó en el año 476.', 'Roma cayó en 476.'),
        TidyProblem.missing,
      );
    });

    test('una respuesta vacía', () {
      expect(problemOf('Roma cayó.', ''), TidyProblem.missing);
      expect(problemOf('Roma cayó.', '   \n'), TidyProblem.missing);
    });

    test('el orden cambiado', () {
      expect(
        problemOf(
          'Primero cayó Roma.\n\nDespués cayó Bizancio.',
          'Después cayó Bizancio.\n\nPrimero cayó Roma.',
        ),
        TidyProblem.reordered,
      );
    });

    test('dos palabras dadas vuelta', () {
      expect(
        problemOf('el gran imperio', 'el imperio gran'),
        TidyProblem.reordered,
      );
    });

    test('una palabra con guion en el medio del renglón no se junta', () {
      // Sin el salto de renglón, el guion es de la palabra: «bien-estar»
      // no es «bienestar».
      expect(
        problemOf('el bien-estar general', 'el bienestar general'),
        TidyProblem.invented,
      );
    });

    test('una palabra partida sin guion no se junta', () {
      expect(
        problemOf('el Medite\nrráneo', 'el Mediterráneo'),
        TidyProblem.invented,
      );
    });

    test('un renglón que se repite pocas veces no es un encabezado', () {
      const extracted = 'Historia de Roma\nRoma cayó.\nHistoria de Roma\nFin.';
      expect(
        problemOf(
          extracted,
          'Roma cayó. Fin.',
          margins: TidyMargins.of(extracted),
        ),
        TidyProblem.missing,
      );
    });

    test('sin los márgenes del documento, un encabezado no se puede sacar', () {
      expect(
        problemOf(
          'Historia de Roma\nRoma cayó.\nHistoria de Roma\nFin.\n'
              'Historia de Roma',
          'Roma cayó. Fin.',
        ),
        TidyProblem.missing,
      );
    });

    test('de un encabezado se saca todo el renglón o nada', () {
      const extracted =
          'Historia de Roma\nRoma cayó.\nHistoria de Roma\nFin.\n'
          'Historia de Roma';
      expect(
        problemOf(
          extracted,
          'de Roma\n\nRoma cayó. Fin.',
          margins: TidyMargins.of(extracted),
        ),
        isNotNull,
      );
    });

    test('los títulos numerados no son encabezados: no se sacan', () {
      const extracted =
          'Capítulo 1\nRoma nació.\nCapítulo 2\nRoma creció.\nCapítulo 3\n'
          'Roma cayó.';
      expect(
        problemOf(
          extracted,
          'Roma nació. Roma creció. Roma cayó.',
          margins: TidyMargins.of(extracted),
        ),
        TidyProblem.missing,
      );
    });

    test('un texto que abriría demasiadas formas de alinearse no se da por '
        'fiel', () {
      const extracted = 'a\na\na\na\na\na\na\na';
      expect(
        checkTidiedText(
          extracted,
          'a a a a',
          margins: TidyMargins.of(extracted),
          maxStates: 5,
        ).isFaithful,
        isFalse,
      );
    });
  });

  group('los márgenes del documento', () {
    test('un renglón que se repite tres veces o más', () {
      final margins = TidyMargins.of(
        'Introducción\nUno.\nIntroducción\nDos.\n  introducción \nTres.',
      );
      expect(margins.contains('Introducción'), isTrue);
      expect(margins.contains('INTRODUCCIÓN  '), isTrue);
      expect(margins.contains('Uno.'), isFalse);
    });

    test('el número de una punta no cuenta, si quedan dos palabras', () {
      final margins = TidyMargins.of(
        'Historia de Roma 1\nx\n2 Historia de Roma\ny\nHistoria de Roma 3',
      );
      expect(margins.contains('Historia de Roma 140'), isTrue);
      expect(margins.contains('Historia de Grecia 3'), isFalse);
    });

    test('un renglón largo nunca es un encabezado', () {
      const long =
          'una dos tres cuatro cinco seis siete ocho nueve diez once doce '
          'trece';
      final margins = TidyMargins.of('$long\n$long\n$long');
      expect(margins.contains(long), isFalse);
    });

    test('vuelven iguales de otro hilo', () {
      final margins = TidyMargins.of(
        'Historia de Roma 1\nx\nHistoria de Roma 2\ny\nHistoria de Roma 3\n'
        'Fin\nFin\nFin',
      );
      final back = TidyMargins.fromLists(margins.toLists());
      expect(back.contains('Historia de Roma 9'), isTrue);
      expect(back.contains('Fin'), isTrue);
      expect(back.contains('Roma cayó.'), isFalse);
    });

    test('los números de página, como se escriben', () {
      for (final line in [
        '12',
        '  - 12 -  ',
        '— 7 —',
        'Página 12 de 300',
        'pág. 5',
        'p. 7',
        '12 / 300',
        'xii',
        '[3]',
      ]) {
        expect(isPageNumberLine(line), isTrue, reason: line);
      }
      for (final line in [
        '',
        '12 de octubre',
        'Capítulo 12',
        'Roma',
        '1789 y 1799',
      ]) {
        expect(isPageNumberLine(line), isFalse, reason: line);
      }
    });
  });

  group('lo que rodea a la respuesta', () {
    test('sin el bloque de código que algunos modelos agregan', () {
      expect(cleanTidyReply('```\nRoma cayó.\n```'), 'Roma cayó.');
      expect(cleanTidyReply('```text\nRoma\n\ncayó.\n```\n'), 'Roma\n\ncayó.');
      expect(cleanTidyReply('  Roma cayó.  \n'), 'Roma cayó.');
    });

    test('lo ordenado conserva los espacios de las puntas del pedazo', () {
      expect(
        withTidiedCore('\n\nRoma\ncayó.\n\n', 'Roma cayó.'),
        '\n\nRoma cayó.\n\n',
      );
      expect(withTidiedCore('Roma cayó. ', 'Roma cayó.'), 'Roma cayó. ');
      expect(withTidiedCore('   ', ''), '   ');
    });

    test(
      'lo que se le da por pedido entra en la ventana con lo que contesta',
      () {
        // Gemma: 2048 tokens para todo.
        final gemma = tidyPartCharBudget(2048);
        expect(gemma, inInclusiveRange(2000, 3000));
        expect(gemma / 3.5 + tidyReplyTokens(gemma) + 320, lessThan(2048));
        // En la nube, una página entera.
        expect(tidyPartCharBudget(1000000), 8000);
      },
    );
  });
}
