import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:sinapsis/core/domain/entities/note_kind.dart';
import 'package:sinapsis/core/domain/entities/note_maturity.dart';
import 'package:sinapsis/features/health/domain/entities/health_thresholds.dart';

part 'note_composition.freezed.dart';

/// De qué está hecha la bóveda de notas: cuántas de cada subtipo y cuántas en
/// cada etapa de madurez. Es el indicador que dice, de un vistazo, si se están
/// acumulando fragmentos sin construir entendimiento.
///
/// Los dos mapas traen SIEMPRE todos los valores, con cero donde no hay
/// ninguna: quien los lee no tiene que decidir qué significa que falte uno.
@freezed
sealed class NoteComposition with _$NoteComposition {
  const factory NoteComposition({
    required Map<NoteKind, int> byKind,
    required Map<NoteMaturity, int> byMaturity,
  }) = _NoteComposition;

  const NoteComposition._();

  /// Sin ninguna nota.
  static const empty = NoteComposition(byKind: {}, byMaturity: {});

  /// Cuántas notas hay, de cualquier subtipo.
  int get total => byKind.values.fold(0, (sum, count) => sum + count);

  int kindCount(NoteKind kind) => byKind[kind] ?? 0;

  int maturityCount(NoteMaturity maturity) => byMaturity[maturity] ?? 0;

  /// Muchas notas atómicas y pocas vivas: se están sacando fragmentos de las
  /// fuentes sin escribir lo propio con ellos. Ver [kFragmentWarningMinAtomic]
  /// y [kFragmentWarningRatio].
  bool get fragmentsOutweighSynthesis {
    final atomic = kindCount(NoteKind.atomic);
    return atomic >= kFragmentWarningMinAtomic &&
        atomic > kindCount(NoteKind.living) * kFragmentWarningRatio;
  }
}
