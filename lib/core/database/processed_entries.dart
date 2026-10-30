/// Qué elementos son documentos procesados (F41), para las consultas escritas a
/// mano.
///
/// Un documento procesado es un elemento de la bóveda —con su papelera, su
/// copia y su unión de bóvedas—, pero **no es de la Biblioteca**: vive en
/// «Procesado». La Biblioteca es la base de consulta, con las fuentes enteras y
/// las notas de la persona; lo procesado es lo trabajado. Este archivo es el
/// único lugar que dice cómo se reconoce uno: tener su fila en
/// `processed_documents`, buscada por su clave.
///
/// Y, desde el paso 6, el corpus del Atlas, el Mapa, el grafo local y la
/// Línea de tiempo: leen solo esto.
library;

import 'package:sinapsis/core/domain/entities/processed_depth.dart';

/// La condición SQL de que el elemento [itemId] —una columna o expresión, como
/// `item.id`— sea un documento procesado.
String isProcessedSql(String itemId) =>
    'EXISTS (SELECT 1 FROM processed_documents processed '
    'WHERE processed.item_id = $itemId)';

/// La condición SQL de que el elemento [itemId] NO sea un documento procesado:
/// lo que deja afuera la Biblioteca.
String notProcessedSql(String itemId) => 'NOT ${isProcessedSql(itemId)}';

/// El escalón de [ProcessedDepth] del documento procesado [itemId], como su
/// nombre: el más alto cuyas secciones tiene.
///
/// Cada escalón es un `EXISTS` sobre `idx_processed_parts_document`
/// —documento y sección—: una búsqueda por clave, sin recorrer las páginas de
/// un libro entero. De un elemento que no es un procesado da el primero.
String processedDepthSql(String itemId) {
  String reaches(ProcessedDepth depth) {
    final sections = depth.sections.map((s) => "'${s.name}'").join(', ');
    return 'WHEN EXISTS (SELECT 1 FROM processed_parts depth_part '
        'WHERE depth_part.document_id = $itemId '
        'AND depth_part.section IN ($sections)) '
        "THEN '${depth.name}'";
  }

  final steps = [
    for (final depth in ProcessedDepth.values.reversed)
      if (depth.sections.isNotEmpty) reaches(depth),
  ];
  return "CASE ${steps.join(' ')} ELSE '${ProcessedDepth.textOnly.name}' END";
}

/// Los documentos procesados que tienen UNA palabra —tres parámetros: la
/// palabra para el título, para las partes y para las notas—, vivos o no: lo
/// vivo lo decide quien la usa. Cada palabra buscada tiene que estar en el
/// documento, en su título, en cualquiera de sus partes o en una de sus notas
/// en el texto —las de la copia del original y las del texto procesado (F45,
/// mejora 19), que son texto de la persona; las del original de la Biblioteca
/// son de la fuente y no entran acá—: con varias, se intersecan.
///
/// Envuelta en su propio `SELECT … FROM (…)` a propósito: en SQLite `UNION` e
/// `INTERSECT` tienen la misma precedencia y se asocian a la izquierda, así que
/// sin envolverla `A UNION B INTERSECT C UNION D` sería
/// `((A UNION B) INTERSECT C) UNION D`.
const processedDocumentsWithTermSql =
    'SELECT doc FROM ( '
    'SELECT item_search.item_id AS doc FROM item_search '
    'WHERE item_search MATCH ? '
    'UNION SELECT pp.document_id AS doc FROM processed_part_search '
    'JOIN processed_parts pp ON pp.row_key = processed_part_search.rowid '
    'WHERE processed_part_search MATCH ? '
    'UNION SELECT text_note_search.item_id AS doc FROM text_note_search '
    'WHERE text_note_search MATCH ? '
    "AND text_note_search.target IN ('processed_original', 'processed_text'))";
