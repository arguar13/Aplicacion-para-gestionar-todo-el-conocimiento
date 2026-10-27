import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/features/chat/presentation/widgets/chat_markdown_blocks.dart';

import '../../../../support/time_growth.dart';

/// Los bloques de una respuesta del chat (F42): qué es cada pedazo y dónde
/// está en el texto crudo —lo que usan el lector en voz alta y el fundido—.
void main() {
  String contentOf(String raw, ChatBlock block) =>
      raw.substring(block.content.start, block.content.end);

  List<(ChatBlockKind, String)> read(String raw) => [
    for (final block in parseChatBlocks(raw))
      (block.kind, contentOf(raw, block)),
  ];

  group('qué es cada bloque', () {
    test('párrafos separados por un renglón en blanco; un salto adentro se '
        'respeta', () {
      expect(read('Uno.\nSigue uno.\n\nDos.'), [
        (ChatBlockKind.paragraph, 'Uno.\nSigue uno.'),
        (ChatBlockKind.paragraph, 'Dos.'),
      ]);
    });

    test('títulos de los seis niveles, sin sus numerales', () {
      const raw = '# Uno\n## Dos\n###### Seis\n#Sin espacio';
      final blocks = parseChatBlocks(raw);
      expect(blocks.map((b) => (b.kind, b.level, contentOf(raw, b))), [
        (ChatBlockKind.heading, 1, 'Uno'),
        (ChatBlockKind.heading, 2, 'Dos'),
        (ChatBlockKind.heading, 6, 'Seis'),
        (ChatBlockKind.paragraph, 0, '#Sin espacio'),
      ]);
    });

    test('listas con viñetas y con números, anidadas, y el renglón partido '
        'de un ítem', () {
      const raw =
          '- uno\n'
          '  sigue uno\n'
          '  * adentro\n'
          '1. primero\n'
          '2) segundo\n'
          '+ más';
      final blocks = parseChatBlocks(raw);
      expect(
        blocks.map((b) => (b.kind, b.depth, b.ordinal, contentOf(raw, b))),
        [
          (ChatBlockKind.listItem, 0, null, 'uno\n  sigue uno'),
          (ChatBlockKind.listItem, 1, null, 'adentro'),
          (ChatBlockKind.listItem, 0, '1.', 'primero'),
          (ChatBlockKind.listItem, 0, '2)', 'segundo'),
          (ChatBlockKind.listItem, 0, null, 'más'),
        ],
      );
    });

    test('un renglón sin sangría después de un ítem es un párrafo nuevo', () {
      expect(read('- ítem\nOtra cosa.'), [
        (ChatBlockKind.listItem, 'ítem'),
        (ChatBlockKind.paragraph, 'Otra cosa.'),
      ]);
    });

    test('«2 * 3» o «-5 grados» no son listas', () {
      expect(read('2 * 3 = 6\n-5 grados'), [
        (ChatBlockKind.paragraph, '2 * 3 = 6\n-5 grados'),
      ]);
    });

    test('citas, de a un renglón', () {
      expect(read('> uno\n>dos'), [
        (ChatBlockKind.quote, 'uno'),
        (ChatBlockKind.quote, 'dos'),
      ]);
    });

    test('código entre cercas, con su lenguaje, tal cual adentro', () {
      const raw =
          'Mirá:\n```dart\nvoid main() {\n  # no es título\n}\n```\nListo.';
      final blocks = parseChatBlocks(raw);
      expect(blocks.map((b) => b.kind), [
        ChatBlockKind.paragraph,
        ChatBlockKind.code,
        ChatBlockKind.paragraph,
      ]);
      expect(blocks[1].language, 'dart');
      expect(contentOf(raw, blocks[1]), 'void main() {\n  # no es título\n}');
      expect(blocks[1].end, raw.indexOf('```\nListo') + 3);
    });

    test('un bloque de código sin cerrar —mientras se escribe— llega hasta el '
        'final', () {
      const raw = '```\nuno\ndos';
      final blocks = parseChatBlocks(raw);
      expect(blocks.single.kind, ChatBlockKind.code);
      expect(blocks.single.language, isNull);
      expect(contentOf(raw, blocks.single), 'uno\ndos');
    });

    test('una cerca de virgulillas no la cierra una de comillas', () {
      const raw = '~~~\n```\n~~~';
      expect(contentOf(raw, parseChatBlocks(raw).single), '```');
    });

    test('un bloque de código recién abierto, sin nada adentro', () {
      const raw = '```py';
      final block = parseChatBlocks(raw).single;
      expect(block.kind, ChatBlockKind.code);
      expect(block.content, (start: raw.length, end: raw.length));
    });

    test('separadores de tres o más', () {
      expect(parseChatBlocks('---\n* * *\n___').map((b) => b.kind), [
        ChatBlockKind.rule,
        ChatBlockKind.rule,
        ChatBlockKind.rule,
      ]);
    });

    test('una tabla: los títulos, el separador y las filas, celda por '
        'celda', () {
      const raw =
          '| País | Capital |\n|---|:---:|\n| Perú | Lima |\n'
          'Chile | Santiago\n\nFin.';
      final blocks = parseChatBlocks(raw);
      expect(blocks.map((b) => b.kind), [
        ChatBlockKind.table,
        ChatBlockKind.paragraph,
      ]);
      expect(
        [
          for (final row in blocks.first.rows)
            [for (final cell in row) raw.substring(cell.start, cell.end)],
        ],
        [
          ['País', 'Capital'],
          ['Perú', 'Lima'],
          ['Chile', 'Santiago'],
        ],
      );
    });

    test('un renglón con «|» sin separador debajo es un párrafo', () {
      expect(read('a | b\nc'), [(ChatBlockKind.paragraph, 'a | b\nc')]);
    });

    test('un párrafo termina donde empieza otro bloque', () {
      expect(
        read('Texto\n# Título\nMás\n- ítem\nY\n> cita\nZ\n---\nW\n```\nc\n```'),
        [
          (ChatBlockKind.paragraph, 'Texto'),
          (ChatBlockKind.heading, 'Título'),
          (ChatBlockKind.paragraph, 'Más'),
          (ChatBlockKind.listItem, 'ítem'),
          (ChatBlockKind.paragraph, 'Y'),
          (ChatBlockKind.quote, 'cita'),
          (ChatBlockKind.paragraph, 'Z'),
          (ChatBlockKind.rule, ''),
          (ChatBlockKind.paragraph, 'W'),
          (ChatBlockKind.code, 'c'),
        ],
      );
    });

    test(r'con saltos de Windows, el \r no es parte de nada', () {
      expect(read('# Hola\r\n\r\nuno\r\n- dos'), [
        (ChatBlockKind.heading, 'Hola'),
        (ChatBlockKind.paragraph, 'uno'),
        (ChatBlockKind.listItem, 'dos'),
      ]);
      // Un separador o una tabla con saltos de Windows siguen siéndolo.
      final crlf = parseChatBlocks(
        '---\r\n| a | b |\r\n|---|---|\r\n| 1 | 2 |',
      );
      expect(crlf.map((b) => b.kind), [
        ChatBlockKind.rule,
        ChatBlockKind.table,
      ]);
    });

    test('los espacios de las puntas no son contenido', () {
      const raw = '  hola  \n\n#  título  ';
      expect(read(raw), [
        (ChatBlockKind.paragraph, 'hola'),
        (ChatBlockKind.heading, 'título'),
      ]);
      // El bloque empieza en su renglón, con la sangría.
      expect(parseChatBlocks(raw).first.start, 0);
    });

    test('nada que leer: ningún bloque', () {
      expect(parseChatBlocks(''), isEmpty);
      expect(parseChatBlocks('\n \n\t'), isEmpty);
    });
  });

  group('de a pedazos, mientras se escribe', () {
    const answer =
        '# Roma\n\n'
        'Roma fue **una república** y después un imperio [1].\n'
        'Duró siglos.\n\n'
        '- uno\n'
        '  sigue\n'
        '- dos\n\n'
        '| a | b |\n'
        '|---|---|\n'
        '| 1 | 2 |\n\n'
        '```dart\n'
        'print(1);\n'
        '```\n\n'
        '> cita\n'
        '---\n'
        'Fin.';

    test('letra por letra, da siempre lo mismo que leerlo entero', () {
      final stream = ChatBlockStream();
      for (var i = 1; i <= answer.length; i++) {
        final prefix = answer.substring(0, i);
        expect(
          stream.update(prefix),
          parseChatBlocks(prefix),
          reason: 'con $i caracteres: «${prefix.split('\n').last}»',
        );
      }
    });

    test('de a palabras, también', () {
      final stream = ChatBlockStream();
      final words = RegExp(r'\S+\s*').allMatches(answer).toList();
      for (final word in words) {
        final prefix = answer.substring(0, word.end);
        expect(stream.update(prefix), parseChatBlocks(prefix));
      }
    });

    test('los bloques asentados son los mismos objetos de antes: la pantalla '
        'no los vuelve a armar', () {
      final stream = ChatBlockStream();
      final first = stream.update('Uno.\n\nDos.\n\nTres.\n\nCua');
      expect(stream.settledCount, 2);
      final next = stream.update('Uno.\n\nDos.\n\nTres.\n\nCuatro.');
      expect(identical(first[0], next[0]), isTrue);
      expect(identical(first[1], next[1]), isTrue);
    });

    test('el anteúltimo no se asienta: el renglón que se escribe puede '
        'cambiarlo', () {
      final stream = ChatBlockStream();
      final before = stream.update('Intro.\n\n| a | b |\n|---|--');
      expect(before.last.kind, ChatBlockKind.table);
      final after = stream.update('Intro.\n\n| a | b |\n|---|--x');
      expect(after.map((b) => b.kind), [
        ChatBlockKind.paragraph,
        ChatBlockKind.paragraph,
      ]);
    });

    test('un texto que no sigue al anterior se lee de nuevo entero', () {
      final stream = ChatBlockStream()
        ..update('Uno.\n\nDos.\n\nTres.\n\nCuatro');
      expect(stream.update('Otra.'), parseChatBlocks('Otra.'));
      // Más corto que lo asentado, o distinto justo antes de donde retoma.
      stream.update('Uno.\n\nDos.\n\nTres.\n\nCuatro');
      expect(stream.update('Uno.'), parseChatBlocks('Uno.'));
      stream.update('Uno.\n\nDos.\n\nTres.\n\nCuatro');
      expect(
        stream.update('Uno.\n\nDos.\n\nTres. Cuatro y más'),
        parseChatBlocks('Uno.\n\nDos.\n\nTres. Cuatro y más'),
      );
    });

    test('una respuesta larga cuesta lo que su largo, no su largo al '
        'cuadrado', () async {
      String paragraph(int i) =>
          'El párrafo $i habla de **algo** con [1] y sigue un poco más, como '
          'escribe un modelo.';
      String reply(int paragraphs) =>
          [for (var i = 0; i < paragraphs; i++) paragraph(i)].join('\n\n');

      Future<int> stream(String text) => micros(() {
        final blocks = ChatBlockStream();
        // De a cuatro caracteres, como llegan los pedazos.
        for (var i = 4; i < text.length; i += 4) {
          blocks.update(text.substring(0, i));
        }
        blocks.update(text);
      });

      final small = reply(60);
      final big = reply(240);
      final growth = await timeGrowth(() => stream(small), () => stream(big));
      // Cuatro veces más texto: lineal da cerca de 4 —el recorte del texto
      // que llega ya es lineal en cada pedazo—; leer todo de nuevo, cerca de
      // 16.
      expect(growth, lessThan(9));
    });
  });

  test('dos bloques iguales son iguales, y distintos si cambia algo', () {
    final a = parseChatBlocks('| a | b |\n|---|---|\n| 1 | 2 |').single;
    final b = parseChatBlocks('| a | b |\n|---|---|\n| 1 | 2 |').single;
    // Las posiciones, no el texto: una celda más ancha es otro bloque.
    final c = parseChatBlocks('| a | b |\n|---|---|\n| 1 | 33 |').single;
    expect(a, b);
    expect(a.hashCode, b.hashCode);
    expect(a, isNot(c));
    expect(a.toString(), contains('table'));

    // Mismo largo y mismos títulos, pero tres filas contra dos.
    final threeRows = parseChatBlocks(
      '| a | b |\n|---|---|\n| 1 | 2 |\n| 3 | 4 |',
    ).single;
    final twoRows = parseChatBlocks(
      '| a | b |\n|---|---|\n| 1 | 2           |',
    ).single;
    expect(threeRows.rows, hasLength(3));
    expect(twoRows.rows, hasLength(2));
    expect((threeRows.start, threeRows.end), (twoRows.start, twoRows.end));
    expect(threeRows, isNot(twoRows));
    expect(twoRows, isNot(threeRows));
  });
}
