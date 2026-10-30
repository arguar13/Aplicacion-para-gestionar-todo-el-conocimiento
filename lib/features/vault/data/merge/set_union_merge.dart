import 'package:drift/drift.dart' show TableInfo;
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/features/vault/data/merge/ai_provenance_merge.dart';
import 'package:sinapsis/features/vault/data/merge/incoming_vault.dart';
import 'package:sinapsis/features/vault/data/merge/merge_work.dart';
import 'package:sinapsis/features/vault/data/merge/set_union_rules.dart';
import 'package:sinapsis/features/vault/data/merge/study_creations_merge.dart';
import 'package:sinapsis/features/vault/data/merge/text_notes_merge.dart';

/// Cuánto entró de lo que se une por conjuntos.
class SetUnionResult {
  const SetUnionResult({
    this.relations = 0,
    this.highlights = 0,
    this.flashcards = 0,
    this.flashcardsUpdated = 0,
    this.flashcardOptions = 0,
    this.reviews = 0,
    this.provenances = 0,
    this.conversations = 0,
    this.messages = 0,
    this.habitEvents = 0,
    this.studyMarks = 0,
    this.datedEvents = 0,
    this.processedDocuments = 0,
    this.processedParts = 0,
    this.processedOriginals = 0,
    this.processedImages = 0,
    this.studyCreations = 0,
    this.textNotes = 0,
  });

  final int relations;
  final int highlights;
  final int flashcards;

  /// Tarjetas que ya estaban y cuyo calendario pasó a ser el de la copia.
  final int flashcardsUpdated;

  /// Opciones de una tarjeta de opción múltiple (F20): entran junto con su
  /// tarjeta, nunca solas.
  final int flashcardOptions;
  final int reviews;
  final int provenances;
  final int conversations;
  final int messages;

  /// El rastro mínimo de la racha (F17, D6).
  final int habitEvents;

  /// Lo resaltado para estudiar un documento (F36).
  final int studyMarks;

  /// Los hechos fechados dentro de un documento (F40).
  final int datedEvents;

  /// Los documentos procesados (F41), sus partes, la copia de su original y
  /// sus imágenes.
  final int processedDocuments;
  final int processedParts;
  final int processedOriginals;
  final int processedImages;

  /// «Lo creado» de Estudiar (F43).
  final int studyCreations;

  /// Las notas en el texto (F45, mejora 19).
  final int textNotes;
}

/// Las columnas de cada tabla que se une, en el orden en que se copian. Un test
/// comprueba que cubren la tabla entera: una columna nueva que no esté acá no
/// viajaría en la fusión.
const kRelationColumns = [
  'id',
  'from_item_id',
  'to_item_id',
  'kind',
  'note',
  'created_at',
  'reviewed_at',
  'source_char_start',
  'source_char_end',
  // Quién lo hizo y en qué pasada de la IA (F27).
  'origin',
  'confidence',
  'ai_run_id',
];
const kHighlightColumns = [
  'id',
  'rendition_id',
  'start_offset',
  'end_offset',
  'excerpt',
  'note',
  'created_at',
  // Cómo se ve (F38).
  'color',
  'style',
];
const kStudyMarkColumns = [
  'id',
  'rendition_id',
  'kind',
  'origin',
  'start_offset',
  'end_offset',
  'excerpt',
  'created_at',
];
const kStudyAnalysisColumns = [
  'rendition_id',
  'analyzed_until',
  'completed_at',
  'updated_at',
];
const kDatedEventColumns = [
  'id',
  'item_id',
  'rendition_id',
  'title',
  'date_from_year',
  'date_from_month',
  'date_from_day',
  'date_precision',
  'date_is_circa',
  'date_end_year',
  'date_end_month',
  'date_end_day',
  'date_end_precision',
  'start_offset',
  'end_offset',
  'excerpt',
  'origin',
  'ai_run_id',
  'created_at',
  'updated_at',
];
const kProcessedDocumentColumns = [
  'item_id',
  'source_item_id',
  'source_kind',
  'created_at',
  // Hasta dónde se estudió su texto (v46): viaja con el documento que entra,
  // que entra con su texto.
  'study_analyzed_until',
  'study_completed_at',
];

