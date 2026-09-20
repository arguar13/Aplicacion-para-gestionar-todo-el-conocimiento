import 'package:meta/meta.dart';
import 'package:sinapsis/core/database/device_identity.dart';

/// La versión de un campo en una bóveda: quién lo escribió, cuándo, y sobre qué
/// versión ajena (F11). Es una fila de `field_version` sin el elemento ni el
/// nombre del campo.
@immutable
class FieldStamp {
  const FieldStamp({
    required this.updatedAt,
    required this.deviceId,
    this.baseUpdatedAt,
    this.baseDeviceId,
  });

  /// Cuándo y desde qué dispositivo se escribió esta versión.
  final DateTime updatedAt;
  final String deviceId;

  /// La versión AJENA sobre la que se editó, o nulos si la cadena de ediciones
  /// es propia. Ver `KnowledgeEntryWriter`.
  final DateTime? baseUpdatedAt;
  final String? baseDeviceId;

  /// Si es de algo escrito antes de que existieran los identificadores de
  /// dispositivo: no se sabe quién fue.
  bool get isLegacy => isLegacyDevice(deviceId);

  /// Si esta versión se escribió SOBRE [other]: quien la escribió tenía la de
  /// [other] delante y la cambió. Es lo único que dice que una versión sigue a
  /// la otra; la hora no lo dice, porque dos relojes no coinciden.
  bool isBasedOn(FieldStamp other) =>
      baseUpdatedAt != null &&
      baseUpdatedAt == other.updatedAt &&
      baseDeviceId == other.deviceId;

  /// Si es más reciente que [other]: por la hora y, si coincide, por el
  /// identificador del dispositivo, para que dos bóvedas que fusionan la una
  /// con la otra elijan la misma.
  bool isNewerThan(FieldStamp other) {
    final byTime = updatedAt.compareTo(other.updatedAt);
    if (byTime != 0) return byTime > 0;
    return deviceId.compareTo(other.deviceId) > 0;
  }

  @override
  bool operator ==(Object other) =>
      other is FieldStamp &&
      other.updatedAt == updatedAt &&
      other.deviceId == deviceId &&
      other.baseUpdatedAt == baseUpdatedAt &&
      other.baseDeviceId == baseDeviceId;

  @override
  int get hashCode =>
      Object.hash(updatedAt, deviceId, baseUpdatedAt, baseDeviceId);

  @override
  String toString() {
    final base = baseUpdatedAt == null
        ? ''
        : ', base $baseDeviceId @ $baseUpdatedAt';
    return 'FieldStamp($deviceId @ $updatedAt$base)';
  }
}

/// Qué hacer con un campo que las dos bóvedas tienen distinto.
enum FieldDecision {
  /// Valen lo mismo: no hay nada que hacer.
  same,

  /// Queda la de esta bóveda y no se guarda nada más.
  keepLocal,

  /// Queda la de la copia y no se guarda nada más.
  takeIncoming,

  /// Las dos se modificaron sin que ninguna partiera de la otra: queda en vivo
  /// la de esta bóveda, que es la más reciente, y la de la copia se guarda como
  /// conflicto.
  conflictKeepLocal,

  /// Igual, pero la más reciente es la de la copia: pasa a estar en vivo y la
  /// de esta bóveda se guarda como conflicto.
  conflictTakeIncoming;

  /// Si hay que guardar la otra versión para que el usuario la revise.
  bool get isConflict =>
      this == conflictKeepLocal || this == conflictTakeIncoming;

  /// Si el valor de la copia pasa a ser el de esta bóveda.
  bool get takesIncoming =>
      this == takeIncoming || this == conflictTakeIncoming;

  /// Si queda el valor de esta bóveda, habiendo uno distinto en la copia.
  bool get keepsLocal => this == keepLocal || this == conflictKeepLocal;
}

/// La regla que decide, campo a campo, qué versión queda al fusionar la copia
/// de otra bóveda con esta (F11).
///
/// Es una función pura de las dos versiones: sin base de datos, sin reloj. La
/// vista previa y la fusión la usan las dos, y por eso no pueden discrepar.
///
/// La regla, en orden:
///
/// 1. Si el valor es el mismo, nada.
/// 2. **Sin versión.** Un campo sin `field_version` no se modificó desde que se
///    llevan versiones —o nunca tuvo valor—: es el valor de partida. Si solo el
///    otro lado tiene versión, ese lado lo modificó y gana. Si ninguno la
///    tiene, no hay cómo ordenarlos por campo y gana el elemento modificado más
///    recientemente (`localItem` contra `incomingItem`), sin conflicto: es
///    lo escrito antes de F11, de origen desconocido.
/// 3. **Dispositivo desconocido** (`legacy`): no puede haber conflicto con
///    alguien que no se sabe quién es; gana la más reciente.
/// 4. **El mismo dispositivo** en las dos: una edición siguió a la otra; gana
///    la más reciente.
/// 5. **Linaje.** Si una versión se escribió sobre la otra —su `base` es la
///    otra—, la que sigue gana aunque su reloj marque una hora anterior:
///    ninguno de los dos se equivocó, los relojes no coinciden. Es lo que evita
///    marcar como conflicto el uso normal, teléfono→compu→teléfono.
/// 6. **Conflicto real.** Dos dispositivos conocidos, distintos, que
///    modificaron el campo sin que ninguno partiera de la versión del otro.
///    Gana en vivo la más reciente y la otra se guarda: jamás se pisa en
///    silencio.
///
/// El linaje solo reconoce la descendencia DIRECTA (la `base` es exactamente la
/// otra versión). Cuando una edición pasó por un tercer dispositivo, la cadena
/// no se puede reconstruir y se trata como concurrente: un conflicto de más,
/// que se puede resolver, y nunca una edición pisada de menos.
abstract final class FieldMergeRule {
  static FieldDecision decide({
    required bool valuesDiffer,
    required FieldStamp? local,
    required FieldStamp? incoming,
    required FieldStamp localItem,
    required FieldStamp incomingItem,
  }) {
    if (!valuesDiffer) return FieldDecision.same;

    if (local == null && incoming == null) {
      return _newerWins(localItem, incomingItem);
    }
    if (local == null) return FieldDecision.takeIncoming;
    if (incoming == null) return FieldDecision.keepLocal;

    if (local.isLegacy || incoming.isLegacy) {
      return _newerWins(local, incoming);
    }
    if (local.deviceId == incoming.deviceId) {
      return _newerWins(local, incoming);
    }
    if (incoming.isBasedOn(local)) return FieldDecision.takeIncoming;
    if (local.isBasedOn(incoming)) return FieldDecision.keepLocal;

    return incoming.isNewerThan(local)
        ? FieldDecision.conflictTakeIncoming
        : FieldDecision.conflictKeepLocal;
  }

  static FieldDecision _newerWins(FieldStamp local, FieldStamp incoming) =>
      incoming.isNewerThan(local)
      ? FieldDecision.takeIncoming
      : FieldDecision.keepLocal;
}
