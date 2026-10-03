import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:path/path.dart' as p;
import 'package:sinapsis/features/chat/data/services/gemma_runtime.dart';
import 'package:sinapsis/features/chat/data/services/http_gemma_model_downloader.dart';
import 'package:sinapsis/features/chat/domain/entities/chat_model_option.dart';
import 'package:sinapsis/features/chat/domain/services/chat_model_manager.dart'
    as domain;

/// Qué repositorio de Hugging Face, qué archivo y qué [ModelType] le
/// corresponde a cada [ChatModelOption].
class _ModelSpec {
  const _ModelSpec({
    required this.modelType,
    required this.repo,
    required this.file,
    required this.publishedBytes,
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

  /// Lo que pesa [file] según Hugging Face (`/api/models/<repo>/tree/main`,
  /// consultado el 2026-10-03). Solo sirve para reconocer lo que se bajó
  /// antes de que la descarga dejara su marca de terminada: ver
  /// `HttpGemmaModelDownloader.isComplete`.
  final int publishedBytes;
}

const _specs = {
  ChatModelOption.gemma4E4b: _ModelSpec(
    modelType: ModelType.gemma4,
    repo: 'litert-community/gemma-4-E4B-it-litert-lm',
    // El general —3,7 GB—, el que el propio repositorio mide en Android con
    // el procesador y con la GPU. Las variantes `-gpu` y `-web` son para
    // escritorio y para el navegador.
    file: 'gemma-4-E4B-it.litertlm',
    publishedBytes: 3659530240,
  ),
  ChatModelOption.gemma3nE4b: _ModelSpec(
    modelType: ModelType.gemmaIt,
    repo: 'google/gemma-3n-E4B-it-litert-lm',
    file: 'gemma-3n-E4B-it-int4.litertlm',
    publishedBytes: 4919541760,
  ),
  ChatModelOption.gemma412b: _ModelSpec(
    modelType: ModelType.gemma4,
    repo: 'litert-community/gemma-4-12B-it-litert-lm',
    // Ídem: el general, 6,9 GB.
    file: 'gemma-4-12B-it.litertlm',
    publishedBytes: 6883278368,
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
  GemmaChatModelManager({
    required this.option,
    required this.downloader,
    GemmaRuntime runtime = const FlutterGemmaRuntime(),
  }) : _runtime = runtime;

  /// Qué modelo gestiona esta instancia. La pantalla de descarga crea una
  /// instancia distinta por cada opción que muestra, no una que cambie de
  /// opción sobre la marcha.
  final ChatModelOption option;

  final HttpGemmaModelDownloader downloader;
  final GemmaRuntime _runtime;

  /// La comprobación en curso: varias a la vez —la cola de la IA y una
  /// pantalla, al abrir la app— registran el modelo una sola vez.
  Future<bool>? _checking;

  _ModelSpec get _spec => _specs[option]!;

  /// Cómo se llama el archivo en el dispositivo.
  String get _fileName => '${option.name}.litertlm';

  /// Si el modelo de [option] está en el dispositivo, listo para responder;
  /// si su archivo está entero pero `flutter_gemma` no lo tiene activo, lo
  /// registra en el acto.
  ///
  /// Hace falta porque `flutter_gemma` 1.8.3 no recuerda un modelo instalado
  /// con `fromFile` entre una sesión y la siguiente: al arrancar busca el
  /// archivo en la raíz de sus documentos (`<documentos>/<nombre>`), no en
  /// `modelos/gemma/` donde está, lo da por borrado («active model restore:
  /// file … missing — skipping») y arranca sin modelo activo. Sin esto, cada
  /// vez que se abría la app pedía bajarlo de nuevo y la IA que organiza
  /// sola se frenaba. Registrarlo no baja ni copia nada.
  @override
  Future<bool> isReady() =>
      _checking ??= _ensureReady().whenComplete(() => _checking = null);

  Future<bool> _ensureReady() async {
    if (_isActive()) return true;
    if (!await downloader.isComplete(
      _fileName,
      publishedBytes: _spec.publishedBytes,
    )) {
      return false;
    }
    await _install();
    return _isActive();
  }

  /// Si el modelo activo es el de [option]: mismo tipo y el nombre con que
  /// queda registrado su archivo.
  ///
  /// Por nombre exacto y no por un pedazo: `flutter_gemma` registra el
  /// archivo sin la extensión —`gemma3nE4b` para Gemma 3n—, así que buscar
  /// `gemma-3n` adentro no coincidía nunca y Gemma 3n no se daba por lista
  /// ni recién bajada. El tipo solo no alcanza: Gemma 4 E4B y Gemma 4 12B
  /// comparten `ModelType.gemma4`. También vale el nombre del archivo de
  /// Hugging Face, el que dejaba instalado la descarga de `flutter_gemma`
  /// que se usaba antes de la propia.
  bool _isActive() {
    final active = _runtime.activeModel;
    if (active == null || active.type != _spec.modelType) return false;
    final name = active.name.toLowerCase();
    return name == option.name.toLowerCase() ||
        name == p.basenameWithoutExtension(_spec.file).toLowerCase();
  }

  Future<void> _install() async {
    final file = await downloader.targetFile(_fileName);
    await _runtime.installModelFile(type: _spec.modelType, path: file.path);
  }

  @override
  Future<int?> downloadSizeInBytes() async {
    // El tamaño aproximado que ve quien elige la opción está en el texto de
    // la pantalla, no acá.
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
      // Si ya está entero no se baja: el descargador lo dice sin tocar la
      // red, y solo queda registrarlo.
      final progress = downloader.download(
        url: downloadUrlOf(option),
        fileName: _fileName,
        token: token,
        publishedBytes: _spec.publishedBytes,
      );

      await for (final value in progress) {
        if (!controller.isClosed) controller.add(value);
      }

      await _install();
      if (!controller.isClosed) await controller.close();
    } on Object catch (e, stackTrace) {
      // La descarga y la instalación pueden fallar cada una por su cuenta,
      // y las dos tienen que llegar como el mismo tipo de error a la
      // pantalla.
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
