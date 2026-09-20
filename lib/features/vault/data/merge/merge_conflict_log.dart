import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/util/clock.dart';
import 'package:sinapsis/core/util/id_generator.dart';
import 'package:sinapsis/features/vault/domain/merge/field_merge_rule.dart';

/// Los conflictos de fusión: los que ya hay, y cómo se guarda uno nuevo (F11).
///
/// Lo comparten los campos de los elementos y el texto de las formas: los dos
/// guardan la versión que no queda en vivo, y los dos tienen que no repetirla
/// si la misma copia se fusiona otra vez.
class MergeConflictLog {
  MergeConflictLog({
    required AppDatabase database,
    IdGenerator ids = const UuidV7Generator(),
    Clock clock = DateTime.now,
  }) : _db = database,
       _ids = ids,
       _clock = clock;

  final AppDatabase _db;
  final IdGenerator _ids;
  final Clock _clock;

  /// Las claves de los conflictos que esta bóveda ya tiene, resueltos o no. Se
  /// lee UNA vez por fusión: son pocos y se consultan muchas veces.
  Future<Set<String>> known() async {
    final rows = await _db.customSelect('''
      SELECT item_id, field_name, incoming_updated_at, incoming_device_id
        FROM main.merge_conflict''').get();
    return {
      for (final row in rows)
        key(
          row.read<String>('item_id'),
          row.read<String>('field_name'),
          row.read<int?>('incoming_updated_at'),
          row.read<String?>('incoming_device_id'),
        ),
    };
  }

  /// Qué identifica a un conflicto: el elemento, el campo y la versión de la
  /// copia que lo provocó. La misma versión de la copia contra lo de acá es el
  /// mismo conflicto, no otro.
  static String key(String item, String field, int? at, String? device) =>
      '$item\u0000$field\u0000$at\u0000$device';

  /// La clave del conflicto de [field] del elemento [itemId] provocado por la
  /// versión [incoming] de la copia.
  static String keyFor(String itemId, String field, FieldStamp? incoming) =>
      key(itemId, field, _at(incoming), incoming?.deviceId);

  static int? _at(FieldStamp? stamp) =>
      stamp == null ? null : seconds(stamp.updatedAt);

  /// Guarda el conflicto: las dos versiones, de quién era cada una y cuándo se
  /// detectó. La que queda en vivo ya se escribió; esto es la otra.
  ///
  /// En el texto de una forma no hay valores —puede ser un documento entero—:
  /// la versión de la copia es la forma [otherRenditionId].
  Future<void> record({
    required String itemId,
    required String field,
    String? localValue,
    String? incomingValue,
    String? otherRenditionId,
    FieldStamp? localStamp,
    FieldStamp? incomingStamp,
  }) => _db.customStatement(
    '''
    INSERT INTO main.merge_conflict (
      id, item_id, field_name, local_value, incoming_value, other_rendition_id,
      local_updated_at, local_device_id,
      incoming_updated_at, incoming_device_id, detected_at
    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)''',
    [
      _ids.next(),
      itemId,
      field,
      localValue,
      incomingValue,
      otherRenditionId,
      _at(localStamp),
      localStamp?.deviceId,
      _at(incomingStamp),
      incomingStamp?.deviceId,
      seconds(_clock()),
    ],
  );

  /// Los instantes se guardan como segundos desde 1970.
  static int seconds(DateTime at) => at.millisecondsSinceEpoch ~/ 1000;
}
