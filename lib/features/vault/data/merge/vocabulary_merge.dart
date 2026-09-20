import 'package:drift/drift.dart' show Variable;
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/util/id_generator.dart';
import 'package:sinapsis/features/vault/data/merge/incoming_vault.dart';
import 'package:sinapsis/features/vault/data/merge/merge_work.dart';

/// Cuánto entró del vocabulario.
class VocabularyResult {
  const VocabularyResult({
    this.definitions = 0,
    this.values = 0,
    this.aliases = 0,
    this.assignments = 0,
  });

  final int definitions;
  final int values;
  final int aliases;

  /// Asignaciones de una propiedad a un elemento.
  final int assignments;
}

/// Une el vocabulario de la copia —las propiedades, sus valores, sus alias y
/// lo que cada elemento tiene asignado— con el de esta bóveda (F11).
///
/// «Mismo identificador = mismo objeto» no alcanza acá:
/// `property_definitions.name` y los valores por definición son únicos SIN
/// distinguir mayúsculas, y los identificadores de «Tema» o «Fecha del hecho»
/// se siembran por bóveda —dos bóvedas tienen el «Tema» de cada una, con otro
/// identificador—. Unir por id dejaría dos «Tema», o chocaría con la
/// restricción. Por eso:
///
/// - una **definición** es la misma si tiene el mismo nombre;
/// - un **valor** es el mismo si tiene el mismo identificador —aunque la
///   etiqueta se haya cambiado en una de las bóvedas: la etiqueta de la copia
///   queda como alias, para que se siga encontrando por ella— o, si no, si
///   tiene la misma etiqueta dentro de la misma definición;
/// - lo que no coincide por ninguno de los dos entra tal cual.
///
/// Los alias y las asignaciones de la copia se escriben con los identificadores
/// de acá. Es una unión: no se quita ni se cambia nada de lo que hay.
///
/// Corre dentro de la transacción de la fusión, con la copia adjuntada, DESPUÉS
/// de los elementos.
class VocabularyMerge {
  VocabularyMerge({
    required AppDatabase database,
    IdGenerator ids = const UuidV7Generator(),
  }) : _db = database,
       _ids = ids;

  final AppDatabase _db;
  final IdGenerator _ids;

  static const _incoming = kIncomingSchema;

  static const _valueColumns = [
    'id',
    'definition_id',
    'value',
    'created_at',
    'number_value',
    'date_from_year',
    'date_from_month',
    'date_from_day',
    'date_to_year',
    'date_to_month',
    'date_to_day',
    'date_precision',
    'date_is_circa',
  ];

  Future<VocabularyResult> apply() async {
    final definitions = await _mapDefinitions();
    final values = await _mapValues();
    final aliases = await _addAliases();
    final assignments = await _db.customUpdate(
      '''
      INSERT OR IGNORE INTO main.item_property_values
        (item_id, property_value_id, origin)
      SELECT x.item_id, vm.local_id, x.origin
        FROM $_incoming.item_property_values x
        JOIN ${MergeWork.valueMap} vm ON vm.incoming_id = x.property_value_id
       WHERE EXISTS (SELECT 1 FROM main.item i WHERE i.id = x.item_id)''',
      updates: {_db.itemPropertyValues},
    );
    return VocabularyResult(
      definitions: definitions,
      values: values,
      aliases: aliases,
      assignments: assignments,
    );
  }

  /// Cuántos valores traería la copia que acá no hay, por identificador ni por
  /// etiqueta: lo que la vista previa cuenta sin escribir.
  static String newValuesSql() =>
      '''
      SELECT COUNT(*) FROM $_incoming.property_values v
       WHERE NOT EXISTS (
               SELECT 1 FROM main.property_values l WHERE l.id = v.id)
         AND NOT EXISTS (
               SELECT 1
                 FROM main.property_values l
                 JOIN main.property_definitions ld ON ld.id = l.definition_id
                 JOIN $_incoming.property_definitions d
                   ON d.id = v.definition_id
                  AND d.name = ld.name COLLATE NOCASE
                WHERE l.value = v.value COLLATE NOCASE)''';

