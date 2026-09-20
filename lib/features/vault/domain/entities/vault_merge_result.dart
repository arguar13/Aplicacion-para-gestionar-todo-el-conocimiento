import 'package:freezed_annotation/freezed_annotation.dart';

part 'vault_merge_result.freezed.dart';

/// Lo que hizo una fusión de la copia de otra bóveda con esta (F11).
///
/// Cuenta lo que se escribió, no lo que se leyó: una fusión de la misma copia
/// por segunda vez da todo en cero.
@freezed
sealed class VaultMergeResult with _$VaultMergeResult {
  const factory VaultMergeResult({
    /// Elementos de la copia que esta bóveda no tenía.
    @Default(0) int itemsAdded,

    /// Elementos que esta bóveda ya tenía y que cambiaron, y cuántos campos.
    @Default(0) int itemsUpdated,
    @Default(0) int fieldsUpdated,

    /// Conflictos nuevos, guardados para que el usuario los revise: campos que
    /// se modificaron en las dos bóvedas sin que ninguna partiera de la otra.
    @Default(0) int conflictsRecorded,

    /// Espacios de la copia que esta bóveda no tenía.
    @Default(0) int spacesAdded,
  }) = _VaultMergeResult;

  const VaultMergeResult._();

  /// Si la fusión no cambió nada.
  bool get changedNothing =>
      itemsAdded == 0 &&
      fieldsUpdated == 0 &&
      conflictsRecorded == 0 &&
      spacesAdded == 0;
}
