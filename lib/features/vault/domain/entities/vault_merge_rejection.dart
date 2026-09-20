import 'package:freezed_annotation/freezed_annotation.dart';

part 'vault_merge_rejection.freezed.dart';

/// Por qué una copia elegida NO se puede fusionar (F11).
///
/// No es un error de la app: es que el archivo no sirve para esto, y la
/// respuesta es decírselo al usuario —con qué hacer— y dejarlo elegir otro. Por
/// eso es un valor y no un fallo de dominio: cada motivo tiene su mensaje, con
/// las versiones que hacen falta para entenderlo.
@freezed
sealed class VaultMergeRejection with _$VaultMergeRejection {
  /// La copia es de una versión de Sinapsis más nueva que esta.
  const factory VaultMergeRejection.tooNew({
    required int backupVersion,
    required int currentVersion,
  }) = VaultMergeTooNew;

  /// La copia es de una versión tan vieja que esta no sabe actualizarla.
  const factory VaultMergeRejection.tooOld({
    required int backupVersion,
    required int minimumVersion,
  }) = VaultMergeTooOld;

  /// No tiene la forma de una copia de Sinapsis.
  const factory VaultMergeRejection.invalid() = VaultMergeInvalid;
}
