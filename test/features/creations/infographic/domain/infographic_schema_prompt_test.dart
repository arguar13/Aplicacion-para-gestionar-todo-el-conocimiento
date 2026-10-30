import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/features/creations/design/creation_icon_names.dart';
import 'package:sinapsis/features/creations/infographic/domain/infographic.dart';
import 'package:sinapsis/features/creations/infographic/domain/infographic_design.dart';
import 'package:sinapsis/features/creations/infographic/domain/infographic_json.dart';
import 'package:sinapsis/features/creations/infographic/domain/infographic_schema_prompt.dart';

/// El esquema que se le explica a la IA (F43, decisión G): describe
/// exactamente lo que lee `InfographicJson`.
void main() {
  test('nombra cada tipo de bloque, cada gráfico y sus campos', () {
    for (final kind in InfographicBlockKind.values) {
      expect(infographicJsonSchemaPrompt, contains('"${kind.jsonName}"'));
    }
    for (final chart in InfographicChartKind.values) {
      expect(infographicJsonSchemaPrompt, contains('"${chart.jsonName}"'));
    }
    // Y el campo "chart" ofrece los ocho, los de F45 también.
    expect(
      infographicJsonSchemaPrompt,
      contains(
        '"chart": uno de '
        '${InfographicChartKind.values.map((c) => '"${c.jsonName}"').join(', ')}',
      ),
    );
    for (final field in [
      'title',
      'subtitle',
      'kicker',
      'blocks',
      'takeaway',
      'source',
      'style_hint',
      'composition_hint',
      'illustration_prompt',
      'level',
      'value',
      'label',
      'detail',
      'icon',
      'left',
      'right',
      'heading',
      'points',
      'conclusion',
      'date',
      'quote',
      'author',
      'data',
      'display',
      'unit',
      'total',
    ]) {
      expect(infographicJsonSchemaPrompt, contains('"$field"'), reason: field);
    }
  });

  test('ofrece los estilos y las composiciones de verdad, sin «auto»', () {
    for (final style in InfographicStyleId.values) {
      expect(
        infographicJsonSchemaPrompt.contains('"${style.id}"'),
        style != InfographicStyleId.auto,
        reason: style.id,
      );
    }
    for (final composition in InfographicComposition.concrete) {
      expect(
        infographicJsonSchemaPrompt,
        contains('"${composition.jsonName}"'),
      );
    }
  });

  test('los topes y los íconos son los que lee el JSON', () {
    expect(
      infographicJsonSchemaPrompt,
      contains('entre 4 y ${InfographicLimits.blocks}'),
    );
    expect(
      infographicJsonSchemaPrompt,
      contains('hasta ${InfographicLimits.value} caracteres'),
    );
    expect(infographicJsonSchemaPrompt, contains(creationIconNames.join(', ')));
  });

  test('pide no inventar números', () {
    expect(infographicJsonSchemaPrompt, contains('no inventes datos, cifras'));
  });

  test('cada detalle pide lo suyo', () {
    final prompts = {
      for (final d in InfographicDetail.values) d: infographicDetailPrompt(d),
    };
    expect(prompts.values.toSet(), hasLength(3));
    expect(prompts[InfographicDetail.concise], contains('"conciso"'));
    expect(
      prompts[InfographicDetail.detailed],
      contains('${InfographicLimits.blocks}'),
    );
  });

  test('un JSON escrito como dice el esquema se lee entero', () {
    final sheet = InfographicJson.tryDecode({
      'title': 'Éxodo',
      'style_hint': 'editorial',
      'composition_hint': 'timeline',
      'blocks': [
        {'type': 'event', 'date': 'Cap. 1', 'title': 'Opresión', 'level': 1},
        {
          'type': 'chart',
          'title': 'Plagas',
          'chart': 'pictogram',
          'data': [
            {'label': 'plagas', 'value': 10},
          ],
          'total': 10,
          'level': 2,
        },
      ],
      'takeaway': 'Libres para servir',
    })!;
    expect(sheet.styleHint, 'editorial');
    expect(sheet.compositionHint, 'timeline');
    expect(sheet.blocks, hasLength(2));
    expect(
      (sheet.blocks[1] as ChartBlock).chartKind,
      InfographicChartKind.pictogram,
    );
    expect(sheet.blocks[1].level, InfographicLevel.supporting);
  });
}
