import 'dart:async';

import 'package:flutter_gemma/flutter_gemma.dart';
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
/// con la otra. Gemma 4 no tiene ese problema: `ModelType.gemma4` es propio
/// y exclusivo de esa familia en esta app, así que ahí [nameContains] queda
/// en `null`.
class _ModelSpec {
  const _ModelSpec({
    required this.modelType,
    required this.repo,
    this.file,
    this.nameContains,
  });

  final ModelType modelType;
  final String repo;

  /// `null` cuando el repositorio publica un manifiesto de despliegue y
  /// conviene dejar que `flutter_gemma` resuelva la variante exacta —ver el
  /// comentario de Gemma 4 en `_specs`—. Cuando el repositorio expone un
  /// único archivo fijo sin manifiesto —como el de Gemma 3n—, va nombrado
  /// acá para no depender de una resolución que ese repositorio no ofrece.
  final String? file;

  final String? nameContains;
}

const _specs = {
  ChatModelOption.gemma4E4b: _ModelSpec(
    modelType: ModelType.gemma4,
    repo: 'litert-community/gemma-4-E4B-it-litert-lm',
  ),
  ChatModelOption.gemma3nE4b: _ModelSpec(
    modelType: ModelType.gemmaIt,
    repo: 'google/gemma-3n-E4B-it-litert-lm',
    file: 'gemma-3n-E4B-it-int4.litertlm',
    nameContains: 'gemma-3n',
  ),
};

/// [domain.ChatModelManager] sobre `flutter_gemma`: el mismo mecanismo de
/// descarga bajo pedido explícito en Android y en Windows —
/// `flutter_gemma_litertlm` es lo que hace que el formato LiteRT-LM también
/// funcione en escritorio, ver la decisión 20 en docs/arquitectura.md—,
/// para cualquiera de las opciones de [ChatModelOption].
///
/// A diferencia de `HttpWhisperModelManager`, que baja los archivos a mano
/// con `dio`, acá se delega la descarga al propio `flutter_gemma`: ya trae
/// reintentos, progreso y —en Android— un servicio en primer plano para
/// descargas largas, así que reimplementar eso a mano sería duplicar
/// trabajo que el paquete ya resuelve bien.
class GemmaChatModelManager implements domain.ChatModelManager {
  const GemmaChatModelManager({required this.option});

  /// Qué modelo gestiona esta instancia. La pantalla de descarga crea una
  /// instancia distinta por cada opción que muestra, no una que cambie de
  /// opción sobre la marcha.
  final ChatModelOption option;

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
    // `flutter_gemma` no expone el tamaño de antemano: lo sabe recién
    // durante la descarga, por el progreso que reporta `withProgress`. Un
    // tamaño aproximado fijo en el código sería mentir apenas el modelo
    // cambie de variante o de cuantización. El tamaño aproximado que sí ve
    // quien elige la opción está en el texto de la pantalla, no acá.
    return null;
  }

  @override
  Stream<double> download({String? huggingFaceToken}) {
    final controller = StreamController<double>();
    final spec = _spec;

    // `fromHuggingFace` resuelve el archivo solo (por manifiesto) cuando
    // `file` queda en null, y usa el nombrado a mano cuando no —ver el
    // comentario de `_ModelSpec.file`—.
    unawaited(
      FlutterGemma.installModel(
            modelType: spec.modelType,
            fileType: ModelFileType.litertlm,
          )
          .fromHuggingFace(spec.repo, file: spec.file, token: huggingFaceToken)
          .withProgress((int progress) {
            if (!controller.isClosed) controller.add(progress / 100);
          })
          .install()
          .then((_) => controller.close())
          .catchError((Object e, StackTrace stackTrace) {
            controller.addError(_toDomainError(e), stackTrace);
          }),
    );

    return controller.stream;
  }

  /// El repositorio de Gemma está protegido (ver el comentario de
  /// `_specs`): `flutter_gemma` distingue el motivo exacto de una falla
  /// —401/403 no es lo mismo que sin conexión— y acá se traduce a algo que
  /// la pantalla pueda mostrar sin necesitar saber nada de HTTP ni de este
  /// paquete en particular.
  domain.ChatModelDownloadError _toDomainError(Object e) {
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
