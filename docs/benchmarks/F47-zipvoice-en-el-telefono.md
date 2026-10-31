# F47, paso 4: clonar en el teléfono con ZipVoice — por qué todavía no, y cómo medirlo

El plan (decisión C) pide clonar en el teléfono con ZipVoice sobre `sherpa_onnx`, **midiendo antes
si anda bien en español**, y no ofrecerlo hasta que lo haga. Esto es lo que se comprobó el
31/10/2026 y lo que hay que hacer para ofrecerlo.

## Lo que hay en `sherpa_onnx` 1.13.8 (la versión de la app)

- **La API de Dart lo trae.** `OfflineTtsZipVoiceModelConfig` (`tokens`, `encoder`, `decoder`,
  `vocoder`, `dataDir`, `lexicon`, `featScale`, `tShift`, `targetRms`, `guidanceScale`) y, al
  generar, `OfflineTtsGenerationConfig` con `referenceAudio` (un `Float32List` mono, de −1 a 1),
  `referenceSampleRate`, `referenceText` (lo que dice la muestra, palabra por palabra) y `numSteps`.
  Fuente: `lib/src/tts_config.dart` del paquete.
- **Un solo modelo publicado**, en la versión `tts-models` de sherpa-onnx:
  `sherpa-onnx-zipvoice-distill-int8-zh-en-emilia.tar.bz2` (109.162.785 bytes, SHA-256
  `77219c8b…2803`), más el vocoder `vocos_24khz.onnx` de la versión `vocoder-models`
  (54.157.409 bytes, SHA-256 `bcb3b970…3cc0`). Entrenado con Emilia en **chino e inglés**
  (`k2-fsa.github.io/sherpa/onnx/tts/zipvoice.html`).
- **El frente de texto lee el español como inglés.** ZipVoice usa `MatchaTtsLexicon`
  (`offline-tts-zipvoice-impl.h`); lo que no está en el léxico chino pasa por espeak-ng con la voz
  **`en-us` fija** (`matcha-tts-lexicon.cc`, `config.voice = "en-us"`). «Hola» sale como /hoʊlə/.
  No es una cuestión de calidad a medir: con esta versión, **no habla español**.
- **El otro que clona, Pocket TTS** (`OfflineTtsPocketModelConfig`, clona sin transcripción), es
  solo inglés. Supertonic no clona.

Por eso `OnDeviceCloning.available` es `false` y la pantalla de clonar dice «En el teléfono,
todavía no», con el motivo. No se dejó construido detrás de una marca: sin un modelo que hable
español, el código no tendría con qué probarse y bajaría 163 MB para leer mal.

## Qué haría falta

1. **Un modelo de ZipVoice que hable español** (o multilingüe con español) publicado para
   sherpa-onnx, con sus tokens y su léxico.
2. **Un frente que pase a espeak-ng la voz del idioma** (`es`) en vez de `en-us` fijo: un cambio en
   sherpa-onnx (`matcha-tts-lexicon.cc`, o un `lang` en `OfflineTtsZipVoiceModelConfig` como el de
   Kokoro), y la versión de `sherpa_onnx` que lo traiga.
3. Con eso, en la app: el paquete en el catálogo con su tamaño y su huella, la bajada a pedido
   como Kokoro, una familia `zipvoice` en `OfflineVoiceEngineConfig` y, en el isolate del motor,
   pasar la grabación de la voz (ya está en la bóveda, a 44,1 kHz) remuestreada a 24 kHz como
   `referenceAudio`, con el texto que se leyó al grabar como `referenceText` —el que propone la
   app, así que se sabe palabra por palabra—.

## Cómo medirlo en el teléfono, cuando haya modelo

Se mide en el teléfono del dueño (Xiaomi Redmi Note 13 Pro+) y, si se usa el emulador, se rotula
«emulador». La carpeta de cifras: `docs/benchmarks/<equipo>/<fecha>/latest_zipvoice_report.md`.

- **Las muestras:** tres voces con permiso —una de mujer, una de hombre, una con acento
  rioplatense marcado—, cada una grabada con la pantalla de clonar (1 a 2 minutos del texto
  propuesto, «Salió bien»).
- **Lo que se lee:** las mismas diez oraciones para todas, en español, con números, nombres
  propios, preguntas y una oración larga (más de 30 palabras).
- **Lo que se mide:**
  - **inteligibilidad**: se transcribe cada audio con el Whisper de la app y se cuenta el error
    por palabra (WER) contra el texto. Umbral: **≤ 10 %** (la voz del teléfono da menos del 5 %);
  - **parecido**: tres personas que conocen la voz puntúan de 1 a 5 si suena a ella. Umbral:
    **promedio ≥ 3,5**;
  - **acento**: las mismas personas dicen si suena a español nativo (sí/no). Umbral: **sí en las
    tres voces**;
  - **tiempo**: segundos de generación por segundo de audio (RTF), con `numSteps` 4 y 8. Umbral:
    **RTF ≤ 1**, para que el tramo que sigue esté listo antes de que termine el que suena;
  - **memoria**: la residente antes y con el motor armado. Umbral: que quepa junto con la app
    abierta sin que Android la cierre.
- **La decisión:** si las cinco cifras pasan, `OnDeviceCloning.available` pasa a `true` y se
  registra en la arquitectura con las cifras; si no, queda como está, con las cifras de por qué.
