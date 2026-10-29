/// Lo que se le pide a la IA para un mapa mental (F43, punto 6 del plan):
/// la tarea, el esquema y lo de cada parte cuando el material va por partes.
/// Breve a propósito: con Gemma, la instrucción y el esquema entran en
/// `kCreationInstructionTokens`.
library;

/// La forma del JSON, dicha para el modelo: lo que lee `MindMapJson.read`.
const mindMapSchemaPrompt = '''
{"title": "título breve del mapa",
 "root": {"label": "idea central, de 1 a 6 palabras",
  "children": [
   {"label": "rama principal, de 1 a 6 palabras",
    "note": "una frase que la explica (opcional)",
    "source": "el título del documento del que sale, tal como va después de ## en el material",
    "quote": "de 5 a 15 palabras copiadas TAL CUAL del material, donde se dice",
    "children": [ ...ramas más chicas, con la misma forma ]}]}}
Reglas: entre 3 y 7 ramas principales; hasta 4 niveles; cada nombre, corto y sin repetir el de arriba; "quote" siempre literal, para encontrarlo en el texto.''';

/// La tarea del mapa entero, con unas [nodes] ideas en total y, si se eligió,
/// sobre [topic].
String mindMapTask(int nodes, {String? topic}) =>
    'armar un mapa mental con las ideas del material, de lo general a lo '
    'particular: una idea central como raíz, sus ramas principales y, debajo '
    'de cada una, las ideas que la desarrollan; unas $nodes ideas en total'
    '${_about(topic)}';

/// La tarea de una parte, cuando el material va por partes: cada una da su
/// rama, y un último paso las une ([mindMapMergeTask]).
String mindMapPartTask(int nodes, {String? topic}) =>
    'armar el mapa mental de SOLO esta parte del material —su idea central '
    'como raíz y sus ramas—, que después se une con los de las otras partes; '
    'unas $nodes ideas como mucho${_about(topic)}';

/// La tarea de unir los mapas de cada parte en uno.
String mindMapMergeTask(int nodes, {String? topic}) =>
    'unir en un solo mapa mental los mapas parciales que se te dan —cada uno '
    'salió de una parte del material, en orden—: una sola raíz con la idea '
    'central de todo, las ramas que hablan de lo mismo unidas en una, sin '
    'repetir y sin perder ninguna idea importante, y cada "source" y "quote" '
    'tal como vienen; unas $nodes ideas en total${_about(topic)}';

/// El tema elegido en la hoja: el mapa gira alrededor de él.
String _about(String? topic) {
  final text = topic?.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (text == null || text.isEmpty) return '';
  return '. El mapa es sobre este tema: «$text». La raíz es ese tema, y '
      'entran solo las ideas del material que tienen que ver con él';
}
