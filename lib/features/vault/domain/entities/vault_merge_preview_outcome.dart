import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:sinapsis/features/vault/domain/entities/vault_merge_preview.dart';
import 'package:sinapsis/features/vault/domain/entities/vault_merge_rejection.dart';

part 'vault_merge_preview_outcome.freezed.dart';

/// Lo que dijo la vista previa de fusionar una copia (F11).
@freezed
sealed class VaultMergePreviewOutcome with _$VaultMergePreviewOutcome {
  /// La copia se pudo leer: esto es lo que traería.
  const factory VaultMergePreviewOutcome.ready({
    required VaultMergePreview preview,
  }) = VaultMergePreviewReady;

  /// La copia no sirve para fusionar.
  const factory VaultMergePreviewOutcome.rejected({
    required VaultMergeRejection rejection,
  }) = VaultMergePreviewRejected;
}
