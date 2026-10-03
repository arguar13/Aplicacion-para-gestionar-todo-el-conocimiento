import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:sinapsis/core/domain/entities/source_kind.dart';

part 'pending_source.freezed.dart';

/// Una fuente que espera en la Bandeja, tal como se lista en «N pendientes»
/// (F28): lo justo para reconocerla —su tipo, su título y cuándo se guardó—,
/// no el `KnowledgeItem` entero. Mismo criterio que `NoteReference`.
@freezed
sealed class PendingSource with _$PendingSource {
  const factory PendingSource({
    required String id,
    required String title,
    required SourceKind kind,
    required DateTime capturedAt,
  }) = _PendingSource;
}
