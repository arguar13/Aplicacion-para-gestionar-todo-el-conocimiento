import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:sinapsis/features/vault/domain/entities/compaction_assessment.dart';
import 'package:sinapsis/features/vault/domain/entities/compaction_progress.dart';
import 'package:sinapsis/features/vault/domain/entities/compaction_result.dart';

part 'compaction_state.freezed.dart';

/// En qué anda la pantalla de espacio de la bóveda.
///
/// Los motivos por los que una compactación no se hizo son estados aparte y no
/// un texto: cada uno lleva lo que la pantalla necesita para explicarlo en el
/// idioma de quien la mira, y ninguno es un error de la app salvo
/// [CompactionFailed] y [CompactionVerificationFailed].
@freezed
sealed class CompactionState with _$CompactionState {
  /// Todavía no se empezó: la pantalla muestra qué hay para recuperar.
  const factory CompactionState.idle() = CompactionIdle;

  /// Compactando: en qué fase va y cuánto lleva.
  const factory CompactionState.running(CompactionProgress progress) =
      CompactionRunning;

  /// Terminó —o se paró entre dos tramos—: cuánto se devolvió.
  const factory CompactionState.finished(CompactionResult result) =
      CompactionFinished;

  /// El disco no tiene el lugar que hace falta; no se tocó nada. Lleva la
  /// medición para decir cuánto hay y cuánto falta.
  const factory CompactionState.noSpace(CompactionAssessment assessment) =
      CompactionNoSpace;

  /// SQLite falló; la bóveda sigue completa.
  const factory CompactionState.failed() = CompactionFailed;

  /// La bóveda compactada no coincide con la de antes. [problem] dice qué
  /// difiere, sin contenido de ninguna fila.
  const factory CompactionState.verificationFailed(String problem) =
      CompactionVerificationFailed;
}
