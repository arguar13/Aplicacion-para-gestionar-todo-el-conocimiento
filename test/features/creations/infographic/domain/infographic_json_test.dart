import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/features/creations/infographic/domain/infographic.dart';
import 'package:sinapsis/features/creations/infographic/domain/infographic_json.dart';

import '../support/sample_infographics.dart';

/// El JSON de una infografía (F43, decisión G): lo que se guarda vuelve
/// igual, y lo que devuelve la IA se lee con tolerancia —nunca se pierde un
/// bloque por un campo raro, y nunca entra un texto sin tope—.
void main() {
  InfographicBlock only(Object? json) => InfographicJson.tryDecode({
    'title': 'Lámina',
    'blocks': [json],
  })!.blocks.single;

  group('ida y vuelta', () {
    test('la infografía de ejemplo vuelve idéntica, con sus ocho tipos', () {
      final sheet = sampleInfographic(illustrations: true);
      final again = InfographicJson.decode(InfographicJson.encodeString(sheet));
      expect(again, sheet);
      expect(
        again.blocks.map((b) => b.kind).toSet(),
        InfographicBlockKind.values.toSet(),
      );
    });

    test('las pistas, la ilustración ya hecha y los decimales también', () {
      const sheet = Infographic(
        title: 'T',
        styleHint: 'data',
        compositionHint: 'stat_panel',
        illustrationRef: 'creaciones/abc/cabecera.png',
        blocks: [
          InfographicBlock.chart(
            title: 'Avance',
            chartKind: InfographicChartKind.progress,
            data: [InfographicDatum(label: 'Hecho', value: 12.5)],
            total: 40,
            unit: '%',
            level: InfographicLevel.supporting,
            illustrationRef: 'creaciones/abc/1.png',
          ),
        ],
      );
      expect(InfographicJson.decode(InfographicJson.encode(sheet)), sheet);
    });

    test('lo vacío no se escribe', () {
      expect(
        InfographicJson.encodeBlock(const InfographicBlock.fact(title: 'Solo')),
        {'type': 'fact', 'title': 'Solo', 'level': 1},
      );
    });
  });

  group('lo que devuelve la IA', () {
    test('envuelto en ```json y con texto alrededor', () {
      const text =
          'Acá está tu infografía:\n```json\n'
          '{"title": "Éxodo", "blocks": [{"type": "fact", "title": "Salida"}]}'
          '\n```\n¡Espero que sirva!';
      final sheet = InfographicJson.tryDecode(text)!;
      expect(sheet.title, 'Éxodo');
      expect(sheet.blocks.single, const InfographicBlock.fact(title: 'Salida'));
    });

    test('una lista suelta de bloques es una lámina con su título', () {
      final sheet = InfographicJson.tryDecode([
        {'type': 'concept', 'title': 'Alianza'},
      ])!;
      expect(sheet.title, 'Alianza');
    });

    test('las claves y los tipos en castellano, con tildes y mayúsculas', () {
      final sheet = InfographicJson.tryDecode({
        'Título': 'Lámina',
        'Subtítulo': 'Bajada',
        'Idea clave': 'Para llevarse',
        'Fuente': 'El libro',
        'Estilo': 'Pizarra',
        'Composición': 'Línea de tiempo',
        'Bloques': [
          {'Tipo': 'Cifra', 'Valor': '40 %', 'Etiqueta': 'del libro'},
          {'tipo': 'Hito', 'fecha': 1492, 'título': 'Llegada'},
          {'tipo': 'Paso', 'Título': 'Primero', 'Descripción': 'Esto'},
          {'tipo': 'Cita', 'cita': '«Deja ir a mi pueblo»', 'autor': 'Moisés'},
          {'tipo': 'Concepto', 'nombre': 'Ley', 'icono': 'Ley'},
        ],
      })!;
      expect(sheet.subtitle, 'Bajada');
      expect(sheet.takeaway, 'Para llevarse');
      expect(sheet.source, 'El libro');
      expect(sheet.styleHint, 'pizarra');
      expect(sheet.compositionHint, 'linea_de_tiempo');
      expect(sheet.blocks[0], isA<StatBlock>());
      expect((sheet.blocks[0] as StatBlock).value, '40 %');
      expect((sheet.blocks[1] as EventBlock).date, '1492');
      expect((sheet.blocks[2] as StepBlock).detail, 'Esto');
      // Las comillas de la cita las dibuja el diseño.
      expect((sheet.blocks[3] as QuoteBlock).quote, 'Deja ir a mi pueblo');
      expect((sheet.blocks[4] as ConceptBlock).icon, 'Ley');
    });

    test('sin tipo, se deduce de los campos', () {
      expect(only({'value': '3.000', 'label': 'x'}), isA<StatBlock>());
      expect(only({'date': '1492', 'title': 'x'}), isA<EventBlock>());
      expect(only({'quote': 'Algo dicho'}), isA<QuoteBlock>());
      expect(
        only({
          'left': ['a'],
          'right': ['b'],
        }),
        isA<ComparisonBlock>(),
      );
      expect(
        only({
          'data': [
            {'label': 'a', 'value': 1},
          ],
        }),
        isA<ChartBlock>(),
      );
      expect(only({'title': 'Una idea'}), isA<FactBlock>());
      expect(
        only('Un texto suelto'),
        const InfographicBlock.fact(title: 'Un texto suelto'),
      );
    });

    test('un tipo al que le falta lo suyo se lee como un hecho', () {
      // Una cifra sin cifra, una comparación con un solo lado, un gráfico
      // sin números: lo que traen no se pierde.
      expect(
        only({'type': 'stat', 'label': 'Sin número'}),
        const InfographicBlock.fact(title: 'Sin número'),
      );
      expect(
        only({
          'type': 'comparison',
          'title': 'Uno solo',
          'left': ['a'],
        }),
        const InfographicBlock.fact(title: 'Uno solo'),
      );
      expect(
        only({
          'type': 'chart',
          'title': 'Sin datos',
          'data': ['mucho', 'poco'],
        }),
        const InfographicBlock.fact(title: 'Sin datos'),
      );
      expect(
        only({'type': 'desconocido', 'detail': 'Solo un detalle'}),
        const InfographicBlock.fact(title: 'Solo un detalle'),
      );
    });

    test('un bloque sin nada de texto se descarta, y sin bloques no hay '
        'lámina', () {
      final sheet = InfographicJson.tryDecode({
        'title': 'T',
        'blocks': [
          {'type': 'fact'},
          42,
          {'type': 'fact', 'title': 'Queda'},
        ],
      })!;
      expect(sheet.blocks, [const InfographicBlock.fact(title: 'Queda')]);
      expect(
        InfographicJson.tryDecode({'title': 'T', 'blocks': <Object?>[]}),
        isNull,
      );
      expect(InfographicJson.tryDecode('no hay JSON acá'), isNull);
      expect(InfographicJson.decode(null), const Infographic(title: ''));
    });

    test('las secciones se leen como bloques uno detrás de otro', () {
      final sheet = InfographicJson.tryDecode({
        'title': 'T',
        'secciones': [
          {
            'encabezado': 'Uno',
            'bloques': [
              {'type': 'fact', 'title': 'a'},
              {'type': 'fact', 'title': 'b'},
            ],
          },
          {'type': 'fact', 'title': 'c'},
        ],
      })!;
      expect(sheet.blocks.map((b) => b.headline), ['a', 'b', 'c']);
    });

    test('«40 años de travesía» en el valor se parte en cifra y rótulo', () {
      final stat = only({'type': 'stat', 'value': '40 años de travesía larga'});
      expect(stat, isA<StatBlock>());
      expect((stat as StatBlock).value, '40 años');
      expect(stat.label, 'de travesía larga');
    });
  });

  group('los gráficos', () {
    test('los datos como objetos, pares, un mapa o dos listas', () {
      ChartBlock chart(Object? data, [Map<String, Object?> extra = const {}]) =>
          only({'type': 'chart', 'title': 'G', 'data': data, ...extra})
              as ChartBlock;

      final objects = chart([
        {'Etiqueta': 'Uno', 'Valor': '1.500'},
        {'label': 'Dos', 'value': 2.5, 'display': '2,5 M'},
      ]);
      expect(objects.data, const [
        InfographicDatum(label: 'Uno', value: 1500, display: '1.500'),
        InfographicDatum(label: 'Dos', value: 2.5, display: '2,5 M'),
      ]);
      expect(
        chart([
          ['A', 10],
          ['B', '20 %'],
        ]).data.map((d) => d.value),
        [10, 20],
      );
      expect(chart({'A': 1, 'B': 2}).data.map((d) => d.label), ['A', 'B']);
      final parallel =
          only({
                'type': 'chart',
                'labels': ['x', 'y'],
                'values': [3, 4],
              })
              as ChartBlock;
      expect(parallel.data.map((d) => '${d.label}=${d.value}'), [
        'x=3.0',
        'y=4.0',
      ]);
    });

    test('el tipo de gráfico en sus nombres, y si no lo dice, null', () {
      ChartBlock chart(String kind) =>
          only({
                'type': 'chart',
                'chart': kind,
                'data': [1],
              })
              as ChartBlock;
      expect(chart('Barras').chartKind, InfographicChartKind.bars);
      expect(chart('donut').chartKind, InfographicChartKind.ring);
      expect(chart('Torta').chartKind, InfographicChartKind.ring);
      expect(chart('progreso').chartKind, InfographicChartKind.progress);
      expect(chart('Pictograma').chartKind, InfographicChartKind.pictogram);
      expect(chart('radar').chartKind, isNull);
    });

    test('el total en texto, y uno negativo o cero no cuenta', () {
      ChartBlock chart(Object? total) =>
          only({
                'type': 'chart',
                'data': [1],
                'total': total,
              })
              as ChartBlock;
      expect(chart('de 10').total, 10);
      expect(chart(0).total, isNull);
      expect(chart(-3).total, isNull);
    });
  });

  group('los niveles', () {
    test('escritos como número o como palabra', () {
      InfographicLevel level(Object? raw) =>
          only({'type': 'fact', 'title': 'x', 'level': raw}).level;
      expect(level(1), InfographicLevel.essential);
      expect(level('2'), InfographicLevel.supporting);
      expect(level(7), InfographicLevel.extra);
      expect(level('Alta'), InfographicLevel.essential);
      expect(level('media'), InfographicLevel.supporting);
      expect(level('detalle'), InfographicLevel.extra);
    });

    test('sin ningún nivel escrito, se reparten por orden', () {
      final sheet = InfographicJson.tryDecode({
        'title': 'T',
        'blocks': [
          for (var i = 0; i < 8; i++) {'type': 'fact', 'title': 'b$i'},
        ],
      })!;
      expect(sheet.blocks.map((b) => b.level.value), [1, 1, 1, 1, 2, 2, 3, 3]);
    });

    test('con alguno escrito, los que faltan son esenciales', () {
      final sheet = InfographicJson.tryDecode({
        'title': 'T',
        'blocks': [
          {'type': 'fact', 'title': 'a', 'level': 3},
          {'type': 'fact', 'title': 'b'},
        ],
      })!;
      expect(sheet.blocks.map((b) => b.level.value), [3, 1]);
    });
  });

  group('los topes', () {
    test('cada texto se corta en su tope, en una palabra entera, con «…»', () {
      final long = List.filled(80, 'palabra').join(' ');
      final sheet = InfographicJson.tryDecode({
        'title': long,
        'subtitle': long,
        'takeaway': long,
        'blocks': [
          {'type': 'fact', 'title': long, 'detail': long},
          {'type': 'stat', 'value': '1234567890123456789012', 'label': 'x'},
        ],
      })!;
      expect(sheet.title.length, lessThanOrEqualTo(InfographicLimits.title));
      expect(sheet.title, endsWith('palabra…'));
      expect(
        sheet.subtitle.length,
        lessThanOrEqualTo(InfographicLimits.subtitle),
      );
      expect(
        sheet.takeaway.length,
        lessThanOrEqualTo(InfographicLimits.takeaway),
      );
      final fact = sheet.blocks.first as FactBlock;
      expect(fact.title.length, lessThanOrEqualTo(InfographicLimits.label));
      expect(fact.detail.length, lessThanOrEqualTo(InfographicLimits.detail));
      expect(
        (sheet.blocks[1] as StatBlock).value.length,
        lessThanOrEqualTo(InfographicLimits.value),
      );
    });

    test('a lo sumo los bloques, los puntos y los datos de su tope', () {
      final sheet = InfographicJson.tryDecode({
        'title': 'T',
        'blocks': [
          {
            'type': 'comparison',
            'left': List.generate(9, (i) => 'a$i'),
            'right': {'heading': 'B', 'points': List.generate(9, (i) => 'b$i')},
          },
          {'type': 'chart', 'data': List.generate(20, (i) => i + 1)},
          for (var i = 0; i < 30; i++) {'type': 'fact', 'title': 'f$i'},
        ],
      })!;
      expect(sheet.blocks, hasLength(InfographicLimits.blocks));
      final comparison = sheet.blocks.first as ComparisonBlock;
      expect(comparison.left.points, hasLength(InfographicLimits.points));
      expect(comparison.right.points, hasLength(InfographicLimits.points));
      expect(
        (sheet.blocks[1] as ChartBlock).data,
        hasLength(InfographicLimits.data),
      );
    });

    test('una referencia de ilustración desmesurada no entra', () {
      final block = only({
        'type': 'fact',
        'title': 'x',
        'illustration_ref': 'a' * 5000,
        'illustration_prompt': 'Un río',
      });
      expect(block.illustrationRef, isNull);
      expect(block.illustrationPrompt, 'Un río');
    });
  });

  test('lo guardado se lee igual aunque venga como texto con espacios', () {
    final json = jsonEncode(InfographicJson.encode(processInfographic()));
    expect(InfographicJson.decode('  $json \n'), processInfographic());
  });
}