/// Todas menos `row_key`: es la clave local que usa el índice de texto, y una
/// parte que entra recibe la suya.
const kProcessedPartColumns = [
  'id',
  'document_id',
  'section',
  'position',
  'content',
  'origin',
  'edited',
  'source_rendition_id',
  'source_start',
  'source_end',
  // Su lugar en el texto propio y los tramos de sus palabras clave (v46).
  'text_start',
  'text_end',
  'spans',
  'created_at',
  'updated_at',
];

/// La copia del original de un procesado (v46): su forma —con el archivo— ya
/// entró con las formas de los elementos.
const kProcessedOriginalColumns = [
  'document_id',
  'rendition_id',
  'source_file_path',
  'source_file_size',
  'text_hash',
  'copied_at',
];

/// Las imágenes de un procesado (v47, decisión L): su forma —con el archivo—
/// ya entró con las formas de los elementos.
const kProcessedImageColumns = [
  'rendition_id',
  'document_id',
  'position',
  'source_file_path',
  'source_file_size',
  'copied_at',
];

const kFlashcardColumns = [
  'id',
  'item_id',
  'front',
  'back',
  'kind',
  'ease_factor',
  'interval_days',
  'repetitions',
  'due_at',
  'created_at',
  'last_reviewed_at',
  'source_chunk_id',
  'source_char_start',
  'source_char_end',
  'last_exported_at',
  // Quién la hizo y en qué pasada de la IA (F27).
  'origin',
  'ai_run_id',
  // Pausada, pospuesta, en qué paso de aprendizaje va y con qué hermanas (F31).
  'suspended',
  'buried_until',
  'learning_step',
  'group_id',
  'cloze_index',
];
const kFlashcardOptionColumns = [
  'id',
  'flashcard_id',
  'content',
  'is_correct',
  'position',
  'source_chunk_id',
  'source_char_start',
  'source_char_end',
  'source_item_id',
];
const kReviewLogColumns = [
  'id',
  'flashcard_id',
  'reviewed_at',
  'grade',
  'quality',
  'interval_before',
  'interval_after',
  'ease_before',
  'ease_after',
  'device_id',
  // De qué etapa partió el repaso y lo necesario para deshacerlo (F31).
  'phase_before',
  'step_before',
  'step_after',
  'due_before',
  'last_reviewed_before',
  'repetitions_before',
];
const kProvenanceColumns = [
  'id',
  'item_id',
  'source_kind',
  'url',
  'author_name',
  'author_url',
  'published_at',
  'captured_at',
  'merged_at',
];
const kConversationColumns = [
  'id',
  'mode',
  'title',
  'notebook_id',
  'created_at',
  'updated_at',
];
const kChatMessageColumns = [
  'id',
  'conversation_id',
  'is_user',
  'content',
  'sources_json',
  'attachments_json',
  'error',
  'created_at',
];
const kHabitEventColumns = ['id', 'kind', 'occurred_at'];

/// Une lo que cuelga de los elementos y se junta sin decidir nada (F11): los
/// vínculos, los resaltados, las tarjetas y sus repasos, las procedencias y las
/// conversaciones.
///
/// Es una UNIÓN: entra lo que esta bóveda no tiene, por su identificador, y
/// nada se quita ni se cambia. Sin lápidas, una quita hecha en un lado puede
/// reaparecer al fusionar con una copia que todavía la tenía: es lo
/// conservador, y queda dicho.
///
/// Corre dentro de la transacción de la fusión, con la copia adjuntada, DESPUÉS
/// de los elementos y de sus formas (todo esto los referencia).
class SetUnionMerge {
  const SetUnionMerge(this._db);

  final AppDatabase _db;

  static const _incoming = kIncomingSchema;

