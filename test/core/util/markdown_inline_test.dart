import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/util/markdown_inline.dart';

/// Qué es una construcción en línea y dónde se puede cortar sin partir una
/// (F46, paso 5b).
const _wiki = 'https://es.wikipedia.org/wiki';

void main() {
  group('markdownInlineAt', () {
    const text =
        'la realizan las [bacterias purpúreas]($_wiki/Bacteria) y otras';
    final open = text.indexOf('[');
    final close = text.indexOf(') y') + 1;

    test(
      'un corte adentro de un enlace lo parte: devuelve el enlace entero',
      () {
        final at = text.indexOf(' purpúreas');

        expect(markdownInlineAt(text, at), (start: open, end: close));
        // También adentro de la dirección.
        expect(markdownInlineAt(text, text.indexOf('wiki/')), (
          start: open,
          end: close,
        ));
      },
    );

    test('en los bordes, o afuera, no parte nada', () {
      expect(markdownInlineAt(text, open), isNull);
      expect(markdownInlineAt(text, close), isNull);
      expect(markdownInlineAt(text, 3), isNull);
      expect(markdownInlineAt(text, text.length - 2), isNull);
    });

    test('las demás construcciones también: imagen, énfasis, código, '
        'superíndice, enlace de nota', () {
      for (final construct in [
        '![un puerto al atardecer](https://x.org/a.jpg)',
        '**negrita de varias palabras**',
        '*cursiva de varias palabras*',
        '_cursiva con guion bajo_',
        '`código con espacios`',
        '<sup>[[12]](#cite_note-12)</sup>',
        '[![](https://x.org/a.jpg)](https://x.org/Archivo:a.jpg)',
        '[[Una nota enlazada]]',
      ]) {
        final line = 'antes $construct después';
        final start = line.indexOf(construct);
        final span = (start: start, end: start + construct.length);
        for (var at = start + 1; at < span.end; at++) {
          expect(markdownInlineAt(line, at), span, reason: '$construct en $at');
        }
        expect(markdownInlineAt(line, start), isNull);
        expect(markdownInlineAt(line, span.end), isNull);
      }
    });

    test('un texto sin Markdown no tiene construcciones', () {
      const plain =
          'Una transcripción cualquiera, con 2 * 3 * 4 y var_uno_dos.';
      for (var at = 0; at <= plain.length; at++) {
        expect(markdownInlineAt(plain, at), isNull);
      }
    });

    test('ninguna cruza un renglón: lo que se encuentra en el texto entero es '
        'lo que el lector encuentra renglón por renglón', () {
      final random = Random(46);
      const pieces = [
        'palabra ',
        '[enlace](https://x.org/a) ',
        '[corchete suelto ',
        '](',
        '*',
        '**',
        '_',
        '`',
        '<a href="x">',
        '</a>',
        '<img src="y"\n alt="z">',
        '<sup>',
        '</sup>',
        '\n',
        '\n\n',
        ' ',
        'x',
      ];
      for (var round = 0; round < 300; round++) {
        final buffer = StringBuffer();
        for (var i = random.nextInt(60); i > 0; i--) {
          buffer.write(pieces[random.nextInt(pieces.length)]);
        }
        final whole = buffer.toString();
        final inWhole = [
          for (final m in markdownInlinePattern.allMatches(whole))
            (start: m.start, end: m.end),
        ];
        final byLine = <MarkdownSpan>[];
        var lineStart = 0;
        for (final line in whole.split('\n')) {
          for (final m in markdownInlinePattern.allMatches(line)) {
            byLine.add((start: lineStart + m.start, end: lineStart + m.end));
          }
          lineStart += line.length + 1;
        }
        expect(inWhole, byLine, reason: whole);
      }
    });

    test('se puede buscar desde un corte anterior: encuentra lo mismo que '
        'desde el comienzo', () {
      const line = 'uno [dos tres](u) cuatro *cinco seis* siete';
      final from = line.indexOf(' cuatro');
      final at = line.indexOf(' seis');

      expect(
        markdownInlineAt(line, at, from: from),
        markdownInlineAt(line, at),
      );
    });
  });

  group('markdownSafeCut', () {
    test('afuera de todo, corta donde se pidió', () {
      expect(markdownSafeCut('uno dos [tres](u)', 3), 3);
    });

    test('adentro de una construcción, justo antes de ella', () {
      const line = 'uno dos [tres cuatro](u) cinco';

      expect(markdownSafeCut(line, line.indexOf(' cuatro')), line.indexOf('['));
    });

    test('si la construcción empieza donde empieza el tramo, justo después: '
        'un enlace más largo que una página va entero', () {
      final link = '[enlace](https://x.org/${'a' * 5000})';
      final line = '$link y sigue';

      expect(markdownSafeCut(line, 2400), link.length);
      // Desde un corte anterior que quedó justo antes del enlace, lo mismo.
      final after = 'Antes. $line';
      expect(markdownSafeCut(after, 2400, from: 7), 7 + link.length);
    });
  });
}
