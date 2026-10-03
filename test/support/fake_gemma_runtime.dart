import 'package:flutter_gemma/core/utils/file_name_utils.dart';
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:path/path.dart' as p;
import 'package:sinapsis/features/chat/data/services/gemma_runtime.dart';

/// `flutter_gemma` sin el plugin: registra lo que se le instala y lo deja
/// activo con **el mismo nombre** que le pondría el paquete real
/// (`FileNameUtils.getBaseName` del archivo), que es lo que miran los
/// gestores para saber si el modelo activo es el suyo.
///
/// Arranca sin nada activo, como `flutter_gemma` 1.8.3 al reabrir la app
/// con un modelo instalado desde `modelos/gemma/`.
class FakeGemmaRuntime implements GemmaRuntime {
  @override
  ActiveGemmaModel? activeModel;

  /// Las rutas de los modelos de lenguaje registrados, en orden.
  final modelInstalls = <String>[];

  /// Los pares modelo-tokenizador de relaciones registrados, en orden.
  final embedderInstalls = <(String, String)>[];

  @override
  bool hasActiveEmbedder = false;

  @override
  Future<void> installModelFile({
    required ModelType type,
    required String path,
  }) async {
    modelInstalls.add(path);
    activeModel = (
      type: type,
      name: FileNameUtils.getBaseName(p.basename(path)),
    );
  }

  @override
  Future<void> installEmbedderFiles({
    required String modelPath,
    required String tokenizerPath,
  }) async {
    embedderInstalls.add((modelPath, tokenizerPath));
    hasActiveEmbedder = true;
  }
}
