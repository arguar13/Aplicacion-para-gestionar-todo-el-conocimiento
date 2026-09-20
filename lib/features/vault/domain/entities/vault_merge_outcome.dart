import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:sinapsis/features/vault/domain/entities/vault_merge_rejection.dart';
import 'package:sinapsis/features/vault/domain/entities/vault_merge_result.dart';

part 'vault_merge_outcome.freezed.dart';

/// Cómo terminó de fusionar una copia (F11).
@freezed
sealed class VaultMergeOutcome with _$VaultMergeOutcome {
  /// Se fusionó: esto es lo que se hizo.
  const factory VaultMergeOutcome.merged({required VaultMergeResult result}) =
      VaultMergeMerged;

  /// La copia no sirve para fusionar: no se tocó nada.
  const factory VaultMergeOutcome.rejected({
    required VaultMergeRejection rejection,
  }) = VaultMergeRejected;

  /// Una compuerta de seguridad no se cumplió y la fusión se revirtió entera:
  /// no se tocó nada. [gate] dice cuál.
  const factory VaultMergeOutcome.reverted({required String gate}) =
      VaultMergeReverted;
}