  Future<SetUnionResult> apply() async {
    // Un vínculo es el mismo por su id o por unir lo mismo con el mismo tipo:
    // dos bóvedas pudieron crearlo cada una por su cuenta. Sus dos extremos
    // tienen que existir. Uno de la IA que acá alguien dijo que «no era» no
    // vuelve (F27), y su pasada se conserva solo si llegó con él.
    final relations = await _union(
      _db.relations,
      'relations',
      kRelationColumns,
      '''
      FROM $_incoming.relations x
     WHERE ${_itemExists('x.from_item_id')} AND ${_itemExists('x.to_item_id')}
       AND NOT ${AiProvenanceMerge.rejectedRelation('x')}
       AND NOT EXISTS (
         SELECT 1 FROM main.relations m
          WHERE m.id = x.id
             OR (m.from_item_id = x.from_item_id
                 AND m.to_item_id = x.to_item_id AND m.kind = x.kind))''',
      select: {'ai_run_id': AiProvenanceMerge.runOrNull('x.ai_run_id')},
    );

    // Uno de la IA que en la copia la persona adoptó —lo editó, y pasó a ser
    // suyo (F27)— es suyo también acá: si no, «deshacer todo» se lo llevaría
    // en este dispositivo. Solo la procedencia: el vínculo en sí no se toca,
    // como en toda la unión.
    await _db.customUpdate(
      '''
      UPDATE main.relations
         SET origin = 'user', confidence = NULL, ai_run_id = NULL
        FROM $_incoming.relations x
       WHERE x.id = relations.id
         AND x.origin = 'user' AND relations.origin = 'ai'
      ''',
      updates: {_db.relations},
    );

    // Las posiciones de un resaltado son de UN texto: si la forma de la copia
    // entró como otra (o ya estaba con otro identificador), van a esa; si no
    // hay dónde, no entran.
    final highlights = await _union(
      _db.highlights,
      'highlights',
      kHighlightColumns,
      '''
      FROM $_incoming.highlights x
      LEFT JOIN ${MergeWork.renditionMap} rm ON rm.incoming_id = x.rendition_id
     WHERE (rm.incoming_id IS NULL OR rm.local_id IS NOT NULL)
       AND EXISTS (
         SELECT 1 FROM main.renditions r
          WHERE r.id = COALESCE(rm.local_id, x.rendition_id))
       AND NOT EXISTS (SELECT 1 FROM main.highlights m WHERE m.id = x.id)''',
      select: {'rendition_id': 'COALESCE(rm.local_id, x.rendition_id)'},
    );

    // Los identificadores de los chunks no son estables —cambiar el texto los
    // rehace—: la tarjeta que apunta a uno que acá no existe conserva solo el
    // rango de caracteres, que es lo que usa «Ver en la fuente». Y
    // `last_exported_at` (F17, D4) es de ESTE dispositivo —cuándo exportó SU
    // .apkg, no un dato que viaje entre bóvedas—: una tarjeta que llega de
    // otra bóveda nunca se exportó desde acá, así que entra en null y no con
    // lo que diga la incoming, o la próxima exportación incremental la
    // saltearía creyendo que ya está en el Anki de este dispositivo.
    // Una de la IA que acá alguien dijo que «no era» no vuelve (F27).
    //
    // Pausada, pospuesta y en qué paso de aprendizaje va (F31): `suspended`
    // viaja con la tarjeta, porque quien la pausó en la otra bóveda no la
    // quería ver acá tampoco; `buried_until` NO: es un «hoy no» de un
    // dispositivo, y a la tarjeta que llega le toca estudiarse cuando le toque.
    final flashcards = await _union(
      _db.flashcards,
      'flashcards',
      kFlashcardColumns,
      '''
      FROM $_incoming.flashcards x
     WHERE ${_itemExists('x.item_id')}
       AND NOT ${AiProvenanceMerge.rejectedFlashcard('x')}
       AND NOT EXISTS (SELECT 1 FROM main.flashcards m WHERE m.id = x.id)''',
      select: {
        'source_chunk_id':
            'CASE WHEN EXISTS (SELECT 1 FROM main.chunks c '
            'WHERE c.id = x.source_chunk_id) THEN x.source_chunk_id END',
        'last_exported_at': 'NULL',
        'buried_until': 'NULL',
        'ai_run_id': AiProvenanceMerge.runOrNull('x.ai_run_id'),
      },
    );

    // Una de la IA que en la copia la persona adoptó es suya también acá,
    // mismo motivo que los vínculos (F27). El texto de la tarjeta no se toca.
    await _db.customUpdate(
      '''
      UPDATE main.flashcards SET origin = 'user', ai_run_id = NULL
        FROM $_incoming.flashcards x
       WHERE x.id = flashcards.id
         AND x.origin = 'user' AND flashcards.origin = 'ai'
      ''',
      updates: {_db.flashcards},
    );

    // Una tarjeta que las dos tienen: el calendario es el del repaso más
    // reciente, con su paso de aprendizaje (F31): el paso va con la fecha, o
    // una tarjeta quedaría «aprendiéndose» con la fecha de un repaso en días.
    // El texto de la tarjeta, si está pausada y si está pospuesta no se tocan:
    // son decisiones de quien la usa en cada lugar.
    final flashcardsUpdated = await _db.customUpdate(
      '''
      UPDATE main.flashcards SET
        ease_factor = x.ease_factor,
        interval_days = x.interval_days,
        repetitions = x.repetitions,
        learning_step = x.learning_step,
        due_at = x.due_at,
        last_reviewed_at = x.last_reviewed_at
       FROM $_incoming.flashcards x
      WHERE x.id = flashcards.id
        AND x.last_reviewed_at IS NOT NULL
        AND (flashcards.last_reviewed_at IS NULL
             OR x.last_reviewed_at > flashcards.last_reviewed_at)''',
      updates: {_db.flashcards},
    );

    // Las opciones de una tarjeta de opción múltiple (F20) entran junto con
    // su tarjeta: si la tarjeta no llegó —por ejemplo, esta bóveda ya la
    // tenía y no es de opción múltiple— sus opciones tampoco. Mismo criterio
    // que `source_chunk_id` de la tarjeta, más arriba: se conserva solo si
    // por coincidencia ya existe localmente.
    final flashcardOptions = await _union(
      _db.flashcardOptions,
      'flashcard_options',
      kFlashcardOptionColumns,
      '''
      FROM $_incoming.flashcard_options x
     WHERE EXISTS (SELECT 1 FROM main.flashcards f WHERE f.id = x.flashcard_id)
       AND NOT EXISTS (
         SELECT 1 FROM main.flashcard_options m WHERE m.id = x.id)''',
      select: {
        'source_chunk_id':
            'CASE WHEN EXISTS (SELECT 1 FROM main.chunks c '
            'WHERE c.id = x.source_chunk_id) THEN x.source_chunk_id END',
        'source_item_id':
            'CASE WHEN ${_itemExists('x.source_item_id')} '
            'THEN x.source_item_id END',
      },
    );

    final reviews = await _union(
      _db.reviewLogs,
      'review_log',
      kReviewLogColumns,
      '''
      FROM $_incoming.review_log x
     WHERE EXISTS (SELECT 1 FROM main.flashcards f WHERE f.id = x.flashcard_id)
       AND NOT EXISTS (SELECT 1 FROM main.review_log m WHERE m.id = x.id)''',
    );

    final provenances = await _union(
      _db.mergedProvenances,
      'merged_provenances',
      kProvenanceColumns,
      '''
      FROM $_incoming.merged_provenances x
     WHERE ${_itemExists('x.item_id')}
       AND NOT EXISTS (
         SELECT 1 FROM main.merged_provenances m WHERE m.id = x.id)''',
    );

    // Los cuadernos son de un dispositivo (F16): no viajan en la fusión, así
    // que casi ningún `notebook_id` de la copia va a existir acá. Igual que
    // `source_chunk_id` más arriba, se conserva solo si por coincidencia ya
    // existe localmente; si no, la conversación entra sin acotar en vez de
    // dejar una clave rota.
    final conversations = await _union(
      _db.conversations,
      'conversations',
      kConversationColumns,
      '''
      FROM $_incoming.conversations x
     WHERE NOT EXISTS (SELECT 1 FROM main.conversations m WHERE m.id = x.id)''',
      select: {
        'notebook_id':
            'CASE WHEN EXISTS (SELECT 1 FROM main.notebook n '
            'WHERE n.id = x.notebook_id) THEN x.notebook_id END',
      },
    );
    // Una conversación que las dos tienen: queda la fecha más reciente.
    await _db.customUpdate(
      '''
      UPDATE main.conversations SET updated_at = x.updated_at
        FROM $_incoming.conversations x
       WHERE x.id = conversations.id AND x.updated_at > conversations.updated_at''',
      updates: {_db.conversations},
    );

    final messages = await _union(
      _db.chatMessages,
      'chat_messages',
      kChatMessageColumns,
      '''
      FROM $_incoming.chat_messages x
     WHERE EXISTS (
             SELECT 1 FROM main.conversations c WHERE c.id = x.conversation_id)
       AND NOT EXISTS (SELECT 1 FROM main.chat_messages m WHERE m.id = x.id)''',
    );

    // Sin ninguna referencia a otra tabla —solo dice que algo pasó, y
    // cuándo (F17, D6)—: entra igual que review_log, por id.
    final habitEvents = await _union(
      _db.habitEvents,
      'habit_event',
      kHabitEventColumns,
      '''
      FROM $_incoming.habit_event x
     WHERE NOT EXISTS (SELECT 1 FROM main.habit_event m WHERE m.id = x.id)''',
    );

    // Lo resaltado para estudiar un documento (F36), como los subrayados: a
    // la forma que le toca. Pero un análisis es uno solo: si acá ya se analizó
    // ese texto, queda el de acá —sumar el de la copia mezclaría dos
    // resúmenes—, y de la copia entran solo las palabras clave que alguien
    // eligió a mano. Si acá no se analizó, entra el de la copia entero, con
    // hasta dónde llegaba. Las marcas van antes que el análisis: la condición
    // mira si acá había uno.
    const renditionOf = SetUnionRules.studyRenditionOf;
    final studyMarks = await _union(
      _db.studyMarks,
      'study_marks',
      kStudyMarkColumns,
      SetUnionRules.studyMarksFrom(),
      select: {'rendition_id': renditionOf},
    );
    await _union(
      _db.studyAnalyses,
      'study_analyses',
      kStudyAnalysisColumns,
      '''
      FROM $_incoming.study_analyses x
      ${SetUnionRules.studyRenditionJoin()}
       AND NOT EXISTS (
         SELECT 1 FROM main.study_analyses a
          WHERE a.rendition_id = $renditionOf)''',
      select: {'rendition_id': renditionOf},
    );

    // Los hechos fechados (F40). Un hecho es de un elemento, no de un texto: si
    // el texto de su cita no llegó —entró como otro, o acá no está—, el hecho
    // entra igual, con su fecha, su título y su fragmento, pero sin la
    // posición, que es de UN texto. Es el mismo hecho si tiene el mismo id, o
    // la misma fecha y la misma cita en el mismo elemento (dos dispositivos
    // pudieron leerlo cada uno por su cuenta); sin cita, el mismo título. Uno
    // de la IA que acá alguien dijo que «no era» no vuelve, y su pasada se
    // conserva solo si llegó con él.
    final datedEvents = await _union(
      _db.datedEvents,
      'dated_events',
      kDatedEventColumns,
      SetUnionRules.datedEventsFrom(),
      select: {
        'rendition_id': 'lr.id',
        'start_offset': 'CASE WHEN lr.id IS NOT NULL THEN x.start_offset END',
        'end_offset': 'CASE WHEN lr.id IS NOT NULL THEN x.end_offset END',
        'ai_run_id': AiProvenanceMerge.runOrNull('x.ai_run_id'),
      },
    );

    // Uno de la IA que en la copia la persona adoptó es suyo también acá, mismo
    // motivo que los vínculos (F27). Su título y sus fechas no se tocan.
    await _db.customUpdate(
      '''
      UPDATE main.dated_events SET origin = 'user', ai_run_id = NULL
        FROM $_incoming.dated_events x
       WHERE x.id = dated_events.id
         AND x.origin = 'user' AND dated_events.origin = 'ai'
      ''',
      updates: {_db.datedEvents},
    );

    // Los documentos procesados (F41): el elemento de cada uno ya entró con los
    // demás. El mismo id es el mismo procesado —sale de su fuente—, así que dos
    // dispositivos que procesaron la misma fuente se juntan acá en vez de
    // chocar con «uno por fuente».
    final processedDocuments = await _union(
      _db.processedDocuments,
      'processed_documents',
      kProcessedDocumentColumns,
      SetUnionRules.processedDocumentsFrom,
      select: {'source_item_id': SetUnionRules.processedSourceOf},
    );
    // Uno que acá perdió su fuente —se borró de verdad— y que en la copia la
    // tiene vuelve a enlazarse, si la fuente volvió con la fusión.
    await _db.customUpdate(
      '''
      UPDATE main.processed_documents
         SET source_item_id = ${SetUnionRules.processedSourceOf}
        FROM $_incoming.processed_documents x
       WHERE x.item_id = processed_documents.item_id
         AND processed_documents.source_item_id IS NULL
         AND x.source_item_id IS NOT NULL
      ''',
      updates: {_db.processedDocuments},
    );

    // Sus partes, sumadas sin repetir: lo de la copia, después de lo de acá en
    // cada sección, en su orden. El ancla va a la forma que le toca, o se
    // queda sin enlace (con sus posiciones) si esa forma no llegó.
    final processedParts = await _union(
      _db.processedParts,
      'processed_parts',
      kProcessedPartColumns,
      SetUnionRules.processedPartsFrom(),
      select: {
        'source_rendition_id': 'lr.id',
        'position':
            'x.position + COALESCE((SELECT MAX(m.position) + 1 '
            'FROM main.processed_parts m WHERE m.document_id = x.document_id '
            'AND m.section = x.section), 0)',
        // Su lugar en el texto propio es el del texto de la copia: vale acá
        // solo si ese texto es el que entra —acá no había—. Si no, la parte
        // entra sin lugar y se vuelve a ubicar la próxima vez que se procese.
        'text_start': SetUnionRules.processedTextPlaceOf('x.text_start'),
        'text_end': SetUnionRules.processedTextPlaceOf('x.text_end'),
      },
    );

    // La copia del original de un procesado (decisión H): su forma, con el
    // archivo, ya entró —o no, si acá se había soltado—; sin su forma no hay
    // copia que anotar. Un procesado tiene una sola.
    final processedOriginals = await _union(
      _db.processedOriginals,
      'processed_originals',
      kProcessedOriginalColumns,
      SetUnionRules.processedOriginalsFrom,
    );

    // Sus imágenes (decisión L): su forma, con el archivo, ya entró —o no, si
    // acá se había soltado—; sin su forma no hay copia que anotar. Las de la
    // copia van después de las de acá, en su orden.
    final processedImages = await _union(
      _db.processedImages,
      'processed_images',
      kProcessedImageColumns,
      SetUnionRules.processedImagesFrom,
      select: {
        'position':
            'x.position + COALESCE((SELECT MAX(m.position) + 1 '
            'FROM main.processed_images m '
            'WHERE m.document_id = x.document_id), 0)',
      },
    );

    // «Lo creado» (F43): entra lo que acá no hay, por id. Lo que en la copia
    // esperaba en la cola o se estaba generando entra fallido por
    // interrumpido —con «Reintentar»—: generarlo solo acá gastaría la cuota de
    // la persona sin que lo haya pedido en este dispositivo.
    final studyCreations = await _union(
      _db.studyCreations,
      'study_creations',
      kStudyCreationColumns,
      SetUnionRules.studyCreationsFrom,
      select: SetUnionRules.studyCreationIncomingColumns,
    );
    // Una que las dos tienen: la versión tocada más tarde (ver
    // [StudyCreationsMerge]).
    await StudyCreationsMerge(_db).adoptNewer();

    // Las notas en el texto (F45, mejora 19): después de lo creado, que puede
    // ser su dueño. Entra lo que acá no hay, por id, y de una que las dos
    // tienen queda lo editado más tarde (ver [TextNotesMerge]).
    final textNotes = await _union(
      _db.textNotes,
      'text_notes',
      kTextNoteColumns,
      TextNotesMerge.from(),
      select: {'rendition_id': TextNotesMerge.renditionOf},
    );
    await TextNotesMerge(_db).adoptNewer();

    return SetUnionResult(
      relations: relations,
      highlights: highlights,
      flashcards: flashcards,
      flashcardsUpdated: flashcardsUpdated,
      flashcardOptions: flashcardOptions,
      reviews: reviews,
      provenances: provenances,
      conversations: conversations,
      messages: messages,
      habitEvents: habitEvents,
      studyMarks: studyMarks,
      datedEvents: datedEvents,
      processedDocuments: processedDocuments,
      processedParts: processedParts,
      processedOriginals: processedOriginals,
      processedImages: processedImages,
      studyCreations: studyCreations,
      textNotes: textNotes,
    );
  }

  /// Inserta en [table] lo que [from] selecciona de la copia —con el alias
  /// `x`—. Cada columna se copia tal cual salvo las de [select], que traen su
  /// propia expresión. Devuelve cuántas filas entraron.
  Future<int> _union(
    TableInfo<dynamic, dynamic> info,
    String table,
    List<String> columns,
    String from, {
    Map<String, String> select = const {},
  }) => _db.customUpdate(
    '''
    INSERT INTO main.$table (${columns.join(', ')})
    SELECT ${columns.map((c) => select[c] ?? 'x.$c').join(', ')}
    $from''',
    updates: {info},
  );

  /// Que el elemento [column] exista acá —vivo o en la papelera—: por eso mira
  /// `item` y no ningún filtro de lo activo.
  static String _itemExists(String column) =>
      'EXISTS (SELECT 1 FROM main.item i WHERE i.id = $column)';
}
