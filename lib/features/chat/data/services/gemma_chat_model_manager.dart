import 'dart:async';

import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:sinapsis/features/chat/domain/services/chat_model_manager.dart'
    as domain;

/// Dónde vive el modelo Gemma, en Hugging Face, y qué variante se usa.
///
/// Gemma 3 1B —cuantizado, formato LiteRT-LM— es la más chica de la familia
/// con calidad de redacción razonable en español: por debajo de mil
/// millones de parámetros la prosa se degrada notoriamente (ver la
/// decisión 20). Pesa unos cientos de megas, bastante menos que las
/// variantes de escritorio de 3-4B que tendrían más calidad pero triplican
/// la descarga — se prioriza que la función funcione en un celular de gama
/// media antes que la mejor redacción posible.
///
/// Gratis de verdad: Gemma es de pesos abiertos, sin costo ni clave de
/// pago. El repositorio está protegido en Hugging Face —Google exige
/// aceptar su licencia con una cuenta antes de dejar bajar el archivo,
/// nunca un pago— así que una descarga sin autenticarse siempre falla con
/// 401, sin importar la conexión de quien la pide: ver
/// `GemmaChatModelManager.download`.
const _modelUrl =
    'https://huggingface.co/litert-community/Gemma3-1B-IT/'
    'resolve/main/Gemma3-1B-IT_multi-prefill-seq_q4_ekv4096.litertlm';

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
  Future<bool> isReady() async => FlutterGemma.hasActiveModel();

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
            modelType: ModelType.gemmaIt,
            fileType: ModelFileType.litertlm,
          )
          .fromNetwork(_modelUrl, token: huggingFaceToken)
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
  /// `_modelUrl`): `flutter_gemma` distingue el motivo exacto de una falla
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
