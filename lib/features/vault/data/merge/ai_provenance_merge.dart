import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/features/vault/data/merge/incoming_vault.dart';

/// Cuánto entró de las pasadas de la IA y de lo que «no era» (F27).
class AiProvenanceResult {
  const AiProvenanceResult({this.runs = 0, this.rejections = 0});

  final int runs;
  final int rejections;
}

/// Las columnas de cada tabla que se une, en el orden en que se copian. Un test
/// comprueba que cubren la tabla entera: una columna nueva que no esté acá no
/// viajaría en la fusión.
const kAiRunColumns = [
  'id',
  'item_id',
  'model',
  'started_at',
  'finished_at',
  'undone_at',
  'relations_created',
  'flashcards_created',
  'properties_created',
];
const kAiRejectionColumns = [
  'id',
  'kind',
  'item_id',
  'other_item_id',
  'fingerprint',
  'subject_id',
  'created_at',
];

/// Une las pasadas de la IA y la memoria de lo que «no era» (F27).
///
/// Corre ANTES del vocabulario y de lo que se une por conjuntos: los vínculos,
/// las tarjetas y las propiedades de la copia apuntan a sus pasadas, y esas
/// pasadas tienen que estar acá para que lo que llega de otro dispositivo se
/// pueda deshacer en este. Y lo que «no era» tiene que estar antes que lo que
/// la IA hizo: es la lápida que impide que una copia vieja devuelva lo que la
/// persona ya descartó (ver `SetUnionMerge` y `VocabularyMerge`).
///
/// Es una UNIÓN, como el resto: entra lo que acá no hay, por su identificador
/// —y, para lo que «no era», también por su clave—, y nada se quita ni se
/// cambia. Una pasada deshecha en un lado y no en el otro no se deshace sola
/// al fusionar: lo de la IA que todavía está acá sigue estando.
class AiProvenanceMerge {
  const AiProvenanceMerge(this._db);

  final AppDatabase _db;

  static const _incoming = kIncomingSchema;

  Future<AiProvenanceResult> apply() async {
    final runs = await _db.customUpdate(
      '''
      INSERT INTO main.ai_runs (${kAiRunColumns.join(', ')})
      SELECT ${kAiRunColumns.map((c) => 'x.$c').join(', ')}
        FROM $_incoming.ai_runs x
       WHERE ${_itemExists('x.item_id')}
         AND NOT EXISTS (SELECT 1 FROM main.ai_runs m WHERE m.id = x.id)''',
      updates: {_db.aiRuns},
    );

    // Lo mismo se recuerda una vez: por su id o por su clave. Un vínculo
    // necesita sus dos extremos acá.
    final rejections = await _db.customUpdate(
      '''
      INSERT INTO main.ai_rejections (${kAiRejectionColumns.join(', ')})
      SELECT ${kAiRejectionColumns.map((c) => 'x.$c').join(', ')}
        FROM $_incoming.ai_rejections x
       WHERE ${_itemExists('x.item_id')}
         AND (x.other_item_id IS NULL OR ${_itemExists('x.other_item_id')})
         AND NOT EXISTS (
           SELECT 1 FROM main.ai_rejections m
            WHERE m.id = x.id
               OR (m.kind = x.kind AND m.item_id = x.item_id
                   AND m.fingerprint = x.fingerprint))''',
      updates: {_db.aiRejections},
    );

    return AiProvenanceResult(runs: runs, rejections: rejections);
  }

  /// La pasada [column] de la copia, si existe acá; si no, nula. Lo que la IA
  /// hizo y llega sin su pasada sigue siendo de la IA —se puede borrar uno por
  /// uno—, pero no se deshace en bloque.
  static String runOrNull(String column) =>
      'CASE WHEN EXISTS (SELECT 1 FROM main.ai_runs r WHERE r.id = $column) '
      'THEN $column END';

  /// Que el vínculo de la copia, con el alias [x], sea uno de la IA que la
  /// persona dijo que «no era»: la misma fila, por su id, o el mismo par y
  /// tipo, con la clave de `relationRejectionKey`. Mira las dos bases para
  /// que la vista previa —que corre antes de unir nada— cuente lo mismo que
  /// la fusión.
  static String rejectedRelation(String x) => _rejectedIn(
    'relation',
    '(j.subject_id = $x.id '
        'OR (j.item_id = MIN($x.from_item_id, $x.to_item_id) '
        'AND j.fingerprint = '
        "MAX($x.from_item_id, $x.to_item_id) || ':' || $x.kind))",
    origin: '$x.origin',
  );

  /// Que la tarjeta de la copia, con el alias [x], sea una de la IA que la
  /// persona dijo que «no era». Por su id: la huella de la pregunta pliega
  /// acentos y no se puede armar en SQL, pero la misma tarjeta que vuelve de
  /// una copia vieja trae el mismo id.
  static String rejectedFlashcard(String x) =>
      _rejectedIn('flashcard', 'j.subject_id = $x.id', origin: '$x.origin');

  /// Que la propiedad de la copia, con el alias [x], sea una de la IA que la
  /// persona dijo que «no era» en ese elemento: por el valor de la copia o el
  /// de acá al que se mapeó ([localValueId]).
  static String rejectedProperty(String x, {required String localValueId}) =>
      _rejectedIn(
        'property',
        'j.item_id = $x.item_id '
            'AND j.subject_id IN ($x.property_value_id, $localValueId)',
        origin: '$x.origin',
      );

  static String _rejectedIn(
    String kind,
    String matches, {
    required String origin,
  }) =>
      "($origin = 'ai' AND ( "
      'EXISTS (SELECT 1 FROM main.ai_rejections j '
      "WHERE j.kind = '$kind' AND $matches) OR "
      'EXISTS (SELECT 1 FROM $_incoming.ai_rejections j '
      "WHERE j.kind = '$kind' AND $matches)))";

  static String _itemExists(String column) =>
      'EXISTS (SELECT 1 FROM main.item i WHERE i.id = $column)';
}
