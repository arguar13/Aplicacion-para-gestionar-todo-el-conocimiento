import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/util/markdown_lead.dart';
import 'package:sinapsis/core/util/markdown_plain_text.dart';

import '../../support/wikipedia_fixtures.dart';

/// Dónde empieza la prosa de un texto (F46, paso 5j, decisión 5b): pasada la
/// ficha con que abre un artículo de Wikipedia.
void main() {
  /// Lo que se lee desde donde empieza la prosa, en un renglón.
  String leadOf(String markdown) => markdownPlainText(
    markdown.substring(markdownLeadStart(markdown)),
  ).split('\n').first;

  /// Un párrafo de prosa: más de doce palabras, terminado en punto.
  const prose =
      'La ciudad creció junto al río durante siglos y llegó a dominar todo '
      'el comercio de la región.';
  const prose2 =
      'Sus murallas se levantaron en el siglo tercero y todavía hoy se '
      'pueden recorrer a pie.';

  group('con el texto real de Wikipedia', () {
    test('Platón: empieza por el primer párrafo, no por la ficha', () {
      final text = wikipediaMarkdown('platon', 'Plat%C3%B3n');
      // La ficha está en el texto, y es lo primero.
      expect(text, startsWith('Platón'));
      expect(text, contains('Nacimiento'));

      expect(leadOf(text), startsWith('Platón (en griego'));
      expect(leadOf(text), contains('filósofo griego'));
    });

    test('Imperio romano —la ficha de un Estado, como la de República '
        'romana—: empieza por «El Imperio romano fue…»', () {
      final text = File(
        'test/fixtures/web/wikipedia_imperio_romano_inicio.md',
      ).readAsStringSync();
      expect(text, startsWith('Imperio romano\nRēs pūblica'));

      expect(leadOf(text), startsWith('El Imperio romano fue el periodo'));
    });

    test('Fotosíntesis, sin ficha: queda igual', () {
      final text = File(
        'test/fixtures/web/wikipedia_fotosintesis_parrafo.md',
      ).readAsStringSync();

      expect(markdownLeadStart(text), 0);
    });
  });

  group('la ficha', () {
    test('las filas que se vieron en la tarjeta de República romana se '
        'saltean', () {
      const text =
          'República romana\nRes Publica Romana\n\nEstado de la antigüedad\n\n'
          '509-27 a. C.\n\n[![Escudo](https://x.org/e.png)](https://x.org/e)\n\n'
          'Escudo\n\nCapital\n\nRoma\n\n'
          'La **República romana** fue el periodo de la antigua civilización '
          'romana en el que el gobierno fue una república.\n\n$prose';

      expect(leadOf(text), startsWith('La República romana fue el periodo'));
    });

    test('con tres renglones cortos ya es una ficha; con dos, no', () {
      expect(
        markdownLeadStart('Uno\n\nDos\n\nTres\n\n$prose\n\n$prose2'),
        'Uno\n\nDos\n\nTres\n\n'.length,
      );
      expect(markdownLeadStart('Por Ana\n\n5 de mayo\n\n$prose\n\n$prose2'), 0);
    });

    test('el pie de la foto de la ficha es una oración, pero lo sigue la '
        'ficha: no es el primer párrafo', () {
      const text =
          'Agustín\n\n![](https://x.org/a.jpg)\n\n'
          'Retrato más antiguo conocido de san Agustín, pintado al fresco en '
          'el siglo sexto en Roma.\n\n* * *\n\nNacimiento\n\n354\n\n'
          'Fallecimiento\n\n430\n\n$prose\n\n$prose2';

      expect(leadOf(text), prose);
    });

    test('el primer párrafo puede seguir con un título, una lista o nada', () {
      for (final after in ['## Historia', '- un elemento', '| a | b |', '']) {
        final text = 'A\n\nB\n\nC\n\n$prose\n\n$after';
        expect(leadOf(text), prose, reason: after);
      }
    });

    test('una foto sin texto o una raya, entre medio, no cuentan', () {
      const text =
          'A\n\n![](https://x.org/f.png)\n\nB\n\n* * *\n\nC\n\n$prose\n\n'
          '![](https://x.org/g.png)\n\n$prose2';

      expect(leadOf(text), prose);
      expect(markdownLeadStart('![](x.png)\n\n* * *\n\n$prose'), 0);
    });

    test('las listas, las tablas y los títulos no son renglones de ficha', () {
      expect(
        markdownLeadStart(
          '# Receta\n\n- harina\n- agua\n\n| a | b |\n| --- | --- |\n\n'
          'Corta\n\n$prose\n\n$prose2',
        ),
        0,
      );
      // Una lista adentro de la ficha —«Cónyuge: Jantipa, Myrto», en la de
      // Sócrates— tampoco es el primer párrafo.
      expect(
        leadOf('A\n\nB\n\nCónyuge\n\n- Jantipa\n- Myrto\n\n$prose\n\n$prose2'),
        prose,
      );
    });
  });

  group('qué es una oración de un párrafo', () {
    String withRows(String paragraph) => 'A\n\nB\n\nC\n\n$paragraph\n\n$prose2';

    test('doce palabras y un punto, sí; once, no', () {
      const twelve =
          'Una dos tres cuatro cinco seis siete ocho nueve diez once '
          'doce.';
      const eleven =
          'Una dos tres cuatro cinco seis siete ocho nueve diez '
          'once.';
      expect(leadOf(withRows(twelve)), twelve);
      expect(leadOf(withRows(eleven)), prose2);
    });

    test('termina en punto, en signo de cierre o en puntos suspensivos, '
        'aunque los sigan comillas o un paréntesis', () {
      const start =
          'Una dos tres cuatro cinco seis siete ocho nueve diez '
          'once doce';
      for (final end in ['.', '!', '?', '…', '.»', '.)', '."', '.”']) {
        expect(leadOf(withRows('$start$end')), '$start$end', reason: end);
      }
    });

    test('sin punto al final no lo es, por larga que sea', () {
      const start =
          'Una dos tres cuatro cinco seis siete ocho nueve diez '
          'once doce trece catorce';
      for (final end in [
        '',
        ':',
        ';',
        ',',
        ' (Museo Fitzwilliam)',
        ' (c. 80 años)',
      ]) {
        expect(leadOf(withRows('$start$end')), prose2, reason: end);
      }
    });

    test('las palabras se cuentan como se leen: un enlace es su texto y una '
        'llamada a una nota no cuenta', () {
      // Doce palabras como se leen; crudo, termina en la dirección de la nota.
      const linked =
          '[Una](https://x.org/1) dos tres cuatro cinco seis siete ocho nueve '
          'diez once doce.[[1]](#cite_note-1)';
      expect(
        leadOf(withRows(linked)),
        'Una dos tres cuatro cinco seis siete ocho nueve diez once doce.',
      );
    });
  });

  group('lo que no se toca', () {
    test('un texto que empieza con prosa empieza ahí', () {
      expect(markdownLeadStart('$prose\n\n$prose2'), 0);
      expect(markdownLeadStart('# Título\n\n$prose'), 0);
      expect(markdownLeadStart(''), 0);
    });

    test('sin ningún párrafo de prosa, empieza donde empieza', () {
      expect(markdownLeadStart('A\n\nB\n\nC\n\nD'), 0);
    });

    test('solo se mira el principio: una ficha que no termina en los '
        'primeros bloques no se saltea', () {
      final rows = [for (var i = 0; i < kLeadScanBlocks; i++) 'Fila $i'];
      expect(markdownLeadStart('${rows.join('\n\n')}\n\n$prose'), 0);
      final fewer = rows.take(kLeadScanBlocks - 1).join('\n\n');
      expect(markdownLeadStart('$fewer\n\n$prose'), fewer.length + 2);
    });

    test('ni las primeras letras: un libro no se recorre entero', () {
      final long = 'Fila\n\n' * 3 + 'x' * kLeadScanChars;
      expect(markdownLeadStart('$long\n\n$prose'), 0);
      final book = '${'Una línea de un libro largo.\n' * 200000}fin';
      final watch = Stopwatch()..start();
      markdownLeadStart(book);
      expect(watch.elapsedMilliseconds, lessThan(200));
    });

    test(r'los renglones con \r\n se leen igual', () {
      expect(
        markdownLeadStart('Uno\r\n\r\nDos\r\n\r\nTres\r\n\r\n$prose'),
        'Uno\r\n\r\nDos\r\n\r\nTres\r\n\r\n'.length,
      );
    });
  });
}
