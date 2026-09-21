import 'package:sinapsis/features/vault/domain/entities/compaction_assessment.dart';
import 'package:sinapsis/features/vault/domain/entities/compaction_progress.dart';
import 'package:sinapsis/features/vault/domain/entities/compaction_result.dart';

/// Devuelve al sistema el espacio que la bóveda ya no usa.
///
/// SQLite no lo hace solo: lo que se borra deja páginas libres DENTRO del
/// archivo, que se reusan pero no se devuelven. La primera compactación
/// reescribe la bóveda entera y la deja en modo incremental; de ahí en más se
/// devuelven de a tramos. En los dos casos, lo que la bóveda tiene —cada fila
/// de cada tabla y el texto íntegro de cada fuente— es exactamente lo mismo
/// antes y después, y se comprueba: si algo cambió, [compact] no da la
/// compactación por buena.
// ignore: one_member_abstracts
abstract interface class VaultCompactor {
  /// Compacta la bóveda y devuelve cómo quedó.
  ///
  /// Lanza [VaultCompactionNoSpaceException] sin tocar nada si el disco no
  /// tiene lugar; [VaultCompactionFailedException] si SQLite falló —y la bóveda
  /// sigue completa—; y [VaultCompactionVerificationException] si al terminar
  /// no coincide lo de antes con lo de después.
  ///
  /// [onProgress] avisa en qué fase va. [cancellation] deja pedir que pare:
  /// solo lo atiende en las fases que lo admiten
  /// ([CompactionPhase.isCancellable]), y devuelve entonces lo hecho hasta ahí,
  /// con `wasCancelled`.
  Future<CompactionResult> compact({
    void Function(CompactionProgress progress)? onProgress,
    CompactionCancellation? cancellation,
  });
}

/// El disco no tiene el lugar que la compactación necesita: no se tocó nada.
class VaultCompactionNoSpaceException implements Exception {
  const VaultCompactionNoSpaceException(this.assessment);

  /// La medición que la rechazó: dice cuánto hay, cuánto hace falta y cuánto
  /// falta.
  final CompactionAssessment assessment;

  @override
  String toString() =>
      'VaultCompactionNoSpaceException(${assessment.missingBytes} bytes '
      'de menos)';
}

/// SQLite falló compactando. Cada paso de la compactación es una transacción:
/// la bóveda quedó como antes de ese paso, y por lo tanto completa.
class VaultCompactionFailedException implements Exception {
  const VaultCompactionFailedException(this.cause);

  final Object cause;

  @override
  String toString() => 'VaultCompactionFailedException($cause)';
}

/// La bóveda compactada NO es igual a la de antes: una tabla cambió de tamaño o
/// el texto de una fuente ya no se reconstruye con sus chunks.
///
/// No debería pasar —SQLite copia cada fila—; que se compruebe es lo que separa
/// «terminó» de «quedó intacta». La compactación ya se hizo y no se puede
/// deshacer: el mensaje dice qué difiere para que se pueda actuar, y el
/// respaldo previo es lo que corresponde recuperar.
class VaultCompactionVerificationException implements Exception {
  const VaultCompactionVerificationException(this.problem);

  /// Qué difiere, sin el contenido de ninguna fila.
  final String problem;

  @override
  String toString() => 'VaultCompactionVerificationException($problem)';
}
