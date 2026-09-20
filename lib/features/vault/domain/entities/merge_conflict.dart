import 'package:freezed_annotation/freezed_annotation.dart';

part 'merge_conflict.freezed.dart';

/// De qué es un conflicto de fusión (F11).
enum MergeConflictKind {
  /// Un campo corto del elemento —título, notas, espacio, estado…— que se
  /// modificó en las dos bóvedas a la vez. Cada versión es un valor.
  field,

  /// El texto de una forma: las dos versiones son textos enteros. La de la
  /// otra bóveda entró como otra forma del mismo elemento.
  text,
}

/// Cómo resuelve el usuario un conflicto: qué versión queda.
///
/// Es el vocabulario de `merge_conflict.resolution`: `keepLocal`, `useIncoming`
/// o `keepBoth`.
enum MergeConflictChoice {
  /// La versión de ESTA bóveda, la que había antes de fusionar.
  keepLocal,

  /// La versión de la OTRA bóveda, la de la copia.
  useIncoming,

  /// Las dos, juntas. Solo tiene sentido en un texto libre —las notas y el
  /// subtítulo—.
  keepBoth,
}

/// Una de las dos versiones de un conflicto.
@freezed
sealed class MergeConflictVersion with _$MergeConflictVersion {
  const factory MergeConflictVersion({
    /// El valor tal como se guardó —el nombre de un enumerado, el identificador
    /// de un espacio, segundos desde 1970— o, en un conflicto de texto, un
    /// fragmento del texto. `null` si no tiene valor: un campo vacío, o una
    /// versión que ya no está.
    String? text,

    /// El valor como fecha, si el campo es una fecha (`deletedAt`,
    /// `publishedAt`).
    DateTime? date,

    /// El nombre del espacio, si el campo es un espacio.
    String? spaceName,

    /// Cuánto texto tiene, en un conflicto de texto: el fragmento de [text]
    /// puede ser una parte.
    int? length,

    /// Desde qué dispositivo y cuándo se escribió esta versión.
    String? deviceId,
    DateTime? at,

    /// Si es la que está en uso ahora.
    @Default(false) bool inUse,
  }) = _MergeConflictVersion;
}

/// Un conflicto pendiente: el mismo campo del mismo elemento, modificado en las
/// dos bóvedas sin que ninguna partiera de la otra (F11). Jamás se pisó nada en
/// silencio: la más reciente quedó en uso y la otra se guardó acá.
@freezed
sealed class MergeConflict with _$MergeConflict {
  const factory MergeConflict({
    required String id,
    required String itemId,
    required String itemTitle,

    /// El nombre del campo: `title`, `notes`, `spaceId`… o `rendition:<id>` si
    /// es un texto.
    required String fieldName,
    required MergeConflictKind kind,

    /// La versión que había en ESTA bóveda antes de fusionar.
    required MergeConflictVersion local,

    /// La que trajo la otra bóveda.
    required MergeConflictVersion incoming,
    required DateTime detectedAt,

    /// Si el elemento está en la papelera.
    @Default(false) bool itemInTrash,
  }) = _MergeConflict;

  const MergeConflict._();

  /// Si se puede elegir «las dos»: solo en un texto libre.
  bool get canKeepBoth =>
      kind == MergeConflictKind.field &&
      (fieldName == 'notes' || fieldName == 'subtitle');
}
