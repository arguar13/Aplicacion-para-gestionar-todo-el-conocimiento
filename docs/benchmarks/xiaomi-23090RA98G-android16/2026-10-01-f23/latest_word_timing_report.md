# F23 — Tiempos por palabra para el resaltado sincronizado

**Para qué:** el resaltado amarillo que sigue al audio necesita saber en qué momento se dice cada
palabra. Esto mide qué tan exactos son esos tiempos y cuánto cuesta calcularlos.

**El modelo:** Whisper small int8, en la exportación "con atención"
`clairemcw/sherpa-onnx-whisper-small-attention`, fijada al commit
`9a896a02c311676d366ebfda3797753df4153fe2`. La exportación oficial
(`csukuangfj/sherpa-onnx-whisper-small`) no entrega la atención del decodificador, y sin ella
`enableTokenTimestamps` vuelve vacío. Motor: sherpa-onnx 1.13.8, el mismo de la app.

| Archivo | Bytes | SHA-256 |
|---|---|---|
| encoder | 112.445.386 | `570e2b92cce6a8be62dc37934057b82dd601298ecb3a2a25161542e2b59862aa` |
| decoder | 262.482.583 | `63233cc33d6c11ae514467a69132de87cc61e6b28d3dab40cdf8b0e3060a3439` |
| tokens | 816.730 | `b34b360dbb493e781e479794586d661700670d65564001f23024971d1f2fa126` |
| **Total** | **375.744.699** | |

**El audio de referencia:** 59 s de voz sintética en español (la voz "Sabina" de Windows), que
informa el instante real en que dice cada palabra (evento `SpeakProgress` de `System.Speech`): 160
palabras de referencia. "Veces la duración" es el tiempo total dividido por la duración del audio.

## Precisión (medida en la PC, Windows)

Mismo recorrido que la app: tramos cortados en pausas, con 3 s de solape.

| | |
|---|---|
| Palabras que devolvió el modelo | 156 |
| Emparejadas con la referencia | 155 |
| Error mediano | **60 ms** |
| p90 | 155 ms |
| p99 | 375 ms |
| Peor palabra | 400 ms |
| A menos de 250 ms | 97 % |
| A menos de medio segundo | **100 %** |
| Texto transcrito | **idéntico** al del modelo oficial, tramo por tramo |

Costo en la PC de calcular los tiempos (4 hilos): 49,8 y 45,1 s sin; 48,7 y 47,3 s con. La
diferencia es menor que lo que varía una corrida a otra: no medible.

## Velocidad en el teléfono

**Equipo:** Xiaomi 23090RA98G, MediaTek Dimensity 7200, Android 16 / HyperOS 3. App de pruebas
`staging`, compilación profile, 4 hilos, en primer plano. Dos corridas de cada una.

| Audio | Modelo oficial | Con atención y tiempos |
|---|---|---|
| Voz de referencia (59 s) | 70,7 s (1,199×, primera pasada, en frío) · 55,5 s (0,942×) | 60,8 s (1,030×) · 55,9 s (0,949×) |
| Nota de voz real del usuario (112 s, Opus de WhatsApp) | 91,8 s (0,819×) · 94,1 s (0,840×) | 92,1 s (0,822×) · 95,6 s (0,854×) |

Calcular los tiempos por palabra cuesta alrededor de **1 %** en el teléfono.

## Notas honestas

1. **La precisión por palabra se midió en la PC; en el teléfono, solo la velocidad.** Los archivos
   con los tiempos calculados en el teléfono se perdieron: `flutter drive` desinstaló la app de
   pruebas al terminar. El cálculo es el mismo motor, en la misma versión.
2. **Corrección al commit `da5439c`.** Su mensaje dice que el texto salió idéntico "en la PC y en
   el teléfono". En el teléfono no se verificó el texto, solo la velocidad; el texto idéntico, tramo
   por tramo, se verificó en la PC.
3. **Una primera medición se descarta.** Dio 1,6–1,8× porque la app de pruebas quedó en segundo
   plano y HyperOS la limitó (y terminó cerrándola por "uso excesivo de CPU en segundo plano").
   Las cifras de arriba son con la app en primer plano.
4. **No se compara con F22.** El 0,8–0,95× de acá no se puede poner al lado del 0,36–0,68× del
   [informe de F22](../2026-09-30-f22/latest_transcription_report.md): aquel midió el transcriptor
   de la app —el motor en un isolate propio, tramos sin solape—, y este llama al motor directo
   desde la prueba, con los tramos solapados 3 s (unos 3 s más de audio por cada 14,5, alrededor de
   un 20 % más de trabajo, por cuenta). Cuánto pesa cada diferencia no se midió. Lo que sí vale es
   la comparación de esta tabla: el modelo oficial y el con atención corrieron en las mismas
   condiciones, y la diferencia es de alrededor de 1 %.
