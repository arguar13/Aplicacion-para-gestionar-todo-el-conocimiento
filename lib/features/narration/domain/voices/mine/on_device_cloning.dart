/// Clonar una voz **en el teléfono** (F47, paso 4, decisión C): con ZipVoice
/// sobre `sherpa_onnx`. Hoy **no se ofrece**, y no por falta de medirlo: con
/// la versión de la app (1.13.8) no puede hablar español.
///
/// **Qué hay** (comprobado en el código de sherpa-onnx v1.13.8 y en su versión
/// `tts-models` el 31/10/2026):
///
/// - La API de Dart lo trae: `OfflineTtsZipVoiceModelConfig` (`tokens`,
///   `encoder`, `decoder`, `vocoder`, `dataDir`, `lexicon`) y, al generar,
///   `OfflineTtsGenerationConfig` con `referenceAudio` (las muestras de la
///   voz a clonar, de −1 a 1), `referenceSampleRate` y `referenceText` (lo
///   que dice esa muestra, palabra por palabra).
/// - **Un solo modelo publicado**, `sherpa-onnx-zipvoice-distill-int8-zh-en-
///   emilia` (109 MB, más el vocoder `vocos_24khz.onnx`, 54 MB): entrenado
///   con Emilia en **chino e inglés**.
/// - **El texto se pasa a fonemas con el léxico chino y, lo que no está ahí,
///   con espeak-ng en `en-us`, fijo** (`matcha-tts-lexicon.cc`, que es el
///   frente de ZipVoice: `config.voice = "en-us"`). Un texto en español se
///   pronunciaría como si fuera inglés —«hola» como /hoʊlə/—, aunque la voz
///   clonada fuera la de quien habla español.
/// - Pocket TTS, el otro que clona en esa versión, es solo inglés.
///
/// **Qué haría falta para ofrecerlo**: un modelo de ZipVoice entrenado en
/// español (o multilingüe con español) publicado para sherpa-onnx, y un frente
/// que pase a espeak-ng la voz del idioma (`es`) en vez de `en-us` fijo. Con
/// eso, se mide en el teléfono antes de ofrecerlo, como dice
/// `docs/benchmarks/F47-zipvoice-en-el-telefono.md`.
abstract final class OnDeviceCloning {
  /// Si clonar en el teléfono se ofrece. `false` hasta que haya un modelo
  /// que hable español y se mida en el teléfono.
  static const available = false;
}
