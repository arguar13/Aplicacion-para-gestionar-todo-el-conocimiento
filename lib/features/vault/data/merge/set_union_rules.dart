import 'package:sinapsis/features/vault/data/merge/ai_provenance_merge.dart';
import 'package:sinapsis/features/vault/data/merge/incoming_vault.dart';
import 'package:sinapsis/features/vault/data/merge/merge_work.dart';

/// Qué filas de la copia entran en la unión por conjuntos y cuáles ya estaban
/// (F40).
///
/// Una sola fuente de la regla para quien escribe —`SetUnionMerge`— y para
/// quien cuenta sin escribir —la vista previa, `VaultMergeReader`—: si cada
/// uno tuviera su copia del `WHERE`, lo que la vista previa dice y lo que la
/// fusión hace terminarían discrepando, y la vista previa dejaría de ser una
/// promesa. Cada método devuelve el `FROM … WHERE` que, desde la tabla de la
/// copia con el alias `x`, deja solo lo que entra.
abstract final class SetUnionRules {
  static const _incoming = kIncomingSchema;

  /// El mapa de formas con el que se cuenta sin escribir: una tabla con ese
  /// nombre que arma quien cuenta, con `WITH` (ver [dryRunRenditionMapCte]).
  /// Es en lugar de [MergeWork.renditionMap], que es una tabla temporal de la
  /// fusión: una vista previa no crea nada en la conexión.
  static const dryRunRenditionMap = 'dry_run_rendition_map';

  /// El `WITH` que arma [dryRunRenditionMap] a partir de un único parámetro:
  /// el JSON `{ "id en la copia": "id de acá" | null }`.
  static const dryRunRenditionMapCte =
      'WITH $dryRunRenditionMap (incoming_id, local_id) AS MATERIALIZED '
      '(SELECT key, value FROM json_each(?))';

  static String _map(bool dryRun) =>
      dryRun ? dryRunRenditionMap : MergeWork.renditionMap;

  /// La forma de texto de acá a la que va una fila de estudio de la copia: la
  /// que el mapa de la fusión diga, o la misma si el mapa no la nombra.
  static const studyRenditionOf = 'COALESCE(rm.local_id, x.rendition_id)';

  /// El `LEFT JOIN … WHERE` que ubica una fila de estudio de la copia en una
  /// forma de acá: las posiciones son de UN texto, así que si la forma de la
  /// copia no tiene dónde ponerse, la fila no entra. Lo usan las marcas y los
  /// análisis.
  ///
  /// [dryRun] es para contar sin escribir: las formas de los elementos nuevos
  /// todavía no están acá, así que «hay dónde» se lee de la copia —la forma va
  /// a entrar con su mismo id— o del mapa. Lo demás es idéntico.
  static String studyRenditionJoin({bool dryRun = false}) {
    final lands = dryRun
        ? '(rm.local_id IS NOT NULL OR EXISTS (SELECT 1 '
              'FROM $_incoming.renditions r '
              'WHERE r.id = x.rendition_id))'
        : 'EXISTS (SELECT 1 FROM main.renditions r '
              'WHERE r.id = $studyRenditionOf)';
    return '''
      LEFT JOIN ${_map(dryRun)} rm ON rm.incoming_id = x.rendition_id
     WHERE (rm.incoming_id IS NULL OR rm.local_id IS NOT NULL)
       AND $lands''';
  }

  /// Las marcas de estudio (F36) que entran.
  ///
  /// Es la misma marca si tiene el mismo id o marca lo mismo —tipo y
  /// posiciones— en la misma forma. Y las que puso la IA entran solo si acá
  /// ese texto no se analizó: un análisis es uno solo, y sumar el de la copia
  /// mezclaría dos resúmenes.
  static String studyMarksFrom({bool dryRun = false}) =>
      '''
      FROM $_incoming.study_marks x
      ${studyRenditionJoin(dryRun: dryRun)}
       AND NOT EXISTS (SELECT 1 FROM main.study_marks m WHERE m.id = x.id)
       AND NOT EXISTS (
         SELECT 1 FROM main.study_marks m
          WHERE m.rendition_id = $studyRenditionOf AND m.kind = x.kind
            AND m.start_offset = x.start_offset
            AND m.end_offset = x.end_offset)
       AND (x.origin = 'user' OR NOT EXISTS (
         SELECT 1 FROM main.study_analyses a
          WHERE a.rendition_id = $studyRenditionOf))''';

  /// Los hechos fechados (F40) que entran —con `lr` como la forma de texto de
  /// acá donde cae su cita, si cae—.
  ///
  /// Un hecho es de un elemento, no de un texto: si el texto de su cita no
  /// llegó, el hecho entra igual, con su fecha, su título y su fragmento, pero
  /// sin la posición. Es el mismo si tiene el mismo id, o la misma fecha y la
  /// misma cita en el mismo elemento (dos dispositivos pudieron leerlo cada
  /// uno por su cuenta); sin cita, el mismo título. Uno de la IA que acá
  /// alguien dijo que «no era» no vuelve. Nada de esto depende de dónde caiga
  /// la cita: contar y escribir dan lo mismo con o sin el mapa de formas.
  ///
  /// [dryRun] es para contar sin escribir: los elementos nuevos todavía no
  /// están acá, así que «el elemento existe» se lee de la copia, cuyos
  /// elementos entran todos.
  static String datedEventsFrom({bool dryRun = false}) =>
      '''
      FROM $_incoming.dated_events x
      LEFT JOIN ${_map(dryRun)} rm ON rm.incoming_id = x.rendition_id
      LEFT JOIN main.renditions lr
             ON lr.id = COALESCE(rm.local_id, x.rendition_id)
            AND (rm.incoming_id IS NULL OR rm.local_id IS NOT NULL)
     WHERE EXISTS (
             SELECT 1 FROM ${dryRun ? _incoming : 'main'}.item i
              WHERE i.id = x.item_id)
       AND NOT ${AiProvenanceMerge.rejectedDatedEvent('x')}
       AND NOT EXISTS (SELECT 1 FROM main.dated_events m WHERE m.id = x.id)
       AND NOT EXISTS (
         SELECT 1 FROM main.dated_events m
          WHERE m.item_id = x.item_id
            AND m.date_from_year = x.date_from_year
            AND m.date_from_month = x.date_from_month
            AND m.date_from_day = x.date_from_day
            AND m.date_precision = x.date_precision
            AND (m.excerpt = x.excerpt
                 OR (x.excerpt IS NULL AND m.excerpt IS NULL
                     AND m.title = x.title COLLATE NOCASE)))''';

