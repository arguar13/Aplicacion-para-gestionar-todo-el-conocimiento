# F23 — El texto sigue al audio: resaltado palabra por palabra

> **Estado: aprobado** (2026-10-01), en el chat: A como se recomendó; B con un agregado del usuario
> —ver la decisión B—. Pedido del
> usuario: *"cuando está reproduciendo el audio (y ya tengo el texto transcripto) me gustaría que
> pongas un resaltado amarillo en la palabra que va leyendo el audio, así esté sincronizado con el
> texto y el audio […] que siempre que dé play al audio, el resaltado amarillo acompañe el dictado
> del audio en el texto"*. Y, ante una primera idea de repartir el tiempo "a ojo" dentro de cada
> renglón: *"hazmelo profesionalmente y de manera senior"*.

## Lo que hay hoy y por qué no alcanza

La transcripción guarda una marca de tiempo por renglón —"[0:14] …"—, uno cada ~14 s. El
momento de cada **palabra** no existe en ningún lado: el modelo que usa la app
(`csukuangfj/sherpa-onnx-whisper-small`) es una exportación de Whisper que no entrega la
"atención" del decodificador, y sin ella sherpa-onnx no puede calcular tiempos por palabra
(`enableTokenTimestamps` vuelve vacío: medido). Repartir los 14 s entre las palabras según su largo
daría errores de varios segundos en cada pausa: descartado.

## La solución: los tiempos que calcula el propio Whisper

Whisper sabe dónde está cada palabra: es la técnica de OpenAI para sus tiempos por palabra
(alineación por los "cabezales de atención" del decodificador más DTW), y sherpa-onnx la
implementa desde febrero de 2026 (PR #2945). Solo necesita una exportación del **mismo modelo**
que conserve esa salida. Existe: `clairemcw/sherpa-onnx-whisper-small-attention`, Whisper small
int8, mismos archivos y mismo tamaño (112 + 262 MB) que el de hoy.

### Medido en la PC (sherpa-onnx 1.13.8, el mismo de la app)

Un audio de un minuto en español con **los tiempos reales de cada palabra** —la voz de Windows
informa el instante exacto en que dice cada una: 160 palabras de referencia—, transcrito con el
mismo recorrido de la app (tramos cortados en pausas, con solape):

| | |
|---|---|
| Error mediano por palabra | **60 ms** |
| 90 % de las palabras | a menos de **155 ms** |
| Peor palabra | 400 ms |
| A menos de medio segundo | **100 %** |
| Costo extra de calcular los tiempos | **ninguno medible** (49,8 y 45,1 s sin; 48,7 y 47,3 s con) |
| Texto transcrito | **idéntico** al del modelo actual, tramo por tramo |

Un resaltado con 60 ms de error se ve "pegado" a la voz. Falta medirlo en el teléfono (el cálculo
de los tiempos corre en el procesador; en la PC no costó nada, en el teléfono se verifica) y con
voz real de tus audios.

## Qué se construye

1. **El modelo.** La app pasa a bajar la exportación con atención. Ya instalada la de hoy, se
   reemplaza (375 MB que se bajan, 375 MB que se liberan: el espacio no cambia) la próxima vez
   que haya que transcribir, avisando antes. Los archivos se verifican por su huella SHA-256 —ver
   decisión A—.
2. **Los tiempos por palabra salen del motor y no se pierden en el camino.** Cada tramo devuelve
   su texto **y** el momento de cada palabra; la protección contra bucles (que parte tramos en
   mitades), el cosido de los tramos solapados y el retomar tras un corte los conservan. Un hueco
   marcado ("[fragmento no reconocido]") no tiene tiempos, y el resaltado lo salta.
3. **Se guardan junto al texto** (esquema v33): la lista de palabras con su inicio y fin. Se
   vuelven a ubicar en el texto al mostrarlo, palabra por palabra, así que siguen sirviendo
   después de "Quitar marcas de tiempo" o de corregir una palabra a mano.
4. **En la pantalla del elemento**, mientras el audio suena: la palabra que se está diciendo, en
   **amarillo**, avanzando con la voz —también a 0,5× o 2×—. Además:
   - **Tocar una palabra lleva el audio a ese momento**, como en las transcripciones de YouTube.
   - La pantalla no se mueve sola: vos decidís dónde leer. Si el reproductor sale de la vista,
     aparece el mini reproductor flotante, con "Volver al audio" (decisión B).
5. **Lo que ya transcribiste** no tiene tiempos por palabra: con "Volver a extraer el texto" se
   transcribe de nuevo con el modelo nuevo y los gana. Mientras tanto, esos textos se resaltan
   **renglón por renglón** con las marcas que ya tienen, que son exactas. Nunca se inventa un
   tiempo por palabra que no se midió.

Fuera de esto, a propósito: los videos de YouTube no se reproducen dentro de la app (se abren en
YouTube), así que ahí no hay audio que seguir.

## Decisiones que necesito que confirmes

- **A. De dónde se baja el modelo.**
  - *(Recomendado)* De `clairemcw/sherpa-onnx-whisper-small-attention`, **fijado a una versión
    exacta** (commit `9a896a02`) y verificando la huella SHA-256 de cada archivo antes de usarlo:
    si alguien cambiara los archivos, la app no los acepta. Es de un tercero, pero ya comprobé que
    transcribe exactamente igual que el oficial.
  - Alternativa: exportarlo yo mismo desde los pesos oficiales de OpenAI. Hace falta instalar en
    la PC Python con PyTorch y Whisper (unos 3 GB, se borran después) y **alojarlo en una cuenta
    tuya** (GitHub o Hugging Face), porque la app tiene que bajarlo de algún lado. Más control,
    más pasos tuyos.
- **B. Seguir el audio.** *(Aprobado, con un agregado del usuario)* La pantalla no se mueve sola.
  Y como en un texto largo habría que subir hasta el reproductor para pausar: cuando el
  reproductor sale de la vista, aparece abajo un **mini reproductor flotante** —una pastilla, como
  la de YouTube Music o Spotify— con reproducir/pausar, una barra fina con el avance y el tiempo,
  la velocidad y **"Volver al audio"**, que lleva hasta la palabra que suena. Cuando el reproductor
  vuelve a verse, la pastilla se va. Los dos manejan el **mismo** audio: la reproducción pasa a ser
  de la pantalla del elemento, no del recuadro del reproductor.

## Orden de trabajo (cada paso compila, pasa el analizador y tiene sus pruebas)

1. Medir en el teléfono con la app de pruebas `staging`: costo de los tiempos y precisión con tus
   audios reales.
2. El modelo nuevo: descarga fijada y verificada, reemplazo del viejo.
3. El motor devuelve palabras con tiempos; bucles, solape y retomar los conservan.
4. Esquema v33: guardar las palabras con su tiempo junto al texto.
5. La reproducción pasa a la pantalla del elemento (un solo audio para el reproductor y la
   pastilla); el mini reproductor flotante.
6. El resaltado amarillo, tocar para saltar, "Volver al audio"; renglón por renglón para lo viejo.
7. Prueba de punta a punta en tu teléfono, decisión de arquitectura y cierre.

## Cómo se verifica

- Pruebas: los tiempos sobreviven a la partición por bucles, al cosido y al retomar; el resaltado
  avanza con la posición y la velocidad; tocar una palabra salta al momento justo; "Quitar marcas
  de tiempo" no rompe la sincronización.
- Medición contra referencia —la voz de Windows con sus tiempos— en la PC y en el teléfono, con
  cifras en `docs/benchmarks/`.
- Tu prueba en el teléfono con tus audios.
