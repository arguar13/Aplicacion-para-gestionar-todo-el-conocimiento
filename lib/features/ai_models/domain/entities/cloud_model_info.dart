import 'package:meta/meta.dart';

/// Un modelo que un proveedor ofrece con una clave (F32), tal como lo
/// devuelve su lista de modelos: la app no trae una lista fija, porque los
/// proveedores cambian de modelos cada pocos meses.
@immutable
class CloudModelInfo {
  const CloudModelInfo({
    required this.id,
    required this.displayName,
    this.inputTokens,
    this.outputTokens,
  });

  /// El código que se manda en cada pedido: «gemini-3.8-flash».
  final String id;

  /// Cómo lo llama el proveedor: «Gemini 3.8 Flash».
  final String displayName;

  /// Cuánto lee de una vez, si el proveedor lo dice.
  final int? inputTokens;

  /// Cuánto escribe como mucho por respuesta, si el proveedor lo dice.
  final int? outputTokens;

  @override
  bool operator ==(Object other) =>
      other is CloudModelInfo &&
      other.id == id &&
      other.displayName == displayName &&
      other.inputTokens == inputTokens &&
      other.outputTokens == outputTokens;

  @override
  int get hashCode => Object.hash(id, displayName, inputTokens, outputTokens);

  @override
  String toString() => 'CloudModelInfo($id)';
}
