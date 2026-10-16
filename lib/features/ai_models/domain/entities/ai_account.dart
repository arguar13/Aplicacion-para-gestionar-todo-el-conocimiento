import 'package:meta/meta.dart';
import 'package:sinapsis/features/ai_models/domain/entities/ai_provider.dart';

/// Una cuenta de un proveedor en la nube (F32): un nombre que pone la persona
/// —«armando@gmail.com», «cuenta 2»— y su clave de API.
///
/// La clave NO es parte de esta clase: vive aparte, en el almacén seguro del
/// sistema, y solo se lee en el momento de mandar un pedido. Lo que se lista,
/// se muestra y se compara es esto.
@immutable
class AiAccount {
  const AiAccount({
    required this.id,
    required this.provider,
    required this.label,
    required this.addedAt,
  });

  /// Lo leído de [toJson], o `null` si no se entiende (una versión futura,
  /// o algo tocado a mano): se descarta esa cuenta sola, no todas.
  static AiAccount? fromJson(Object? json) {
    if (json is! Map) return null;
    final id = json['id'];
    final provider = AiProvider.fromStorageKey(json['provider'] as String?);
    final label = json['label'];
    final added = DateTime.tryParse(json['addedAt'] as String? ?? '');
    if (id is! String || id.isEmpty || provider == null || label is! String) {
      return null;
    }
    return AiAccount(
      id: id,
      provider: provider,
      label: label,
      addedAt: added ?? DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
    );
  }

  final String id;
  final AiProvider provider;

  /// Cómo la llama la persona. Nunca vacío: si no le puso nombre, la app le
  /// pone uno («Cuenta 1»).
  final String label;

  /// Cuándo se agregó: ordena el menú y decide a cuál se pasa primero cuando
  /// una se queda sin cuota.
  final DateTime addedAt;

  Map<String, Object> toJson() => {
    'id': id,
    'provider': provider.storageKey,
    'label': label,
    'addedAt': addedAt.toUtc().toIso8601String(),
  };

  AiAccount copyWith({String? label}) => AiAccount(
    id: id,
    provider: provider,
    label: label ?? this.label,
    addedAt: addedAt,
  );

  @override
  bool operator ==(Object other) =>
      other is AiAccount &&
      other.id == id &&
      other.provider == provider &&
      other.label == label &&
      other.addedAt == addedAt;

  @override
  int get hashCode => Object.hash(id, provider, label, addedAt);

  @override
  String toString() => 'AiAccount($id, ${provider.storageKey}, $label)';
}
