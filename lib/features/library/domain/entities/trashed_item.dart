import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:sinapsis/core/domain/entities/source_kind.dart';

part 'trashed_item.freezed.dart';

/// Un elemento en la papelera (F11): lo justo para listarlo y decidir si se
/// restaura o se borra para siempre.
///
/// No es un `KnowledgeItem`: la papelera no muestra el contenido ni lo arma —
/// una lista de cientos de elementos borrados no puede traer sus textos—, y un
/// elemento en la papelera no se abre: primero se restaura.
@freezed
sealed class TrashedItem with _$TrashedItem {
  const factory TrashedItem({
    required String id,
    required String title,

    /// De qué tipo de fuente era; una nota es [SourceKind.manualNote].
    required SourceKind sourceKind,

    /// Cuándo se mandó a la papelera.
    required DateTime deletedAt,
  }) = _TrashedItem;
}
