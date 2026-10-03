import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:sinapsis/features/chat/data/services/http_gemma_model_downloader.dart';
import 'package:sinapsis/features/chat/domain/entities/chat_model_option.dart';
import 'package:sinapsis/features/chat/domain/services/chat_model_manager.dart'
    as domain;

/// Qué repositorio de Hugging Face y qué [ModelType] le corresponde a cada
/// [ChatModelOption], y cómo reconocer que el modelo activo en el
/// dispositivo es justo ese y no otro.
///
/// [nameContains] hace falta porque [ModelType] por sí solo no siempre
/// alcanza: tanto la Gemma 3 1B que esta pantalla usaba antes de la
/// decisión 20 como la Gemma 3n E4B nueva comparten `ModelType.gemmaIt` —es
/// el tipo genérico "familia Gemma 3", no una por modelo—, así que hace
/// falta mirar también el nombre del archivo activo para no confundir una
/// con la otra. Lo mismo pasa ahora con `ModelType.gemma4`: Gemma 4 E4B y
/// Gemma 4 12B (decisión 27) son dos repositorios y dos archivos
/// distintos, pero comparten el mismo `ModelType`, así que las dos
/// necesitan su propio [nameContains].
class _ModelSpec {
  const _ModelSpec({
    required this.modelType,
    required this.repo,
    required this.file,
    this.nameContains,
  });

  final ModelType modelType;
  final String repo;

  /// El archivo exacto a bajar del repositorio.
  ///
  /// Antes, para Gemma 4, se dejaba en blanco y se le pedía a
  /// `FlutterGemma.resolveHuggingFace` que eligiera la variante leyendo el
  /// `litertlm_manifest.json` del repositorio. Ninguno de los dos
  /// repositorios de Gemma 4 publica ese archivo (comprobado el 2026-10-03),
  /// así que la resolución terminaba en un 404 y la pantalla decía
  /// «comprobá tu conexión» en cualquier teléfono. Nombrarlo es la única
  /// forma de que la descarga no dependa de un archivo que no está.
  final String file;

  final String? nameContains;
}

const _specs = {
  ChatModelOption.gemma4E4b: _ModelSpec(
    modelType: ModelType.gemma4,
    repo: 'litert-community/gemma-4-E4B-it-litert-lm',
    // El general —3,7 GB—, el que el propio repositorio mide en Android con
    // el procesador y con la GPU. Las variantes `-gpu` y `-web` son para
    // escritorio y para el navegador.
    file: 'gemma-4-E4B-it.litertlm',
    // Ahora que `ModelType.gemma4` también es de Gemma 4 12B (ver más
    // abajo), hace falta el mismo desambiguador por nombre de archivo que
    // ya usaba Gemma 3n E4B.
    nameContains: 'e4b',
  ),
  ChatModelOption.gemma3nE4b: _ModelSpec(
    modelType: ModelType.gemmaIt,
    repo: 'google/gemma-3n-E4B-it-litert-lm',
    file: 'gemma-3n-E4B-it-int4.litertlm',
    nameContains: 'gemma-3n',
  ),
  ChatModelOption.gemma412b: _ModelSpec(
    modelType: ModelType.gemma4,
    repo: 'litert-community/gemma-4-12B-it-litert-lm',
    // Ídem: el general, 6,9 GB.
    file: 'gemma-4-12B-it.litertlm',
    nameContains: '12b',
  ),
};

/// [domain.ChatModelManager] sobre `flutter_gemma`, con la descarga bajada
/// a mano en vez de delegada al paquete — ver [HttpGemmaModelDownloader]
/// para el motivo completo: en Android, la descarga que hace `flutter_gemma`
/// por dentro pasa por WorkManager, que corta cualquier tarea a los ~9
/// minutos, y Hugging Face no admite retomarla ahí donde quedó. Para estos
/// modelos —de varios cientos de megas a unos pocos gigas— eso significa
/// que una conexión que no llegue a bajarlos enteros en esos 9 minutos
/// nunca termina, sin importar cuántas veces se reintente.
///
/// Lo único que sigue viniendo de `flutter_gemma` es **instalarlo** una vez
/// que ya está entero en el disco, con `fromFile`. Qué archivo bajar lo dice
/// [_ModelSpec.file].
class GemmaChatModelManager implements domain.ChatModelManager {
  const GemmaChatModelManager({required this.option, required this.downloader});

