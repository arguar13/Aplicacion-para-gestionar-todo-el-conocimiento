import 'package:flutter_gemma/flutter_gemma.dart';

/// El modelo de lenguaje que `flutter_gemma` tiene activo: de qué tipo es y
/// con qué nombre quedó registrado —el del archivo instalado, sin la
/// extensión—.
typedef ActiveGemmaModel = ({ModelType type, String name});

/// Lo poco que los gestores de modelos usan de `flutter_gemma`: qué está
/// activo y registrar un archivo que ya está entero en el disco.
///
/// Una interfaz y no las llamadas estáticas sueltas para poder probar lo
/// que importa —que un modelo ya bajado se reconozca al reabrir la app— sin
/// el plugin real, que en una prueba no corre.
abstract interface class GemmaRuntime {
  /// `null` si no hay ningún modelo de lenguaje activo.
  ActiveGemmaModel? get activeModel;

  /// Registra el modelo de lenguaje en [path] y lo deja activo. No copia ni
  /// baja nada: es anotarlo.
  Future<void> installModelFile({
    required ModelType type,
    required String path,
  });

  bool get hasActiveEmbedder;

  /// Registra el modelo de relaciones —sus dos archivos— y lo deja activo.
  Future<void> installEmbedderFiles({
    required String modelPath,
    required String tokenizerPath,
  });
}

/// [GemmaRuntime] de verdad, sobre las llamadas estáticas de
/// `FlutterGemma`.
class FlutterGemmaRuntime implements GemmaRuntime {
  const FlutterGemmaRuntime();

  @override
  ActiveGemmaModel? get activeModel {
    final spec = FlutterGemma.activeModelSpec;
    return spec == null ? null : (type: spec.modelType, name: spec.name);
  }

  @override
  Future<void> installModelFile({
    required ModelType type,
    required String path,
  }) async {
    await FlutterGemma.installModel(
      modelType: type,
      fileType: ModelFileType.litertlm,
    ).fromFile(path).install();
  }

  @override
  bool get hasActiveEmbedder => FlutterGemma.hasActiveEmbedder();

  @override
  Future<void> installEmbedderFiles({
    required String modelPath,
    required String tokenizerPath,
  }) async {
    await FlutterGemma.installEmbedder()
        .modelFromFile(modelPath)
        .tokenizerFromFile(tokenizerPath)
        .install();
  }
}
