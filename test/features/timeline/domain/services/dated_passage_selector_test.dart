import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/features/timeline/domain/services/dated_passage_selector.dart';
import 'package:sinapsis/features/timeline/domain/services/temporal_expressions.dart';

/// La selección de los pasajes con fechas que se mandan al modelo (F40).
void main() {
  const darwin =
      'Charles Darwin fue un naturalista inglés. '
      'En 1859 publicó El origen de las especies. '
      'Murió en 1882 en Down House.';

  List<DatedPassage> passagesOf(List<DatedTextPart> parts) => [
    for (final part in parts) ...part.passages,
  ];

  group('qué se manda', () {
    test('un texto sin expresiones de tiempo no manda nada', () {
      expect(selectDatedParts('', maxChars: 3000), isEmpty);
      expect(
        selectDatedParts('Una oración sin fecha. Otra más.', maxChars: 3000),
        isEmpty,
      );
    });

    test('solo hay un «sin año»: el 12 de febrero, el martes siguiente', () {
      expect(
        selectDatedParts(
          'Salió el 12 de febrero. Volvió el martes siguiente.',
          maxChars: 3000,
        ),
        isEmpty,
      );
    });

    test('la oración con la fecha va con la anterior de contexto', () {
      final parts = selectDatedParts(darwin, maxChars: 3000);

      expect(parts, hasLength(1));
      final passage = parts.single.passages.single;
      // Las dos oraciones fechadas pegadas, con la primera de contexto.
      expect(passage.start, 0);
      expect(passage.text, darwin);
      expect(passage.expressions.map((e) => darwin.substring(e.start, e.end)), [
        '1859',
        '1882',
      ]);
    });

    test('lo que lleva cada pasaje es el tramo del texto entero', () {
      const text =
          'Introducción larga sin fechas. Más de lo mismo. '
          'La Revolución francesa empezó en 1789. Terminó en 1799. '
          'Después vino otra cosa. Y otra. Y otra más sin ninguna fecha. '
          'Napoleón murió en 1821.';
      final passages = passagesOf(selectDatedParts(text, maxChars: 3000));

      expect(passages, hasLength(2));
      for (final passage in passages) {
        expect(text.substring(passage.start, passage.end), passage.text);
        for (final e in passage.expressions) {
          expect(e.start, greaterThanOrEqualTo(passage.start));
          expect(e.end, lessThanOrEqualTo(passage.end));
        }
      }
      expect(
        passages[0].text,
        'Más de lo mismo. La Revolución francesa empezó en 1789. '
        'Terminó en 1799.',
      );
      expect(
        passages[1].text,
        'Y otra más sin ninguna fecha. Napoleón murió en 1821.',
      );
    });

    test('la primera oración fechada no tiene contexto', () {
      final passage = passagesOf(
        selectDatedParts('En 1859 pasó algo. Luego nada.', maxChars: 3000),
      ).single;
      expect(passage.text, 'En 1859 pasó algo.');
      expect(passage.start, 0);
    });

    test('el contexto es solo de la oración anterior, no de más atrás', () {
      final passage = passagesOf(
        selectDatedParts(
          'Primera sin nada. Segunda sin nada. Tercera sin nada. '
          'Cuarta con 1859 adentro.',
          maxChars: 3000,
        ),
      ).single;
      expect(passage.text, 'Tercera sin nada. Cuarta con 1859 adentro.');
    });

    test('el contexto tiene que ser del mismo párrafo', () {
      const text = 'Fin de otro párrafo.\n\nEn 1859 publicó su libro.';
      final passage = passagesOf(selectDatedParts(text, maxChars: 3000)).single;
      expect(passage.text, 'En 1859 publicó su libro.');
      expect(passage.start, text.indexOf('En 1859'));

      const withBlanks =
          'Fin de otro párrafo.\n  \t\nEn 1859 publicó su libro.';
      expect(
        passagesOf(selectDatedParts(withBlanks, maxChars: 3000)).single.text,
        'En 1859 publicó su libro.',
      );
    });

    test('un salto de línea simple no corta el contexto', () {
      const text = 'Fue un naturalista inglés\nque en 1859 publicó su libro.';
      expect(
        passagesOf(selectDatedParts(text, maxChars: 3000)).single.text,
        text,
      );
      const two = 'Era un naturalista.\nEn 1859 publicó su libro.';
      expect(
        passagesOf(selectDatedParts(two, maxChars: 3000)).single.text,
        two,
      );
    });

    test('una oración anterior larguísima no se usa de contexto', () {
      final long = '${'palabra ' * 60}terminó.';
      expect(long.length, greaterThan(kMaxContextSentenceChars));
      final passage = passagesOf(
        selectDatedParts('$long En 1859 pasó algo.', maxChars: 3000),
      ).single;
      expect(passage.text, 'En 1859 pasó algo.');
    });

    test('justo en el largo máximo todavía sirve de contexto', () {
      final body = 'a' * (kMaxContextSentenceChars - 1);
      final context = '$body.';
      expect(context.length, kMaxContextSentenceChars);
      final passage = passagesOf(
        selectDatedParts('$context En 1859 pasó algo.', maxChars: 3000),
      ).single;
      expect(passage.text.startsWith(context), isTrue);
    });

    test('oraciones fechadas seguidas forman un solo pasaje', () {
      const text =
          'Sin fecha aquí. En 1914 empezó. En 1915 siguió. En 1916 siguió. '
          'Sin fecha allá.';
      final passages = passagesOf(selectDatedParts(text, maxChars: 3000));
      expect(passages, hasLength(1));
      expect(
        passages.single.text,
        'Sin fecha aquí. En 1914 empezó. En 1915 siguió. En 1916 siguió.',
      );
      expect(passages.single.expressions, hasLength(3));
    });

    test('dos pasajes que se tocan por el contexto se juntan en uno', () {
      // La oración 3 es el contexto de la 4, y la 2 el de la 3.
      const text = 'Uno. Dos con 1700 años. En 1800 pasó. Tres. En 1900 pasó.';
      final passages = passagesOf(selectDatedParts(text, maxChars: 3000));
      expect(passages, hasLength(1));
    });

    test('una expresión que cruza el final de la oración queda adentro', () {
      // «a.C.» tiene un punto, pero la expresión se lee completa.
      const text = 'César murió en el 44 a.C. en Roma.';
      final passage = passagesOf(selectDatedParts(text, maxChars: 3000)).single;
      expect(
        text.substring(
          passage.expressions.single.start,
          passage.expressions.single.end,
        ),
        '44 a.C.',
      );
      expect(passage.text, text);
    });

    test('lo que está en una marca de lista no cuenta como oración', () {
      const text = '- En 1859 publicó.\n- Murió en 1882.';
      final passages = passagesOf(
        selectDatedParts(text, maxChars: 3000, markdown: true),
      );
      expect(passages, hasLength(1));
      expect(passages.single.text, 'En 1859 publicó.\n- Murió en 1882.');
      expect(passages.single.start, 2);
    });

    test('una expresión al principio o al final del pasaje queda adentro', () {
      final atStart = passagesOf(
        selectDatedParts('1859 fue un año clave.', maxChars: 3000),
      ).single;
      expect(atStart.expressions, hasLength(1));
      expect(atStart.expressions.single.start, 0);

      const atEndText = 'Todo pasó en 1859';
      final atEnd = passagesOf(
        selectDatedParts(atEndText, maxChars: 3000),
      ).single;
      expect(atEnd.expressions, hasLength(1));
      expect(atEnd.expressions.single.end, atEndText.length);
    });

    test('un año dentro de un título de Markdown', () {
      const text = '# La guerra de 1914\n\nEmpezó en el verano.';
      final passage = passagesOf(
        selectDatedParts(text, maxChars: 3000, markdown: true),
      ).single;
      expect(passage.text, 'La guerra de 1914');
      expect(passage.start, 2);
    });

    test('con un solo hecho fechado hay un solo pedido de un pasaje', () {
      final parts = selectDatedParts('En 1859 pasó.', maxChars: 3000);
      expect(parts, hasLength(1));
      expect(parts.single.passages, hasLength(1));
      expect(parts.single.chars, 'En 1859 pasó.'.length);
    });
  });

  group('cómo se reparte en pedidos', () {
    String sentences(int count) {
      const nothing = 'Sin nada. Sin nada otra. Sin nada más.';
      return [
        for (var i = 0; i < count; i++)
          '$nothing En ${1500 + i} pasó el hecho número $i.',
      ].join(' ');
    }

    test('ningún pedido pasa del presupuesto', () {
      final text = sentences(30);
      for (final maxChars in [300, 500, 1000, 3000]) {
        final parts = selectDatedParts(text, maxChars: maxChars);
        expect(parts, isNotEmpty);
        for (final part in parts) {
          expect(
            part.chars + part.passages.length * kDatedPassageOverheadChars,
            lessThanOrEqualTo(maxChars),
            reason: 'maxChars $maxChars',
          );
        }
      }
    });

    test('no se pierde ni se repite ninguna expresión, y siguen el orden', () {
      final text = sentences(30);
      final all = findTemporalExpressions(text);
      expect(all, hasLength(30));

      final parts = selectDatedParts(text, maxChars: 500);
      expect(parts.length, greaterThan(1));
      final seen = [for (final p in passagesOf(parts)) ...p.expressions];
      expect(seen, all);

      var previousEnd = -1;
      for (final passage in passagesOf(parts)) {
        expect(passage.start, greaterThanOrEqualTo(previousEnd));
        previousEnd = passage.end;
      }
    });

    test('un pedido no tiene más pasajes que los que entran de respuesta', () {
      // Pasajes separados por mucho texto sin fechas.
      final text = [
        for (var i = 0; i < 40; i++)
          '${'Relleno sin fecha. ' * 6}Pasó en ${1600 + i}.',
      ].join(' ');
      final parts = selectDatedParts(text, maxChars: 3000);

      expect(maxPassagesPerPart(3000), 7);
      for (final part in parts) {
        expect(part.passages.length, lessThanOrEqualTo(7));
      }
      expect(parts.fold(0, (n, p) => n + p.passages.length), 40);
      // Los primeros pedidos van llenos.
      expect(parts.first.passages, hasLength(7));
    });

    test('con un presupuesto grande entran más pasajes por pedido', () {
      expect(maxPassagesPerPart(3000), 7);
      expect(maxPassagesPerPart(60000), 40);
      expect(maxPassagesPerPart(1 << 30), 40);
      expect(maxPassagesPerPart(100), 1);
      expect(maxPassagesPerPart(400), 1);
      expect(maxPassagesPerPart(800), 2);
      expect(maxPassagesPerPart(12000), 30);
    });

    test('un pasaje más largo que el pedido se corta, y sin cortes huecos', () {
      // Una sola oración enorme, con una fecha al principio y otra al final.
      final text =
          'En 1809 nació ${'y siguió contando cosas sin parar ' * 40}'
          'hasta que en 1882 murió.';
      final parts = selectDatedParts(text, maxChars: 500);

      final passages = passagesOf(parts);
      expect(passages.length, greaterThan(1));
      for (final passage in passages) {
        expect(text.substring(passage.start, passage.end), passage.text);
        expect(
          passage.text.length + kDatedPassageOverheadChars,
          lessThanOrEqualTo(500),
        );
        expect(passage.expressions, isNotEmpty);
      }
      final years = [
        for (final p in passages)
          for (final e in p.expressions) text.substring(e.start, e.end),
      ];
      expect(years, ['1809', '1882']);
    });

    test('un pasaje cortado deja afuera los pedazos sin ninguna fecha', () {
      final text =
          'En 1809 nació ${'relleno sin ninguna fecha escrita aquí ' * 100}';
      final passages = passagesOf(selectDatedParts(text, maxChars: 500));
      expect(passages, hasLength(1));
      expect(passages.single.text, startsWith('En 1809'));
    });

    test('dos pasajes que llenan justo el pedido entran juntos', () {
      // Cada pasaje: 392 caracteres de texto + 8 del pedido = 400.
      String passage(int year) => 'En $year ${'x' * 383}.';
      expect(passage(1501).length, 392);
      final text = [
        passage(1501),
        'Relleno sin fecha.',
        passage(1502),
      ].join('\n\n');

      final fits = selectDatedParts(text, maxChars: 800);
      expect(fits, hasLength(1));
      expect(fits.single.passages, hasLength(2));

      final tooSmall = selectDatedParts(text, maxChars: 799);
      expect(tooSmall, hasLength(2));
    });

    test('las fechas con sus pasajes están en el orden del texto', () {
      final text = sentences(10);
      final starts = [
        for (final p in passagesOf(selectDatedParts(text, maxChars: 400)))
          p.start,
      ];
      expect([...starts]..sort(), starts);
    });
  });

  group('las piezas', () {
    final e = findTemporalExpressions('En 1859.');
    final passage = DatedPassage(start: 0, text: 'En 1859.', expressions: e);

    test('DatedPassage', () {
      expect(passage.end, 8);
      expect(passage, DatedPassage(start: 0, text: 'En 1859.', expressions: e));
      expect(
        passage.hashCode,
        DatedPassage(start: 0, text: 'En 1859.', expressions: e).hashCode,
      );
      expect(
        passage,
        isNot(DatedPassage(start: 1, text: 'En 1859.', expressions: e)),
      );
      expect(
        passage,
        isNot(DatedPassage(start: 0, text: 'En 1860.', expressions: e)),
      );
      expect(
        passage,
        isNot(const DatedPassage(start: 0, text: 'En 1859.', expressions: [])),
      );
      expect(passage.toString(), contains('8'));
    });

    test('DatedTextPart', () {
      final second = DatedPassage(
        start: 20,
        text: 'Otra en 1860.',
        expressions: findTemporalExpressions('Otra en 1860.'),
      );
      final part = DatedTextPart([passage, second]);

      expect(part.chars, 8 + 13);
      expect(part, DatedTextPart([passage, second]));
      expect(part.hashCode, DatedTextPart([passage, second]).hashCode);
      expect(part, isNot(DatedTextPart([passage])));
      expect(part.toString(), contains('2'));
    });

    test('DatedTextPart.after da lo que falta o nada', () {
      final second = DatedPassage(start: 20, text: 'Otra', expressions: e);
      final third = DatedPassage(start: 40, text: 'Otra más', expressions: e);
      final part = DatedTextPart([passage, second, third]);

      expect(part.after(0), part);
      expect(part.after(1)!.passages, [second, third]);
      expect(part.after(2)!.passages, [third]);
      expect(part.after(3), isNull);
      expect(part.after(10), isNull);
    });

    test(
      'un pedido sin pasajes no existe, y no se puede cambiar por fuera',
      () {
        expect(() => DatedTextPart(const []), throwsA(isA<AssertionError>()));
        final list = [passage];
        final part = DatedTextPart(list);
        list.add(passage);
        expect(part.passages, hasLength(1));
        expect(() => part.passages.add(passage), throwsUnsupportedError);
      },
    );
  });
}