  /// Qué modelo gestiona esta instancia. La pantalla de descarga crea una
  /// instancia distinta por cada opción que muestra, no una que cambie de
  /// opción sobre la marcha.
  final ChatModelOption option;

  final HttpGemmaModelDownloader downloader;

  _ModelSpec get _spec => _specs[option]!;

  @override
  Future<bool> isReady() async {
    // `FlutterGemma.hasActiveModel()` no alcanza: solo dice "hay algún
    // modelo activo", sin importar cuál. Comparar el tipo de modelo, y —para
    // las opciones donde el tipo no alcanza, ver el comentario de
    // `_ModelSpec`— también el nombre del archivo activo, es lo que
    // distingue "ya tengo la opción que elegiste" de "tengo alguna, pero no
    // esta".
    final active = FlutterGemma.activeModelSpec;
    if (active == null || active.modelType != _spec.modelType) return false;

    final marker = _spec.nameContains;
    return marker == null || active.name.toLowerCase().contains(marker);
  }

  @override
  Future<int?> downloadSizeInBytes() async {
    // El tamaño exacto solo se sabe resolviendo el manifiesto —o, para el
    // archivo fijo de Gemma 3n, pidiéndoselo al servidor—, y las dos cosas
    // valen la pena solo cuando la descarga arranca de verdad. El tamaño
    // aproximado que sí ve quien elige la opción está en el texto de la
    // pantalla, no acá.
    return null;
  }

  @override
  Stream<double> download({String? huggingFaceToken}) {
    final controller = StreamController<double>();
    unawaited(_runDownload(controller, huggingFaceToken));
    return controller.stream;
  }

  Future<void> _runDownload(
    StreamController<double> controller,
    String? token,
  ) async {
    try {
      final spec = _spec;
      // El tamaño no se sabe de antemano: lo dice el servidor al empezar.
      final progress = downloader.download(
        url: downloadUrlOf(option),
        fileName: '${option.name}.litertlm',
        token: token,
      );

      await for (final value in progress) {
        if (!controller.isClosed) controller.add(value);
      }

      final file = await downloader.targetFile('${option.name}.litertlm');
      await FlutterGemma.installModel(
        modelType: spec.modelType,
        fileType: ModelFileType.litertlm,
      ).fromFile(file.path).install();

      if (!controller.isClosed) await controller.close();
      // Catch-all deliberado: la resolución del manifiesto, la descarga y
      // la instalación pueden fallar cada una por su cuenta, y las tres
      // tienen que llegar como el mismo tipo de error a la pantalla.
      // ignore: avoid_catches_without_on_clauses
    } catch (e, stackTrace) {
      if (!controller.isClosed) {
        controller.addError(_toDomainError(e), stackTrace);
      }
      if (!controller.isClosed) await controller.close();
    }
  }

  /// La dirección que baja [option]: la ruta del archivo dentro de su
  /// repositorio, armada a mano —lo mismo que haría `flutter_gemma` con un
  /// archivo explícito—.
  static String downloadUrlOf(ChatModelOption option) {
    final spec = _specs[option]!;
    final encodedPath = spec.file.split('/').map(Uri.encodeComponent).join('/');
    return 'https://huggingface.co/${spec.repo}/resolve/main/$encodedPath';
  }

  /// Traduce lo que salga mal —resolviendo el manifiesto, bajando el
  /// archivo o instalándolo— a algo que la pantalla pueda mostrar sin
  /// necesitar saber nada de HTTP ni de `flutter_gemma`.
  ///
  /// El repositorio de Gemma está protegido (ver el comentario de
  /// `_specs`), así que un 401/403 —de la descarga propia, con `dio`, o de
  /// `flutter_gemma` resolviendo el manifiesto— significa lo mismo: hace
  /// falta un token de Hugging Face válido, no reintentar.
  domain.ChatModelDownloadError _toDomainError(Object e) {
    if (e is DioException) {
      final status = e.response?.statusCode;
      if (status == 401 || status == 403) {
        return const domain.ChatModelNeedsAuthentication();
      }
    }
    if (e is DownloadException &&
        (e.error is UnauthorizedError || e.error is ForbiddenError)) {
      return const domain.ChatModelNeedsAuthentication();
    }
    // `toUserMessage()`/`toString()` van como detalle técnico nomás, nunca
    // como texto para mostrar: están en inglés, sin importar el idioma
    // activo de la app.
    if (e is DownloadException) {
      return domain.ChatModelDownloadFailed(e.error.toUserMessage());
    }
    return domain.ChatModelDownloadFailed(e.toString());
  }
}
