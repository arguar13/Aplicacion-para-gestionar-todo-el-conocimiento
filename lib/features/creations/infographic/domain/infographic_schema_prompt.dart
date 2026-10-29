import 'package:sinapsis/features/creations/design/creation_icon_names.dart';
import 'package:sinapsis/features/creations/infographic/domain/infographic_design.dart';
import 'package:sinapsis/features/creations/infographic/domain/infographic_json.dart';

/// El esquema del JSON de una infografía, tal como se le explica a la IA
/// (F43, decisión G): la IA escribe el contenido, dice qué tipo es cada
/// bloque y cuánto pesa; la composición, el estilo y el dibujo los pone la
/// app.
///
/// Es exactamente la forma que escribe `InfographicJson.encode` y que lee
/// `InfographicJson.tryDecode` (que además tolera variaciones). Los topes son
/// los de [InfographicLimits]: escribirlos en el pedido ahorra el recorte
/// después.
final String infographicJsonSchemaPrompt =
    '''
Devolvé SOLO un objeto JSON válido, sin texto antes ni después y sin ```.

Forma del objeto:
{
  "title": texto, el título de la lámina (hasta 10 palabras),
  "subtitle": texto opcional, una bajada de una oración,
  "kicker": texto opcional, una línea muy corta arriba del título (hasta
    ${InfographicLimits.kicker} caracteres),
  "style_hint": el estilo visual que mejor va con el tema, uno de:
    ${_styles()},
  "composition_hint": la forma de componer que mejor cuenta el contenido, una
    de: ${_compositions()},
  "illustration_prompt": texto opcional, la ilustración grande de la
    cabecera, en una o dos oraciones, sin texto escrito adentro de la imagen,
  "blocks": [ bloque, ... ] (entre 4 y ${InfographicLimits.blocks}),
  "takeaway": texto opcional, la idea para llevarse, en una oración,
  "source": texto opcional, de dónde sale (el documento o el autor)
}

Cada bloque es un objeto con "type", los campos de ese tipo y además:
  "level": 1, 2 o 3 — cuánto pesa: 1 lo esencial (se ve siempre), 2 lo de
    apoyo, 3 lo de más (solo en la versión detallada). Poné primero lo más
    importante.
  "illustration_prompt": texto opcional, solo si una ilustración ayuda de
    verdad a entender el bloque: describila en una oración, sin texto escrito.

Los ocho tipos ("type") y sus campos:
- "stat" (una cifra destacada): "value" (la cifra tal como se escribe,
  hasta ${InfographicLimits.value} caracteres: "3.000.000", "40 %", "x2"),
  "label" (qué es), "detail" opcional, "icon" opcional.
- "fact" (una idea o un dato clave): "title" (corto), "detail" opcional,
  "icon".
- "step" (un paso de un proceso, en orden): "title", "detail" opcional,
  "icon" opcional.
- "comparison" (dos cosas frente a frente): "title" opcional, "left" y
  "right", cada uno {"heading": el nombre de la cosa, "points": lista de 2 a
  ${InfographicLimits.points} textos cortos, "icon" opcional}, "conclusion"
  opcional.
- "event" (un hito de una cronología): "date" (la fecha tal como la dice el
  material: "1492", "Siglo XIII", "Día 3"), "title", "detail" opcional.
- "concept" (un concepto del tema): "title", "detail" opcional, "icon".
- "quote" (una frase textual del material): "quote" (sin comillas), "author"
  opcional, "source" opcional.
- "chart" (un gráfico, solo con números que da el material): "title",
  "chart": "bars", "ring", "progress" o "pictogram", "data": lista de 1 a
  ${InfographicLimits.data} objetos {"label": texto corto, "value": número,
  "display": opcional, cómo se escribe el número}, "unit" opcional ("%",
  "años"), "total" opcional (el total contra el que se mide: 100 en un
  porcentaje, 10 en "7 de cada 10"), "detail" opcional.
  - "bars" compara cantidades; "ring", un porcentaje o las partes de un todo;
    "progress", cuánto de un total; "pictogram", "N de cada M" con M hasta 20.

Reglas:
- Usá solo lo que dice el material: no inventes datos, cifras, fechas ni
  citas. Un "stat" o un "chart" llevan solo números que el material da; si
  no hay números, no los uses.
- Elegí el tipo que mejor cuente cada cosa. Una cronología usa "event"; un
  proceso, "step"; dos posturas, "comparison".
- Textos cortos y claros: títulos de hasta 6 palabras, detalles de una o dos
  oraciones, sin punto final en los títulos.
- "icon" solo puede ser uno de estos nombres: ${creationIconNames.join(', ')}.
- Escribí en el idioma que se pide, con ortografía cuidada.
''';

/// Lo que cambia según el detalle elegido en la hoja (F43, punto 4). La IA
/// escribe igual los tres niveles —así el detalle se cambia después sin
/// volver a pedir nada—; esto le dice cuánto poner en cada uno.
String infographicDetailPrompt(InfographicDetail detail) => switch (detail) {
  InfographicDetail.concise =>
    'Detalle "conciso": entre 4 y 6 bloques, casi todos de nivel 1, con '
        'detalles muy breves (una línea).',
  InfographicDetail.standard =>
    'Detalle "estándar": entre 6 y 9 bloques; unos 4 a 6 de nivel 1 y el '
        'resto de nivel 2, con detalles de una o dos oraciones.',
  InfographicDetail.detailed =>
    'Detalle "detallado": entre 9 y ${InfographicLimits.blocks} bloques, '
        'repartidos en los tres niveles, con detalles de dos oraciones.',
};

String _styles() => [
  for (final style in InfographicStyleId.values)
    if (style != InfographicStyleId.auto) '"${style.id}"',
].join(', ');

String _compositions() => [
  for (final composition in InfographicComposition.concrete)
    '"${composition.jsonName}"',
].join(', ');
