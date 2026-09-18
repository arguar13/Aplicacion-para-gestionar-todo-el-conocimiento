import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:sinapsis/core/domain/entities/source_kind.dart';

part 'merged_provenance.freezed.dart';

/// La procedencia congelada de un elemento que se fusionó dentro de otro
/// — F7, deduplicación. Ver `MergeDuplicateItemsUseCase`, que es quien la
/// crea, y la tabla `MergedProvenances` de la que sale.
@freezed
sealed class MergedProvenance with _$MergedProvenance {
  const factory MergedProvenance({
    required String id,

    /// El elemento que sobrevivió a la fusión — no el que se descartó.
    required String itemId,
    required SourceKind sourceKind,

    /// Cuándo se había capturado el elemento descartado, no cuándo se
    /// fusionó — eso es `mergedAt`.
    required DateTime capturedAt,
    required DateTime mergedAt,
    String? url,
    String? authorName,
    String? authorUrl,
    DateTime? publishedAt,
  }) = _MergedProvenance;
}
