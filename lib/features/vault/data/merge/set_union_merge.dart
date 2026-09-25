import 'package:drift/drift.dart' show TableInfo;
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/features/vault/data/merge/incoming_vault.dart';
import 'package:sinapsis/features/vault/data/merge/merge_work.dart';

/// Cuánto entró de lo que se une por conjuntos.
class SetUnionResult {
  const SetUnionResult({
    this.relations = 0,
    this.highlights = 0,
    this.flashcards = 0,
    this.flashcardsUpdated = 0,
    this.reviews = 0,
    this.provenances = 0,
    this.conversations = 0,
    this.messages = 0,
    this.habitEvents = 0,
  });

  final int relations;
  final int highlights;
  final int flashcards;

  /// Tarjetas que ya estaban y cuyo calendario pasó a ser el de la copia.
  final int flashcardsUpdated;
  final int reviews;
  final int provenances;
  final int conversations;
  final int messages;

  /// El rastro mínimo de la racha (F17, D6).
  final int habitEvents;
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
];
const kHighlightColumns = [
  'id',
  'rendition_id',
  'start_offset',
  'end_offset',
  'excerpt',
  'note',
  'created_at',
];
const kFlashcardColumns = [
  'id',
  'item_id',
  'front',
  'back',
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
    // tienen que existir.
    final relations = await _union(
      _db.relations,
      'relations',
      kRelationColumns,
      '''
      FROM $_incoming.relations x
     WHERE ${_itemExists('x.from_item_id')} AND ${_itemExists('x.to_item_id')}
       AND NOT EXISTS (
         SELECT 1 FROM main.relations m
          WHERE m.id = x.id
             OR (m.from_item_id = x.from_item_id
                 AND m.to_item_id = x.to_item_id AND m.kind = x.kind))''',
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
    final flashcards = await _union(
      _db.flashcards,
      'flashcards',
      kFlashcardColumns,
      '''
      FROM $_incoming.flashcards x
     WHERE ${_itemExists('x.item_id')}
       AND NOT EXISTS (SELECT 1 FROM main.flashcards m WHERE m.id = x.id)''',
      select: {
        'source_chunk_id':
            'CASE WHEN EXISTS (SELECT 1 FROM main.chunks c '
            'WHERE c.id = x.source_chunk_id) THEN x.source_chunk_id END',
        'last_exported_at': 'NULL',
      },
    );

    // Una tarjeta que las dos tienen: el calendario es el del repaso más
    // reciente. El texto de la tarjeta no se toca.
    final flashcardsUpdated = await _db.customUpdate(
      '''
      UPDATE main.flashcards SET
        ease_factor = x.ease_factor,
        interval_days = x.interval_days,
        repetitions = x.repetitions,
        due_at = x.due_at,
        last_reviewed_at = x.last_reviewed_at
       FROM $_incoming.flashcards x
      WHERE x.id = flashcards.id
        AND x.last_reviewed_at IS NOT NULL
        AND (flashcards.last_reviewed_at IS NULL
             OR x.last_reviewed_at > flashcards.last_reviewed_at)''',
      updates: {_db.flashcards},
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

    return SetUnionResult(
      relations: relations,
      highlights: highlights,
      flashcards: flashcards,
      flashcardsUpdated: flashcardsUpdated,
      reviews: reviews,
      provenances: provenances,
      conversations: conversations,
      messages: messages,
      habitEvents: habitEvents,
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
