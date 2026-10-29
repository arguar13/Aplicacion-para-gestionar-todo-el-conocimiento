import 'package:sinapsis/features/ai_models/domain/entities/illustration_account.dart';
import 'package:sinapsis/features/ai_models/domain/entities/illustration_provider.dart';

/// Las cuentas que solo dibujan (F43): hoy, las de Hugging Face, con su
/// token. Como las de F32, en el almacén seguro del sistema, fuera de la base
/// y de las copias. Las de Gemini y OpenAI no están acá: son las mismas de
/// escribir; el modelo del teléfono no es una cuenta guardada.
abstract interface class ImageAccountRepository {
  /// Todas, en el orden en que se agregaron.
  Future<List<IllustrationAccount>> list();

  /// [list], y de nuevo cada vez que cambia.
  Stream<List<IllustrationAccount>> watch();

  /// Agrega una de [provider] con [key]. Sin [label], «Hugging Face 1».
  Future<IllustrationAccount> add({
    required IllustrationProvider provider,
    required String key,
    String? label,
  });

  Future<void> rename(String id, String label);

  Future<void> replaceKey(String id, String key);

  Future<void> remove(String id);

  /// La clave de [id], o `null` si no tiene.
  Future<String?> keyOf(String id);
}
