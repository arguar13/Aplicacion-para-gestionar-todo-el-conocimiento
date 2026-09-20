import 'package:drift/drift.dart' show QueryRow;
import 'package:sinapsis/features/vault/domain/merge/field_merge_rule.dart';

/// Cómo se piden y se leen las versiones de un campo en las consultas de la
/// fusión (F11): las dos —la de acá y la de la copia— más las del elemento
/// entero, con los mismos nombres de columna, para que quien decide un campo y
/// quien decide el texto de una forma lean lo mismo de la misma manera.
abstract final class StampRows {
  /// Las columnas a pedir. [localVersion] e [incomingVersion] son los alias de
  /// las filas de `field_version` de cada lado (unidas con LEFT JOIN: sin fila,
  /// el campo no tiene versión); [localItem] e [incomingItem], los de las filas
  /// de `item`.
  static String columns({
    required String localVersion,
    required String incomingVersion,
    required String localItem,
    required String incomingItem,
  }) =>
      '''
      $localVersion.updated_at AS l_at, $localVersion.device_id AS l_dev,
      $localVersion.base_updated_at AS l_base_at,
      $localVersion.base_device_id AS l_base_dev,
      $incomingVersion.updated_at AS i_at, $incomingVersion.device_id AS i_dev,
      $incomingVersion.base_updated_at AS i_base_at,
      $incomingVersion.base_device_id AS i_base_dev,
      $localItem.updated_at AS l_item_at, $localItem.device_id AS l_item_dev,
      $incomingItem.updated_at AS i_item_at,
      $incomingItem.device_id AS i_item_dev''';

  /// Qué versión queda, según la regla, si los valores son distintos.
  static FieldDecision decide(QueryRow row, {required bool valuesDiffer}) =>
      FieldMergeRule.decide(
        valuesDiffer: valuesDiffer,
        local: field(row, 'l'),
        incoming: field(row, 'i'),
        localItem: item(row, 'l'),
        incomingItem: item(row, 'i'),
      );

  /// La versión del campo de un lado —`l` o `i`—, o `null` si no la tiene.
  static FieldStamp? field(QueryRow row, String side) {
    final at = row.read<int?>('${side}_at');
    if (at == null) return null;
    final baseAt = row.read<int?>('${side}_base_at');
    return FieldStamp(
      updatedAt: dateTime(at),
      deviceId: row.read<String>('${side}_dev'),
      baseUpdatedAt: baseAt == null ? null : dateTime(baseAt),
      baseDeviceId: row.read<String?>('${side}_base_dev'),
    );
  }

  /// La versión del elemento entero de un lado: con lo que se decide cuando el
  /// campo no tiene ninguna.
  static FieldStamp item(QueryRow row, String side) => FieldStamp(
    updatedAt: dateTime(row.read<int>('${side}_item_at')),
    deviceId: row.read<String>('${side}_item_dev'),
  );

  /// Los instantes están guardados como segundos desde 1970.
  static DateTime dateTime(int seconds) =>
      DateTime.fromMillisecondsSinceEpoch(seconds * 1000);
}
