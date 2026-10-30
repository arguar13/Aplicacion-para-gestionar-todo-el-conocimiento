import 'package:sinapsis/features/creations/design/creation_icon_names.dart';
import 'package:sinapsis/features/creations/presentation_deck/domain/slide_deck.dart';
import 'package:sinapsis/features/creations/presentation_deck/domain/slide_deck_json.dart';

/// El esquema del JSON de un mazo, tal como se le explica a la IA (F43,
/// decisión G): la IA escribe el contenido y elige el diseño de cada
/// diapositiva; el dibujo lo hace la app.
///
/// Es exactamente la forma que escribe `SlideDeckJson.encode` y que lee
/// `SlideDeckJson.tryDecode` (que además tolera variaciones). Los topes son
/// los de [SlideLimits]: escribirlos en el pedido ahorra el recorte después.
final String slideDeckJsonSchemaPrompt =
    '''
Devolvé SOLO un objeto JSON válido, sin texto antes ni después y sin ```.

Forma del objeto:
{
  "title": texto, el título del mazo (hasta ${SlideLimits.title} caracteres),
  "subtitle": texto opcional, una bajada corta,
  "format": "detailed" o "presenter",
  "slides": [ diapositiva, ... ] (entre 4 y ${SlideLimits.slides})
}

Cada diapositiva es un objeto con "layout" y los campos de ese diseño. Todas
aceptan además:
  "speaker_notes": texto, lo que se dice en voz alta al mostrarla,
  "illustration_prompt": texto opcional, solo si una ilustración ayuda de
    verdad a entenderla: describí la imagen en una o dos oraciones, sin texto
    escrito adentro de la imagen.

Los veinte diseños ("layout") y sus campos:
- "cover" (portada; la primera diapositiva): "title", "subtitle" opcional,
  "kicker" opcional (una línea muy corta arriba del título, hasta
  ${SlideLimits.kicker} caracteres).
- "section" (comienzo de una parte): "title", "subtitle" opcional.
- "bullets" (viñetas): "title", "bullets": lista de 3 a ${SlideLimits.bullets} textos.
- "two_columns" (dos columnas): "title", "left" y "right", cada uno
  {"heading": texto corto, "points": lista de 2 a ${SlideLimits.columnPoints} textos}.
- "quote" (cita textual del material): "quote" (sin comillas), "author"
  opcional, "source" opcional (de dónde sale).
- "big_number" (cifra destacada): "value" (la cifra tal como se escribe, hasta
  ${SlideLimits.value} caracteres: "3.000.000", "40 %", "x2"), "label" (qué
  es), "title" opcional, "detail" opcional.
- "steps" (línea de pasos, en orden): "title", "steps": lista de 2 a
  ${SlideLimits.steps} objetos {"title": texto corto, "detail": texto opcional}.
- "comparison" (dos cosas frente a frente): "title", "left" y "right" como en
  "two_columns" (el "heading" es el nombre de cada cosa), "conclusion"
  opcional.
- "timeline" (cronología): "title", "events": lista de 2 a ${SlideLimits.events}
  objetos {"date": la fecha tal como la dice el material ("1492", "Siglo
  XIII", "Día 3"), "title": texto corto, "detail": texto opcional}.
- "image_text" (imagen grande con texto): "title", "body" (un párrafo),
  "bullets" opcional (hasta 4), y conviene "illustration_prompt".
- "concept_grid" (cuadrícula de conceptos): "title", "concepts": lista de 2 a
  ${SlideLimits.concepts} objetos {"title": texto corto, "detail": texto
  opcional, "icon": uno de los nombres de íconos de abajo}.
- "closing" (cierre; la última diapositiva): "title", "subtitle" opcional,
  "takeaways": lista opcional de hasta ${SlideLimits.takeaways} ideas para llevarse.
- "full_quote" (cita a toda página, para una frase textual del material que
  merece ocupar todo): "quote" (sin comillas), "author" opcional, "source"
  opcional.
- "image_grid" (cuadrícula de imágenes): "title", "images": lista de 2 a
  ${SlideLimits.images} objetos {"caption": un epígrafe corto, "icon": uno de los
  nombres de íconos de abajo}; conviene "illustration_prompt" para la
  primera.
- "concept_map" (mapa de conceptos: una idea y sus ramas): "title", "center"
  (la idea del medio, corta), "nodes": lista de 3 a ${SlideLimits.nodes} objetos
  {"title": texto corto, "detail": texto opcional, "icon": opcional}.
- "questions" (cierre con preguntas para pensar o conversar; puede ir
  después del cierre): "title", "subtitle" opcional, "questions": lista de 1 a
  ${SlideLimits.questions} preguntas.
- "stat_grid" (panel de cifras): "title", "stats": lista de 2 a ${SlideLimits.stats}
  objetos {"value": la cifra tal como se escribe (hasta ${SlideLimits.value}
  caracteres), "label": qué es, "detail": opcional}.
- "cycle" (ciclo: pasos que vuelven a empezar): "title", "center" opcional (lo
  que gira, corto), "steps": lista de 3 a ${SlideLimits.cycleSteps} objetos
  {"title": texto corto, "detail": texto opcional}.
- "matrix" (matriz de dos por dos): "title", "x_axis" y "y_axis" opcionales
  (el nombre de cada eje), "quadrants": exactamente 4 objetos {"heading":
  texto corto, "points": lista de 1 a 3 textos}, en orden: arriba a la
  izquierda, arriba a la derecha, abajo a la izquierda, abajo a la derecha.
- "definition" (definición de un término clave): "term", "definition" (una o
  dos oraciones), "example" opcional, "kicker" opcional (la disciplina o la
  categoría, muy corta).

Reglas:
- Usá solo lo que dice el material: no inventes datos, cifras, fechas ni citas.
  Una "quote" o una "full_quote" es una frase textual del material; una
  "big_number" o una "stat_grid", cifras que el material da.
- Elegí el diseño que mejor cuente cada idea y variá: no repitas el mismo
  diseño más de dos veces seguidas.
- Textos cortos y claros: títulos de hasta 8 palabras; viñetas de una línea o
  dos, sin punto final.
- "icon" solo puede ser uno de estos nombres: ${creationIconNames.join(', ')}.
- Escribí en el idioma que se pide, con ortografía cuidada.
''';

/// Lo que cambia según el formato elegido en la hoja (F43, punto 4).
String slideDeckFormatPrompt(DeckFormat format) => switch (format) {
  DeckFormat.detailed =>
    'Formato "detailed": las diapositivas se leen solas, sin nadie que las '
        'explique. Cada una lleva el texto necesario para entenderla; las '
        '"speaker_notes" son un resumen breve de una o dos oraciones.',
  DeckFormat.presenter =>
    'Formato "presenter": las diapositivas acompañan a quien habla. Poco '
        'texto en cada una (títulos y viñetas muy cortos) y, en '
        '"speaker_notes", lo que hay que decir: de 60 a 150 palabras por '
        'diapositiva, en un tono natural para decir en voz alta.',
};
