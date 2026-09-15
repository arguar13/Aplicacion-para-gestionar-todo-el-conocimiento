/// Qué modelo de lenguaje se descarga y usa para el chat, las tarjetas de
/// repaso y las sugerencias de vínculos del grafo — las tres tareas que
/// comparten el mismo modelo cargado (ver `GemmaChatModel` en la capa de
/// datos).
///
/// Dos opciones, no una escala continua de "calidad": la persona que usa la
/// app elige entre la que ya pedía menos espacio y la más nueva, más pesada
/// y con mejor redacción, sabiendo de antemano cuánto pesa cada una. Cuál
/// repositorio de Hugging Face y qué tipo de modelo le corresponde a cada
/// opción es un detalle de `flutter_gemma`, y vive en la implementación
/// concreta de `ChatModelManager`, no acá.
enum ChatModelOption {
  /// La opción por defecto en Android: Gemma 4 E4B, ~3.66 GB, ~4.000
  /// millones de parámetros "efectivos" (arquitectura elástica MatFormer:
  /// el modelo físico es más grande, pero se ejecuta como si tuviera ese
  /// tamaño). Ver la decisión 20 en docs/arquitectura.md.
  gemma4E4b,

  /// Gemma 3n E4B, ~4.9 GB, ~4.000 millones de parámetros efectivos —mismo
  /// mecanismo de activación selectiva que Gemma 4 E4B, de la familia
  /// anterior—. Sigue siendo Gemma, así que el mismo mecanismo de licencia
  /// y token de Hugging Face aplica igual.
  gemma3nE4b,

  /// La opción más pesada e inteligente de las tres: Gemma 4 12B, ~6.9 GB,
  /// 12.000 millones de parámetros densos —sin activación selectiva, es el
  /// modelo entero cargado—. Por defecto en Windows y demás escritorio,
  /// donde el tamaño y el consumo de RAM no compiten con la batería ni con
  /// la memoria limitada de un teléfono.
  ///
  /// **No está disponible en Android**: el propio fabricante del modelo
  /// (litert-community) lo publica listo para macOS, Linux y Windows —y
  /// una variante aparte y más liviana para web—, sin ningún build para
  /// Android ni iOS. Pedirle a un teléfono que cargue casi 7 GB en RAM no
  /// es una limitación arbitraria de esta app: es la realidad del modelo.
  /// Ver `isDesktopChatPlatform` en `chat_model_option_notifier.dart`, que
  /// es lo que oculta esta opción fuera de escritorio.
  gemma412b,
}