  /// La fuente de un documento procesado de la copia (F41), si puede quedar
  /// enlazado a ella acá: la fuente existe —viva o en la papelera— y ningún
  /// procesado de acá es el de esa fuente (uno por fuente). Si no, entra sin
  /// enlace: su texto es suyo y no se pierde. Con los ids que salen de la
  /// fuente (`processedDocumentIdFor`) el choque no ocurre; queda cubierto por
  /// si una copia lo trae igual. El propio documento nunca cuenta como «otro»:
  /// al entrar todavía no está acá, y al re-enlazarse no tiene fuente.
  static const processedSourceOf =
      'CASE WHEN EXISTS (SELECT 1 FROM main.item i '
      'WHERE i.id = x.source_item_id) '
      'AND NOT EXISTS (SELECT 1 FROM main.processed_documents m '
      'WHERE m.source_item_id = x.source_item_id) '
      'THEN x.source_item_id END';

  /// Los documentos procesados (F41) que entran: los de la copia que acá no
  /// están. Su elemento ya entró con los demás —o ya estaba: el mismo id es el
  /// mismo procesado—.
  static const processedDocumentsFrom =
      '''
      FROM $_incoming.processed_documents x
     WHERE EXISTS (SELECT 1 FROM main.item i WHERE i.id = x.item_id)
       AND NOT EXISTS (
         SELECT 1 FROM main.processed_documents m WHERE m.item_id = x.item_id)''';

  /// [column] —el lugar de una parte de la copia en el texto propio de su
  /// procesado (v46)— si vale acá: es una página, o el procesado no tenía
  /// sección «Texto» y entra la de la copia, así que el texto es el mismo. Se
  /// mira antes de escribir nada: `INSERT … SELECT` arma lo que inserta
  /// primero.
  static String processedTextPlaceOf(String column) =>
      "CASE WHEN x.section = 'text' OR NOT EXISTS ( "
      'SELECT 1 FROM main.processed_parts mt '
      "WHERE mt.document_id = x.document_id AND mt.section = 'text') "
      'THEN $column END';

  /// La copia del original de los procesados (v46) que entra: la de la copia,
  /// si su forma está acá y el procesado todavía no tiene una.
  static const processedOriginalsFrom =
      '''
      FROM $_incoming.processed_originals x
     WHERE EXISTS (
             SELECT 1 FROM main.processed_documents d
              WHERE d.item_id = x.document_id)
       AND EXISTS (SELECT 1 FROM main.renditions r WHERE r.id = x.rendition_id)
       AND NOT EXISTS (
         SELECT 1 FROM main.processed_originals m
          WHERE m.document_id = x.document_id OR m.rendition_id = x.rendition_id)''';

  /// Las partes de documentos procesados (F41) que entran —con `lr` como la
  /// forma de texto de acá donde cae su ancla, si cae—.
  ///
  /// - Es la misma parte si tiene el mismo id, o el mismo texto en la misma
  ///   sección del mismo documento: dos dispositivos pudieron copiar lo mismo
  ///   cada uno por su cuenta.
  /// - El texto de un documento es uno solo: si acá ya tiene su sección
  ///   «Texto», la de la copia no entra —sumarla lo repetiría entero, o
  ///   mezclaría dos versiones página por página—. Lo demás se suma.
  /// - El ancla va a la forma que le toca, como la cita de un hecho fechado; si
  ///   no llegó, la parte entra igual, con su texto y sus posiciones, sin el
  ///   enlace.
  ///
  /// [dryRun] es para contar sin escribir: los documentos nuevos todavía no
  /// están acá, así que «el documento existe» se lee de la copia.
  static String processedPartsFrom({bool dryRun = false}) =>
      '''
      FROM $_incoming.processed_parts x
      LEFT JOIN ${_map(dryRun)} rm ON rm.incoming_id = x.source_rendition_id
      LEFT JOIN main.renditions lr
             ON lr.id = COALESCE(rm.local_id, x.source_rendition_id)
            AND (rm.incoming_id IS NULL OR rm.local_id IS NOT NULL)
     WHERE EXISTS (
             SELECT 1 FROM ${dryRun ? _incoming : 'main'}.processed_documents d
              WHERE d.item_id = x.document_id)
       AND NOT EXISTS (SELECT 1 FROM main.processed_parts m WHERE m.id = x.id)
       AND NOT EXISTS (
         SELECT 1 FROM main.processed_parts m
          WHERE m.document_id = x.document_id AND m.section = x.section
            AND m.content = x.content)
       AND (x.section <> 'text' OR NOT EXISTS (
         SELECT 1 FROM main.processed_parts m
          WHERE m.document_id = x.document_id AND m.section = 'text'))''';
}
