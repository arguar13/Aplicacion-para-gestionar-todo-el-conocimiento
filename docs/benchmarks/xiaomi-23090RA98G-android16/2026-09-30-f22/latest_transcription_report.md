# F22 — Transcripción en el teléfono del usuario

**Equipo:** Xiaomi 23090RA98G (Redmi Note 13 Pro+), MediaTek Dimensity 7200 (MT6886: 2 núcleos
de 2,8 GHz y 6 de 2,0 GHz), Android 16, HyperOS. 299 GB libres. El teléfono llegó a 52 °C en las
corridas seguidas.

**Cómo se midió:** `integration_test/transcription_fidelity_test.dart`, con el sabor `staging`
(otra app, sin tocar la bóveda del usuario). Motor: Whisper small int8 (sherpa-onnx 1.13.8), con
los tramos de hasta 14,5 s cortados en pausas y la protección contra bucles de F22. Los JSON de
cada corrida están en `raw/`. "Veces la duración" es el tiempo total dividido por la duración del
audio: 0,5 es que media hora de audio tarda un cuarto de hora.

Audios: una alabanza cantada con música ("La Bondad de Dios", 299 s) y los primeros 180 s de una
charla TEDx en español con subtítulos hechos por personas.

## Velocidad por cantidad de hilos (WAV de 16 kHz, compilación de depuración)

| Hilos | Alabanza (canto) | Charla (habla) |
|---|---|---|
| 2 | 0,34 / 0,44 | 0,68 |
| 3 | 0,38 | 0,67 |
| 4 (el de la app) | 0,36 | 0,68 |
| 6 | 0,36 | 0,69 |

Las diferencias entre 2 y 6 hilos son menores que lo que varía una misma configuración de una
corrida a otra (0,34 y 0,44 con 2 hilos, la segunda con el teléfono caliente): el procesador tiene
solo dos núcleos rápidos. La app sigue con 4. Una hora de habla densa: unos 40 minutos; una hora
de música: unos 20 a 26.

## Fidelidad

- Charla, contra los subtítulos humanos: **11,2 %** de diferencia palabra por palabra, el mismo
  texto exacto con 2 y con 4 hilos (el método de antes de F22 daba 11,5 % en la PC sobre el mismo
  tramo). Parte de esa diferencia no son errores: los subtítulos de TED están editados.
- Alabanza: ningún bucle, ningún hueco marcado; aparecen versos que el método viejo perdía
  ("Desde el momento que despierto").
- Ningún carácter roto en ningún texto.

## La conversión del audio (el defecto que daba disparates)

Duración del WAV que recibe Whisper, para el mismo audio de 299,4 s:

| Formato | Con `audio_decoder` | Con el conversor propio |
|---|---|---|
| WAV 16 kHz | 299,3 s | 299,3 s |
| AAC 44,1 kHz | 299,4 s | 299,4 s |
| HE-AAC (declara 22,05 kHz, entrega 44,1) | **598,9 s** ❌ | **299,4 s** ✅ |
| Opus 48 kHz | — | 299,3 s |

Tiempo de convertir 5 minutos (compilación profile, optimizada):

| | `audio_decoder` | Conversor propio |
|---|---|---|
| AAC 44,1 kHz | 103-113 s | 60-67 s |
| HE-AAC | 54 s | 32-35 s |
| WAV | 3,6 s | 0,6 s |

Del conversor propio, el remuestreo (Dart, polifásico) son 2 s; el resto es el decodificador del
sistema, unos 5 ms por bloque de audio: igual leyendo del almacenamiento privado que de `/sdcard`,
e igual con el decodificador de software (`c2.android.aac.decoder`) que con el que elige el
sistema. Transcripción completa con conversión incluida (profile, 4 hilos): WAV 0,36, HE-AAC
0,49, AAC 0,76 veces la duración.

## Otros motores (medidos en la PC, no en el teléfono)

Whisper "turbo" reconoce mejor la letra cantada pero inventa frases ("¡Suscríbete al canal!"),
entra en más bucles y es 3 a 4 veces más lento; en la charla dio 12,1 % contra 10,7 % de small. El
limpiador de voz GTCRN borra el canto como si fuera ruido. Ninguno se adoptó.
