import 'package:sinapsis/features/ai_models/domain/entities/ai_account.dart';
import 'package:sinapsis/features/ai_models/domain/entities/ai_provider.dart';

/// Las cuentas de los proveedores en la nube y sus claves (F32, decisión C):
/// viven en el almacén seguro del sistema, fuera de la base y de las copias
/// de seguridad. Si se desinstala la app, se van con ella.
abstract interface class AiAccountRepository {
  /// Todas, en el orden en que se agregaron.
  Future<List<AiAccount>> list();

  /// [list], y de nuevo cada vez que cambia.
  Stream<List<AiAccount>> watch();

  /// Agrega una cuenta de [provider] con [key]. Sin [label] (o vacío), le pone
  /// «Cuenta N». La clave se guarda sin espacios en las puntas.
  Future<AiAccount> add({
    required AiProvider provider,
    required String key,
    String? label,
  });

  /// Le cambia el nombre. Vacío: no cambia nada.
  Future<void> rename(String id, String label);

  /// Le cambia la clave (se regeneró en el proveedor).
  Future<void> replaceKey(String id, String key);

  /// La borra, con su clave.
  Future<void> remove(String id);

  /// La clave de [id], o `null` si no está. Solo para mandar un pedido: nunca
  /// se muestra entera ni se registra.
  Future<String?> keyOf(String id);
}

/// Una clave para mostrar sin revelarla: «AIza…k3Fq».
String maskedKey(String key) {
  final trimmed = key.trim();
  if (trimmed.length <= 8) return '••••';
  return '${trimmed.substring(0, 4)}…${trimmed.substring(trimmed.length - 4)}';
}