  /// Mapea las definiciones de la copia a las de acá y agrega las que faltan.
  /// Devuelve cuántas agregó.
  Future<int> _mapDefinitions() async {
    await _db.customStatement('''
      INSERT INTO ${MergeWork.definitionMap} (incoming_id, local_id)
      SELECT d.id, l.id
        FROM $_incoming.property_definitions d
        JOIN main.property_definitions l ON l.name = d.name COLLATE NOCASE''');

    // Pocas —decenas—: una por una. Si su identificador ya lo usa OTRA
    // definición de acá, entra con uno nuevo.
    final missing = await _db.customSelect('''
      SELECT d.id AS id,
             EXISTS (SELECT 1 FROM main.property_definitions l
                      WHERE l.id = d.id) AS taken
        FROM $_incoming.property_definitions d
       WHERE d.id NOT IN (SELECT incoming_id FROM ${MergeWork.definitionMap})
       ORDER BY d.created_at, d.id''').get();
    for (final row in missing) {
      final incomingId = row.read<String>('id');
      final id = row.read<int>('taken') == 1 ? _ids.next() : incomingId;
      await _db.customStatement(
        '''
        INSERT INTO main.property_definitions
          (id, name, created_at, type, is_system)
        SELECT ?, x.name, x.created_at, x.type, x.is_system
          FROM $_incoming.property_definitions x WHERE x.id = ?''',
        [id, incomingId],
      );
      await _db.customStatement(
        'INSERT INTO ${MergeWork.definitionMap} (incoming_id, local_id) '
        'VALUES (?, ?)',
        [incomingId, id],
      );
    }
    return missing.length;
  }

  /// Mapea los valores de la copia a los de acá y agrega los que faltan.
  /// Devuelve cuántos agregó.
  Future<int> _mapValues() async {
    // El mismo identificador: el mismo valor.
    await _db.customStatement('''
      INSERT INTO ${MergeWork.valueMap} (incoming_id, local_id)
      SELECT v.id, l.id
        FROM $_incoming.property_values v
        JOIN main.property_values l ON l.id = v.id''');

    // La misma etiqueta dentro de la misma definición.
    await _db.customStatement('''
      INSERT OR IGNORE INTO ${MergeWork.valueMap} (incoming_id, local_id)
      SELECT v.id, l.id
        FROM $_incoming.property_values v
        JOIN ${MergeWork.definitionMap} dm ON dm.incoming_id = v.definition_id
        JOIN main.property_values l
          ON l.definition_id = dm.local_id
         AND l.value = v.value COLLATE NOCASE''');

    // El resto entra tal cual, en la definición de acá.
    final added = await _db.customUpdate(
      '''
      INSERT INTO main.property_values (${_valueColumns.join(', ')})
      SELECT ${_valueColumns.map((c) => c == 'definition_id' ? 'dm.local_id' : 'x.$c').join(', ')}
        FROM $_incoming.property_values x
        JOIN ${MergeWork.definitionMap} dm ON dm.incoming_id = x.definition_id
       WHERE x.id NOT IN (SELECT incoming_id FROM ${MergeWork.valueMap})''',
      updates: {_db.propertyValues},
    );
    await _db.customStatement(
      '''
      INSERT OR IGNORE INTO ${MergeWork.valueMap} (incoming_id, local_id)
      SELECT x.id, x.id FROM $_incoming.property_values x
       WHERE EXISTS (SELECT 1 FROM main.property_values l WHERE l.id = x.id)''',
    );
    return added;
  }

  /// Los alias de la copia, y la etiqueta de la copia de un valor que acá se
  /// llama distinto. Devuelve cuántos entraron.
  Future<int> _addAliases() async {
    var added = 0;

    // Mismo identificador y otra etiqueta: se cambió el nombre en una de las
    // bóvedas. La de la copia queda como alias —salvo que ya sea la etiqueta de
    // otro valor de la definición—.
    final renamed = await _db.customSelect('''
      SELECT v.id AS id
        FROM $_incoming.property_values v
        JOIN main.property_values l ON l.id = v.id
       WHERE l.value <> v.value COLLATE NOCASE
       ORDER BY v.id''').get();
    for (final row in renamed) {
      added += await _db.customUpdate(
        '''
        INSERT OR IGNORE INTO main.property_aliases
          (id, property_value_id, definition_id, alias, created_at)
        SELECT ?, l.id, l.definition_id, v.value, v.created_at
          FROM $_incoming.property_values v
          JOIN main.property_values l ON l.id = v.id
         WHERE v.id = ?
           AND NOT EXISTS (
                 SELECT 1 FROM main.property_values w
                  WHERE w.definition_id = l.definition_id
                    AND w.value = v.value COLLATE NOCASE)''',
        variables: [
          Variable<String>(_ids.next()),
          Variable<String>(row.read<String>('id')),
        ],
        updates: {_db.propertyAliases},
      );
    }

    // Los alias que la copia ya tenía, sobre el valor de acá que le
    // corresponde.
    final carried = await _db.customUpdate(
      '''
      INSERT OR IGNORE INTO main.property_aliases
        (id, property_value_id, definition_id, alias, created_at)
      SELECT a.id, vm.local_id, l.definition_id, a.alias, a.created_at
        FROM $_incoming.property_aliases a
        JOIN ${MergeWork.valueMap} vm ON vm.incoming_id = a.property_value_id
        JOIN main.property_values l ON l.id = vm.local_id
       WHERE NOT EXISTS (
               SELECT 1 FROM main.property_aliases m WHERE m.id = a.id)''',
      updates: {_db.propertyAliases},
    );
    return added + carried;
  }
}
