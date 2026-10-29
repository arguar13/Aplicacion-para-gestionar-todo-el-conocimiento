import 'package:meta/meta.dart';
import 'package:sinapsis/features/ai_models/domain/entities/ai_account.dart';
import 'package:sinapsis/features/ai_models/domain/entities/illustration_provider.dart';

/// El id fijo del modelo del teléfono visto como una cuenta: no se guarda en
/// ningún lado, existe mientras haya un motor registrado.
const kOnDeviceIllustrationAccountId = 'on-device';

/// Una cuenta que puede dibujar ilustraciones (F43): una de Gemini u OpenAI
/// de las de F32 —la misma clave—, una propia de Hugging Face (con su token)
/// o el modelo del teléfono («Exigente»), que no tiene clave.
///
/// Como en [AiAccount], la clave no está acá: vive en el almacén seguro y se
/// lee solo al mandar un pedido.
@immutable
class IllustrationAccount {
  const IllustrationAccount({
    required this.id,
    required this.provider,
    required this.label,
    required this.addedAt,
  });

  /// El modelo del teléfono llamado [label] (su nombre: «SDXS 512»).
  factory IllustrationAccount.onDevice(String label) => IllustrationAccount(
    id: kOnDeviceIllustrationAccountId,
    provider: IllustrationProvider.onDevice,
    label: label,
    addedAt: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
  );

  /// La cuenta de F32 [account] vista como de imágenes, o `null` si su
  /// proveedor no dibuja (Claude, Gemma).
  static IllustrationAccount? ofTextAccount(AiAccount account) {
    final provider = IllustrationProvider.ofText(account.provider);
    if (provider == null) return null;
    return IllustrationAccount(
      id: account.id,
      provider: provider,
      label: account.label,
      addedAt: account.addedAt,
    );
  }

  /// Lo leído de [toJson], o `null` si no se entiende: se descarta esa sola.
  /// Solo las propias de imágenes se guardan así (hoy, Hugging Face).
  static IllustrationAccount? fromJson(Object? json) {
    if (json is! Map) return null;
    final id = json['id'];
    final provider = IllustrationProvider.fromStorageKey(
      json['provider'] as String?,
    );
    final label = json['label'];
    final added = DateTime.tryParse(json['addedAt'] as String? ?? '');
    if (id is! String ||
        id.isEmpty ||
        provider == null ||
        provider.usesTextAccount ||
        provider.isOnDevice ||
        label is! String) {
      return null;
    }
    return IllustrationAccount(
      id: id,
      provider: provider,
      label: label,
      addedAt: added ?? DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
    );
  }

  final String id;
  final IllustrationProvider provider;

  /// Cómo la llama la persona; nunca vacío.
  final String label;
  final DateTime addedAt;

  /// Si es una de F32 (la clave es la de escribir).
  bool get isTextAccount => provider.usesTextAccount;

  Map<String, Object> toJson() => {
    'id': id,
    'provider': provider.storageKey,
    'label': label,
    'addedAt': addedAt.toUtc().toIso8601String(),
  };

  IllustrationAccount copyWith({String? label}) => IllustrationAccount(
    id: id,
    provider: provider,
    label: label ?? this.label,
    addedAt: addedAt,
  );

  @override
  bool operator ==(Object other) =>
      other is IllustrationAccount &&
      other.id == id &&
      other.provider == provider &&
      other.label == label &&
      other.addedAt == addedAt;

  @override
  int get hashCode => Object.hash(id, provider, label, addedAt);

  @override
  String toString() =>
      'IllustrationAccount($id, ${provider.storageKey}, $label)';
}
