import 'dart:async';

import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:sinapsis/features/chat/domain/services/chat_model_manager.dart'
    as domain;

/// Qué modelo Gemma se baja, y de dónde.
///
/// Gemma 4 E4B —cuantizado, formato LiteRT-LM— en vez de la Gemma 3 1B que
/// usaba esta pantalla antes (ver la decisión 20 en docs/arquitectura.md,
/// y la corrección posterior ahí mismo con el motivo del cambio): la 1B
/// contestaba con una redacción pobre y a veces vaga incluso citando bien
/// sus fuentes, un límite conocido de los modelos por debajo de los mil
/// millones de parámetros. E4B pesa considerablemente más —unos 4 GB contra
/// unos cientos de MB— y necesita un teléfono con memoria de sobra; es un
/// cambio consciente de prioridad hacia la calidad de la respuesta, sabiendo
/// que deja afuera a equipos de gama baja.
///
/// Se resuelve por **repositorio**, no por archivo suelto: a diferencia de
/// la Gemma 3 1B —que era un único `.litertlm`—, el repositorio de Gemma 4
/// publica el manifiesto de despliegue del modelo (`litertlm_manifest.json`)
/// con la variante exacta para cada plataforma. `fromHuggingFace(repo)` sin
/// `file` se lo pide a ese manifiesto en el momento de instalar, en vez de
/// que acá quede escrito a mano un nombre de archivo que un cambio de
/// versión del repositorio podría romper en silencio.
///
/// Gratis de verdad: Gemma es de pesos abiertos, sin costo ni clave de
/// pago. El repositorio está protegido en Hugging Face —Google exige
/// aceptar su licencia con una cuenta antes de dejar bajar el archivo,
/// nunca un pago— así que una descarga sin autenticarse siempre falla con
/// 401, sin importar la conexión de quien la pide: ver
/// `GemmaChatModelManager.download`.
const _modelRepo = 'litert-community/gemma-4-E4B-it-litert-lm';

/// [domain.ChatModelManager] sobre `flutter_gemma`: el mismo Gemma, con el
/// mismo mecanismo de descarga bajo pedido explícito, en Android y en
/// Windows — `flutter_gemma_litertlm` es lo que hace que el formato
/// LiteRT-LM también funcione en escritorio, ver la decisión 20 en
/// docs/arquitectura.md—.
///
/// A diferencia de `HttpWhisperModelManager`, que baja los archivos a mano
/// con `dio`, acá se delega la descarga al propio `flutter_gemma`: ya trae
/// reintentos, progreso y —en Android— un servicio en primer plano para
/// descargas largas, así que reimplementar eso a mano sería duplicar
/// trabajo que el paquete ya resuelve bien.
class GemmaChatModelManager implements domain.ChatModelManager {
  const GemmaChatModelManager();

  @override
  Future<bool> isReady() async {
    // `FlutterGemma.hasActiveModel()` no alcanza: solo dice "hay algún
    // modelo activo", sin importar cuál. Quien instaló esta app cuando
    // todavía bajaba Gemma 3 1B (ver la corrección posterior de la
    // decisión 20) sigue teniendo ESE modelo activo, y con solo
    // `hasActiveModel()` la pantalla de descarga se saltearía derecho a
    // "ya está listo" sin ofrecerle nunca bajar la 4B nueva. Comparar el
    // tipo de modelo es lo que distingue "ya tengo el que quiero" de "tengo
    // uno, pero no este".
    return FlutterGemma.activeModelSpec?.modelType == ModelType.gemma4;
  }

  @override
  Future<int?> downloadSizeInBytes() async {
    // `flutter_gemma` no expone el tamaño de antemano: lo sabe recién
    // durante la descarga, por el progreso que reporta `withProgress`. Un
    // tamaño aproximado fijo en el código sería mentir apenas el modelo
    // cambie de variante o de cuantización.
    return null;
  }

  @override
  Stream<double> download({String? huggingFaceToken}) {
    final controller = StreamController<double>();

    unawaited(
      FlutterGemma.installModel(
            modelType: ModelType.gemma4,
            fileType: ModelFileType.litertlm,
          )
          .fromHuggingFace(_modelRepo, token: huggingFaceToken)
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
  /// `_modelRepo`): `flutter_gemma` distingue el motivo exacto de una falla
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
