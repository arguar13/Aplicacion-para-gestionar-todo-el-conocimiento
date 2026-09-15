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
  /// La opción por defecto: Gemma 4 E4B, unos 4.3 GB. Ver la decisión 20 en
  /// docs/arquitectura.md.
  gemma4E4b,

  /// La opción más pesada e inteligente: Gemma 3n E4B, unos 4.9 GB, con
  /// mejor redacción a costa de más espacio y más RAM. Sigue siendo Gemma,
  /// así que el mismo mecanismo de licencia y token de Hugging Face aplica
  /// igual.
  gemma3nE4b,
}
