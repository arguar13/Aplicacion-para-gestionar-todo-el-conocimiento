# Arquitectura de Sinapsis

Cómo está pensada la app, qué decisiones la sostienen y en qué orden se
construye lo que falta.

> Este documento describe el **diseño**. Lo que ya está construido se
> distingue en la sección [Estado y orden de construcción](#estado-y-orden-de-construcción);
> el resto todavía no existe en el código.

---

## Principios

Cuatro reglas que resuelven la mayoría de las discusiones de diseño antes de
que empiecen.

**1. Todo ocurre en el dispositivo.** Transcribir, reconocer texto, extraer,
buscar: nada sale de acá. No por purismo, sino porque es lo que hace que la
app sea gratis de verdad, funcione sin conexión y no dependa de que un
servicio siga existiendo el año que viene. Las únicas conexiones salientes son
las que el usuario pide explícitamente: traer la página que quiere archivar.

**2. La procedencia no se pierde nunca.** Un texto sin origen es una cita sin
autor: sirve para leer, no para trabajar. Cada cosa guardada conserva su
enlace, su autor, cuándo se capturó y —cuando tiene sentido— una copia del
formato original. Si un recorte no puede decir de dónde salió, el recorte está
incompleto.

**3. Nada de formatos cerrados.** El contenido se guarda en SQLite y archivos
sueltos, en texto plano y Markdown. Alguien tiene que poder abrir la carpeta
dentro de diez años, sin esta app, y encontrar lo suyo.

**4. Degradar antes que fallar.** Un video sin subtítulos igual entra: queda
el enlace y el título, y la transcripción se puede pedir después. Rechazar
algo porque una etapa opcional no funcionó es peor que aceptarlo incompleto.

---

## El recorrido de una captura

```
        ┌──────────────┐
        │   ENTRADA    │  compartir desde otra app · pegar un enlace
        └──────┬───────┘  soltar un archivo · escribir una nota
               │
               ▼
        ┌──────────────┐
        │   ADAPTER    │  ¿qué es esto? Reconoce la fuente y su procedencia
        └──────┬───────┘  YouTube · web · social · archivo · texto
               │
               ▼
        ┌──────────────┐
        │   ITEM       │  Guardado YA, con su enlace y su título provisional
        └──────┬───────┘  El usuario ya puede cerrar la app
               │
               ▼
        ┌──────────────┐
        │     COLA     │  De a uno, en segundo plano. Lo que falla no se
        └──────┬───────┘  pierde: conserva su enlace y se reintenta
               │
               ▼
        ┌──────────────┐
        │ TRANSFORMER  │  Lo convierte en una o más representaciones
        └──────┬───────┘  video→transcripción · HTML→artículo · audio→texto
               │
               ▼
        ┌──────────────┐
        │ ITEM COMPLETO│  Aparece solo en la lista: las pantallas escuchan
        └──────┬───────┘  los cambios de la base
               │
       ┌───────┴────────┐
       ▼                ▼
  ORGANIZACIÓN      EXPORTACIÓN
  etiquetas          Markdown · PDF
  relaciones         texto · HTML
  búsqueda           NotebookLM
```

El item se guarda **antes** de transformarlo, no después. Es lo que permite
capturar diez enlaces en el subte sin conexión y cerrar la app: lo que se
guardó está guardado, y el contenido llega cuando haya red.

La separación entre **adapter** y **transformer** es la que permite que esto
crezca sin volverse un nudo:

- Un **adapter** sabe de una *fuente*: cómo reconocer una URL de YouTube,
  cómo pedir sus subtítulos, dónde está el nombre del canal.
- Un **transformer** sabe de un *formato*: cómo convertir audio en texto, sin
  que le importe si ese audio salió de un reel, de un podcast o del micrófono.

Agregar TikTok es escribir un adapter. Cambiar el motor de transcripción es
cambiar un transformer. Ninguno de los dos toca al otro.

---

## Modelo de datos

```
  Source ─────────┐
   tipo           │
   url            │        ┌──────────── Rendition
   autor          │        │  tipo (texto/markdown/html/imagen/audio)
   authorUrl      ▼        │  contenido o ruta al archivo
   capturedAt   Item ──────┤  esPrincipal
   originalPath  título    │
                 subtítulo └──────────── Rendition
                 notas
                    │
        ┌───────────┼───────────┐
        ▼           ▼           ▼
      Tag        Relation    Highlight
    etiqueta    itemA↔itemB   recorte + nota
                  tipo        sobre una rendition
```

**`Item`** es la unidad: una cosa guardada. Tiene título y subtítulo porque el
requisito de filtrar por ambos es explícito, y porque un video y un capítulo
de libro se distinguen mejor con dos niveles que con uno.

**`Source`** es de dónde vino. Vive aparte del item para que la procedencia
sea una entidad y no cuatro campos sueltos que alguien pueda olvidarse de
completar.

**`Rendition`** es cada forma en que ese contenido existe. Un video de YouTube
puede tener tres a la vez: la transcripción, el enlace al original y una
captura de la miniatura. Que sean varias —y no un campo `contenido`— es lo que
responde al pedido de *elegir en qué formato conservarlo*: no se elige uno y
se descartan los demás, conviven y se exporta el que haga falta.

**`Relation`** conecta dos items. Es lo que convierte una pila de recortes en
algo con forma: "esto continúa aquello", "esto contradice esto otro", "estos
tres son del mismo tema".

**`Highlight`** es un fragmento marcado dentro de una rendition, con una nota
opcional. Es lo que hacía Glasp, adentro.

### Dónde vive

SQLite mediante [`drift`](https://pub.dev/packages/drift), con **FTS5** para
la búsqueda de texto completo. Los archivos pesados —el PDF original, el audio,
las imágenes, la copia de la página— van al directorio de documentos de la app
y la base guarda la ruta. Meter binarios grandes en SQLite hace lenta cada
consulta que no los necesita, que son casi todas.

FTS5 viene incluido en el SQLite de Android e iOS: la búsqueda por contenido
—no solo por título— no cuesta ninguna dependencia extra.

---

## Adapters: reconocer la fuente

Cada uno implementa un contrato común y declara qué sabe manejar. El registro
le pregunta a cada uno hasta que alguno acepta.

| Adapter | Qué reconoce | Con qué |
|---|---|---|
| `YouTubeAdapter` | youtube.com, youtu.be, Shorts | [`youtube_explode_dart`](https://pub.dev/packages/youtube_explode_dart) — metadatos y subtítulos **sin API key ni cuotas** |
| `WebPageAdapter` | Cualquier http(s) | `dio` + [`html`](https://pub.dev/packages/html) |
| `SocialPostAdapter` | X, Bluesky, Mastodon | oEmbed abierto donde exista; si no, el texto compartido más la URL |
| `FileAdapter` | PDF, EPUB, DOCX, imágenes, audio | Delega en el transformer según el tipo |
| `PlainTextAdapter` | Texto suelto | Nada: es el caso base |

**Sobre Instagram y TikTok.** No hay forma limpia ni estable de extraer su
contenido desde afuera, y tampoco hace falta: cuando compartís un reel a
Sinapsis, el sistema operativo entrega el video o el enlace. De ahí sale el
audio, y del audio la transcripción — que es exactamente lo que se quería. La
ruta pasa por el botón de compartir del teléfono, no por raspar su web.

---

## Transformers: convertir el formato

| Transformer | De → a | Con qué | Dónde corre | Estado |
|---|---|---|---|---|
| `YouTubeTranscriptTransformer` | video → transcripción con marcas de tiempo | [`youtube_explode_dart`](https://pub.dev/packages/youtube_explode_dart) — **sin API key ni cuotas** | Dispositivo | Construido |
| `WebArticleTransformer` | HTML → artículo en Markdown | [`reader_mode`](https://pub.dev/packages/reader_mode) (Readability de Mozilla) + conversor propio sobre [`html`](https://pub.dev/packages/html), sin escapar el texto (F22) | Dispositivo | Construido |
| `AudioTranscriber` | audio → texto | [`sherpa_onnx`](https://pub.dev/packages/sherpa_onnx) con modelos Whisper | Dispositivo, en un isolate | Fase 7 |
| `ImageTextExtractor` | imagen → texto | [`google_mlkit_text_recognition`](https://pub.dev/packages/google_mlkit_text_recognition) | Dispositivo | Fase 7 |
| `PdfParser` | PDF → texto | [`pdfrx_engine`](https://pub.dev/packages/pdfrx_engine) (MIT) sobre el PDFium de Chromium | Dispositivo | Construido |
| `EpubParser` | EPUB → Markdown, en orden de lectura | `archive` + `xml` propios (ver la decisión 3) | Dispositivo | Construido |
| `DocxParser` | DOCX → Markdown con encabezados, listas y tablas | `archive` + `xml` (un .docx es un zip con XML adentro) | Dispositivo | Construido |
| `PlainTextParser` | TXT y MD → Markdown | Nada: los bytes ya son el contenido | Dispositivo | Construido |
| `PageArchiver` | HTML → archivo único | Recursos incrustados como data URI, el enfoque de SingleFile | Dispositivo | Construido |

### La cola

Traer contenido tarda y puede fallar, así que no pasa mientras el usuario
espera. El item se guarda enseguida con lo que se tenga —su enlace, su título
provisional, su nota— y el contenido aparece en la lista cuando llega, porque
las pantallas escuchan los cambios de la base. Nadie debería esperar mirando
una barra de progreso para poder guardar algo.

**De a uno y no en paralelo.** Capturar diez enlaces de golpe —algo normal al
vaciar una lista de pendientes— dispararía diez descargas simultáneas: una
ráfaga contra los mismos servidores, que invita a que corten el acceso, y diez
transcripciones compitiendo por la memoria de un teléfono.

**Lo persistente es el estado, no la cola.** La cola en sí vive en memoria; lo
que sobrevive al cierre de la app es el estado de cada item en la base
—esperando, en curso, listo o fallido—. Al abrir la biblioteca, todo lo que
quedó *esperando* se vuelve a encolar solo. Es lo mismo desde afuera y mucho
menos maquinaria: no hace falta una tabla de trabajos que se pueda
desincronizar de los items que describe.

**Lo que falló no se reintenta solo.** Queda marcado como *fallido*, no como
*esperando*, y por eso no vuelve a entrar en cada arranque. Un fallo puede ser
permanente —un video borrado, una página que ya no existe— y reintentarlo cada
vez sería gastar batería y datos para volver a fallar. Se reintenta a pedido,
con un botón en el elemento.

Todo esto es la forma concreta del principio de *degradar antes que fallar*:
si traer el contenido falla, el item conserva su enlace, su título y su nota.
Nunca se borra nada por un error de red.

---

## Organización

**Etiquetas**, puestas a mano, con autocompletado de las que ya existen —
escribir el nombre de una que ya está, sin distinguir mayúsculas, reutiliza
esa etiqueta en vez de crear una segunda que compite por agrupar lo mismo. Se
filtra la biblioteca por ellas igual que por tipo de fuente.

**Relaciones** explícitas entre elementos, con tipo: relacionado, continúa,
contradice, cita, resume. Se eligen a mano, en dos pasos —con qué elemento y
de qué tipo— y se ven desde los dos lados, con el sentido de la frase
correcto según cuál de los dos se esté mirando: "continúa en X" parado en el
origen, "es la continuación de X" parado en el destino.

Sugerir candidatas automáticamente —por términos compartidos, o por
similitud semántica— quedó fuera a propósito y no es una omisión: un grafo
lleno de vínculos de baja calidad vale menos que veinte hechos a mano, y la
alternativa seria (embeddings, un modelo de lenguaje local) es una pieza de
trabajo aparte, no una extensión de esto. Si alguna vez se agrega, entra como
sugerencia que alguien confirma, nunca como un vínculo que se guarda solo.

**Resaltados** con nota opcional, sobre cualquier forma de texto. Se ven
incrustados en el propio contenido —con un fondo distinto— y listados aparte
para poder repasarlos sin releer todo. Sus índices son independientes del
contenido actual a propósito: si una transcripción se rehace con un modelo
mejor y cambia de longitud, el resaltado sigue mostrando el fragmento que se
guardó en su momento, aunque ya no se pueda ubicar en el texto nuevo.

**Búsqueda** sobre título, subtítulo y contenido completo, vía FTS5, con
filtros combinables por tipo de fuente, etiqueta y estado de procesamiento.

**Orden** por fecha de captura, fecha de publicación original, última
modificación o título — y por relevancia cuando hay una búsqueda activa.

---

## Exportación

Cada `Item` puede salir en cualquiera de sus renditions, y en formatos
derivados:

- **Markdown** con una cabecera YAML que incluye la procedencia. Es el formato
  de intercambio por defecto: lo leen Obsidian, Logseq, Notion y cualquier
  editor de texto.
- **PDF** vía [`pdf`](https://pub.dev/packages/pdf) (Apache-2.0, Dart puro),
  para leer o imprimir fuera de la app.
- **Texto plano**, cuando solo importa el contenido.
- **HTML original**, la copia de la página tal como estaba: recursos
  incrustados como data URI en un solo archivo, al modo de SingleFile.
- **Abrir el archivo original** con la app que el sistema tenga asociada —el
  lector de PDF, la galería de fotos—, para lo que no tiene sentido convertir.
- **Paquete para NotebookLM**: los items seleccionados como archivos que
  NotebookLM ingiere bien, más un índice con las fuentes, y un enlace que abre
  el sitio para subirlos.

### Por qué NotebookLM se exporta y no se integra

NotebookLM **no tiene API pública**. Existe una de Gemini Notebook Enterprise,
pero es para organizaciones con Google Cloud y no es algo a lo que un usuario
pueda suscribirse. Google reconoció públicamente el pedido de una API de
consumidor; hasta que exista, cualquier "integración" sería automatizar un
navegador contra un sitio que no lo autoriza — frágil, y rompible por Google
en cualquier momento sin aviso.

La exportación cuidada es honesta y funciona hoy. El día que la API exista, se
enchufa como un exportador más: el resto del sistema no se entera.

---

## Decisiones registradas

Las que cuestan caro revertir, con su motivo.

### 1. Sin servidor

Todo en el dispositivo. Elimina costos, cuentas, políticas de privacidad y la
posibilidad de que el proyecto muera cuando se acabe el nivel gratuito de
algo.

**Lo que cuesta:** la sincronización entre dispositivos deja de ser gratis en
esfuerzo. Cuando haga falta, el camino es exportar e importar, o sincronizar
la carpeta con lo que el usuario ya use.

### 2. Bóveda local en lugar de cuenta

Sin servidor no hay a quién autenticarse, pero sí hay un dispositivo que puede
quedar en manos de otra persona. El modelo es "abrir la bóveda", no "iniciar
sesión". Detalles en
[`lib/features/vault/`](../lib/features/vault/).

**Lo que cuesta:** no hay recuperación de clave. Es una consecuencia
inevitable de que la clave no viaje a ningún lado, y la pantalla de creación
lo dice antes de que el usuario elija.

### 3. Librerías abiertas en lugar de servicios de terceros

Reimplementar lo que hacían DownSub, SingleFile, Glasp o PrintFriendly en vez
de integrarlas. Ninguna tiene API gratuita; integrarlas sería scraping frágil
o cuentas de pago.

**Lo que cuesta:** trabajo de implementación propio. A cambio: funciona sin
conexión, sin cuotas, y no se rompe cuando un servicio cambia su HTML.

**Qué cuenta como "libre" acá.** Una licencia libre de verdad —MIT, BSD,
Apache— no una gratuidad condicional. La diferencia importa y es la razón por
la que se descartó `syncfusion_flutter_pdf`, que el plan original proponía: su
"Community License" es una licencia **propietaria** que solo permite el uso
gratuito a organizaciones con menos de un millón de dólares de facturación
anual y menos de cinco desarrolladores. Es un permiso condicional que se puede
perder por crecer, y que obliga a aceptar términos de un tercero para usar la
app. Se usa [`pdfrx`](https://pub.dev/packages/pdfrx) (MIT, sobre el PDFium de
Chromium) en su lugar.

Por el mismo criterio, EPUB y DOCX se leen con `archive` + `xml` en vez de
adoptar un paquete dedicado: los dos formatos son un ZIP con XML adentro y
estándares documentados, y los candidatos disponibles estaban abandonados
—`epubx` lleva tres años sin publicar— o eran demasiado nuevos para
confiarles el formato en el que alguien guarda su biblioteca. Un lector de
spine de EPUB son unas cien líneas que se pueden probar; una dependencia
muerta en el camino crítico, no.

### 4. Adapters y transformers separados

Explicado arriba. La alternativa —una clase por combinación de fuente y
formato— se vuelve inmanejable en cuanto hay cinco de cada.

### 5. SQLite con FTS5, no archivos sueltos ni una base de documentos

La búsqueda de texto completo sobre miles de items es el caso de uso central,
y FTS5 ya viene en el SQLite del sistema. Los binarios grandes van al sistema
de archivos, no adentro de la base.

### 6. Android y escritorio antes que web

La captura real empieza en el botón de compartir del teléfono. Y son las
plataformas donde se puede transcribir y reconocer texto localmente: en web no
hay ML Kit, no hay isolates de verdad para Whisper, y CORS impide descargar
páginas ajenas.

**Lo que cuesta:** la versión web llega después y con menos capacidades.
Consumir y buscar funcionará; capturar y transformar, no del todo.

### 7. Compartir desde otras apps: Android completo, iOS pospuesto a propósito

Aparecer en la hoja de compartir de un sistema operativo exige configuración
nativa, y esa configuración no pesa lo mismo en las dos plataformas. En
Android es agregar intent-filters a un `AndroidManifest.xml` que ya existe:
texto plano, legible, que además ya compila en la integración continua. En
iOS hace falta algo de otra naturaleza — una Share Extension, que es un
**target nuevo** dentro del proyecto de Xcode, con su propio `Info.plist`,
sus entitlements y un App Group para pasarle lo compartido a la app
principal.

Armar eso a mano, editando `project.pbxproj` sin Xcode, es escribir a ciegas
un archivo que ni siquiera se puede abrir para comprobar que quedó bien: este
proyecto corre en Linux, no en una Mac, y la integración continua todavía no
compila iOS (ver "Construido" más abajo). Un error ahí no lo marca ninguna
prueba; lo nota recién quien intente abrir el proyecto en Xcode y lo
encuentre roto.

**Lo que cuesta:** en iOS, compartir un enlace o un archivo a Sinapsis desde
otra app no funciona todavía. Pegarlo a mano en la pantalla de captura, sí.

Y a diferencia de otras cosas pospuestas en este documento, esta no espera a
que el proyecto tenga con qué compilar y probar iOS: Android y la web son
las plataformas reales de quien construye esta app —no hay ningún
dispositivo iOS en el que probarla—, así que no tiene sentido invertir ahí
antes que en profundizar las dos que sí se usan. Si el día de mañana hay un
iPhone de por medio, la Share Extension se agrega con la misma prolijidad
que todo lo demás; hasta entonces, no es una prioridad.

### 8. Whisper "small" multilingüe, traído aparte y con permiso explícito

Transcribir voz en el dispositivo, sin mandar audio a ningún servidor, es
justamente lo que pide el principio 1 — pero exige tres decisiones propias
que no se resuelven solas.

**Qué tamaño de modelo.** [`sherpa_onnx`](https://pub.dev/packages/sherpa_onnx)
(Apache 2.0) corre Whisper en el dispositivo vía FFI, y ofrece varios
tamaños ya exportados a ONNX. Se eligió "small" multilingüe —unos 375 MB
entre encoder, decoder y vocabulario, cuantizados a int8— en vez de "base"
—bastante más chico, ~160 MB, la elección original—: en español, que es el
idioma principal de quien usa esta app, la ganancia de precisión de "base"
a "small" es notoria, y el dispositivo hace ese trabajo una sola vez por
transcripción, no en tiempo real, así que el costo extra de CPU no se nota
tanto como pesa la descarga. Los tres archivos se traen sueltos de Hugging
Face (el repositorio de quien mantiene `sherpa-onnx`), no el paquete
`.tar.bz2` de sus releases de GitHub: es la misma fuente, sin tener que
descomprimir bzip2 en el dispositivo.

**Idioma fijado, no autodetectado.** `OfflineWhisperModelConfig.language`
queda en `'es'` —antes vacío, que en sherpa-onnx significa "autodetectar"—
porque esa autodetección corre por separado en **cada** ventana de 30
segundos en la que se corta un audio largo —ver `transcribeInChunks` en
`pcm16_samples.dart`—, y no en el audio completo una sola vez. Sin fijarlo,
un fragmento corto, con ruido o con un nombre propio en otro idioma puede
hacer que Whisper "cambie de idioma" a mitad de una transcripción en
español. `task` queda en `'transcribe'` por el mismo motivo: explícito, no
librado al valor por defecto.

**Cómo llega el audio hasta ahí.** `sherpa_onnx` sólo sabe leer WAV
—`readWave()` no entiende MP3, M4A ni la pista de audio de un video—, así
que hace falta convertir antes. El estándar histórico para esto,
`ffmpeg_kit_flutter`, se dejó de mantener a mediados de 2025: mismo motivo
por el que se descartaron `epubx` o
`syncfusion_flutter_pdf` en la decisión 3, no se lo va a sumar ahora. En su
lugar,
[`audio_decoder`](https://pub.dev/packages/audio_decoder) (MIT) convierte
cualquier formato común —incluido el audio de un MP4— a PCM crudo usando
las APIs nativas de cada sistema operativo, sin empaquetar FFmpeg.

**Cuándo se descarga.** 375 MB es demasiado para bajarlos solos la primera
vez que alguien toca "transcribir": el principio 1 permite conexiones
salientes cuando el usuario las pide explícitamente, y esta es exactamente
esa excepción, no un atajo alrededor de la regla. Por eso el modelo no se
descarga nunca en silencio: hay una pantalla propia —accesible desde el
ícono de micrófono de la biblioteca— que muestra el tamaño antes de bajar,
el progreso mientras baja, y un error con reintento si algo sale mal. Una
vez descargado queda en la carpeta de documentos de la app y no se vuelve a
pedir.

**Lo que cuesta:** transcribir la primera vez implica un paso previo y una
descarga grande, no es instantáneo. A cambio, la transcripción en sí no
depende de conexión ni de que un servicio externo siga existiendo.

### 9. Base de datos y archivos en la web: WebAssembly y OPFS, no un servidor

`driftDatabase()` se llamaba sin el parámetro que `drift_flutter` exige para
compilar a la web, así que hoy la app revienta apenas intenta abrir la
base ahí. Arreglarlo no es solo pasar un parámetro: hace falta decidir
dónde vive de verdad cada cosa cuando no hay sistema de archivos.

**La base de datos.** `drift` compila a WebAssembly con `sqlite3.wasm`
corriendo en un worker aparte —el mismo SQLite de siempre, no una
reimplementación—, pero a diferencia de `sherpa_onnx_web` (decisión 8), acá
los archivos **no** vienen empaquetados en el paquete: hay que traer
`sqlite3.wasm` y `drift_worker.js` a mano, en la versión exacta que fijan
`sqlite3` y `drift` en `pubspec.lock`. Mismo criterio que
`tool/fetch_pdfium.sh`: un script versionado en vez de un archivo binario
sumado al repositorio a mano, para que actualizar `drift` no deje una copia
vieja del worker dando vueltas sin que nadie lo note.

**Los archivos originales.** `FileStore` guarda documentos, imágenes,
audio y video que pueden pesar cientos de megas, y en el navegador no hay
ningún directorio real donde ponerlos. La respuesta no es meterlos en la
base —seguiría siendo cierto lo que dice `file_store.dart`: SQLite se
vuelve lento con binarios grandes adentro, y en un WASM corriendo en el
navegador ese costo pesa todavía más—. La respuesta es el **Origin Private
File System** (OPFS): un sistema de archivos real, privado al origen de la
página, pensado justo para esto —soporta archivos de cientos de megas sin
mandar nada a ningún lado—. Se accede con `package:web` y
`dart:js_interop` directo, sin sumar un paquete de por medio: la API es
chica (obtener el directorio, un handle de archivo, un stream para
escribir) y ya hay ese mismo estilo de interop en el propio `audio_decoder`
y en `sherpa_onnx`, así que no suma una forma nueva de hacer las cosas.

**Cómo conviven las dos implementaciones.** `FileStore` es una interfaz;
`LocalFileStore` (sobre `dart:io`) y la nueva `OpfsFileStore` son sus dos
implementaciones, elegidas en tiempo de compilación con el mismo mecanismo
de `import if (dart.library.io) ... if (dart.library.js_interop) ...` que
ya usa `sherpa_onnx` puertas adentro. Ninguna de las dos clases importa lo
que no puede compilar en su plataforma: `dart:io` no existe en la web, y no
tiene sentido escribir la versión web con las manos atadas para que
"parezca" la nativa.

**Lo que cuesta:** dos implementaciones de `FileStore` para mantener, y un
par de archivos binarios que hay que resincronizar a mano cuando cambien
las versiones de `drift`/`sqlite3` —el script deja ese trabajo en un solo
comando, pero sigue siendo manual—. A cambio, la web guarda tanto como
Android: nada se trunca ni se manda a ningún servidor por no tener dónde
ponerlo.

### 10. OCR y transcripción en la web: los mismos principios, otro motor

La decisión 6 daba por sentado que la web no iba a tener esto. Investigar
en vez de asumir cambió la respuesta para las dos cosas, aunque no de la
misma forma.

**Transcripción.** `sherpa_onnx` —ya elegido en la decisión 8— trae su
propio soporte de WebAssembly, con la misma API pública que la versión
nativa en el papel. En la práctica hicieron falta dos ajustes reales y el
arreglo de un defecto del propio paquete, ninguno cosmético:

- `readWave()` —la función que lee un WAV de disco— está sin implementar en
  la web ("not yet supported"). La solución no es esquivarla con un parche
  para la web: es dejar de depender de ella *en las dos plataformas*, con
  una sola función de Dart puro (`pcm16ToFloat32Samples`, con sus propias
  pruebas) que convierte PCM de 16 bits a las muestras normalizadas que
  pide `acceptWaveform()`. Lo que sigue siendo distinto es de dónde salen
  esos bytes, porque ahí sí hay una asimetría real entre plataformas: fuera
  de la web, `audio_decoder.convertToWav()` sigue convirtiendo el archivo
  de origen a un WAV temporal *archivo a archivo*, no bytes a bytes —para
  que un video de cientos de megas nunca se cargue entero en la memoria de
  Dart—, y de ahí se leen los bytes ya convertidos para pasarlos por
  `pcm16ToFloat32Samples`. En la web, `convertToWav()` está directamente
  sin implementar ("Use convertToWavBytes instead"): no hay alternativa a
  cargar el origen entero en memoria y usar `convertToWavBytes()`, que
  además ignora el `formatHint` que pide como argumento obligatorio —en la
  web decodifica con la Web Audio API, que reconoce el formato por el
  contenido, no por una pista aparte— y lo resuelve con la propia API del
  navegador en vez de con un archivo temporal. Resultado: una función de
  conversión final compartida entre plataformas; lo que cambia es solo
  cómo se llega a esos bytes, y ese cambio es inherente a no tener sistema
  de archivos en el navegador, no una limitación evitable.
- `dart:isolate` no compila en la web —se le sacó el soporte a `dart2js`
  hace años, y sigue así—, así que `Isolate.run` no es una opción ahí. La
  implementación web de sherpa-onnx tampoco lo intenta: decodifica en el
  hilo principal, con llamadas directas a WebAssembly. Se sigue el mismo
  camino en vez de inventar uno propio con Web Workers: la interfaz se
  congela mientras dura una transcripción, que es una molestia real pero
  medible y documentada, no un fallo silencioso — y muy por debajo de no
  poder transcribir nada en el navegador.
- **Un defecto real de `sherpa_onnx_web` 1.13.8**, encontrado compilando una
  app de prueba y corriéndola en un Chromium de verdad —no alcanzaba con
  leer el código—: `sherpa-onnx-asr.js` declara `OfflineRecognizer` con
  `class`, y `SherpaOnnxWeb.loadWasm()` carga ese archivo con un `eval`
  indirecto. Una clase declarada así nunca queda alcanzable desde afuera:
  ni por `globalThis.OfflineRecognizer` —que es como la busca
  `dart:js_interop`—, ni siquiera nombrándola en un `eval` indirecto
  posterior, porque cada `eval` indirecto tiene su propio entorno léxico
  que desaparece en cuanto esa llamada termina. El resultado, verificado
  con una app Dart real: `sherpa_onnx.OfflineRecognizer(...)` reventaba
  siempre con "OfflineRecognizer not found", incluso después de un
  `initBindingsAsync()` sin ningún error. `createOnlineRecognizer` —el de
  reconocimiento en vivo, que esta app no usa— no tiene este problema: ese
  sí es una función, y las funciones declaradas en un `eval` indirecto sí
  quedan alcanzables. El arreglo, en `sherpa_onnx_offline_recognizer_fix.dart`:
  cargar el mismo archivo una segunda vez, pero como una etiqueta
  `<script>` de verdad en vez de un `eval` —los `<script>`, a diferencia de
  los `eval`, sí comparten un mismo entorno global persistente entre
  ellos— y copiar la clase desde ahí a
  `globalThis.OfflineRecognizer`. Repite el trabajo de cargar un archivo
  que `initBindingsAsync()` ya cargó una vez, pero es la única forma de
  dejar la clase alcanzable sin tocar el paquete. Verificado compilando esa
  misma app de prueba con el arreglo puesto: el motor de WebAssembly llega
  a validar de verdad la configuración que se le pasa, con los mensajes de
  error del propio C++ de sherpa-onnx en la consola del navegador. Si una
  versión futura del paquete expone la clase por su cuenta, este arreglo
  se puede borrar entero.

El modelo en sí se guarda en OPFS con `OpfsWhisperModelManager`, en su
propia carpeta —separada de `originales/`, porque un modelo no es un
archivo original de ningún elemento—. Sus `paths()` no son rutas reales
—OPFS no las tiene—: son las constantes que entiende el sistema de
archivos virtual del propio motor de WebAssembly, sin ninguna relación con
dónde vive nada en OPFS. Para que esas rutas signifiquen algo hace falta
copiar los bytes ahí con `Module.FS.writeFile()` antes de crear el
reconocedor —confirmado que existe y funciona con la misma prueba de la
app real—, porque en la web sherpa-onnx no lee ningún archivo por su
cuenta.

**Una duda que queda abierta, a propósito:** los tres archivos del modelo
siguen viniendo de Hugging Face, igual que en Android, pero ahí sí hay una
diferencia real entre plataformas que no se pudo terminar de verificar. Un
navegador exige que el servidor conteste con encabezados CORS para dejar
leer la respuesta desde otro origen, y una app nativa no tiene esa
restricción. Hugging Face no los mandaba en 2021 (un problema reportado y
ya cerrado en su repositorio), y todo indica que hoy sí —`transformers.js`,
la propia librería de Hugging Face para correr modelos en el navegador,
depende exactamente de esto—, pero este entorno de trabajo bloquea
`huggingface.co` a nivel de red y no hay forma de probarlo de manera
directa. Si algún día resulta que no manda esos encabezados, la descarga
fallaría con un error de red —ya manejado como cualquier otro fallo de
conexión, por el mismo camino que "sin internet" en Android— en vez de
romper la app; no haría falta ningún cambio de arquitectura, solo mover el
origen de los tres archivos a uno que sí los mande.

**Reconocimiento de texto en imágenes.** Google ML Kit no tiene ninguna
versión web: es un SDK nativo de Android/iOS, no algo que se pueda compilar
a WebAssembly. El reemplazo para el navegador es
[Tesseract](https://tesseractocr.org/) —Apache 2.0— compilado a
WebAssembly, corriendo entero del lado del cliente, sin mandar la imagen a
ningún servidor: mismo principio que ML Kit, motor distinto porque no hay
uno solo que cubra las dos plataformas. Los datos de idioma que necesita
Tesseract se sirven como parte de los propios assets de la app —no desde
la CDN que trae por defecto—, para que reconocer texto en una imagen siga
siendo una conexión que nunca sale del dispositivo, en vez de convertirse
en la excepción silenciosa que el principio 1 prohíbe.

**Lo que cuesta:** dos motores de OCR y dos formas de invocar la
transcripción para mantener, uno por plataforma. Y en la web, mientras dura
una transcripción larga, la interfaz no responde —una limitación real,
compartida con el propio motor de sherpa-onnx, no una que esta app podría
evitar sola—. Además, `sherpa-onnx-asr.js` se termina cargando dos veces
—una al pedirlo `initBindingsAsync()`, otra al arreglar el acceso a
`OfflineRecognizer`—: un archivo de menos de 100 KB, un costo real pero
menor comparado con los cientos de megas del propio modelo.

### 11. Lo que en la web se adapta, y lo que se omite sin más

No todo lo que existe en Android tiene un equivalente directo en un
navegador, y forzarlo sería peor que adaptarlo.

**Elegir una carpeta y escribir varios archivos ahí** —lo que usa el
paquete de NotebookLM— no tiene una forma confiable en la web: el único
API que lo permite todavía no lo soportan todos los navegadores por igual.
El reemplazo es el patrón habitual en la web para "exportar varios
archivos de una": armarlos igual que siempre y entregarlos comprimidos en
un único `.zip` que el navegador descarga. Quien lo reciba sigue
encontrando los mismos archivos con el mismo índice adentro.

**Recibir contenido compartido desde otra app** (decisión 7) no existe como
concepto en un navegador —no hay ninguna "hoja de compartir" del sistema
operativo—, y no hizo falta escribirle nada especial: `receive_sharing_intent`
no declara la web entre sus plataformas, así que ahí no hay ningún plugin
del otro lado, y `ReceiveSharingIntentListener` ya atrapaba
`MissingPluginException` desde que se escribió (decisión 7). Soltar un
archivo sobre la ventana, ya cubierto desde la fase 2, sigue siendo el
único camino de entrada en la web, sin que nadie haya tenido que
decidirlo aparte.

**Abrir un archivo con la app del sistema** casi no necesitó cambios:
`open_app_file` ya declara soporte de verdad para web desde que se eligió
—justamente por eso, ver la fase 6—, pero antes de llegar a él el detalle
del item le pedía a `FileStore.resolve()` una ruta absoluta, y esa llamada
ahora lanza a propósito en la web. `WebDownloadFileOpener` reemplaza ese
paso puntual: lee los bytes con `read()` y dispara una descarga con el
nombre real del archivo, en vez de dejar que `open_app_file` le ponga el
identificador de una URL de blob como nombre. La bóveda con clave
(`flutter_secure_storage`) y `pdfrx` para leer PDFs no necesitaron tocarse
en absoluto: los dos ya declaraban soporte de verdad para web desde que se
eligieron.

**Una nota aparte, del propio trabajo de adaptar esto:** `package:web` y
`dart:js_interop` no compilan en absoluto fuera de la web —a diferencia de
`dart:io`, que compila en la web con clases que existen pero revientan
recién al llamarlas—. Confirmado escribiendo una prueba mínima y
corriéndola con `flutter test`: el error aparece en la compilación, no en
tiempo de ejecución. Es la razón de fondo por la que cada pieza nueva de
esta fase —`OpfsFileStore`, `WebDownloadFileOpener`,
`ZipPackageDownloader`— vive detrás del mismo mecanismo de import
condicional que ya usaba `sherpa_onnx`: no es prolijidad de sobra, es lo
único que hace que el proyecto siga compilando para Android.

### 12. Inter empaquetada, no bajada de Google Fonts

Encontrado validando la fase 8 de punta a punta en un Chromium real, no en
ninguna revisión de código: con `fonts.gstatic.com` bloqueada, la app
entera arrancaba con **todo su texto invisible**. Los íconos —una fuente
local, la de Material— se veían bien; cualquier letra, no. La causa era
`AppTypography.textTheme`, que devolvía `GoogleFonts.interTextTheme()`:
esa llamada intenta bajar los archivos de Inter la primera vez que hacen
falta, y cuando esa descarga nunca se resuelve, la web se queda mostrando
el texto con un tamaño que no pinta nada, sin cortarse en ningún fallback.

El principio 1 ya la condenaba —bajar algo de una CDN de terceros en
tiempo de ejecución, sin pedir permiso— pero esto es más grave que una
violación de un principio: es la app rota de verdad para cualquiera cuya
red no llegue a ese dominio, sea por un bloqueador de anuncios, un
firewall corporativo, una extensión de privacidad, o simplemente que
`fonts.gstatic.com` no responda un instante durante el primer arranque.
Arreglarlo no podía esperar a una tarea aparte.

La solución sigue el mismo patrón que sqlite3.wasm y los archivos de
Tesseract: `tool/fetch_inter_font.sh` trae `InterVariable.ttf` —un único
archivo variable, eje "wght", del propio repositorio de Inter en GitHub,
fijado a un commit concreto— y queda commiteado en `assets/fonts/`, SIL
Open Font License 1.1 verificada contra el LICENSE.txt real. La escala
tipográfica por defecto de Material 3 solo usa dos pesos —regular y medio,
confirmado leyendo `typography.dart` del propio SDK de Flutter—, así que
alcanza con declarar ese mismo archivo dos veces en `pubspec.yaml`, una
por peso: Flutter elige sola la instancia correcta de la fuente variable
según cuál pida cada estilo. `AppTypography.textTheme` pasó a ser
`ThemeData.light().textTheme.apply(fontFamily: 'Inter')` —la misma base
que ya usaba `GoogleFonts.interTextTheme()` por dentro, ahora con la
fuente puesta en vez de pedida—, y `google_fonts` se sacó de
`pubspec.yaml` por completo: no queda ningún uso.

Verificado de la única forma que importa: la misma prueba de punta a
punta que encontró el problema, repetida con el arreglo puesto y
`fonts.gstatic.com` todavía bloqueada, vuelve a mostrar cada pantalla con
su texto real.

### 13. Android Gradle Plugin 8.13.0, no 9.x

`flutter create` había generado el proyecto con AGP 9.1.0 —la línea recién
publicada al momento de escribir esto—, y nunca se había compilado contra
un SDK de Android real hasta la validación de la fase 7/8 en un emulador de
verdad. Ese primer intento reveló, uno detrás de otro, cuatro choques
distintos entre AGP 9 y el ecosistema de plugins:

- **`resValues` apagado por defecto.** AGP 9 cambió el default de varios
  `buildFeatures` —antes venían prendidos— para acelerar builds que no los
  usan. Los tres flavors (`dev`/`staging`/`prod`) generan
  `@string/app_name` con `resValue()`, así que la build fallaba con
  "contains custom resource values, but the feature is disabled" hasta
  pedirlo a mano.
- **`receive_sharing_intent` 1.9.0 declara `compileSdk 37` a secas.** Desde
  el ciclo de Android 17 (API 37), Google ya no publica una plataforma "37"
  simple: solo existen "37.0", "37.1", etc. Ese entero nunca resuelve a
  nada instalable, en ninguna máquina, hasta que el paquete lo arregle río
  arriba.
- **`sentry_flutter` 8.14.2 fija Kotlin `languageVersion 1.6`**, que el
  compilador Kotlin 2.4 —el que trae AGP 9.1.0— ya no soporta ("Language
  version 1.6 is no longer supported; use version 2.0 or greater instead").
- **El Kotlin integrado de AGP 9 (`android.builtInKotlin`) es
  irreconciliable entre dos plugins a la vez.** `file_picker` 11.0.3 da por
  sentado que viene prendido en AGP 9+ y no aplica ningún plugin de Kotlin
  externo como respaldo si no lo está; `audio_decoder` 0.8.1 hace lo
  contrario —aplica `kotlin-android` a mano sin fijarse en la propiedad ni
  en la versión de AGP— y el propio AGP rechaza tener las dos cosas
  prendidas a la vez ("Remove the 'org.jetbrains.kotlin.android' plugin
  from this project's build file"). No hay una propiedad de Gradle por
  subproyecto que lo resuelva: se probó fijar una `extra` property desde
  `gradle.beforeProject` apuntando solo a `audio_decoder`, sin efecto — la
  bandera se lee por una vía que ese mecanismo no alcanza a pisar.

Los primeros tres tienen arreglo local sin tocar el paquete vendorizado
(pedir `resValues` a mano, fijar el `compileSdk` real del módulo de
`receive_sharing_intent`, subir `sentry_flutter`). El cuarto no: es un
choque real entre dos paquetes de terceros, ninguno con una versión
publicada que lo resuelva, y sin un mecanismo de Gradle que permita
apagar el Kotlin integrado para uno solo de los dos.

**La decisión:** en vez de seguir persiguiendo, uno por uno, los
próximos choques de una versión de AGP publicada hace días, bajar a
**8.13.0** —la última de la línea 8.x, probada por el ecosistema entero de
plugins de Flutter— que no tiene Kotlin integrado en absoluto, así que ese
choque puntual desaparece solo. De paso simplifica el arreglo de
`receive_sharing_intent`: en vez de perseguir la plataforma 37 que pidió de
más (y tener que subir el `compileSdk` de toda la app para satisfacer los
metadatos del AAR que ese `compileSdk` alto genera), alcanza con fijarlo a
la 36 —la misma que ya usa el resto del proyecto, y la que 8.13.0 prueba
oficialmente como máximo—: el plugin es un puente simple al botón de
compartir del sistema, no usa ninguna API exclusiva de API 37.

**Lo que cuesta:** quedar un paso por detrás de la versión más nueva de
AGP, con la migración a Kotlin integrado pendiente para cuando el
ecosistema de plugins la soporte parejo. A cambio, la build funciona hoy,
sin parches por proyecto que dependan de una API de Gradle que no se
comporta como documentada.

### 14. Cuatro fallas reales, encontradas usando la app de verdad

La compilación contra un SDK de Android real (decisión 13) fue el primer
paso; el segundo fue recorrer a mano cada flujo principal en el emulador.
Cuatro cosas fallaban o se veían mal, ninguna visible con `flutter analyze`
ni con la batería de pruebas existente porque las cuatro dependían de cómo
se comporta una librería de verdad, un sistema operativo de verdad, o una
pantalla larga de verdad — nada de eso lo simula un doble de prueba.

**El artículo de Wikipedia no se podía extraer.** `reader_mode` (decisión
3) usa por defecto `ParserType.jsdom`, un parser de HTML escrito a mano
para ese paquete. Contra una página de Wikipedia real revienta con
errores como "expected '</main>' and got '</div>'" en cuanto encuentra
una etiqueta que no cierra exactamente como él espera —algo común en
páginas grandes con años de historia—, y `parse()` devuelve `null` en vez
de un artículo: el elemento quedaba con "Couldn't extract" para siempre,
en una de las fuentes más comunes que alguien va a querer archivar. El
paquete también ofrece `ParserType.html`, que delega en `package:html`
—el parser HTML5 estándar de Dart, el mismo que ya usa `WebPageAdapter` en
el resto del proyecto—, y que tolera exactamente lo que el parser a mano
no tolera: elementos vacíos y cierre implícito de etiquetas, igual que un
navegador. Cambiar el parser en
[`reader_mode_article_extractor.dart`](../lib/features/transform/data/clients/reader_mode_article_extractor.dart)
resolvió el `Flutter` de Wikipedia (una redirección real a "Trémolo
(electrónica y comunicación)") de punta a punta, imágenes y todo.

**Un `content://` sin permiso de lectura tumbaba la app entera.**
Simulando un intent de compartir a mano —sin pasar por la hoja de
compartir real del sistema, que sí otorga el permiso de lectura
correctamente— apareció un `SecurityException` fatal, en el hilo
principal, que mataba el proceso. La causa: `receive_sharing_intent`
1.9.0 no envuelve en try/catch sus propias llamadas a `ContentResolver`
(`query`, `getType`, `openInputStream`) en `FileDirectory.getDataColumn`,
y las dispara de forma síncrona desde `onNewIntent`, fuera de cualquier
`MethodChannel.Result` que pudiera convertir el fallo en una excepción
Dart atrapable. Ningún manejador del lado Dart —ni `FlutterError.onError`,
ni `PlatformDispatcher.onError`, ni `runZonedGuarded`— puede interceptar
algo que nunca cruzó al lado Dart. Reproducido con la hoja de compartir
real de Android (en vez de un intent armado a mano), la app no crashea:
el sistema operativo otorga el permiso de lectura correctamente antes de
entregar el intent, así que este defecto del paquete no se dispara en el
uso real. Aun así, degradar antes que fallar (principio 4) también vale
para lo que pasa del lado nativo: se envolvió `onNewIntent` en la única
actividad que este proyecto controla,
[`MainActivity.kt`](../android/app/src/main/kotlin/app/sinapsis/MainActivity.kt),
para que cualquier intent de compartir que no se pueda leer —por este
paquete o cualquier otra razón— quede en un `Log.w` en vez de costar el
resto de la sesión, sin parchear un paquete de terceros que se
sobrescribiría en el próximo `flutter pub get`.

**Resaltar una selección era, en la práctica, invisible.** El botón para
confirmar un resaltado aparecía después de todo el `SelectableText` de la
rendition, no junto a la selección: en cualquier contenido más largo que
una pantalla —una transcripción, un artículo— quedaba a miles de píxeles
de donde el usuario estaba mirando. El diseño original evitaba a
propósito el menú nativo de selección (copiar/pegar) porque ese menú lo
dibuja el sistema operativo y no hay una forma confiable de tocarlo en
pruebas automatizadas — una razón válida, pero que asumía que la única
alternativa a "un botón aparte" era "el menú nativo del sistema".
`contextMenuBuilder`, el mecanismo que el propio Flutter expone para
personalizar el menú de selección, resuelve las dos cosas a la vez: sigue
siendo un widget de Flutter normal y corriente —se prueba con
`tester.tap()` como cualquier otro, sin tocar ninguna API nativa—, y
Flutter lo posiciona junto a la selección activa en vez de en un lugar
fijo, sea cual sea el punto de un texto largo donde el usuario esté
parado. El cambio quedó en
[`highlightable_text.dart`](../lib/features/organize/presentation/widgets/highlightable_text.dart),
con una prueba de widget nueva —el paquete no tenía ninguna hasta
ahora— que verifica el menú completo, más las pruebas de integración ya
existentes en `item_detail_screen_test.dart`, que ejercitan lo mismo con
un `longPressAt` real y ya pasaban sin cambios: la prueba con el gesto
real es la que de verdad hubiera encontrado este problema antes de
llegar al emulador.

**El botón que confirmaba un vínculo decía "Link to another item".** La
misma cadena de localización, `detailAddRelation`, se usaba para dos
botones con propósitos distintos: el ícono que abre el flujo completo de
vincular (donde "Vincular con otro elemento" tiene sentido) y el botón
que confirma el tipo de vínculo ya elegido, en el último paso del mismo
flujo (donde ese texto hace pensar que todavía falta elegir otro
elemento, no que el vínculo ya se va a guardar). Se agregó una clave
propia, `pickRelationConfirm` ("Add" / "Agregar"), específica para ese
botón, en vez de seguir reusando un texto pensado para otro lugar de la
pantalla.

**El paquete de NotebookLM no se podía guardar en algunas carpetas.**
Elegir "Alarms" —o cualquier otra carpeta que Android reserva a una
colección de medios: Ringtones, Notifications, Podcasts, Music— terminaba
en "Couldn't save to the chosen folder", con "Documents" o "Download"
funcionando sin problema. La causa: `SystemDirectoryChooser` usa
`file_picker`, que en Android devuelve una ruta de archivo *adivinada* a
partir del URI real que entrega el selector del sistema —funciona, por
coincidencia, en la mayoría de las carpetas—, y `LocalDirectoryWriter`
escribía ahí con `dart:io` liso y llano. El almacenamiento con ámbito de
Android concede el permiso del árbol SAF, pero no el permiso de escritura
directa por el sistema de archivos en las carpetas de una colección de
medios: esas exigen escribir por el propio Storage Access Framework, sea
cual sea el URI que se haya otorgado. `SafDirectoryChooser` (sobre
`saf_util`) devuelve el URI real sin traducirlo a nada, y
`SafDirectoryWriter` (sobre `saf_stream`) escribe por ese URI con
`ContentResolver`/`DocumentFile`, no con `dart:io` — los dos, BSD-3-Clause.
La elección entre esto y lo de siempre queda en
[`directory_services_io.dart`](../lib/features/export/data/services/directory_services_io.dart),
detrás del mismo import condicional que ya separaba el resto de este
proyecto por plataforma: la web —que no tiene ninguna de las dos cosas—
sigue con
[`directory_services_web.dart`](../lib/features/export/data/services/directory_services_web.dart)
sin tocarse.

**Ningún PDF ni documento se podía extraer en Android, de ningún tamaño.**
Guardar cualquier PDF —chico o grande, de texto o escaneado— terminaba en
"No se pudo extraer" en el teléfono, mientras `flutter test` pasaba en
verde. El logcat real mostró la causa: `PdfParser.parse` llamaba a
`pdfrxInitialize()`, la versión de `pdfrx_engine` pensada para un programa
de Dart de escritorio sin Flutter. Para decidir dónde cachear, esa función
resuelve el directorio con `Platform.environment['HOME']!` —con un
null-check forzado—, y Android (a diferencia de Windows, con
`LOCALAPPDATA`, o Linux/macOS de escritorio, con `HOME`) no define esa
variable de entorno: revienta con "Null check operator used on a null
value" antes de llegar siquiera a abrir el archivo, para cualquier PDF,
sin que el archivo tenga nada de malo. Nunca se vio en las pruebas
automáticas porque estas inyectan explícitamente `pdfrxInitialize` desde
`pdf_parser_test.dart`, corriendo en la máquina de escritorio donde esa
variable sí existe — exactamente lo que hacía falta para las pruebas, pero
también lo que escondía el problema real de la app. `pdfrx` (el paquete
Flutter, ya una dependencia del visor) expone `pdfrxFlutterInitialize`,
que resuelve ese directorio con `path_provider` en vez de una variable de
entorno, y es lo que la propia documentación del paquete indica usar
"para Flutter" en vez de la versión de Dart puro. Cambiar el inicializador
que usa [`PdfParser`](../lib/features/transform/data/documents/pdf_parser.dart)
por defecto resolvió el problema de punta a punta, verificado con un PDF
chico, un PDF de más de 1 MB y un `.docx` reales guardados desde el
selector de archivos del emulador. El umbral de 64 MB de la decisión
anterior en este mismo archivo seguía siendo necesario —cubre un defecto
distinto, en el camino de lectura por bloques de PDFium— pero por sí solo
nunca iba a arreglar esto: el `null` reventaba antes de que ese código
llegara a ejecutarse.

**Lo que tienen en común los seis.** Ninguno lo iba a encontrar
`flutter analyze` ni una prueba con un doble: el primero necesitaba HTML
de una página real con años de historia; el segundo, un permiso de
Android real, mal otorgado; el tercero, una transcripción más larga que
una pantalla; el cuarto, leer el mismo botón en dos contextos distintos
de la misma pantalla; el quinto, una carpeta real de Android con reglas
de almacenamiento propias; el sexto, una variable de entorno que
Android simplemente no tiene. Es la razón concreta detrás de "nunca des
algo por probado si se puede probar de verdad": los seis pasaron
`flutter test` en verde antes de esta validación.

### 15. Windows como tercera plataforma real, y OCR de escritorio sobre el Tesseract del sistema

El proyecto nació pensado para Android y la web (decisión 6): son las
plataformas donde vive quien lo construye. Sumar Windows como una tercera
plataforma de uso real —la misma bóveda, en la compu y en el celular,
sincronizada a mano por el usuario en vez de con la app (ver más abajo)—
significó agregar el target de escritorio de Flutter y resolver una cadena
de dependencias del toolchain nativo que ninguna otra plataforma de este
proyecto necesitaba: Modo de Desarrollador de Windows (símlinks de
plugins), Visual Studio Build Tools con el workload de C++ y su componente
ATL —lo pide `flutter_secure_storage_windows`, no algo que este proyecto
elija—, y un JDK completo con cabeceras JNI —el JBR que trae Android Studio
no las incluye, y `jni` (transitiva de `saf_stream` y `sentry_flutter`)
las exige para compilar su parte nativa incluso en Windows, aunque nada de
esta app entrada por JNI en escritorio—. Ninguno de los tres es específico
de Sinapsis: es lo que pide compilar cualquier app de Flutter con estos
plugins en un Windows sin herramientas de desarrollo previas.

**OCR en escritorio: ni ML Kit ni Tesseract-WebAssembly sirven ahí.**
`ImageTextExtractor` ya tenía dos motores —ML Kit fuera de la web
(decisión 7/Fase 7) y Tesseract-WASM en la web (decisión 10)— y ninguno de
los dos cubre Windows: ML Kit es un SDK nativo de Android/iOS sin versión
de escritorio, y Tesseract-WASM depende de `package:web` y
`dart:js_interop`, que no compilan fuera de la web (nota al cierre de la
decisión 11). `platform_image_text_extractor_io.dart` pasó de devolver
siempre `MlKitImageTextExtractor` a elegir en tiempo de ejecución, con
`Platform.isAndroid || Platform.isIOS`, entre ese motor y uno nuevo,
`TesseractCliImageTextExtractor`, para el resto de las plataformas de
`dart:io` —Windows, Linux, macOS—.

**Por qué no se bundlea un Tesseract propio para escritorio, a diferencia
de la web.** La decisión 10 sí empaqueta Tesseract-WASM con la app porque
ahí no hay otra forma: un navegador no puede invocar un binario del
sistema. En escritorio sí puede, así que bundlear un `tesseract.exe` de
terceros dentro del repositorio repetiría exactamente el problema que la
decisión 3 evitó con `syncfusion_flutter_pdf` y la decisión 8 con
`ffmpeg_kit_flutter`: una dependencia binaria ajena al ecosistema de Dart,
sin una forma clara de fijar versión ni de confirmar que el mantenedor
siga publicando. `TesseractCliImageTextExtractor` en cambio invoca
`tesseract` como estuviera en el `PATH` del sistema —el mismo binario que
instala el proyecto oficial de Tesseract, versionado y firmado por su
propio equipo—, con `Process.run` inyectable para poder probarlo sin
depender de que el binario esté presente en cada máquina que corra la
batería de pruebas.

**Qué pasa si Tesseract no está instalado.** No es un caso especial: es el
principio 4 de siempre. `extractText` lanza
`TesseractNotAvailableException` —igual de concreta que
`MissingOriginalFileException`—, `ImageTransformer.transform` no la
atrapa, y el elemento queda marcado como fallido con el mismo botón de
reintento que un enlace roto. Nadie tiene que instalar Tesseract para usar
el resto de la app; sin él, simplemente el reconocimiento de texto en
imágenes no está disponible en esa máquina hasta que se instale.

**Los datos entrenados, del mismo commit que la web.** El instalador de
Tesseract para Windows solo trae inglés por defecto. `spa.traineddata` se
suma a mano a su carpeta de datos, bajado del mismo commit fijo del
repositorio `tessdata_fast` que ya usa `tool/fetch_tesseract_web.sh`
(`TESSDATA_REF` en ese script): así el texto que reconoce la versión de
escritorio en español es exactamente el mismo motor y los mismos pesos que
reconoce la versión web, no una variante distinta por casualidad de qué
trajo el instalador del sistema operativo.

**Lo que cuesta:** a diferencia de Android (ML Kit viaja con la app) y la
web (Tesseract-WASM viaja con la app), en escritorio el reconocimiento de
texto depende de una instalación aparte que el usuario tiene que hacer una
vez, fuera de Sinapsis. Es una asimetría real entre plataformas, pero
consistente con lo que ya cuesta la decisión 3: mejor una dependencia
externa clara y con licencia libre de verdad, que una atada al
repositorio sin una forma sana de mantenerla al día.

### 16. Copia de seguridad completa de la bóveda: manual, no sincronización

Con Windows como plataforma real (decisión 15), usar la misma bóveda en la
compu y en el celular dejó de ser hipotético. La decisión 1 ya descarta un
servidor propio, y ninguna sincronización automática entre dispositivos es
gratis en esfuerzo sin uno —CRDTs, resolución de conflictos, un protocolo
de transporte—, así que el camino elegido es manual: `VaultBackupService`
arma un único `.zip` con la base y todos los archivos originales, el
usuario lo lleva como quiera —un cable, una nube que ya use— y lo restaura
del otro lado.

**Un solo archivo, no una carpeta como el paquete de NotebookLM.** La
exportación a NotebookLM (decisión 5) arma varios archivos porque cada uno
tiene que poder subirse suelto a un sitio ajeno. Acá es lo contrario: una
copia de la bóveda es una sola unidad, y separarla en archivos sueltos
solo complicaría llevarla de un lado a otro sin ganar nada.

**`VACUUM INTO` en vez de copiar el archivo a mano.** La base sigue
abierta y en uso mientras se arma la copia —no tiene sentido pedirle al
usuario que cierre la app para hacer un backup—, y copiar el archivo
`.sqlite` con `dart:io` mientras hay escrituras en curso puede llevarse una
página a medio escribir, o dejar afuera los archivos `-wal`/`-shm` sueltos
si la conexión usa journal en modo WAL. `VACUUM INTO` es una sentencia SQL
que corre sobre la misma conexión que la app ya tiene abierta y deja un
archivo consistente de un solo golpe, sin bloquear nada más que esa
sentencia.

**Restaurar exige cerrar la conexión antes de escribir, y reiniciar
después.** El archivo de destino es el mismo que `AppDatabase.open()` ya
tiene abierto: escribirle encima con una conexión viva es pedirle
comportamiento indefinido a SQLite, en el mejor de los casos, y un archivo
bloqueado por Windows, en el peor. `VaultBackupScreen` cierra
`appDatabaseProvider` explícitamente antes de restaurar, y ninguna otra
pantalla de la app puede seguir funcionando con esa conexión cerrada a
mitad de camino —los streams que alimentan la biblioteca dependen de
ella—, así que la única salida honesta es pedirle a la app que se cierre
del todo (`exit(0)`) y que el usuario la vuelva a abrir. Es la misma lógica
que un instalador de Windows pidiendo reiniciar después de reemplazar sus
propios archivos en uso, no una limitación que se pueda evitar con más
código.

**Validar antes de preguntar.** `PickVaultBackupFileUseCase` confirma que
el `.zip` elegido tenga la base de datos adentro antes de que
`VaultBackupScreen` muestre el diálogo de confirmación irreversible: no
tiene sentido advertirle a alguien que va a perder su bóveda entera por un
archivo que ni siquiera es una copia válida. `RestoreVaultBackupUseCase`
vuelve a comprobarlo del lado de `VaultBackupService` de todas formas —no
confía en que la validación previa se haya hecho—, por si algún día se
llama desde otro lado que se salte ese paso.

**Lo que cuesta:** ningún camino en tiempo real, ni resolución de
conflictos si dos dispositivos cambiaron cosas distintas —restaurar
siempre reemplaza todo, nunca combina—. A cambio, cero servidor, cero
cuenta, y un archivo que el usuario controla de punta a punta: se puede
abrir dentro de diez años con cualquier programa que entienda un `.zip`, ni
siquiera hace falta Sinapsis para ver qué hay adentro.

**Actualización de F11.** Restaurar dejó de reemplazar: «Traer otra copia» lee
el `.zip`, muestra qué traería y lo fusiona con la bóveda de acá en una sola
transacción, sin cerrar la conexión y sin reiniciar la app. Lo que este texto
dice de cerrar `appDatabaseProvider`, de `exit(0)` y de que restaurar «siempre
reemplaza todo» describe cómo era hasta F10: ver la decisión 44.

### 17. Espacios: carpetas, no otra forma de etiquetar

Las etiquetas (decisión de la Fase 5) ya resuelven "marcar" un elemento con
uno o varios conceptos que se cruzan entre sí —un video puede ser
"filosofía" y "para revisar" a la vez—. Lo que no resuelven es la pregunta
inversa: "¿qué hay en mi carpeta de Trabajo?", donde cada cosa vive en
**un** lugar, no en varios. Confundir las dos —por ejemplo, tratando un
espacio como una etiqueta más— dejaría sin resolver el caso de uso real
(una vista tipo carpeta) a cambio de nada, porque las etiquetas ya cubren
bien el caso de las marcas que se combinan.

**Una columna nullable en `Items`, no una tabla de unión.** Las etiquetas
son muchos-a-muchos y necesitan `ItemTags`; los espacios son
muchos-a-uno —un elemento pertenece a lo sumo a uno— así que alcanza con
`Items.spaceId`, igual que ya existe `Items.sourceId`. Menos una tabla
completa, un repositorio de sincronización y una consulta con subconsulta
para evitar duplicados (ver `_matchingIds` y el filtro de etiquetas):
acá el filtro es un `WHERE spaceId = ?` liso.

**`ON DELETE SET NULL`, no `CASCADE`.** Borrar un espacio es borrar una
carpeta, no lo que había adentro — el principio de procedencia (principio
2) no aplica acá porque un espacio no es de dónde vino algo, es solo cómo
se lo organiza. La app ya tiene un ejemplo de la cascada contraria
(`Items.sourceId` con `CASCADE`, porque un elemento sin fuente no es un
elemento) que sirve para contrastar: acá el elemento sigue siendo el mismo
elemento completo, solo que sin carpeta.

**Primera migración real del esquema.** `schemaVersion` nunca había subido
de 1 —las siete tablas originales se crean todas juntas en `onCreate`—.
Sumar `Spaces` y la columna en `Items` obligó al primer `onUpgrade` real
del proyecto. Se optó por una columna **nullable** en vez de exigir un
valor por defecto: así una bóveda que ya existe sube de versión con todo
"sin clasificar" en vez de fallar la migración por una columna `NOT NULL`
sin con qué llenarse, o inventar un espacio "General" que nadie pidió.

**Nombres únicos, pero sin fusionar en silencio.** `getOrCreateTag` fusiona
en silencio porque una etiqueta se escribe al vuelo, sobre un elemento, y
dos veces el mismo nombre casi siempre quiere decir la misma etiqueta.
`createSpace` en cambio **falla** ante un nombre repetido: un espacio se
crea desde su propia pantalla, con un nombre elegido a propósito, así que
escribir dos veces "Trabajo" amerita un aviso —quizás ya existe y el
usuario no lo vio— en vez de una fusión que podría no ser lo que quiso.

**Lo que cuesta:** un elemento no puede estar en dos espacios a la vez —si
alguna vez hiciera falta, la respuesta ya existe y se llama etiqueta—.

### 18. Notas de bloques: JSON dentro de una `Rendition.text`, no una tabla nueva

Un editor estilo Notion —encabezados, listas, casilleros, citas, cada uno
reordenable— pide un modelo de contenido más rico que "un texto suelto",
pero no pide tocar el esquema de la base en absoluto: `Rendition.text` ya
tiene una columna `content` de texto libre, pensada desde la Fase 1 para
llevar cualquier forma de texto que un elemento pueda tener. Un nuevo
`RenditionKind.blocks` y una convención —el `content` de esa rendition es
un JSON con la lista de bloques, codificado por `encodeContentBlocks`— alcanzan
sin agregar ninguna columna, ninguna tabla ni ninguna migración. Es la
`textEnum` de siempre: `RenditionKind` se guarda como texto, así que un
valor nuevo en el enum no le pide nada al esquema.

**JSON a mano, no `@JsonSerializable` sobre `@freezed`.** Ninguna otra
entidad sellada del proyecto necesita serializarse a JSON —cada una vive
en sus propias columnas tipadas de drift—; `ContentBlock` es la primera
que sí, porque es la única que se guarda como texto en una columna pensada
para texto. Sumar `json_serializable` encima de `freezed` —otro `part`,
otro paso de codegen, otra anotación por campo— para una sola clase de seis
variantes es más superficie nueva que las ~30 líneas de
`_blockToJson`/`_blockFromJson` escritas a mano.

**Un tipo desconocido se lee como párrafo, no rompe la nota.** Si una
versión futura agrega un séptimo tipo de bloque y luego alguien vuelve a
una versión vieja de la app —o restaura un backup hecho con una versión más
nueva, ver la decisión 16—, `decodeContentBlocks` no sabe qué hacer con
`{"type": "tabla", ...}` más que mostrar su texto como si fuera un párrafo
liso. Es el principio 4 de siempre: degradar antes que fallar. La
alternativa —lanzar una excepción al toparse con un tipo que no reconoce—
dejaría toda la nota inaccesible por un solo bloque que no entiende, cuando
lo que hay ahí es perfectamente legible como texto plano.

**`searchableText` decodifica los bloques en vez de indexar el JSON
crudo.** Sin este cuidado, buscar "encabezado" encontraría cualquier nota
de bloques —la clave `"type": "heading"` aparece en su JSON— sin que el
usuario haya escrito esa palabra en ningún lado. `Rendition.searchableText`
distingue `RenditionKind.blocks` como caso aparte y concatena solo el texto
de cada bloque, así que el índice de búsqueda ve exactamente lo que la
persona escribió, ni una clave de estructura de más.

**Un editor propio, aparte de `HighlightableText`.** El resto de las
formas de texto se leen y se resaltan con el mismo widget porque son,
literalmente, texto: una cadena que se puede seleccionar de punta a punta.
Una nota de bloques no lo es —tiene estructura, tipos y orden—, así que
necesita su propio editor (`BlockEditorScreen`) y su propia vista de
lectura (`BlockView`). Resaltar un fragmento dentro de un bloque queda
fuera de esta primera versión a propósito: mezclar índices de resaltado
—que ya son delicados, ver la Fase 5— con una estructura que además se
puede reordenar es una pieza de trabajo aparte, no una extensión barata de
esto.

**Guardar reemplaza toda la rendition de bloques, nunca la mezcla con
otra.** `BlockEditorScreen` busca si el elemento ya tenía una rendition de
tipo `blocks` y, si la había, reutiliza su `id` —es la misma forma de
contenido actualizada, no una nueva que convive con la vieja—; el resto de
las renditions del elemento (una transcripción, el enlace original) no se
tocan. Es el mismo criterio que ya usa `_syncRenditions` en
`LibraryRepositoryImpl`: se guarda el agregado completo y el repositorio
decide qué actualizar y qué dejar igual.

**Lo que cuesta:** ni resaltados ni búsqueda de texto completo dentro de un
bloque individual —la búsqueda encuentra la nota, no en qué bloque estaba—,
y sin sugerencias de formato al estilo "escribir `#` para encabezado": el
tipo se elige con un selector, no con comandos de barra. Ambas son
extensiones genuinas de esto, no omisiones por descuido.

### 19. El grafo de relaciones: Fruchterman-Reingold propio, no un paquete

La decisión 5 (Fase 5) ya explica por qué las relaciones se eligen a mano y
no se sugieren solas: un grafo lleno de vínculos de baja confianza vale
menos que veinte hechos a mano. Lo que faltaba no era más vínculos, era una
forma de *verlos* como red en vez de como una lista de líneas de texto en
el detalle de cada elemento —que es como se veían hasta ahora—.

**Un layout de fuerzas propio, en unas cien líneas, en vez de una
dependencia.** Dibujar un grafo bien —que los grupos conectados queden
juntos y el resto se separe, en vez de una fila o un círculo parejo que no
dice nada sobre la estructura— pide un algoritmo, no solo un `CustomPaint`.
Fruchterman-Reingold es el clásico para esto: cada nodo repele a todos los
demás como una carga eléctrica, cada arista atrae a sus dos extremos como
un resorte, y unas pocas decenas de iteraciones con una "temperatura" que
baja alcanzan para que el sistema converja en una disposición estable. Es
público desde 1991 y son unas cien líneas de matemática de vectores sin
estado oculto ni casos raros de UI; sumar un paquete de grafos completo
—con su propio sistema de renderizado, generalmente pensado para grafos de
miles de nodos— sería mucho más superficie para lo que hace falta acá: una
bóveda personal, no una red social.

**Determinístico a propósito.** El layout no usa `Random()`: arranca de una
disposición en círculo por índice, siempre igual para la misma lista de
nodos. Abrir el grafo dos veces con los mismos vínculos da exactamente la
misma imagen las dos veces. Un layout con azar de verdad "saltaría" cada
vez que se abre la pantalla — desorientador para algo que se supone que
ayuda a construir un mapa mental de la bóveda.

**Solo entran los elementos con al menos un vínculo.** La mayoría de una
biblioteca no tiene ninguno puesto —es lo esperable, dado que la decisión 5
exige ponerlos a mano—, así que incluir cada elemento sin vínculos como un
punto suelto llenaría el grafo de ruido sin ninguna línea que lo conecte a
nada. El grafo muestra la red que el usuario construyó, no el catálogo
entero.

**`RelationEdge`, aparte de `ItemRelation`.** `ItemRelation` (Fase 5) está
pensado para mostrar los vínculos de **un** elemento en su propio detalle,
con el sentido de la frase ya resuelto según desde dónde se lo mira. El
grafo necesita lo contrario: todos los vínculos de la bóveda a la vez, sin
la noción de "desde qué elemento". Forzar `ItemRelation` a este uso
hubiera significado pedirle un `otherItemId` sin "otro" del que hablar, o
llamarlo una vez por cada elemento de la biblioteca —N consultas donde una
sola alcanza—.

**Lo que cuesta:** sin agrupamiento por comunidad ni resaltado de qué tan
central es un elemento en la red —ninguno de los dos existe todavía—, y el
cálculo del layout recorre todos los pares de nodos en cada iteración
(orden N² por vuelta), que para una bóveda con miles de elementos
vinculados entre sí empezaría a notarse. No es un problema hoy: hace falta
un grafo bastante más grande que el de una biblioteca personal típica para
llegar a sentirlo.

### 20. Preguntarle a la bóveda: RAG local, con `flutter_gemma` como único motor nuevo

El pedido —"preguntale algo a tus notas y que conteste citando de dónde
sale"— tiene dos mitades que conviene separar desde el diseño: encontrar
qué es relevante (retrieval) y redactar una respuesta a partir de eso
(generation). Es el patrón RAG de siempre, y separarlo en
`VaultRetriever` / `ChatModel` —dos interfaces que `AskVaultQuestionUseCase`
es la única pieza que conoce a la vez— es lo que permite que la mitad sin
riesgo funcione sola, sin esperar a que la mitad grande y nueva esté lista.

**FTS5 como retriever, no embeddings vectoriales.** La biblioteca ya tiene
búsqueda de texto completo (Fase 1) probada contra SQLite real. Sumarle
embeddings —un modelo aparte, un índice vectorial aparte, otra descarga—
para una primera versión sería resolver un problema que todavía no se
demostró que existe: si la búsqueda por palabras encuentra lo relevante en
la mayoría de las preguntas reales, no hace falta más; si no alcanza, el
camino de mejora es agregar embeddings *detrás* de la misma interfaz
`VaultRetriever`, sin que `AskVaultQuestionUseCase` ni la pantalla se
enteren. Es la misma lógica que separar adapters de transformers
(decisión 4): la interfaz absorbe el cambio, no lo propaga.

**`flutter_gemma`, evaluado antes de elegirlo.** De las alternativas
relevadas —`llamadart`, `llama_cpp_dart`, `cactus`, ONNX Runtime genérico—
es la única con soporte de verdad en Android **y** Windows a la vez con un
solo formato de modelo (LiteRT-LM vía el paquete hermano
`flutter_gemma_litertlm`), sin exigir compilar `llama.cpp` a mano
(`llama_cpp_dart`) ni quedar afuera de escritorio (`cactus`). En escritorio
corre por FFI directo —"no JVM, no gRPC, no servidor aparte", como dice su
propia documentación—, el mismo espíritu que ya tiene `sherpa_onnx` acá.
Verificado compilando de verdad para Windows y para Android en este
proyecto, no solo leyendo su documentación: los dos compilan limpio con la
versión 1.8.2, confirmando además que Gemma 3 1B en formato `.litertlm`
funciona igual en las dos plataformas, sin ninguna rama de código por
sistema operativo — un requisito explícito de este pedido.

**Gemma 3 1B, no una variante más grande.** Por debajo de mil millones de
parámetros la redacción en español se degrada notoriamente; muy por
encima, la descarga deja de ser razonable para un celular de gama media.
1B cuantizado a 4 bits es el punto donde las dos cosas conviven. Nada
impide que una variante de escritorio más grande (3-4B) se sume después
como una opción, no un reemplazo — el `ChatModelManager` ya está pensado
para eso.

**Gratis de verdad, sin excepción.** Gemma es de pesos abiertos —Google la
publica para que cualquiera la use, sin costo—; lo único que Hugging Face
puede pedir es aceptar su licencia con una cuenta gratuita antes de dejar
bajar el archivo, nunca un pago ni una clave de API paga. El principio 1
(todo en el dispositivo) y el compromiso de la app entera —100% gratis,
sin límites— se sostienen los dos: ninguna llamada sale del dispositivo,
y no hay ningún costo escondido en ningún punto de la cadena.

**Sin conversación con memoria, a propósito, por ahora.** Cada pregunta
arma su propia sesión de chat con el contexto que encontró para ELLA, sin
arrastrar el historial de preguntas anteriores. Una charla de ida y vuelta
de verdad —donde la segunda pregunta puede referirse a la primera— es una
extensión genuina de esto: hay que decidir qué hacer cuando el contexto
nuevo contradice al viejo, y no es gratis en complejidad. Se prefirió
dejarla afuera de esta primera versión que forzar una decisión apurada.

**El modelo se descarga aparte, con permiso explícito.** Mismo patrón que
Whisper (decisión 8): una pantalla propia (`ChatModelScreen`) que muestra
tamaño y progreso, nada se baja en silencio ni junto con la app. A
diferencia de Whisper, acá `flutter_gemma` resuelve la descarga por su
cuenta —reintentos, progreso, un servicio en primer plano en Android para
descargas largas—, así que `GemmaChatModelManager` es una capa fina sobre
esa descarga, no una reimplementación con `dio` como la de Whisper.

**Lo que cuesta:** sin conversación con memoria entre preguntas, sin
resaltar en qué bloque exacto de un fragmento salió cada dato, y con una
dependencia de un solo mantenedor (`flutter_gemma` es reciente y de
desarrollo muy activo) — mitigado por vivir enteramente detrás de la
interfaz `ChatModel`, así que cambiar de motor el día de mañana no toca ni
`AskVaultQuestionUseCase` ni la pantalla.

**Corrección posterior: el repositorio de Gemma es gateado de verdad, no
solo de palabra.** Probado en un celular real, la descarga fallaba siempre
con 401, para cualquiera, sin importar la conexión —confirmado con
`curl -I` contra la URL del modelo: `X-Error-Code: GatedRepo`—. El texto
original de esta decisión decía que Hugging Face "puede pedir aceptar la
licencia", pero en los hechos la exige antes de dejar bajar el archivo, y
`flutter_gemma` no manda ninguna credencial por su cuenta. Se agregó
`HuggingFaceTokenNotifier` (persistido con `SharedPreferences`, mismo
patrón que `ThemeModeNotifier`) y un campo en `ChatModelScreen` para pegar
un token de acceso gratuito, que viaja como `token:` en
`.fromNetwork(url, token: ...)` — el parámetro que el propio paquete
expone para esto. `ChatModelManager.download()` también distingue ahora
`ChatModelNeedsAuthentication` de cualquier otra falla
(`ChatModelDownloadFailed`), en vez de un solo mensaje genérico de "revisá
tu conexión" que escondía la verdadera causa. Sigue siendo gratis —el
token es de una cuenta sin costo, nunca una clave paga—, pero deja de ser
"un botón y listo": hace falta un paso de cuenta la primera vez, con
instrucciones en la propia pantalla.

**Segunda corrección posterior: Gemma 4 E4B en vez de Gemma 3 1B.** En uso
real, la 1B contestaba con una redacción pobre y vaga —resúmenes genéricos
que no llegaban a nombrar los documentos citados, aun con el prompt
insistiendo en citar por número entre corchetes—, un límite conocido de los
modelos por debajo de los mil millones de parámetros que esta misma
decisión ya anticipaba ("por debajo de mil millones de parámetros la
redacción en español se degrada notoriamente"). Se cambió a **Gemma 4 E4B**
—la variante "elástica" de 4B efectivos de la familia siguiente, también en
formato LiteRT-LM— siguiendo la salida que esta decisión ya dejaba abierta:
"nada impide que una variante de escritorio más grande se sume después
como una opción". En los hechos se hizo **reemplazo, no opción**: pesa
unos 4 GB contra los cientos de MB de la 1B, y un teléfono de gama baja
puede no tener memoria para correrla — una prioridad consciente hacia la
calidad de la respuesta, sabiendo el costo. `GemmaChatModelManager` pasó
de instalar un único archivo (`fromNetwork` a una URL fija) a resolver el
**manifiesto de despliegue** del repositorio (`fromHuggingFace(repo)` sin
`file`): Gemma 4 publica ese manifiesto porque una misma variante "elástica"
puede resolver a artefactos distintos según la plataforma, así que
hardcodear un nombre de archivo —como sí tenía sentido para el único
`.litertlm` de la 1B— se volvió tanto innecesario como frágil.

**Tercera corrección posterior: elegir entre dos modelos, no uno solo.**
Quien no tiene problema de espacio ni de memoria en su equipo pidió poder
elegir un modelo todavía más grande que Gemma 4 E4B. Se sumó **Gemma 3n
E4B** (~4.9 GB, repositorio `google/gemma-3n-E4B-it-litert-lm`) como
**segunda opción**, no como reemplazo: `ChatModelOption` (dominio) tiene
las dos, `ChatModelOptionNotifier` recuerda cuál se eligió entre reinicios
—mismo patrón que `ThemeModeNotifier`—, y `GemmaChatModelManager` recibe
la opción por constructor en vez de tener un modelo fijo adentro.
`chatModelManagerProvider` arma una instancia nueva cada vez que cambia la
opción elegida, así que el chat, las flashcards y las sugerencias de
vínculos del grafo —los tres consumen `chatModelManagerProvider`/
`chatModelProvider` sin saber nada de esto— siguen a la opción activa sin
ningún cambio de su lado.

Un detalle no obvio: `ModelType.gemmaIt` —el tipo genérico de la familia
Gemma 3 en `flutter_gemma`— es compartido por la vieja Gemma 3 1B (la
primera opción de esta app, antes de la corrección anterior) y por Gemma
3n E4B. Comparar solo el tipo de modelo activo, como alcanzaba para
distinguir Gemma 4 del resto, no alcanza acá: un teléfono con la 1B
todavía activa de una instalación vieja se leería como "ya tengo la Gemma
3n lista" sin serlo. `GemmaChatModelManager.isReady()` compara también un
fragmento del nombre del archivo activo (`nameContains`) para las
opciones donde el tipo no alcanza a distinguir.

---

### 21. Flashcards con SM-2: el estado de repaso vive en la tarjeta, y la IA solo sugiere

Una app de estudio que solo guarda y busca información deja afuera la
mitad del problema: recordarla con el tiempo. La repetición espaciada
—mostrar cada tarjeta justo antes de que se olvide, cada vez más
separada— es la técnica con más evidencia detrás para eso, y es la razón
de ser de Anki. Se sumó acá con el mismo algoritmo, SM-2 de Piotr Wozniak
(1987), en vez de inventar una variante propia: es simple, probado durante
casi cuatro décadas, y cualquiera que haya usado Anki ya entiende cómo se
comporta sin necesitar explicación.

**El estado de repetición vive en la entidad, no en un servicio aparte.**
`Flashcard` guarda `easeFactor`, `intervalDays`, `repetitions` y `dueAt`
junto con la pregunta y la respuesta, porque una tarjeta *es* su historial
de repasos, no solo su contenido — separarlos hubiera significado
sincronizar dos cosas que siempre cambian juntas. `scheduleNext()`
(`sm2_scheduler.dart`) es la única pieza que sabe calcular el próximo
estado a partir del actual y una calificación, y es una función pura: sin
base de datos ni reloj de por medio, así que la fórmula del algoritmo se
prueba con las mismas cuatro operaciones matemáticas que describe el
paper original, no con una base SQLite de fondo.

**Cuelgan de `Item`, no de `Rendition`.** Una tarjeta pregunta por una
idea, no por un fragmento de texto puntual: el mismo elemento puede tener
varias transcripciones o revisiones de contenido a lo largo del tiempo, y
las tarjetas que se armaron sobre él siguen teniendo sentido aunque el
texto exacto cambie. Referenciar la rendition hubiera atado las tarjetas a
una versión específica del contenido, cuando lo que importa es el
elemento como concepto.

**Generación asistida por IA, reutilizando `GemmaChatModel`.** Pedirle al
modelo que proponga preguntas y respuestas a partir del contenido de un
elemento es, en el fondo, el mismo problema que responder una pregunta
sobre la bóveda (decisión 20): un modelo de lenguaje corriendo local que
recibe texto y devuelve texto. En vez de levantar una segunda instancia de
`InferenceModel` — cara en memoria para un modelo que ya vive cargado en
el chat — `GemmaChatModel` implementa dos interfaces a la vez, `ChatModel`
y `FlashcardGenerator`, cada una con su propia instrucción de sistema y su
propio prompt. Es una asimetría real: `FlashcardGenerator` es la única
interfaz de dominio de esta app que no tiene una única implementación de
producción con una razón de ser propia, sino que comparte motor con otra
por conveniencia de recursos. Se aceptó el costo porque separar el
servicio en dos clases hubiera significado dos modelos cargados en
paralelo en un celular de gama media, y el resto de la app no ve la
diferencia: pide un `FlashcardGenerator` y no le importa qué hay detrás.

**Formato de salida deliberadamente austero.** Se le pide al modelo un
formato `P: ...` / `R: ...` línea por línea, sin Markdown ni numeración
ni JSON — un modelo de 1B de parámetros no sigue instrucciones de formato
tan bien como uno mucho más grande, y cuanto más simple lo pedido, menos
formas tiene de desviarse. `parseFlashcardDrafts()` es tolerante a
propósito: una línea que no matchea ninguno de los dos patrones se ignora
en silencio en vez de descartar el lote entero por una sola línea que
salió rara.

**Nunca se guarda nada sin que la persona lo revise.** `FlashcardGenerator`
solo sugiere: `FlashcardDraft` no es una `Flashcard`, y la única forma de
convertir uno en la otra es pasar por el diálogo de revisión, donde cada
borrador se acepta o descarta por separado. Una sugerencia mala se
descarta con un toque; nada llega a la base de datos sin que alguien lo
haya visto primero.

**Lo que cuesta:** la generación por IA hereda las mismas limitaciones que
el chat (decisión 20) — sin memoria entre pedidos, dependiente de
`flutter_gemma` — y un modelo de 1B ocasionalmente ignora el formato
pedido, en cuyo caso el parser simplemente no encuentra nada que ofrecer y
la persona puede volver a intentar o cargar la tarjeta a mano.

---

### 22. Navegación adaptativa: barra o riel, en vez de un AppBar de nueve íconos

Probado en un celular real y no solo en el simulador, el AppBar de la
biblioteca desbordaba: nueve acciones —seleccionar, idioma, tema,
transcripción, backup, grafo, chat, repaso y bloqueo— compitiendo por una
sola fila. Cada función nueva que se agregó a lo largo de las fases sumó un
ícono más a esa fila, hasta pasar el ancho de cualquier celular real.

**Separar destinos de ajustes.** Biblioteca, Grafo, Chat, Repaso y una
nueva pantalla de Ajustes pasan a ser los cinco destinos de la navegación
principal —lo que se visita seguido, cada uno con su lugar propio—.
Idioma, tema, modelo de transcripción y copia de seguridad de la bóveda
—cosas que se tocan una vez y quedan— se consolidan en Ajustes, con
`ListTile` agrupados en tarjetas (`Card`, el mismo estilo que ya define
`app_theme.dart` para las tarjetas de la biblioteca). Bloquear la bóveda
también se muda a Ajustes, como la última acción, separada con un
`Divider` y en el color de error del tema: cuesta un toque más que antes
—ir a Ajustes en vez de tocarlo desde cualquier pantalla—, pero evita
inventar un lugar "clavado" que se comporte distinto según si la pantalla
usa una barra o un riel.

**`NavigationBar` o `NavigationRail`, según el ancho, no uno solo para
siempre.** El punto de quiebre es 600dp — el mismo corte que usa Material 3
entre la clase de ventana "compacta" y "mediana o más", no un número
inventado para esta app. Por debajo, una barra abajo, como espera cualquier
celular; en o por encima, un riel al costado, como espera una ventana de
escritorio que se puede agrandar. Un `Drawer` hubiese escondido los
destinos detrás de un toque justo donde sobra ancho (escritorio); una
barra fija sin adaptar se ve mal estirada a lo ancho de una ventana
maximizada; un menú de "más opciones" resolvía el desborde pero no lo que
se pidió —que cada función tuviera su lugar—. El riel/barra adaptativo es
el único de los cuatro que da un lugar propio a cada función en Android y
en Windows a la vez, con widgets que ya trae el SDK de Flutter
(`NavigationBar`, `NavigationRail`): no hace falta ninguna dependencia
nueva.

**`StatefulShellRoute.indexedStack`, no rutas planas.** Cada uno de los
cinco destinos vive en su propio `Navigator` (`StatefulShellBranch`), así
que cambiar de pestaña y volver conserva el scroll y los filtros de cada
una en vez de reconstruir la pantalla de cero. El guard de la bóveda
(`_redirect` en `app_router.dart`) no necesitó ningún cambio: ya comparaba
la ubicación contra rutas concretas de forma genérica, sin distinguir si
esa ubicación vive dentro de un shell o no — confirmado con un test que
navega directo a `/graph` con la bóveda bloqueada y verifica que sigue
redirigiendo al desbloqueo.

**`NavDestinationSpec.branchIndex`, para no desincronizar la lista visible
de la rama activa.** El chat sigue sin mostrarse en la web (decisión 6), lo
que significa que la lista de destinos visibles tiene un elemento menos
que ramas hay ahí. Usar la posición dentro de esa lista como si fuera el
índice de la rama hubiera hecho que, en la web, `NavigationBar` marcara un
destino distinto del que en verdad está activo apenas la cuenta no
coincidiera. Cada `NavDestinationSpec` lleva su índice de rama real, y el
shell traduce entre "posición visible" y "rama activa" en los dos
sentidos.

**Lo que cuesta:** bloquear la bóveda pasa de un toque a dos (entrar a
Ajustes primero), y la fila de búsqueda y filtros de la biblioteca ahora
convive con una barra o un riel alrededor —verificado que sigue sin
amontonarse ni en 400dp de ancho ni en el punto de quiebre exacto—.

---

### 23. El modo de lectura se pagina, en vez de un solo scroll con todo el libro

`DocumentReaderScreen` —el modo de lectura de un DOCX, un EPUB o texto
suelto— mostraba el contenido entero de la rendition en un único
`SelectableText.rich` dentro de un `SingleChildScrollView`. Ese widget no
recorta lo que no se ve: Flutter tiene que calcular el layout de texto —
salto de línea, posición de cada glifo— del documento **entero** apenas se
abre la pantalla, sin importar cuánto entre en la ventana visible. Contra
un libro de mil o dos mil páginas reales —varios millones de caracteres—
eso significa congelar la app por varios segundos, o quedarse sin memoria
en un equipo modesto, solo para abrir la primera página.

**`splitIntoReaderPages` corta antes de ponerle formato a una sola letra,
y `PageView.builder` arma una página por vez.** La función vive en
`lib/features/viewer/domain/services/reader_pagination.dart`, pura y sin
ningún widget de por medio, así que se prueba sin levantar Flutter.
`DocumentReaderScreen` arma la lista de páginas una sola vez al construirse
y le pasa cada una, ya cortada, a `PageView.builder`: solo la página visible
—y como mucho la siguiente, que `PageView` prepara de antemano— pasa por
`RenderedMarkdown.parse()` y por el layout de texto. Abrir un libro de mil
páginas cuesta, en los hechos, lo mismo que abrir uno de diez.

**Un PDF ya trae sus propias páginas: se usan esas, no una partición
arbitraria.** `PdfParser` ya une el texto de cada página del documento
original con el separador `\n\n---\n\n` (ver la decisión 3). Cortar ahí antes
que nada más da una correspondencia exacta entre la página del libro de
verdad y la página del lector, sin inventar ningún límite de caracteres
para ese caso. Lo que no trae ese separador —un DOCX, un EPUB, texto
suelto— no tiene páginas "de verdad" a las que volver: se arman juntando
párrafos hasta acercarse a un límite de caracteres (2400 por defecto, un
tamaño elegido para que una página se lea de un vistazo sin quedar
minúscula), sin partir nunca un párrafo a la mitad —salvo que un párrafo
solo, sin ningún salto de línea real, ya supere ese límite él solo, el
único caso donde cortarlo a la fuerza es preferible a una página sin techo
de tamaño—.

**Lo que se dejó afuera, a propósito.** El detalle de un elemento
(`ItemDetailScreen`) sigue mostrando el contenido completo en un solo
`HighlightableText`, sin paginar: ahí vive el resaltado de texto, que
depende de poder seleccionar y marcar cualquier rango del documento tal
como está, algo que paginar complicaría de verdad —una selección no puede
cruzar el borde entre dos páginas separadas— para un beneficio menor, ya
que esa pantalla es la vista rápida y no el lugar pensado para leer un
libro entero de corrido. El modo de lectura, en cambio, existe
específicamente para eso, y es donde paginar rinde más.

---

### 24. El modo de lectura: tamaño de letra e ir a página

Con la paginación de la decisión 23 ya puesta, dos cosas seguían faltando
para que el modo de lectura se sintiera como el de un lector de libros de
verdad, y no solo como una pantalla que ya no traba: elegir el tamaño de
la letra, y llegar directo a una página lejana sin tener que pasar todas
las de en medio.

**El tamaño de letra se recuerda entre lecturas, no solo entre páginas del
mismo libro.** `ReaderFontScaleNotifier` guarda la escala elegida en
`SharedPreferences` con el mismo patrón que `ThemeModeNotifier` —ver la
decisión original del tema—: quien agranda la letra para leer más cómodo
no debería tener que repetirlo cada vez que abre otro documento. Un
escalar entre 0.8× y 1.6× sobre `bodyLarge`, no un tamaño en puntos fijo:
así la relación con el resto de la tipografía de la app se mantiene sin
importar la configuración de accesibilidad del sistema.

**Ir a página, con un control deslizante y no un campo de número.** En un
libro de cientos de páginas, escribir "347" a mano exige ya saber el
número exacto —algo que rara vez se sabe—, mientras que arrastrar hasta
la zona aproximada del libro es exactamente cómo se hojea un libro de
papel para encontrar un lugar recordado a medias. El mismo indicador
"Página X de Y" que ya mostraba dónde se está parado (decisión 23) ahora
también abre este selector al tocarlo: un solo elemento que informa y que
actúa, en vez de sumar un botón aparte solo para esto.

---

### 25. El grafo: nodos como tarjetas de entidad, no como círculos

Se pidió explícitamente que el grafo se pareciera más a un diagrama
entidad-relación de base de datos: una forma visual mucho más conocida —y
más informativa de un vistazo— para representar "cosas conectadas entre
sí" que un círculo con un ícono adentro y una etiqueta suelta debajo.

**Cada nodo es una tarjeta rectangular de dos filas, como una tabla en
miniatura.** Un encabezado con el color del espacio —el mismo rol que
cumple el nombre de una tabla— con el ícono y el título del elemento, y
una fila debajo con su tipo de fuente ("Documento", "Video"...) — la
única "columna" visible de esta tabla en miniatura, con la misma etiqueta
que ya usa la biblioteca (`SourceKindPresentation.label`, evitando
duplicar esa correspondencia). Es más información al mismo golpe de vista
que un ícono solo, y la forma rectangular distingue de entrada un nodo de
una arista —que ya se dibujaba con líneas y puntas de flecha rectas—, el
mismo lenguaje visual que cualquier diagrama entidad-relación.

**Las líneas ahora recortan contra el borde de un rectángulo, no contra un
círculo a distancia fija.** Con un nodo circular alcanzaba con parar la
línea a `radius` píxeles del centro, en cualquier dirección — un círculo
es igual de "ancho" mirado desde cualquier ángulo. Una tarjeta rectangular
no: vista de costado, el borde está a `halfWidth`; vista de arriba, a
`halfHeight`, mucho más cerca en una tarjeta ancha y baja como esta.
`clipToRectBorder` (`graph_edges_painter.dart`) resuelve el ángulo real
de cada arista contra la caja del nodo —el mismo método de "recorte de
rayo contra una caja" que usa cualquier motor de físicas 2D, simplificado
porque acá el rayo siempre arranca en el centro de la caja—, expuesta
como función pura y probada con números concretos, sin levantar ningún
widget: el resto del pintor de aristas —color por tipo de vínculo, punta
de flecha, atenuado en modo foco— no cambió.

**Lo que no cambió, a propósito.** El algoritmo de layout
(`computeGraphLayout`, Fruchterman-Reingold, decisión 19) sigue intacto:
ya resuelve bien "qué tan separados van los nodos" tratándolos como
puntos, y ese problema no depende de la forma que se dibuje encima de cada
punto — solo hizo falta agrandar el margen del lienzo y el tamaño mínimo
de separación para el tamaño nuevo, más grande, de la tarjeta. Tampoco se
sumó la notación completa de "pata de gallo" (cardinalidad) que trae un
diagrama entidad-relación de verdad: esta app no modela relaciones
uno-a-muchos ni muchos-a-muchos con esa precisión, y forzar esa notación
sobre vínculos que son, en los hechos, simples aristas dirigidas habría
sido decoración sin información real detrás.

### 26. El chat: historial persistente y adjuntos

Hasta acá el chat vivía enteramente en memoria: `_ChatTurn`/`_FreeTurn` eran
campos de `State`, y cerrar la pantalla —o la app— borraba la conversación
sin dejar rastro. Se pidió explícitamente un historial de verdad, al estilo
de cualquier chat moderno, más la posibilidad de adjuntar una imagen o un
documento al mensaje.

**Dos tablas nuevas, `Conversations` y `ChatMessages`** (schemaVersion 4).
Cada modo del chat (`ChatConversationMode.vault`/`.free`) guarda sus
conversaciones por separado —la columna `mode`, indexada— porque son dos
historiales con reglas distintas, igual que ya eran dos historiales en
memoria antes de este cambio. `sourcesJson`/`attachmentsJson` van como texto
en la fila del mensaje, no en tablas relacionadas aparte: son listas chicas,
propias de un solo mensaje, que nunca se consultan por su cuenta —mismo
criterio que ya usa `Rendition.text` para los bloques de una nota, ver
`encodeContentBlocks`—. `ChatConversationMode` se movió del enum privado que
tenía `ChatScreen` a `lib/core/domain/entities/`: ahora también lo necesita
la persistencia, no solo la pantalla.

**El título de una conversación sale solo, del primer mensaje del
usuario** (`ChatConversationRepositoryImpl._autoTitle`, recortado a 48
caracteres). No hay ningún cuadro para escribir un título a mano: pedirlo
sería una fricción de más para algo que el propio mensaje ya dice.

**Reabrir una conversación pasada arranca una sesión nueva del modelo, sin
memoria de lo hablado antes de reabrirla —aunque el historial completo
se siga mostrando en pantalla.** Es una limitación aceptada, documentada
también en el doc-comment de `ChatScreen`, y no un error: `flutter_gemma`
no ofrece forma de recargar una `InferenceChat` ya cerrada con su
historial previo sin volver a pedirle una respuesta real por cada mensaje
viejo —lo que además tendría un costo de inferencia que nadie pidió pagar
solo por reabrir una charla vieja—.

**El menú de historial es un `Drawer`, no un desplegable de verdad.** El
pedido original decía "menú desplegable al estilo ChatGPT", pero ChatGPT
mismo usa una barra lateral para esto, no un `DropdownButton`: un panel
lateral con título, fecha y borrado por conversación necesita más espacio
del que un desplegable da cómodamente, y es el patrón que la propia
referencia usa en los hechos. Cada modo lista solo sus propias
conversaciones (`chatConversationsProvider(mode)`, más nueva primero por
`updatedAt`), consistente con que ya eran historiales separados antes de
este cambio.

**Los adjuntos se clasifican por sus bytes, no por qué botón del menú se
tocó.** El menú ofrece "Imagen" o "Documento" por claridad de la interfaz,
pero los dos abren el mismo `FileChooser.pickOne()` sin filtrar —igual que
`SystemFileChooser`, que tampoco confía en la extensión— y es
`FileFormat.sourceKind` quien decide de verdad qué es lo que se eligió.
Un documento se lee con `documentParsersProvider` —el mismo registro de
lectores que usa la biblioteca— y su texto se suma al mensaje que ve el
modelo, recortado a 6000 caracteres (`_kAttachmentTextBudget`): un libro
entero adjunto desbordaría la ventana de contexto antes de llegar a la
pregunta misma. Lo que la persona escribió y lo que el modelo recibe se
guardan por separado —`PersistedChatMessage.text` nunca lleva el contenido
extraído— para que releer el historial no obligue a releer también el
documento que una misma ya adjuntó.

**Una imagen adjunta se manda como imagen de verdad, no como una mención
de texto.** `ChatModel.FreeConversation.send`/`VaultConversation.send`
ganaron un parámetro `images` opcional (`List<Uint8List>`, vacío por
defecto): con imágenes, `GemmaChatModel` arma el mensaje con
`Message.withImages` en vez de `Message.text`, la API multimodal real de
`flutter_gemma`. Gemma 4 E4B y Gemma 3n E4B son las dos multimodales —el
"E4B" de ambas es justamente esa familia—, así que no hizo falta una
bandera de "este modelo sí, este no" en `ChatModelOption`: si algún modelo
futuro no soportara imágenes, `flutter_gemma` fallaría al pedirle una
respuesta y ese mensaje quedaría con `error` seteado, el mismo camino que
ya cubre cualquier otro fallo del motor de inferencia.

### 27. Un tercer modelo de chat, más pesado — y por qué no es el que arranca en Android

Se pidió un modelo todavía más inteligente que las dos opciones que ya
había (decisión 20), con su peso y su cantidad de parámetros a la vista, y
que quedara como opción por defecto aunque pesara más.

**Gemma 4 12B, ~6.9 GB, 12.000 millones de parámetros densos** —sin la
activación selectiva que hace que "E4B" signifique un tamaño *efectivo* de
unos 4.000 millones—: es el modelo entero cargado, y por eso es el más
pesado y el más lento de arrancar de los tres.

**No es la opción por defecto en Android — ni siquiera aparece ahí.** El
propio fabricante (`litert-community`) publica este modelo listo para
macOS, Linux y Windows, con una variante aparte y más liviana para web,
pero **sin ningún build para Android ni iOS**: no es una limitación que
esta app le imponga, es lo que el modelo puede correr. Pedirle a un
teléfono que reserve casi 7 GB de RAM para un modelo que su fabricante
nunca preparó para esa plataforma habría sido, en el mejor de los casos,
un `ChatModelDownloadFailed` incomprensible, y en el peor, un teléfono
modesto quedándose sin memoria. `isDesktopChatPlatform`
(`chat_model_option_notifier.dart`) filtra esta opción del selector fuera
de Windows/macOS/Linux, y `defaultChatModelOption` solo apunta a ella en
esas plataformas — en cualquier otra, sigue siendo
`ChatModelOption.gemma4E4b`, la misma de siempre. Es la resolución de raíz
del pedido, no un parche: cumplir "que el modelo más inteligente sea el
que arranca por defecto" en cada plataforma donde eso es real, en vez de
prometerlo en una donde no lo es.

`ModelType.gemma4` pasó a ser compartido por dos opciones —Gemma 4 E4B y
Gemma 4 12B, dos repositorios y dos archivos distintos—, así que las dos
necesitan ahora su propio `nameContains` para que `GemmaChatModelManager`
no confunda cuál de las dos está activa —mismo mecanismo que ya resolvía
la ambigüedad entre la Gemma 3 vieja y Gemma 3n E4B.

### 28. Resumir con IA y leer en voz alta

Se pidió que cualquier texto largo de la app —el contenido ya extraído de
un documento, la transcripción de un audio o un video, un artículo— se
pudiera resumir con el modelo de lenguaje y escuchar en voz alta, con
controles de reproducción y elección de voz, acento y velocidad.

**`SummarizationService` es una interfaz más de dominio, no un método
nuevo en `ChatModel`.** Mismo criterio que ya separa `FlashcardGenerator`
y `RelationSuggestionService` (decisión 20): quien pide un resumen no
tiene por qué conocer nada de citas ni de conversaciones, y la
implementación real sigue siendo el mismo `GemmaChatModel` ya cargado.
Vive en el dominio de `library` y no en `chat` —la asimetría ya aceptada
en la decisión 26 se repite acá— porque quien lo pide es el detalle de un
elemento y el lector de documentos, no el chat.

**`NarrationPlayer` es un feature propio, `narration`, y no vive dentro de
`viewer` ni de `library`.** Lo usan las dos por igual —el detalle de un
elemento y el modo de lectura paginada—, así que ponerlo en cualquiera de
las dos habría sido una dependencia cruzada arbitraria entre feature
hermanos, en vez de una carpeta compartida con nombre propio.

**Sin verdadero pausar a mitad de oración, ni un `seek` real.** El
contenido se corta en fragmentos cortos por oración
(`splitIntoSpeechSegments`, análogo a `splitIntoReaderPages` pero para
escuchar en vez de leer con los ojos) y "pausar" es simplemente no pedir
el próximo fragmento todavía — retomar vuelve a leer el fragmento en el
que se quedó, desde su principio. "Retroceder" y "adelantar" cambian de
fragmento entero por el mismo motivo: no existe un `seek` real sobre voz
sintetizada que nunca se decodificó a un buffer navegable, y Android,
Windows y Web resuelven "pausar y seguir" de formas demasiado distintas
—en Android es, según la propia documentación de `flutter_tts`, un truco
sobre el índice de la última palabra leída— como para prometer que las
tres retoman exactamente en la misma palabra donde se cortó. Fragmentos
cortos y reproducibles de a uno es lo único que las tres plataformas
pueden garantizar por igual.

**`flutter_tts` (4.2.5), no un motor propio.** Corre nativo en Android,
Windows, macOS, iOS y Web sin ningún servidor de por medio —mismo
principio 1 de siempre—, y `getVoices`/`setVoice`/`pause` están
soportados en las dos plataformas que le importan a esta app según su
propia documentación. `TextToSpeechService` (`narration/domain/services`)
es la interfaz de dominio de siempre sobre un plugin no testeable —mismo
patrón que `FileChooser`/`FileOpener`—, con `FakeTextToSpeechService` para
probar `NarrationPlayer` entero sin hablarle a ningún canal nativo,
incluido disparar a mano el evento de "terminó de leer" para probar que
encadena el próximo fragmento solo.

**Un detalle real que las pruebas encontraron:** `_NarrationPlayerState`
llamaba a `ref.read(...)` dentro de `dispose()` para cortar la lectura al
cerrar la pantalla — Riverpod no permite usar `ref` ahí, porque el widget
ya se desmontó. La prueba de "cerrar corta la lectura" lo hizo saltar de
inmediato; la solución fue guardar el servicio una sola vez en un campo
`late final` durante `initState`, no volver a pedirlo en cada uso.

### 29. El Explorador: carpetas jerárquicas, no una extensión de Espacios

Se pidió una pantalla nueva que mostrara solo el resultado de lo ya
procesado —texto, imágenes, enlaces y citas—, organizado por temas al
estilo de un explorador de archivos: con carpetas de verdad, que a su vez
pueden tener subcarpetas, y donde un mismo elemento se pueda llevar a más
de una a la vez ("copiar") o mover de una a otra.

**`Folder`/`Folders` es una entidad nueva, no una extensión de `Space`.**
Un espacio (decisión 17) es deliberadamente plano y de-uno-a-lo-sumo-uno:
sin jerarquía y con una sola columna nullable en `Items`. Forzarlo a
soportar subcarpetas habría significado agregarle un `parentId`
autorreferenciado a una tabla pensada para no tenerlo, y forzar la
relación a muchos-a-muchos para poder "copiar" habría roto la propia
premisa de espacios ("es una carpeta, no una marca") para el código que sí
la necesita. `Folders` se autorreferencia por `parentId` para el árbol, y
una tabla de unión nueva —`ItemFolders`, calcada de `ItemTags`— permite que
un elemento esté en varias carpetas a la vez. Las dos tablas conviven con
`Spaces` sin tocarla: son formas de organizar independientes, no una en
reemplazo de la otra.

**Borrar una carpeta borra sus subcarpetas en cascada, pero nunca los
elementos.** Mismo principio que ya regía en espacios —"borrar la carpeta
no debería borrar lo que había adentro"—, llevado a un árbol: la cascada
de `parentId` sobre `Folders` se lleva puestas las subcarpetas (son
estructura, no contenido, igual que una carpeta vacía de Windows
desaparece con su padre), y la cascada de `ItemFolders` hacia `folderId`
solo borra la fila que ubicaba a un elemento ahí. El elemento en sí, en
`Items`, nunca tiene una fila que referencie a `Folders`: no hay cascada
posible que lo alcance. Un elemento sin ninguna fila en `ItemFolders`
—porque nunca se archivó, o porque la única carpeta que lo tenía se
borró— aparece solo, en la raíz del Explorador, para que nada quede
inalcanzable desde ahí.

**El árbol entero se trae de una sola vez, plano, no nivel por nivel.**
`watchAllFolders()` es el único stream de lectura de carpetas que expone
el repositorio: una bóveda personal no va a tener miles de ellas, así que
traerlas todas y agruparlas por `parentId` del lado de Dart —para la
vista actual, las migas de pan y el selector de destino al agregar un
elemento— es más simple que streams por nivel, sin ningún costo real.

**El Explorador solo muestra lo que ya terminó de procesarse.** A
diferencia de la Biblioteca —todo lo guardado, en cualquier estado, con
filtros de tipo y etiqueta—, acá se filtra a `ProcessingState.ready`: es
la vitrina de resultados, no la cola de trabajo. La combinación se hace en
la pantalla, cruzando los `id` que trae `ExplorerRepository` con los datos
completos que ya expone `libraryItemsProvider`, en vez de duplicar en el
Explorador la lógica de ensamblado de `LibraryRepositoryImpl`.

**Ningún nivel muestra una lista plana: los elementos se agrupan solos por
`SourceKind`, en subcarpetas que nadie crea a mano.** Con cientos de
elementos en una sola carpeta —el caso que importa a medida que crece la
bóveda—, una lista larga es lo primero que deja de ser navegable. En vez
de paginarla o buscar dentro de ella, cada carpeta (y la raíz) agrupa sus
elementos directos por tipo de fuente —redes sociales, documentos, videos
de YouTube, notas...— y solo muestra la subcarpeta de un tipo si tiene
algo adentro. Es una capa puramente de presentación: `ExplorerScreen`
arma el agrupamiento en el propio `build()`, a partir de la lista que ya
trae `libraryItemsProvider`, sin ningún dato nuevo que guardar ni
sincronizar — el tipo de un elemento no cambia nunca después de
capturado, así que no hay nada ahí que pueda desincronizarse. Es una hoja
del árbol: entrar a una subcarpeta de tipo muestra sus elementos y nada
más, sin subcarpetas —reales ni de tipo— debajo.

### 30. Enlaces `[[ ]]` dentro del texto: sobre lo que ya existía, no una red aparte

Se pidió acercar la app al estilo Zettelkasten/Notion: escribir
`[[Colonialismo Británico]]` dentro de una nota y que eso cree un vínculo
de verdad con ese elemento, sin salir del texto a armar la relación aparte.

**No es una red nueva: es una forma de crear una `Relation` que ya
existía (decisión 19, el Grafo) sin salir del editor.** La bóveda ya
tenía vínculos tipados y su propia visualización; lo que faltaba era
poder crearlos *desde adentro de la prosa*, no un segundo sistema de
conexiones en paralelo. Escribir `[[Título]]` —a mano, o con el botón de
enlazar que abre el mismo `PickItemDialog` que ya usan el Grafo y el
detalle— crea una `RelationKind.relatedTo` real al guardar, resuelta por
título (sin distinguir mayúsculas) contra la biblioteca completa. Si el
título ya no coincide con nada —el elemento se borró, o le cambiaron el
nombre después de escrito el enlace—, el texto se ve igual pero deja de
ser tocable: se avisa en vez de fallar en silencio, porque la `Relation`
en sí (la que alimenta el Grafo) ya quedó creada al escribirlo, y solo el
texto de la nota quedó desactualizado.

**El reconocimiento vive en `RenderedMarkdown`, al lado de negrita y
cursiva, no en un parser aparte.** `[[Texto]]` se trata como una marca
inline más —el `[[`/`]]` desaparece igual que los `**`—, pero con un
`TapGestureRecognizer` en vez de un estilo fijo: quien llama a
`buildSpans` decide qué hacer al tocarlo (`onLinkTap`), y el propio
parser no sabe nada de elementos ni de navegación.

**Un hallazgo de testing que vale la pena dejar escrito, para no volver a
gastar el tiempo en diagnosticarlo:** un `testWidgets` que hace, dentro
del mismo callback de un botón, dos o más operaciones seguidas contra
`NativeDatabase.memory()` —guardar, después listar, después crear una
relación— se cuelga bajo el reloj simulado de `flutter_test` hasta su
timeout (`TimeoutException`, con `dart:isolate _RawReceivePort._handleMessage`
en la pila), aunque la misma secuencia, con el mismo repositorio y el
mismo contenido, funcione perfecto —y en milisegundos— tanto en un `test`
puro de Dart como en un `testWidgets` con un widget trivial. No se llegó
a aislar la causa exacta —parece relacionada con los triggers de FTS5
sobre contenido de texto real combinados con el manejo de isolates del
motor bajo el binding de test, no con la lógica en sí—, pero el patrón
para evitarlo es claro: la lógica que encadena varias operaciones contra
la base se prueba aparte, contra el repositorio directo (como ya hacen
`organize_repository_impl_test.dart` y el resto), y el `testWidgets` solo
cubre que la interfaz arma bien el pedido —ver
`block_editor_screen_test.dart`, el grupo "crear el vínculo real, sin
widgets" separado del de interfaz—.

### 31. Propiedades tipadas: categorías con valor, junto a las etiquetas, no en vez de ellas

Se pidió poder clasificar un elemento con categorías propias —"Época:
Siglo I a.C.", "Región: Roma"— para filtrar y explorar la bóveda sin
depender de carpetas, al estilo de las propiedades de una base de datos
de Notion.

**`PropertyDefinition`/`PropertyValue` son entidades nuevas, no una
convención de nombres sobre `Tag`.** Se pudo haber resuelto escribiendo
etiquetas con un prefijo ("Región: Roma") y dejando que la convención
hiciera el trabajo, pero eso no deja *filtrar por categoría* de forma
estructurada —"todo lo que tiene alguna Región puesta", o listar qué
categorías existen— sin parsear texto. `PropertyDefinition` es la
categoría (creada por el usuario, a diferencia de `SourceKind` o
`RelationKind`, que son fijos); `PropertyValue` es un valor concreto bajo
esa categoría, único dentro de ella —mismo criterio que `Tag.name`, pero
con el `definitionId` como parte de la unicidad—; `ItemPropertyValues` es
la tabla de unión entre un elemento y un valor, calcada de `ItemTags`.

**Un elemento puede tener varios valores bajo la misma categoría a la
vez.** Es la razón de ser del pedido: un video sobre las tácticas
militares de Julio César *y* la economía egipcia tiene que poder llevar
"Región: Roma" y "Región: Egipto" a la vez, no obligar a elegir uno. Por
eso `ItemPropertyValues` es una tabla de unión N-a-N —como `ItemTags`—
y no una columna nullable como `Items.spaceId`.

**`properties` vive embebido en `KnowledgeItem`, igual que `tags`, no
aparte como `Relations`/`Highlights`.** La distinción que ya hacía
`OrganizeRepository` —relaciones y resaltados no son parte del agregado
porque no hace falta cargarlos para mostrar un elemento en una lista—
no aplica acá: las propiedades, igual que las etiquetas, tienen que
poder verse y filtrarse desde la Biblioteca sin un viaje aparte a la
base. `LibraryRepositoryImpl._syncProperties` resincroniza la tabla de
unión completa al guardar, mismo patrón que `_syncTags`; la asignación y
remoción día a día, sin embargo, pasan por `OrganizeRepository.
assignProperty`/`removeItemProperty` directo —análogo a cómo un vínculo
o un resaltado se crean sin pasar por `LibraryRepository.save`—.

### 32. El Explorador pasa de carpetas a filtros

Se pidió reemplazar por completo la navegación por carpetas del
Explorador —decisión 29— por una vista de filtrado, siguiendo la misma
lógica que llevó a las propiedades tipadas (decisión 31): la
organización real de una bóveda vive en lo que cada elemento ya tiene
puesto —sus etiquetas, sus propiedades, su tipo—, no en dónde alguien
decidió archivarlo a mano.

**Se eliminó toda la infraestructura de carpetas, no se la dejó en
desuso.** `Folder`, `ExplorerRepository`, y las tablas `Folders`/
`ItemFolders` desaparecieron del código; `AppDatabase.schemaVersion`
subió a 7 con una migración que las dropea (`from < 7`). El paso
histórico que las creaba (`from < 5`) se sacó también: para cualquier
bóveda que migre desde antes de la versión 5, crearlas y borrarlas en
la misma sesión de migración no deja rastro, así que mantener ese paso
solo habría sido código muerto. `ExplorerScreen` sigue siendo el mismo
nombre de clase, en el mismo archivo y la misma rama del router —el
reemplazo no tocó `RoutePaths.explorer` ni la navegación principal—,
pero por dentro es una pantalla nueva.

**`ExplorerQueryNotifier` es a esta pantalla lo que
`LibraryQueryNotifier` es a la Biblioteca —mismo patrón, sin búsqueda de
texto ni paginación—, y ambas comparten la misma `LibraryQuery`.** No
hay un filtro paralelo propio del Explorador: se sumó `propertyValueIds`
a `LibraryQuery` (mismo criterio que `tagIds` —dentro del filtro vale
cualquiera de los valores, resuelto con una subconsulta contra
`ItemPropertyValues` para que un elemento con varios de los valores
buscados no aparezca duplicado—), y el Explorador simplemente arranca la
consulta con `processingStates: {ProcessingState.ready}` fijo —acá no
hay cola de trabajo que mostrar, solo la vitrina de lo que ya
terminó—. El panel de filtros (tipo, categorías con sus valores,
etiquetas) es el mismo `_FiltersSheet` de `library_screen.dart` con una
sección más, observando el notifier como provider en vez de recibir el
estado por parámetro, para que marcar un chip se refleje al instante en
la lista de atrás aunque el panel siga abierto.

### 33. Notas atómicas: extraer una selección, no partir un texto entero

Se pidió poder partir una transcripción o nota larga en varias notas de
una sola idea —el otro pilar del Zettelkasten, junto a los enlaces
`[[ ]]` (decisión 30) y las propiedades tipadas (decisión 31)—. Se
evaluaron dos modos, manual (seleccionar un fragmento y extraerlo) y
automático (una IA propone varias notas de una transcripción larga de
una vez); **se implementó solo el manual**, a pedido explícito.

**"Extraer como nota" vive en el mismo menú contextual que "Resaltar",
no en un botón aparte.** `HighlightableText._buildContextMenu` ya
inyectaba un ítem en el menú de selección nativo de Flutter
(Copiar/Compartir); esto suma un segundo ítem al lado, reutilizando el
mismo cálculo de offsets del texto crudo que ya hacía
`_highlightSelection`. Mismo criterio que llevó a poner "Resaltar" ahí
en primer lugar: cualquier otro lugar de la pantalla queda a miles de
píxeles de la selección real en un texto largo.

**No se construyó un camino de guardado nuevo: la nota atómica pasa por
`CaptureItemUseCase`, el mismo que cualquier captura manual.** Construir
un `KnowledgeItem` a mano se hubiera salteado el id, los timestamps y el
guardado atómico que ese caso de uso ya garantiza para todo lo que
entra a la bóveda — duplicar esa lógica acá hubiera sido el tipo de
atajo que rompe el día que alguien cambie cómo se arma un elemento
nuevo.

**La relación hacia el original usa un tipo nuevo,
`RelationKind.extractedFrom`, no `cites`.** Una nota atómica no está
*citando* una fuente externa: es literalmente un fragmento que estaba
adentro del texto original, y confundir las dos cosas en el grafo le
resta precisión justo al tipo de vínculo que un sistema de notas
atómicas más necesita distinguir. Se crea automáticamente al extraer,
sin ningún diálogo intermedio: a diferencia de una relación cualquiera
—donde hay que elegir con qué otro elemento vincular y de qué tipo—,
acá los dos lados ya se conocen de antemano.

### 34. F1 del modelo Fuente/Nota: esquema y migración, sin tocar nada visible

Se encargó un refactor de fondo de siete fases para la capa de
organización: separar el dominio en **fuente** (lo capturado, inmutable,
con procedencia) y **nota** (lo que el usuario construye, mutable, sin
procedencia propia), con el texto de toda fuente fragmentado en chunks
—indexado, nunca reducción— para dar lugar a un motor de relaciones por
similitud, vocabulario controlado, una bandeja de entrada con estados de
trabajo intelectual, y deduplicación. La restricción que gobierna las
siete fases: el texto de una fuente no se resume, reescribe ni pierde
nunca, bajo ninguna circunstancia.

Esta entrada documenta solo **F1** —modelo de datos, migración,
chunking, reconstrucción verificada—, la única fase atacada hasta acá. El
resto (F2: vocabulario controlado y unificación de etiquetas; F3: estados
de trabajo y bandeja de entrada; F4: clasificación asistida; F5: motor de
relaciones; F6: grafo local y notas mapa; F7: deduplicación y fusión no
destructiva de bóvedas) se planifica recién cuando F1 esté cerrado,
probado y aprobado — tal como pidió el propio encargo, fase por fase.

**Tablas nuevas —`item`/`source`/`note`/`chunk`/`embedding`/
`migration_issue`— conviven con las viejas, sin tocarlas.**
`Items`/`Sources`/`Renditions`/`Tags`/... siguen siendo la única fuente de
verdad para toda la app: ningún repositorio ni pantalla existente lee ni
escribe las tablas nuevas todavía. Retirar las tablas viejas es
explícitamente un paso posterior, de una fase futura, con backup previo.

**Backfill de una sola vez al migrar a `schemaVersion` 8, sin escritura
dual.** Mantener `item`/`source`/`note` sincronizados en cada `save()`
futuro habría significado tocar `LibraryRepositoryImpl.save`/`delete` y
los ~15 sitios que construyen o modifican `KnowledgeItem` —el radio de
impacto más grande del proyecto— sin que existiera todavía ningún lector
real de las tablas nuevas que lo justificara. El espejo queda
desactualizado desde el primer ítem capturado después de la migración;
es aceptable únicamente porque nada lo lee en F1. Queda escrito acá para
que F2, al arrancar, no tenga que redescubrir el trade-off: dual-write
dentro de la misma transacción de `save` (la opción más simple), o un
backfill incremental re-ejecutable mientras tanto.

**`source` es una extensión 1:1 de `item`, a diferencia de la vieja
`Sources`, que puede estar compartida por varios `Items`** (el mismo PDF
capturado dos veces reutiliza la fila). Es una divergencia semántica
real, no un detalle de implementación: el backfill duplica los datos de
una fuente compartida, una fila por cada `item` que la referenciaba.

**Clasificar `note` vs `source` es una lectura directa de una columna
existente, no una heurística.** `Sources.kind == SourceKind.manualNote`
cubre las dos únicas formas hoy de que el usuario cree contenido sin que
venga de afuera —una nota escrita a mano o armada con el editor de
bloques—; todo lo demás entra como `source`. Toda nota migrada entra como
`note_kind: living` por decisión explícita: distinguir `atomic`/`map`
requeriría una heurística nueva, fuera del alcance de F1.

**El chunking es indexado, no reducción, por diseño de la API: el
servicio decide DÓNDE cortar, nunca reescribe el texto de cada lado.**
Cada `chunk.text` es literalmente `fullText.substring(charStart,
charEnd)`, así que la reconstrucción exacta es una propiedad aritmética
de `substring`, no algo que haya que lograr caso por caso —ver
`ChunkingService` en `lib/core/domain/services/chunking_service.dart`—.
Tres estrategias, elegidas por contenido y no solo por `RenditionKind`
—un artículo web y una transcripción de YouTube llegan las dos como
`markdown`—: por párrafo (texto/markdown/HTML), por ventana de ~75s
cerrando en un límite de oración cuando se detectan marcas `[mm:ss]`
(transcripciones), y un fragmento por bloque en notas armadas con
bloques. Una fuente cuyo texto no reconstruye exacto —o cualquier error
al fragmentarla— no se pisa ni queda a medias: se reporta en
`migration_issue` y se sigue con la siguiente, nunca se persiste un
chunk que no cumple el invariante.

**Dos hallazgos técnicos de la propia migración, para no volver a
pagarlos:**
- `migrator.createTable()` no crea los índices declarados con
  `@TableIndex` —a diferencia de `createAll()`, que sí los incluye para
  una base recién creada—, así que cada `onUpgrade` que agregue una tabla
  con índices propios necesita `migrator.createIndex(...)` explícito por
  cada uno.
- Encadenar `SchemaVerifier.startAt(7)` con una segunda instancia de
  `GeneratedDatabase` (el esquema histórico generado, para sembrar datos
  legacy) sobre la misma conexión antes de migrar deja dos instancias
  compitiendo por la misma conexión física —Drift lo avisa en tiempo de
  ejecución, y en la práctica la migración dejaba de aplicarse—. Las
  funciones de backfill (`classifyExistingItems`,
  `fragmentExistingSources`) se prueban en cambio como funciones puras,
  contra una base ya en `schemaVersion` 8: no les importa si llegaron ahí
  por `onCreate` o por `onUpgrade`, así que cubren la misma lógica sin ese
  riesgo.

**Actualización de F10.** El modelo viejo —`Items`, `Sources`, `Tags`,
`ItemTags`— se retiró en el esquema v19 y el modelo nuevo es hoy el único: ver la
decisión 43.

### 35. F2 del vocabulario controlado: tipo, alias y fusión sobre las Properties existentes

Segunda fase del refactor de siete fases (ver la decisión 34): vocabulario
controlado tipado sobre las categorías/valores que F1 dejó sin tocar.
Igual que F1, 100% invisible — ninguna pantalla se toca todavía, ni una
de administración nueva ni `PropertyEditor`/`TagEditor`—.

**Se extendieron las tablas `PropertyDefinitions`/`PropertyValues` que ya
existían, no se creó el tercer esquema paralelo (`property_category`/
`property_value`/`property_alias`) que sugería la letra original del
encargo.** Esas tablas ya vivían en el código real —a diferencia de
`item`/`source`/`note` en F1, que reemplazaban algo que ya existía—, y
tienen poco radio de impacto: extenderlas evita mantener dos
representaciones del mismo concepto en paralelo.

**Esquema nuevo (`schemaVersion` 8→9):** `type`/`isSystem` en
`PropertyDefinitions`; nueve columnas nullable de fecha/número en
`PropertyValues` (`numberValue`, `dateFromYear/Month/Day`,
`dateToYear/Month/Day`, `datePrecision`, `dateIsCirca`); tabla nueva
`PropertyAliases`, única *dentro de la categoría* —`UNIQUE (definition_id,
alias COLLATE NOCASE)`—, no por valor ni global. `seedSystemPropertyCategories`
crea "Tema" (texto) y "Fecha del hecho" (fecha) desde `onCreate` y desde
`onUpgrade` —una bóveda nueva solo pasa por la primera—, reusando y
promoviendo a `isSystem: true` una categoría que ya existiera con ese
nombre en vez de duplicarla. `migrateTagsToPropertyValues` —solo en
`onUpgrade`— migra cada `Tag` a un `PropertyValue` bajo "Tema" con un id
nuevo, y cada `ItemTags` a `ItemPropertyValues`; `Tags`/`ItemTags` no se
tocan ni se borran, siguen siendo la fuente de verdad de `TagEditor` hasta
que una sub-fase de UI migre también eso.

**`HistoricalDate`: año astronómico firmado, aritmética de calendario a
mano.** `1 d.C. → 1`, `1 a.C. → 0`, `44 a.C. → -43` — monótono cruzando el
cero, así que ordenar y comparar rangos no necesita ningún caso especial
para a.C./d.C. El rango (`rangeStart`/`rangeEnd`) y el label legible
(`HistoricalDate.label`) se calculan con aritmética entera propia —regla
gregoriana proléptica para días-en-el-mes—, sin `DateTime`: mezclaría la
numeración implícita de `DateTime` con fechas de calendario reales, y no
depende de que años tan lejanos se comporten igual en todas las
plataformas (la web incluida). El label de `decade`/`century` es el rango
de años que cubren ("1920 – 1929"), no un nombre de siglo/década ("Siglo
XX"): el año que se tipea para esas precisiones es el primero del tramo
de diez o cien años, no un número de siglo, y no hay forma de convertirlo
a un ordinal sin asumir que ese tramo arranca justo en un límite de siglo
canónico.

**Seis métodos nuevos en `OrganizeRepository`:** el guard de `isSystem` en
`deletePropertyDefinition` (no se puede borrar "Tema" ni "Fecha del
hecho"); `type` opcional en `getOrCreatePropertyDefinition`, sin pisarle
el tipo a una categoría existente; `renamePropertyValue` y
`resolvePropertyValue` (label primero, alias después, ambos sin distinguir
mayúsculas y dentro de la categoría); `mergePropertyValues`, transaccional
en un orden exacto —reasignar los conflictos de doble asignación antes
que el resto (la clave de `ItemPropertyValues` es compuesta), reapuntar
los alias del descartado ANTES de borrarlo (su FK es `ON DELETE CASCADE`
y se los llevaría con él), y tolerar sin fallar la fusión entera si el
label del descartado ya es alias de un tercero—; y
`getOrCreateHistoricalPropertyValue`, que valida el tipo de la categoría y
hace el get-or-create por el label calculado.

### 36. F3 de estados y bandeja de entrada: el espejo en vivo, y el primer lector real del modelo nuevo

Tercera fase del refactor de siete fases (ver la decisión 34). Activa lo
que F1 dejó documentado como pendiente: `LibraryRepositoryImpl.save`/
`delete`/`deleteMany` ahora mantienen `item`/`source`/`note`
sincronizados en cada escritura, dentro de la misma transacción —
dual-write, la opción más simple de las dos que dejó anotadas la
decisión 34—, usando el mismo id que esas filas ya comparten con
`Items`/`Sources` desde el backfill de F1.

**Qué se sobreescribe siempre y qué se preserva.** Los campos que son un
reflejo directo de `KnowledgeItem` (título, subtítulo, espacio, y los
campos estructurales de `source`) se sobreescriben en cada `save()`. Los
que una fase futura —o la propia Bandeja— escribe directo contra el
espejo se preservan leyendo la fila existente antes de escribir encima:
`item.state`, `source.fullText`/`contentHash` (F5/F7 los llenan de
verdad), `note.noteKind`/`maturity`. El único avance automático de
`state` es `captured → processed` cuando `ProcessingState` llega a
`ready`; nunca retrocede ni pisa una decisión de triaje ya tomada —
`ProcessItemUseCase` llama `save()` más de una vez por elemento (en
curso, listo), así que recalcular el estado en cada escritura habría
devuelto en silencio a `processed` cualquier elemento que el usuario ya
hubiera triado.

**Migración de catch-up, `schemaVersion` 9→10, sin tabla ni columna
nueva.** Todo lo capturado entre el backfill de F1 y este commit no
tenía fila en `item` —nunca pasó por `classifyExistingItems`—;
`mirrorUnmirroredItems` reusa el mismo mapeo puro que el espejo en vivo
(`knowledge_mirror_mapping.dart`, compartido también por
`classifyExistingItems`) para clasificarlo, sin fragmentar en chunks ni
calcular `fullText`/`contentHash`: ese trabajo sigue siendo de F5/F7. Sin
snapshot de esquema nuevo para v10 —a diferencia de v8/v9, esta
migración no cambia la forma del esquema, solo la puebla—.

**La Bandeja de entrada muestra solo fuentes en `processed`** —no
notas—: su progreso se mide con `maturity`, no con el flujo de triaje,
que el propio encargo describe en términos de fuentes. Tres acciones de
un toque: descartar (`→ discarded`), extraer nota (reusa
`HighlightableText` y el camino de captura existente, sin lógica de
extracción nueva) y vincular a nota viva (`createRelation` con
`RelationKind.cites`, nota→fuente). Cada toque es la decisión de triaje
en sí misma —transiciona a `triaged` (o `discarded`) en el momento del
toque, no cuando termina el flujo secundario que sigue—, consistente con
el propio docstring de `ItemState.triaged`. La cuarta acción del encargo
original, "aceptar propiedades sugeridas", queda explícitamente para F4:
no existe todavía ni la tabla `suggestion` ni el pipeline de Gemma para
propiedades. Por la misma razón, ningún elemento llega a `distilled` a
través de F3.

**`InboxRepository` nuevo**, no métodos agregados a `LibraryRepository` u
`OrganizeRepository`: es el primer lector y escritor real de
`item`/`source`/`note` desde que existen. `OrganizeRepositoryImpl.
createRelation` gana un efecto lateral acotado —un vínculo
`extractedFrom` marca `noteKind: atomic` en la nota de origen—, que
corrige de paso el clasificado del flujo de extracción que ya existía
desde antes de F1.

**`maturity` visible en el detalle de una nota**, no en la tarjeta de la
biblioteca: la tarjeta declara explícitamente que muestra "cuatro
cosas", y una quinta reactiva por fila no vale el costo en una lista
larga.

**La Bandeja de entrada como séptimo destino de navegación**, justo
después de Biblioteca. Su ícono es `move_to_inbox`, no `inbox_outlined`:
ese ya lo usan los estados vacíos de Biblioteca y Explorador, y
coincidir los dejaba ambiguos en pantalla ancha, donde el riel y un
estado vacío conviven en la misma pantalla.

**Actualización de F10.** El espejo en vivo se retiró: `save`, `delete` y mover de
tema escriben solo `item`/`source`/`note`, y el modelo viejo dejó de existir. El
espejo fue durante F3 a F9 la única red que sostenía que las dos mitades
coincidieran; F10 lo reemplaza por claves foráneas al modelo nuevo y por
conteos como compuerta de la migración (decisión 43).

### 37. F4 de clasificación asistida: herencia mecánica, sugerencias del modelo, y el circuito de a un elemento

Cuarta fase del refactor de siete fases (ver la decisión 34). Cierra la
cuarta acción que F3 dejó pendiente en la Bandeja —"aceptar propiedades
sugeridas"—, construyendo lo que le faltaba: herencia mecánica de
propiedades al extraer una nota, una tabla de sugerencias persistente, un
servicio de sugerencias sobre el mismo Gemma del chat, generación
automática al terminar de procesar, y la UI de revisión. Alcance
explícito, confirmado con quien encargó el trabajo: el circuito completo
de A UN ELEMENTO por vez. Sugerencias en lote sobre varios elementos a la
vez ("estos 14 parecen ser Región: Roma, ¿aplico a todos?") quedan para
una sub-fase aparte, todavía sin planear.

**Esquema nuevo (`schemaVersion` 10→11), sin backfill.** Columna `origin`
en `ItemPropertyValues` (`manual`/`inherited`/`suggestedAccepted`, default
`manual`) y tabla `Suggestions` nueva —`kind`, `targetItemId` referenciando
`KnowledgeEntries.id`, `payloadJson`, `status` (`pending`/`accepted`/
`rejected`)—, indexada por `(targetItemId, status)`. A diferencia de la
migración de catch-up de F3 (v9→v10, solo poblaba), esta SÍ cambia la
forma del esquema, así que hizo falta un `drift_schema_v11.json` nuevo. Sin
migración de datos: `origin` trae su propio default y `Suggestions` nace
vacía.

**`origin` tuvo que viajar por `ItemProperty`, la entidad de dominio, no
alcanzaba con la columna sola** — mismo problema que ya tuvo `ItemState`
en F3, misma solución. `LibraryRepositoryImpl._syncProperties` reescribe
`ItemPropertyValues` entera en cada `save()` a partir de `item.properties`
en memoria: si `origin` no viajara en la entidad, cualquier edición
posterior de un elemento —cambiar el título, por ejemplo— lo hubiera
devuelto en silencio a `manual`.

**`GemmaChatModel` gana una quinta interfaz, `PropertySuggestionService`,
mismo patrón que `RelationSuggestionService`.** El vocabulario —categorías
existentes con sus valores y alias— va en el MENSAJE de usuario, no en el
system prompt: es dato por bóveda, no fijo, mismo criterio que la lista de
candidatos de `suggestRelations`. El modelo puede proponer un valor nuevo
bajo una categoría existente, nunca una categoría nueva —reduce la
confirmación a una sola dimensión, "¿es nuevo el valor?", no dos—; el
parser (`parsePropertySuggestions`) descarta en silencio cualquier línea
cuya categoría no matchee, sin distinguir mayúsculas, alguna categoría
conocida. Solo categorías `PropertyValueType.text` entran al vocabulario:
`assignProperty` solo escribe `PropertyValues.value` como texto, nunca los
campos de fecha ni el numérico, así que aceptar una sugerencia bajo
"Fecha del hecho" hubiera dejado esos campos en `null` de forma
inconsistente.

**Herencia: efecto lateral de `createRelation`, mismo bloque que ya marca
`noteKind: atomic` en F3, con `insertOrIgnore`.** Cada
`ItemPropertyValues` de la fuente se copia a la nota nueva con
`origin: inherited`; si la nota ya tenía esa propiedad puesta a mano,
`insertOrIgnore` no la toca —`insertOnConflictUpdate` hubiera
downgradeado en silencio un origen manual en cada extracción, perdiendo
una decisión real del usuario—. Como `fromItemId` en `extractedFrom` es
siempre la nota nueva, esto cubre `HighlightableText._extractSelection` y
`ExtractNoteScreen` sin tocar ninguno de los dos.

**`SuggestionRepository`, primer repositorio del proyecto que depende de
otro repositorio.** `accept(id)` necesita aplicar el payload de verdad, así
que llama a `OrganizeRepository.assignProperty(..., origin:
suggestedAccepted)` en vez de escribir `ItemPropertyValues` directo —cada
tabla sigue teniendo un solo dueño de sus escrituras, y ese dueño sigue
siendo `OrganizeRepository`—. Sin `_db.transaction()`: si `assignProperty`
falla, la sugerencia simplemente queda `pending`, reintentable, sin ningún
estado inconsistente visible.

**`GeneratePropertySuggestionsUseCase` vive en `data/`, no en `domain/`**
—única excepción consciente al patrón del resto del proyecto—: arma el
vocabulario leyendo `PropertyDefinitions`/`PropertyValues`/
`PropertyAliases` directo de `AppDatabase`, una lectura demasiado
específica de esta sub-fase como para agregarle un método nuevo a
`OrganizeRepository` solo para esto. `ProcessItemUseCase` depende de la
interfaz de dominio (`PropertySuggestionGenerator`), no de la clase
concreta.

**Generación fire-and-forget, solo en el camino a `ready`, nunca en el de
`failed`.** `ProcessItemUseCase._process()` dispara
`unawaited(_suggestionGenerator.generate(saved).catchError(...))` después
de guardar el elemento listo, sin esperarlo ni dejar que un error —o que
el `Future` nunca complete— le cueste el resultado del procesamiento. Sin
contenido fiable tras un fallo, no hay nada que sugerir. El generador
también filtra lo que el elemento ya tiene asignado, comparando por
`valueId`, para no repetir sugerencias redundantes.

**Degradación sin modelo, adentro del generador, no en la UI** —mismo
patrón que el grafo (chequeo previo explícito), no el de las tarjetas
(try/catch sin chequear antes)—: `ChatModelManager.isReady()` se comprueba
al principio de `generate()`; si es `false`, no se genera nada, sin
excepción ni telemetría de error —no es un error, es el camino normal
cuando el modelo no está descargado—.

**UI de revisión, mismo patrón checklist que flashcards/grafo, sin estado
de carga.** `showSuggestionReviewDialog` recibe el `SuggestionRepository`
ya resuelto, no un `WidgetRef`: `_PendingItemCard` transiciona el elemento
a `triaged` —y se desmonta en cuanto eso pasa, porque sale de
`processed`— antes de abrir el diálogo, así que un `ref` atado a ese
widget ya no sirve para cuando la persona confirma la selección. El
repositorio se lee mientras el widget sigue montado, antes de transicionar
—un bug real que apareció al escribir el test de punta a punta de la
Bandeja, no una precaución hipotética—.

### 38. F5 del motor de relaciones: embeddings on-device, preselección por similitud, y la pantalla de Tensión

Quinta fase del refactor de siete fases (ver la decisión 34), la primera
que no tenía más que una frase de encargo ("motor de relaciones y
detección de tensión"). Cuatro ambigüedades reales se resolvieron con
quien encargó el trabajo antes de planear: la integración es vía
`Suggestions`/Bandeja, generalizando `Suggestion` para admitir vínculos
—el diálogo manual del grafo queda intacto como vía aparte—; Tensión es
una superficie propia, no un `RelationKind` más tratado igual que el
resto; los embeddings son solo preselección de candidatos, el LLM sigue
juzgando el tipo de vínculo; y el backfill de lo ya capturado es
completo, no solo lo nuevo. `flutter_gemma` 1.8.2, ya instalado para el
chat, resultó tener soporte de embeddings on-device completo —
`EmbeddingGemma 300M 8-bit`—, sin ningún paquete nuevo.

**`Suggestion` pasa de campos planos a unión sellada por variante,
`property`/`relation`.** Freezed expone los campos compartidos entre
constructores (`id`/`status`/`createdAt`/`confidence`) como getters en
la clase base, así que todo el código que solo necesita eso —el diálogo
de revisión, por ejemplo— sigue sin `switch`; los campos específicos de
cada forma sí lo exigen, la garantía real de modelarlo así en vez de
nullable-everything. `SuggestionRepositoryImpl.accept()` hace `switch`
interno: una sugerencia de propiedad sigue aplicando por
`assignProperty`, una de relación aplica por
`OrganizeRepository.createRelation`.

**Chunking y `fullText`/`contentHash`: función compartida entre la
migración de catch-up y el motor en vivo, sin tocar el backfill de F1.**
`chunkAndPersistSource` repite el algoritmo de
`fragmentExistingSources` (F1, ya cerrado y probado) parametrizado por
un solo `itemId`, con idempotencia al principio. Se acepta duplicar esa
lógica como costo de no reabrir una fase cerrada. La migración de
catch-up (`schemaVersion` 11→12) la llama en loop sobre toda
`KnowledgeSources`, sin snapshot de esquema nuevo —mismo criterio que
v10 (decisión 36): puebla, no cambia la forma—; el motor en vivo la
llama una vez por elemento recién procesado, siempre, sin depender de
ningún modelo.

**El motor automático solo actúa sobre fuentes, nunca notas.**
`Chunks`/`fullText` están atados por diseño de F1 a `KnowledgeSources`,
1:1 con `ItemKind.source`; extenderlo a notas sería un cambio de F1 que
ninguna respuesta del encargo pidió. El diálogo manual del grafo —que sí
usa `searchableText`, no `fullText`— sigue siendo la única vía para
vincular notas.

**Similitud coseno sobre centroides, sin índice ANN.** Funciones puras
en `core/` (`embedding_similarity.dart`): con el volumen de una bóveda
personal, traer los vectores y comparar en Dart es del orden de
milisegundos en cualquier dispositivo que ya corre un LLM de cientos de
MB en el mismo hilo. La similitud a nivel de ítem usa el centroide de
sus chunks —`O(n+m)`—, no el máximo por pares —`O(n×m)`—: como los
embeddings son solo preselección, no hace falta esa precisión, el LLM
corrige el error de la preselección. `Embeddings.vector` guarda
`Float32List.sublistView()`, no `.view()`, que exige una alineación de 4
bytes que un `Uint8List` que vuelve de sqlite3 no garantiza.

**`EmbeddingModelManager`/`GemmaEmbeddingModelManager`, interfaz
PARALELA a `ChatModelManager`, no una extensión.** `flutter_gemma`
gestiona el embedder y el modelo de chat como dos "modelos activos"
totalmente independientes (`hasActiveEmbedder()` contra
`hasActiveModel()`), y descargar un embedder necesita dos archivos
—modelo y tokenizador— mientras `ChatModelManager.download()` asume
uno solo. Mismo precedente que la decisión 8 (Whisper vs Gemma): dos
managers paralelos, no una interfaz forzada. Un solo modelo fijo, sin
selector de variantes como el chat: nadie interactúa directo con "el
embedder". `TaskType.retrievalDocument` siempre, nunca
`retrievalQuery`: acá no hay ninguna pregunta de usuario, tanto los
chunks indexados como el excerpt del elemento semilla son documentos,
una comparación simétrica documento-a-documento.

**Un solo generador secuencial por elemento, no dos `unawaited()` en
paralelo.** Hay una dependencia de orden estricta dentro del motor
—candidatos por similitud necesitan el embedding propio, que necesita
los propios chunks— que dos fire-and-forget independientes no podrían
garantizar entre sí. `ProcessItemUseCase` termina con DOS generadores
fire-and-forget en su constructor —el de F4 (propiedades) sin tocar, y
este nuevo—, que sí corren en paralelo *entre sí* sin problema, porque
no comparten ningún orden. El motor reusa `RelationSuggestionService`
del grafo tal cual —ni el servicio, ni el parser, ni
`RelationCandidate` se tocan—, cambiando solo cómo se arma la lista de
candidatos.

**Backfill de embeddings: bajo demanda, con pantalla de progreso propia,
nunca en `onUpgrade`.** A diferencia del chunking (puro, sin modelo,
migración de catch-up), calcular embeddings necesita el modelo
descargado —cientos de MB, gated en Hugging Face—, que puede no estar
nunca: migrarlo en `onUpgrade` bloquearía el arranque y rompería "nada
sale del dispositivo salvo lo que el usuario pide explícitamente" de la
forma más directa. `BackfillEmbeddingsUseCase` recorre las fuentes con
chunks y reusa el mismo `ChunkEmbeddingIndexer` del motor en vivo —un
ítem que falla se reporta y no corta el resto, correrlo dos veces no
reindexa nada, el indexador ya es idempotente por su cuenta—.

**Tensión: pantalla propia alcanzable desde un botón en el grafo, no un
octavo destino de navegación.** Filtra `allRelationEdgesProvider` a
`RelationKind.contradicts` client-side, sin distinguir si el vínculo se
creó a mano, por el diálogo manual, o por el motor automático —
`Relations` no tiene columna de procedencia, y ninguna respuesta del
encargo pidió agregarla—. Ruta plana `/graph/tension`, mismo patrón que
`/chat/model`: es una lente sobre datos que ya vive en `Relations`, no
una sección nueva.

**Dos bugs reales encontrados escribiendo los tests, no precauciones
hipotéticas.** `EmbeddingModelScreen` inicializaba su
`TextEditingController` con un `late final` perezoso que leía `ref`; si
el modelo ya estaba listo desde el primer build, esa rama nunca se
construía, y `dispose()` forzaba la inicialización justo cuando `ref`
ya no era válido —corregido inicializándolo en `initState()`—. El mismo
listener de descarga no cortaba la suscripción tras un error
(`cancelOnError`): el "listo" del cierre del stream, que siempre llega
después de un `addError`, pisaba el aviso de error recién puesto. El
mismo segundo patrón existe también en `ChatModelScreen`, preexistente,
fuera del alcance de esta fase.

---

### 39. F6 del grafo local y notas mapa: panel embebido, pantalla con pan y zoom, y la entrada preferida de una nota mapa

Sexta fase del refactor de siete fases (ver la decisión 34), otra que
llegó sin más que una frase de encargo ("grafo local y notas mapa").
Tres ambigüedades se resolvieron con quien encargó el trabajo antes de
planear: el grafo local vive en dos lugares —un panel embebido en el
detalle de CUALQUIER elemento, y una pantalla completa con pan y zoom
real, a la que se llega tocando el panel—; una nota se marca como mapa
a mano desde su propio detalle, sin ninguna vía de captura nueva; y una
nota mapa recibe trato especial de tres formas —insignia visual, punto
de entrada preferido al grafo local, y una vista propia de sus vínculos
agrupada por tipo—.

**`noteKind` se lee y escribe desde `InboxRepository`, no desde
`OrganizeRepository`.** Ya era, por su propio rol, "primer lector y
escritor real" de `item`/`source`/`note`, y ya leía `noteKind`/
`maturity` — sumarle las dos escrituras que le faltaban completó un rol
que ya tenía, en vez de abrirle una responsabilidad nueva a
`OrganizeRepository`.

**Desmarcar una nota mapa la deja siempre en `NoteKind.living`, nunca
restaura el tipo anterior.** Ninguna columna guarda "qué era antes de
ser mapa", y agregar una para esto habría sido la única pieza de
esquema nueva de toda la fase por un caso marginal; volver a `atomic`
sería además semánticamente falso — esa marca dice "no crece", y una
nota que se usó de índice ya dejó de cumplir esa promesa.

**`MapNoteLinksSection` no duplica el grafo, solo reagrupa la lista de
vínculos por `RelationKind`.** El panel de grafo local ya se embebe en
el detalle de cualquier elemento, notas mapa incluidas — mostrarlo de
nuevo adentro de esta sección pintaría el mismo grafo dos veces en la
misma pantalla. Comparte `RelationTile`/`addRelationFlow` con
`RelationsSection`, extraídos a nivel de archivo sin cambiar su
comportamiento.

**El punto de entrada preferido es una regla de navegación, no solo un
color.** Dentro de cualquier vista de grafo local —panel o pantalla
completa—, tocar un nodo que es una nota mapa entra al grafo local
centrado en esa nota (`openLocalGraphNode`) en vez de ir a su detalle;
es la lectura literal del propio docstring de `NoteKind.map`, "da
puntos de entrada al grafo". La lista de vínculos nunca aplica esta
regla: tocar una fila siempre va al detalle plano, la distinción vive
solo en las vistas de grafo — `CompactGraphNode`, compartido por el
panel (`LocalGraphPanel`, sin pan/zoom) y la pantalla completa
(`LocalGraphScreen`, con `InteractiveViewer` igual que `GraphScreen`).

**Sin migración de esquema.** La columna `note.note_kind` acepta
`NoteKind.map` desde `schemaVersion` 8 (F1); F6 es la primera fase que
la expone para escritura, no la primera que la crea.

**La insignia de nota mapa en `LibraryItemCard` es una excepción
consciente a la decisión 36.** F3 dejó escrito a propósito que una
quinta cosa reactiva por fila no valía el costo en una lista larga;
acá está explícitamente pedida, mitigada con el mismo `autoDispose` que
ya usa el thumbnail de la fila. Sin trabajo aparte para el Explorador:
ya reusa `LibraryItemCard`, así que la insignia aparece ahí gratis.

---

### 40. F7 de deduplicación: hash y simhash, sin ningún modelo de IA

Séptima y última fase planeada del refactor de organización (ver la
decisión 34). A diferencia de F5/F6, esta sí tenía el texto original
del encargo, recordado por quien lo pidió durante la propia sesión:
calcular `content_hash` y `simhash` al capturar, avisar si hay
coincidencia y ofrecer fusionar conservando las dos procedencias o
mantener separados, sin perder nunca texto que uno tenga y el otro no.
Cuatro ambigüedades se resolvieron con quien encargó el trabajo antes
de planear: alcance de esta ronda solo dentro de una misma bóveda —la
fusión de bóvedas completas al importar el backup de otro dispositivo
queda aparte, es una pieza bastante más grande—; un duplicado puede
ser cualquier combinación entre fuente y nota, no solo mismo tipo
contra mismo tipo; detección automática al capturar, no un escaneo
completo de toda la bóveda a pedido; y cómo avisar cuando el texto
recién existe después de procesar —sugerencia pendiente, revisable
después, no un aviso inmediato que a esa altura nadie vería—.

**Detección 100% determinística, sin modelo de IA.** `content_hash`
(SHA-256 sobre texto normalizado: minúsculas, sin puntuación, espacios
colapsados) para duplicados exactos; `simhash` de 64 bits —shingles de
palabras, voto ponderado por bit, hash FNV-1a— para casi-duplicados,
comparados por distancia de Hamming. A diferencia del motor de
relaciones de F5, esta fase funciona desde la primera captura de
cualquier usuario, sin ningún modelo que descargar. Ninguna de las dos
columnas reusa el `contentHash` que F1 ya tenía en `KnowledgeSources`:
ese sirve la idempotencia del chunking sobre texto crudo, un propósito
distinto que mezclar habría sido confuso.

**Dos momentos de detección, forzados por cuándo existe el texto, no
por preferencia de diseño.** Una nota o un texto pegado ya están
completos al momento de guardar: un diálogo interactivo avisa ANTES de
guardar, con la opción de fusionar ahí mismo —el elemento nuevo llega a
existir un instante, y de inmediato se fusiona con el que ya había,
reusando el mismo caso de uso de fusión sin ningún camino aparte—. Una
fuente que hay que traer de la red recién tiene texto después de
procesarse: una `Suggestion.duplicate` —que F1 ya había reservado en
`SuggestionKind`, pensando en esta fase— queda pendiente, revisable
después en su propia pantalla.

**La fusión conserva un solo elemento, con las DOS renditions de
texto.** Ninguna se borra; la más completa queda como principal.
Relaciones, etiquetas, propiedades y tarjetas del descartado se
reasignan al que queda con el mismo criterio tolerante a conflictos
que ya usaba `mergePropertyValues` (F2): se reasigna donde no choca, se
descarta sin romper la fusión entera donde el que queda ya tiene lo
mismo. Un registro nuevo y chico, `MergedProvenances`, congela de
dónde salió el descartado antes de que su fila desaparezca de verdad
—con el mismo `LibraryRepository.delete()` de siempre, que ya limpia
cascadas viejas, espejo nuevo y archivo original en una sola
operación—. Solo el texto está garantizado: el archivo original del
descartado, si tenía uno propio aparte de su texto, se borra igual que
en cualquier borrado normal.

**La sugerencia de duplicado no entra al diálogo de revisión
genérico.** Aceptar una propiedad o un vínculo es reversible con un
toque; fusionar borra un elemento. Tiene su propia pantalla, "Posibles
duplicados" —mismo patrón que Tensión en F5: ruta plana, alcanzable
desde la sección "Bóveda" de Ajustes—, con confirmación explícita por
fila antes de aplicar nada.

**El generador necesita dos puntos de enganche, no uno.** Para
fuentes, un tercer generador fire-and-forget en `ProcessItemUseCase`,
paralelo a los dos de F4/F5. Para notas, un hook en
`LibraryRepositoryImpl.save()` —el único camino central por el que
pasa tanto crear como editar una nota, sin importar desde qué
pantalla—, con su propia `SuggestionRepositoryImpl` sin capacidad de
fusionar:
el generador necesita `SuggestionRepository`, que desde F7 necesita
`MergeDuplicateItemsUseCase` para poder aceptar una sugerencia de
duplicado de verdad, que a su vez necesita `LibraryRepository` — dejar
que el hook de notas dependiera de esa misma cadena habría cerrado un
ciclo real de providers.

**Dos errores reales encontrados al ejercitar el hook de notas de
punta a punta.** Leer `SuggestionRepository.watchPendingSuggestions().
first` desde el generador —fuera del árbol de widgets, mientras uno
seguía montado— colgó un test, el mismo antipatrón ya documentado en
F6; se reemplazó por una consulta directa contra `AppDatabase`. Y el
diálogo interactivo, que fusiona casi enseguida el elemento recién
guardado, corre en paralelo con el generador fire-and-forget que ese
mismo `save()` dispara: sin comprobar que los dos elementos siguen
existiendo justo antes de insertar, la sugerencia podía romper una
restricción de llave foránea contra un elemento que la fusión ya había
borrado — una carrera benigna, resuelta en silencio en vez de con
telemetría.

**Actualización de F11.** Fusionar dos duplicados ya no es irreversible ni pierde
lo escrito a mano: el descartado va a la papelera —de ahí se restaura— y su
subtítulo y sus notas pasan al que queda (decisión 44).

### 41. F8 de higiene: una sola fuente de verdad para las etiquetas, y el mantenimiento del vocabulario

Primera fase del encargo de cierre del refactor (F8 a F11, ver la decisión
34). Arregla un bug activo y cierra un hueco. El bug: F2 había copiado las
etiquetas a valores de Tema UNA sola vez, y `Tags`/`ItemTags` siguieron
siendo la fuente de verdad de la interfaz de etiquetas, así que toda
etiqueta creada después no existía como propiedad y filtrar por propiedad
devolvía resultados incompletos, en silencio. El hueco: renombrar y
fusionar valores existía en el repositorio y ningún botón lo llamaba.

**Una etiqueta ES un valor de Tema.** `PropertyValue` bajo la categoría de
sistema "Tema" es la única fuente de verdad, y `Tag.id` es el id del valor.
La API y la interfaz de etiquetas —`Tag`, `TagEditor`, `watchAllTags`,
`getOrCreateTag`, `renameTag`, `deleteTag`, `LibraryQuery.tagIds`— quedaron
intactas, reimplementadas encima de las propiedades. `KnowledgeItem.tags`
son las asignaciones bajo Tema y `KnowledgeItem.properties` todo lo demás,
sin solapamiento: antes, una etiqueta migrada salía dos veces en el
detalle. `_syncTags` sincroniza por DIFERENCIA y no rehaciendo la
relación, porque una asignación tiene datos propios —su `origin`:
`suggestedAccepted`, `inherited`— y borrarla para reinsertarla la
degradaría a `manual`; una propiedad de Tema que llegue en
`item.properties` se trata como etiqueta en vez de perderse. `Tags` e
`ItemTags` quedaron marcadas obsoletas en el código: las retiró F10 (ver la
decisión 43).

**Resolver por texto sin distinguir acentos.** `normalizeVocabularyLabel`
—minúsculas, sin acentos, sin plegar `ñ` ni `ç` porque "año" y "ano" son
palabras distintas, y la puntuación cuenta— es la base de todo lo demás.
Destapó dos defectos viejos: `assignProperty` ignoraba los alias (escribir
"Constantinopla", alias de "Bizancio", creaba un valor duplicado) y el
`lower()` de SQLite solo baja ASCII, así que "Álgebra" y "álgebra" nunca
coincidían. Un resolvedor único, `findValueByLabelOrAlias`, en
`core/database`: los dos repositorios que lo necesitan tienen que decidir
igual qué es "el mismo texto". Si varios valores normalizan igual —posible
en bases de antes de F8, porque el índice único solo ve mayúsculas ASCII—
gana el escrito idéntico, luego el que solo difiere en mayúsculas, luego el
más antiguo.

**La reconciliación (migración v14).** `planTagReconciliation` solo lee y
devuelve el informe —el dry-run—; `applyTagReconciliation` escribe.
Unifica por texto normalizado y SOLO dentro de Tema: si ya hay valores se
conserva el más usado (a igual uso, el más antiguo) y los demás se fusionan
en él con su label como alias; si no hay ninguno, se crea uno desde la
etiqueta más usada, con su mismo id. Las asignaciones pasan con
`insertOrIgnore`, nunca `insertOnConflictUpdate`: la migración de F2 sí
pisaba el `origin`. Idempotente, con `Tags`/`ItemTags` intactas. Corre
dentro de la transacción de `onUpgrade` y SIN `try`/`catch`: si algo falla
la migración entera revierte —hay copia previa— en vez de saltarse un
grupo y dejar una etiqueta sin valor, que es justo la pérdida que se
evita. El informe queda en `MigrationIssues` y en el registro; el encargo
pedía un informe "previo", y una migración no puede detenerse a preguntar,
así que se calcula antes de aplicar, dentro de la misma migración. Se
verificó que `PRAGMA foreign_keys` vale 0 durante `onUpgrade`: nada
cascadea ahí, por eso la reconciliación descarta las asignaciones de
elementos que ya no existen.

**Respaldo antes de cada migración.** `VACUUM INTO` no puede correr dentro
de una transacción y drift migra dentro de una, así que el respaldo no
puede ir en `onUpgrade`: corre en el `setup` de la conexión nativa, sobre
el SQLite crudo, antes de cualquier migración (`<base>.pre-vN.bak`,
conserva las últimas 3). Si no se puede respaldar, lanza y drift cierra la
base: no se migra sin red de seguridad. En la web no hay archivo que copiar
y la protección es que la migración es transaccional. Solo respalda la
base; los archivos originales no los toca ninguna migración de F8 a F11.

**La fusión NO era reversible.** El encargo daba por hecho que "ya es
reversible a nivel motor"; era transaccional, pero borraba la fila del
descartado sin guardar qué asignaciones y alias tenía. El motor
—`mergePropertyValueRows`, ahora en `core/database` porque lo comparten la
pantalla y la migración— devuelve un registro de deshacer y
`undoPropertyValueMerge` lo revierte. Deshacer se NIEGA si el vocabulario
cambió de una forma que obligaría a adivinar, y no deja nada tocado; solo
cuentan los conflictos de INTEGRIDAD (los que violaría el índice único),
no la comparación sin acentos, porque el estado original pudo tener
casi-duplicados legítimos —justo lo que la pantalla existe para limpiar—.
Las operaciones de lote son transaccionales: si una del lote falla, no
queda ninguna aplicada. El registro vive en memoria, por sesión: cerrar la
app lo olvida.

**Candidatos a fusión.** `findMergeCandidates` es una función pura que
devuelve pares de valores de una misma categoría de texto: mismo texto sin
distinguir acentos, uno contenido en el otro por palabras enteras ("Arte"
no está en "Artesanía"), o casi igual escrito. Nunca fusiona: sugiere.
Se contiene el costo sin comparar todo contra todo —bloques por primera
letra y largo parecido, descarte por firma de letras, índice por palabra— y
se acota la salida por valor, porque cuando muchísimos nombres se parecen
entre sí los pares crecen con el cuadrado: una prueba con 1.001 nombres que
comparten la primera palabra tardaba ~4,8 s antes de acotarlo. Medido: con
2.000 valores realistas, ~40 a 90 ms; el peor caso adversarial, ~250 a 500
ms; el requisito era menos de un segundo. El precio del bloque por primera
letra: un error justo en la primera letra no se detecta. Corre en un
isolate, para no congelar la pantalla.

**La pantalla de Vocabulario.** Ruta plana `/vocabulary`, en la sección
"Bóveda" de Ajustes, con cinco pestañas: parecidos, un solo uso, sin uso,
categorías vacías, y todas las categorías —tocar una abre su explorador,
con búsqueda, renombrar, alias y fusión de los marcados—. Fusionar pide
confirmación con cuántos elementos afecta ANTES de hacerlo. Solo se
preseleccionan los casi seguro iguales: "Guerra" y "Guerra fría" comparten
palabras y pueden ser cosas distintas. Toda operación se puede deshacer, la
última, desde el aviso o desde la barra superior.

**Lo que la construcción encontró, y se corrigió de raíz.**
- `SchemaVerifier.migrateAndValidate(db, N)` abre la base AFIRMANDO que su
  objetivo es N: con 13 desde v13, drift ve una base al día y no ejecuta
  `onUpgrade`. Los tests de v14 siembran una base v13 real (`schemaAt`) y
  abren `AppDatabase` encima, como hace la app.
- El "Deshacer" del aviso no funcionaba tras fusionar: capturaba el
  `BuildContext` de una tarjeta que se reconstruye. Ahora se captura, antes
  de esperar, el `ScaffoldMessenger`, los textos y el controlador.
- Un `ProviderScope` anidado solo cambia los providers que sobrescribe él
  mismo: uno sin sobrescribir sigue leyendo sus dependencias del contenedor
  raíz.
- Ordenar con `toLowerCase()` compara por código de carácter: "Época" iba
  después de "Tema". El orden es sobre el texto normalizado.
- Una hoja modal tapa con su barrera el aviso con "Deshacer" de la pantalla
  de abajo: el detalle de un valor es una página.

**Lo que F8 no hace.** No retira `Tags`/`ItemTags` (lo hizo F10, decisión 43). No hay panel de
salud ni acceso al vocabulario desde él (F9). No detecta espacios temáticos
(F11). El respaldo previo no existe en la web. Los valores de Tema sin
etiqueta —creados en el editor de propiedades, o lo que quedó de una
etiqueta que se renombró o se borró después de F2— no se tocan: no hay
forma de saber cuál de las dos cosas fue, y la pantalla de Vocabulario es
donde se limpian. Y el invariante de chunking —concatenar los chunks
reproduce `fullText` carácter a carácter— se hizo comprobable en cualquier
momento (`verifyChunkInvariant`); un test recorre toda la reconciliación y
el mantenimiento del vocabulario, con sus deshacer, y comprueba que los
chunks y el texto de las fuentes quedan idénticos.

---

### 42. F9 de consolidación: el ciclo de mantenimiento, la línea de tiempo y la bandeja como mazo

Segunda fase del encargo de cierre (F8 a F11, ver la decisión 34). La app ya
tenía entrada, digestión y trabajo, pero ningún lugar donde consolidar lo
acumulado ni ver si algo se pudre. F9 lo construye en veintidós commits: un
panel de salud, la línea de tiempo sobre "Fecha del hecho", los enlaces rotos
de toda la bóveda, las sugerencias en lote, y cuatro cambios del ciclo diario
—la Bandeja como mazo, la vista de lectura para destilar, la nota viva con sus
fuentes citadas y la distinción visual entre fuente y nota—.

**Dónde el encargo chocó con el código real.** Se dijo antes de resolver, y
cada punto tiene su solución más abajo. "Contradicciones no vistas" no existía
como concepto: `Relations` no guardaba si una relación se había revisado. Los
bloques de una nota no tenían fecha propia, solo la nota tenía `updatedAt`, así
que "bloques nuevos en la semana" no se podía calcular. La extracción guardaba
que una nota salió de una fuente pero no DE DÓNDE. Los `[[ ]]` se resolvían al
guardar y los rotos no dejaban rastro. Ningún visor salta a una posición
—salvo el de medios, a un instante—. "Sostenido" en la Bandeja no tiene
historial. Y un choque que apareció recién al armar la línea de tiempo: ninguna
pantalla asignaba una "Fecha del hecho" —el modelo y el método del repositorio
existían desde F5, pero el editor de propiedades solo creaba texto sin fecha—,
así que el eje habría nacido vacío. Se agregó el formulario de fecha como
commit propio, con la aprobación del usuario.

**Un solo cambio de esquema (14 a 15), todo aditivo.** La tabla `inline_link`
—cada `[[Título]]` con el elemento al que apunta, o sin él si está roto— y tres
columnas nulas en `Relations`: `reviewedAt` (la marca de contradicción revisada)
y `sourceCharStart`/`sourceCharEnd` (de dónde salió una extracción). Con el
respaldo previo de F8 y un backfill de los enlaces de las notas existentes que
informa lo que no pudo leer, con su plan en seco. `inline_link` referencia
`Items` como `Relations`: F10 las repuntó juntas (v18, decisión 43).

**Enlaces rotos.** Guardar una nota sincroniza sus enlaces y, al revés, guardar
o renombrar cualquier elemento resuelve los rotos que tenían ese título y crea
la relación real. La regla de coincidencia es la de siempre —recorte y
minúsculas, el más antiguo gana—, y la propia nota no cuenta. Si se borra el
destino el enlace vuelve a quedar roto en vez de desaparecer. El editor ofrece
crear la nota que falta sin salir de él (con subtipo `living` por defecto), y
una pantalla lista los rotos de toda la bóveda con creación en lote. Una nota
con bloques ilegibles se informa por telemetría y deja sus enlaces como estaban:
nunca borra lo que no pudo leer.

**Sugerencias en lote y su deshacer.** Las de propiedad se agrupan por
categoría y valor normalizado; `acceptMany` es transaccional —si una falla,
ninguna—, y el usuario marca fila por fila: el lote acelera la confirmación, no
la quita. Se agregó `revertAccepted`, que quita lo que puso una aceptación y la
deja pendiente: solo lo que puso ELLA. Aceptar una propiedad que el elemento ya
tenía a mano dejó de reasignarla —cambiaba su origen a "sugerida aceptada", y
deshacer después le habría quitado una decisión del usuario—; queda anotado en
el payload. Es el mismo criterio de no rebajar un origen manual que ya usaba la
herencia (decisión 36).

**Contradicciones revisadas, bloques con fecha, panel de salud.** La pantalla
de Tensión muestra las pendientes y permite marcar como revisada, con deshacer.
Cada bloque recuerda cuándo se agregó (`addedAt`, opcional en el JSON y
compatible hacia atrás: los bloques viejos no cuentan como nuevos hasta
editarse). El panel de salud vive al tope de la Biblioteca, plegado por
defecto —un primer diseño siempre desplegado rompía 44 pruebas por desborde—,
con cuatro indicadores tocables: pendientes en la Bandeja, notas por madurez,
candidatos de vocabulario a fusionar y contradicciones sin revisar, más tres
accesos (notas que crecieron en la semana, enlaces rotos, sugerencias por
revisar). El umbral de "se captura más de lo que se digiere" es sobre el conteo
ACTUAL de la Bandeja (más de 50): no hay historial para medir "sostenido".

**La línea de tiempo.** El eje es continuo, en años astronómicos con fracción
(1 d.C. empieza en 1.0, 1 a.C. en 0.0): sin salto en el cero, y a.C./d.C. se
escriben solo al mostrar. La aritmética de calendario es la de `HistoricalDate`,
no una copia. Un evento es un TRAMO, no un punto —"476" ocupa ese año, "siglo V"
cien—, y un "circa" corre cada extremo la mitad del tramo: convención de dibujo,
no un dato que la fuente haya dado. Para que dibujar diez mil hechos cueste lo
que hay en pantalla y no lo que hay guardado, un árbol de intervalos sin
punteros sobre los eventos ordenados devuelve la ventana visible con la cota
del mayor final por tramo —un máximo acumulado se degradaba con un evento
larguísimo al principio—; el reparto en carriles trabaja solo sobre esa
ventana. Con 10.000 eventos: armado en unos 30 ms, ventana de 20 años con unos
cien eventos y menos de 300 nodos vistos, mil cuadros de arrastre en unos 70
ms; la prueba decide por el conteo de nodos, determinista, y usa el cronómetro
solo como red de seguridad. La imprecisión se VE: fecha exacta, barra llena;
aproximada, bordes que se desvanecen; década o siglo, contorno con relleno
tenue. Pan y zoom con gestos, rueda, teclado y botones; filtros con el mismo
`LibraryQuery` de la biblioteca (`matchingIds` expuesto: no hay un segundo motor
de búsqueda que pueda discrepar). Solo cuenta la categoría de sistema "Fecha del
hecho".

**La Bandeja como mazo.** Tres gestos, tres teclas, tres botones que hacen lo
mismo: a la izquierda descarta, a la derecha deja triada, arriba abre para
destilar. Las propiedades sugeridas son chips —tocar acepta, tocar de nuevo
deshace—; deshacer lo último (botón, Ctrl+Z o el aviso) devuelve la fuente a la
Bandeja en el lugar que tenía. Se probó triar 50 fuentes mezclando los tres
caminos sin cambiar de pantalla.

**Vista de lectura para destilar.** Extraer guarda el rango exacto del texto de
la fuente (`sourceCharStart`/`End`, en las coordenadas de los resaltados). La
vista de lectura tiene "Extraer como nota" como acción principal en una barra
fija —`bottomNavigationBar`, para que el aviso de "nota creada" se apoye encima
y no tape el botón—, cuenta las notas que salieron de la fuente y lleva a cada
fragmento con un salto medido con un `TextPainter` armado con los mismos estilos
y ancho que el texto. Desde una nota extraída, "Ver en la fuente" abre la vista
en ese fragmento.

**Nota viva: fuentes citadas y madurez.** `NoteSourcesRepository` da las fuentes
que cita una nota por dos caminos que pueden darse a la vez: un vínculo `cites`
directo, o las fuentes de las notas atómicas que enlaza (cualquier vínculo que
no sea una contradicción, solo los que SALEN de la nota). Cada fragmento dice
qué atómica lo usa y, cuando la fuente tiene trozos con marca de tiempo o
página, en qué minuto o página está. La madurez —semilla, en desarrollo,
madura— pasa de etiqueta que se lee a algo que se mueve, con vuelta atrás: la
decide quien escribe.

**Fuente y nota se distinguen a la vista.** `EntityRole` en
`entity_presentation.dart`, una sola fuente para la lista, el explorador, la
búsqueda, el tablero, la tabla, el grafo, la Bandeja y la línea de tiempo: la
fuente es un documento —esquinas casi rectas, fondo neutro, contorno fino—, la
nota es propia —esquinas muy redondeadas, fondo teñido—. Probado por pantalla.

**Verificación.** El analizador se mantuvo en la línea base (32) en cada commit y
la suite pasó de unas 1.660 pruebas a más de 2.270, todas verdes. El invariante de chunking se
comprobó al cerrar la fase: `f9_source_text_untouched_test.dart` ejecuta todo lo
que hace F9 —enlaces, sugerencias en lote y su deshacer, revisiones, fechar
hechos, extraer con posición, madurez, la Bandeja y todas las lecturas nuevas—
sobre una bóveda con dos fuentes chunkeadas y comprueba que `fullText` y los
chunks —con sus ids— siguen siendo idénticos y que `verifyChunkInvariant` sigue
dando verde. Ninguna función de F9 resume ni reescribe el texto de una fuente. Un solo
commit intermedio, `2fa6ae6`, no compila por sí solo: salió con solo el retiro
de una pantalla por un error al armarlo, y `577e3f0` lo completa; la suite y el
analizador se corrieron sobre el árbol completo.

**Lo que F9 no hace, dicho sin adornos.** Saltar a un instante de un video o
audio, a una página de un PDF o al paginado de DOCX/EPUB desde una nota extraída:
la vuelta al fragmento cubre texto y transcripciones, y los visores de medios
todavía no reciben una posición de texto. La línea de tiempo ubica meses y días
en el eje pero su marca más fina es el mes, y solo lee "Fecha del hecho": las
categorías de fecha que cree el usuario usan el mismo formulario y no aparecen
en el eje. El texto de una fecha (`HistoricalDate.label`, lo que se ve en el
chip) está escrito en español aunque la app esté en inglés: viene de F5 y es el
valor guardado, no una presentación. El deshacer de la Bandeja alcanza a la
última acción, no a un historial; aceptar sugerencias en lote no tiene deshacer
en bloque. El umbral de la Bandeja no es "sostenido" porque no hay historial. Y
el modelo viejo seguía de fuente de verdad: unificarlo, y retirar `Tags`/`ItemTags`
y el espejo, lo hizo F10 (decisión 43); el borrado suave y la fusión no destructiva
al restaurar son F11.

### 43. F10 de unificación: un solo modelo de datos, el texto de una fuente en su forma principal, y una búsqueda que cita el minuto o la página

Tercera fase del encargo de cierre (F8 a F11, ver la decisión 34). Hasta F9 la
app escribía cada elemento dos veces —`Items`/`Sources` y su espejo `item`/
`source`/`note`— y leía casi todo del modelo viejo; el texto de una fuente
estaba guardado tres veces; la búsqueda iba contra un índice de elementos
enteros que no sabía decir DÓNDE; y nadie comprobaba que las dos mitades
coincidieran. F10 lo unifica en dieciocho commits, en cuatro tramos: medir,
poner los chunks a trabajar, leer del modelo nuevo, y apuntar las claves,
escribir una sola vez y retirar el viejo.

**Dónde el encargo chocó con el código real.** Se dijo antes de resolver.
`Renditions`, `Highlights`, `Relations`, `Flashcards`, `InlineLinks` e
`ItemPropertyValues` no estaban duplicadas: el modelo nuevo no tenía
equivalente, solo colgaban de `Items` por clave foránea. No se retiraron: se
**repuntaron** a `item`. `Sources` era N:1 con `Items` y `source` es 1:1: el id de
una fuente deja de ser propio y es el del elemento —una fuente compartida ya
estaba duplicada, una fila por elemento, desde el backfill de F1—. «El texto
íntegro una sola vez» no se puede cumplir del todo: queda el documento entero
UNA vez, en su forma de texto principal, pero los chunks conservan su porción
porque es la unidad que se recupera, se embebe y se cita sin cargar el documento;
son dos copias, no tres. `chunk` tenía clave primaria de texto, o sea `rowid`
implícito, y `VACUUM INTO` —que usan los respaldos— puede renumerarlo: un FTS5 de
contenido externo atado a ese `rowid` habría quedado apuntando a filas
equivocadas sin avisar. `substr` de SQLite cuenta puntos de código y los
desplazamientos de chunks y resaltados son unidades UTF-16: todo recorte por
posición se hace en Dart. Y el benchmark en un Android de gama media no se puede
correr desde acá.

**Medir antes de tocar (tramo 0).** Una bóveda sintética de 10.000 elementos
—7.200 fuentes y 2.800 notas, 312.793 chunks, 25.000 relaciones— generada de
forma determinista y guardada en `.dart_tool`, y un arnés con dos capas: las
afirmaciones de `EXPLAIN QUERY PLAN` y de paginación corren siempre, y el
cronometraje solo con `--dart-define=BENCH=true`, con un umbral de escritorio de
objetivo/3 como sustituto de un dispositivo (estimación, no medición). El mismo
arnés corre en un dispositivo con `integration_test`. La línea base dio dos
problemas reales antes de migrar nada: la búsqueda traía TODOS los ids a Dart
antes de paginar, y el grafo local cargaba la biblioteca entera y todas sus
aristas —casi un minuto con 10.000 elementos—. Se arreglaron primero: la búsqueda pagina en
SQL, y el grafo local lee solo la vecindad (`watchNeighborhood`, con tope de 30
nodos en el panel y 200 en la pantalla) y su disposición usa arreglos tipados en
vez de mapas, bit a bit igual que la versión anterior. No se migra sobre una base
lenta.

**Chunks vivos y una búsqueda que cita (tramo 1, esquema v16).** `chunk` gana
`row_key`, un entero autoincremental que pasa a ser su clave primaria —un entero
declarado clave ES el `rowid` y no se renumera—; `id` sigue siendo la identidad,
única, para que los embeddings le sigan apuntando. `chunk_search` es un FTS5 de
contenido externo sobre `chunks.content` —65,2 MB de índice para 218,7 MB de
texto, sin segunda copia— y `chunk_vocab` una vista `fts5vocab` que dice, antes de
buscar, en cuántos chunks está cada palabra. Con eso `save()` mantiene los
chunks: idempotente por el SHA-256 del texto de la forma principal —si no cambió
no hace nada; si cambió, reemplaza los chunks y con ellos sus embeddings, que ya no
describían el texto—, en la misma transacción. La búsqueda de la Biblioteca va
sobre los chunks y cada resultado lleva su cita —`mm:ss` o `p. N`— y un fragmento.
Ordenar por relevancia cuesta lo que cuestan las coincidencias (≈1,5 µs cada una),
y una palabra en dos tercios de los chunks no distingue nada: por encima de 30.000
coincidencias se ordena una ventana de las 600 más recientes en vez de todas; la
conjunción de palabras se resuelve a nivel de elemento con INTERSECT, y el corte
por relevancia va sobre el índice SOLO, antes de unir con `chunks`. Para citar una
PÁGINA hizo falta arreglar el texto, no el chunker: el parser de PDF descartaba las
páginas vacías, con lo que numerar por posición habría corrido en silencio todos
los números siguientes. Ahora conserva cada página en su lugar y el chunker numera
con `paged: true`. Vale para los PDF capturados desde ahora: uno de antes no trae el
lugar de sus páginas en blanco, se sigue encontrando y citando por fragmento, sin
página, y lo único que lo arreglaría es volver a analizar el archivo y reescribir
el texto de una fuente, que no se hace.

**Leer del modelo nuevo, una superficie por commit (tramo 2).** La Biblioteca,
los vínculos de organize, la fusión de duplicados, los enlaces en línea, y el
panel de salud, la línea de tiempo y las fuentes citadas dejaron de consultar
`items`/`sources`. Flashcards, vocabulario, sugerencias y `property_value_merge`
nunca las leían: solo las claves. Cinco commits en vez de los diez previstos.
`sourceFor(item, source?)` es la regla única de qué es la procedencia de un
elemento —una nota no tiene fila de fuente: es una nota manual, capturada cuando
se creó—. Leer del modelo nuevo destapó cuatro defectos que ninguna prueba veía
porque los dos modelos coincidían por casualidad: `assignSpace` y
`assignSpaceMany` escribían solo `items.space_id` y `item.space_id` quedaba con el
tema de antes; el espejo no copiaba las notas libres; la fusión de duplicados
reasignaba las formas del descartado —y con ellas quizá el texto principal— sin
rehacer los chunks del que queda, con lo que el invariante dejaba de cumplirse y
buscar una palabra del descartado ya no encontraba nada; y `save()` escribía el
espejo DESPUÉS de resolver los enlaces en línea, con lo que una nota que se
guardaba por primera vez no se reconocía a sí misma y quedaba con un enlace roto
hacia sí misma.

**Apuntar las claves y escribir una vez (tramo 3, esquemas v18 y v19).** Antes de
v18 se retiraron los pasos de migración anteriores a v15, con sus pruebas y sus
snapshots —la compatibilidad mínima de actualización es v15; una base más vieja
falla con `SchemaTooOldException` y un mensaje que dice qué hacer, antes de tocar
nada—: sus pruebas sembraban `items` sobre el esquema de hoy y no podían convivir
con las claves nuevas. **v18** reconstruye con `alterTable` las cinco tablas hijas
—formas, vínculos, tarjetas, enlaces en línea y asignaciones de propiedad— con sus
claves hacia `item`, y rehace el índice de texto de los elementos sobre `item`
—sus triggers dejarían de dispararse en cuanto `items` no se escribiera—. Con un
dry-run que no escribe nada y estas compuertas: si a `items` le falta la fila de
`item` de algún elemento se completa con el catch-up de siempre; si después queda
un elemento sin ella o una fila que apunta a uno que no existe, lanza y no sigue;
`PRAGMA foreign_key_check` tiene que quedar vacío; y los conteos de las 16 tablas
de lo que el usuario creó (`captureVaultCounts`) tienen que ser iguales antes y
después. `save`, `delete` y mover de tema escriben solo el modelo nuevo: una
escritura, sin transacción de a dos. **v19** suelta `items`, `sources`, `tags`,
`item_tags` y `source.full_text`; antes de quitar la columna comprueba que ninguna
fuente tenga su texto SOLO ahí —si la hay, lanza: perder el texto de una fuente
está descartado—, y compara los conteos de las 19 tablas de datos y de modelo.

**Lo que este trabajo encontró de fondo.** Cuatro cosas, dichas sin adornos.
Primera: `onUpgrade` de drift NO es transaccional por sí solo —cada sentencia se
confirma sola; la propia documentación de drift lo envuelve a mano con
`transaction`—. Las compuertas de v16 decían «si algún conteo no coincide, la
migración entera revierte», y no revertían. Lo destapó la prueba de v18 que forzaba
un huérfano (la fila del espejo que el catch-up había completado quedaba). Desde
v18 todos los pasos van dentro de UNA transacción y hay prueba: un huérfano corta
la migración, la base queda con las mismas filas y todavía en la versión de antes.
Segunda: `items` tenía cinco índices y `item` dos, que no sirven para filtrar por
espacio ni ordenar por modificación; desde P2 esas consultas recorrían la tabla
entera y solo lo dijo la guarda de plan de consulta al retirar `items`. v19 crea
`idx_knowledge_entries_space` e `idx_knowledge_entries_updated_at`. Tercera: desde
P2 esas guardas seguían comparando contra `items` y `sources`, tablas que ninguna
consulta tocaba, y pasaban solas; ahora comparan contra `item` y `source`, con el
nombre entero (`contains('SCAN item')` dejaba pasar un recorrido de `item_search`).
Cuarta: la prueba «el guardado es atómico» no forzaba ningún fallo —la forma que
creía inválida cumplía el CHECK y aceptaba cualquier desenlace—; ahora una
propiedad de una categoría inexistente viola la clave foránea al FINAL del guardado
y se comprueba que no queda ni el elemento, ni su fuente, ni su forma.

**Medido, en el escritorio del que construye la app** (un Core i5-10300H,
enchufado; el escenario de vocabulario, cuyo código no cambió, dio 79 ms al medir
la línea base y 73 ms ahora: los números son comparables). Mediana, en ms, línea
base de v15 → hoy: búsqueda de una palabra rara 94 → 29, mediana 401 → 40, en casi
todo 702 → 56, dos palabras 85 → 23, prefijo 616 → 53 —el objetivo era 300—;
detalle de la fuente con más chunks 2 → 2 y de una nota con enlaces 15 → 15;
grafo local del elemento más conectado 59.482 → 39 en el panel y 109 en la
pantalla —el objetivo era 500—; línea de tiempo 153 → 131; panel de salud 43 →
42. Migrar una copia de la bóveda sintética de 10.000 elementos (909 MB, esquema
v17) de una vez a v19 tarda 5,9 s: los 19 conteos, iguales; cero violaciones de
claves; el texto de las formas, idéntico (226,6 MB); `verifyChunkInvariant` en
verde sobre las 7.200 fuentes y los 312.793 chunks. El archivo queda en 1.141 MB,
463 de ellos páginas libres reutilizables —soltar tablas no achica el archivo—, y
en 669 MB tras un `VACUUM`: el 26 % menos. Una bóveda recién generada en v19 pesa
683 MB. Lo que dejó de estar es la tercera copia del texto, 218,5 MB; quedan la
forma principal (226,7 MB) y los chunks (218,7 MB), más 65,2 MB del índice de los
chunks y 14,4 MB del de elementos.

**Lo que F10 no hace, dicho sin adornos.** No hay cifras de Android: el arnés
corre en un dispositivo, pero no se corrió en ninguno. Solo se migró una bóveda
sintética; en esta máquina no había una base real. La cita de página vale para los
PDF nuevos. Las notas no se fragmentan: su texto lo indexa `item_search`, y no
tienen minuto ni página que citar. El archivo no se compacta solo después de
migrar: hace falta un `VACUUM`, que no puede correr dentro de la transacción y
pide espacio libre en disco del tamaño de la base; queda para quien lo decida. La
fusión de duplicados sigue sin conservar el subtítulo ni las notas libres del
descartado. La pantalla del grafo completo sigue cargando todos los elementos; solo
el grafo local está acotado. El borrado sigue siendo físico, y `deletedAt`,
`deviceId` y `rev` siguen sin lector: borrado suave con papelera, versionado por
campo y fusión no destructiva al restaurar son F11. `Source.id` sigue en la
entidad, igual al id del elemento, y `knowledge_mirror_mapping.dart` conserva un
nombre de cuando había un espejo. Las etiquetas viejas que quedaban en `tags`/
`item_tags` se sueltan sin más: F8 ya las había unido a Tema.

**Actualización de F12.** Tres de las cosas que F10 dijo que no hacía se
cerraron. Hay cifras de Android —de un emulador, no de un teléfono real— y los
trece escenarios cumplen su objetivo: ver la decisión 45. Medirlos desmintió
algo de esta decisión: la ventana de «una palabra en casi todo» no costaba 600
chunks sino 300 ms por consulta en Android, porque FTS5 lee TODAS las
coincidencias de un prefijo antes de dar la primera cuando se le pide el orden
descendente —en escritorio son 8 ms, y por eso F10 no lo vio—; ahora se pide
desde una cota y ordena SQLite (`searchWindowFloor`, `kSearchWindowSql`). El
prefijo de tres letras, que también pide ventana, pasó de 183 a 41 ms. Y el
archivo ahora se puede compactar después de migrar: una bóveda migrada de 1.141
MB vuelve a 670, con una pantalla en Ajustes y una oferta única sobre la
Biblioteca.

### 44. F11 de durabilidad: una papelera, una versión por campo y una restauración que fusiona en vez de reemplazar

Cuarta y última fase del encargo de cierre (F8 a F11, ver la decisión 34). Hasta
F10 nada dolía; dolía el día que hacía falta. Borrar era un `DELETE` físico y sin
vuelta —cuatro puntos de la interfaz lo confirmaban con «No se puede deshacer»—;
`deletedAt`, `deviceId` y `rev` eran columnas sin lector: todo lo escrito llevaba
el texto fijo `f3-espejo-sin-sync` y `rev` valía 1 para siempre; y «Restaurar
copia» cerraba la base, la pisaba entera con la del `.zip`, borraba `originales/`
y pedía cerrar la app: el único camino que perdía datos en silencio. F11 lo
cambia en dieciocho commits, en cuatro tramos: la base (esquema, identidad y un
solo escritor), la papelera, cuatro complementos menores y la fusión. La
restricción que no se negocia: **el texto de una fuente no se pierde ni se
reescribe**; ninguna fusión ni migración lo toca.

**Dónde el encargo chocó con el código real, y qué decidió el usuario.** Se dijo
antes de resolver. No había identidad de dispositivo: `deviceId` era el marcador
de F3. Con las cuatro columnas que pedía el encargo, `field_version` no distingue
«edité ENCIMA de la versión que me llegó» de «edité a la vez que el otro»: en el
uso normal —teléfono, compu, teléfono— casi todo se marcaría como conflicto.
«Mismo identificador, mismo objeto» no alcanza para el vocabulario: los nombres de
propiedad y las etiquetas son únicos sin distinguir mayúsculas, y cada bóveda
siembra su «Tema» y su «Fecha del hecho» con identificadores propios. Los
identificadores de chunk no son estables —al rehacerse el texto de una fuente se
reemplazan—, así que una tarjeta no puede apuntar solo a uno. Y los chunks, los
embeddings y los enlaces en línea son derivados: se calculan del texto y no se
copian. El usuario decidió dos cosas: que restaurar es SOLO fusionar —el
reemplazo total se retira, sin reiniciar la app y con vista previa— y que
`field_version` lleva seis columnas, con linaje.

**La base (tramo 1, esquema v20).** Aditivo, dentro de la transacción única de
`onUpgrade`, con respaldo previo, plan en seco y los conteos de las 19 tablas como
compuerta. `field_version(item_id, field_name, updated_at, device_id,
base_updated_at, base_device_id)` guarda quién modificó cada campo por última vez,
cuándo y —el linaje— la versión AJENA sobre la que se editó, nula si la cadena es
propia. `merge_conflict` guarda las dos versiones de lo que una fusión no pudo
decidir sola; `review_log`, un renglón por repaso de tarjeta; y `flashcards` gana
`source_chunk_id` (clave al chunk, `SET NULL`) y el rango de caracteres del que
salió. La identidad de dispositivo (`DeviceIdentity`) es un UUID por instalación en
`SharedPreferences` y NO en la base, a propósito: un `.zip` lleva la base a otro
equipo, y si el identificador viajara con ella los dos equipos pasarían a ser «el
mismo dispositivo» y ningún conflicto se vería nunca. Reinstalar crea otro, que
para una fusión es lo que es. Lo escrito antes queda con el centinela `legacy`. La
prueba de cadena de v18 destapó un detalle: ese paso reconstruye `flashcards` con
la definición de HOY y una base de v16 o v17 no tiene las columnas nuevas; v18 las
declara y v20 las agrega solo si faltan.

**Un solo escritor (tramo 1).** `KnowledgeEntryWriter` es el único lugar que
escribe los campos de un elemento (`item`, `note`, `source`). Compara lo que hay
con lo que llega y solo si algo cambió de verdad sube `rev`, escribe el
dispositivo real y registra la versión de cada campo que cambió: un guardado
idéntico —el pipeline guarda más de una vez lo mismo— no ensucia la historia. La
regla del linaje: sin fila previa, la base es nula; si la última edición fue de
este mismo dispositivo, conserva su base; si fue de OTRO —una versión que llegó
por una fusión—, esa versión pasa a ser la base de la nueva. Que sea el ÚNICO lo
hace cumplir una prueba que recorre `lib` y falla si otro archivo escribe esas
tablas, y otra que falla si algo lee `item` sin dejar afuera lo borrado. Las dos
llevan una lista de permisos con el motivo al lado, y la vigilan en los dos
sentidos —un archivo permitido que ya no lo hace también falla—, para que no se
vuelva un permiso general. Buscan las tres formas en que se escribe con drift:
sobre la tabla, con una companion y con SQL crudo.

**Borrar manda a la papelera (tramo 2).** `delete` pone `deletedAt` —con su
versión y su linaje, para que una fusión distinga «lo borró el otro» de «lo edité
yo»— y no borra nada: ni la fila, ni el texto, ni lo que cuelga, ni el archivo.
`restore` lo quita. `purge` es lo único que borra de verdad, solo sobre algo que
ya está en la papelera y a pedido, y no borra un archivo original que use otro
elemento, contando también los que siguen en la papelera. Antes de que nada mandara
un elemento a la papelera, todas las lecturas aprendieron a dejarlo afuera
—Biblioteca, búsqueda, Bandeja, salud, línea de tiempo, grafo, enlaces `[[ ]]`,
candidatos, tarjetas—: no hay un solo momento en que un borrado se siga viendo. La
búsqueda pedía al índice los mejores N chunks y RECIÉN entonces unía con `item`,
así que una papelera con muchas coincidencias dejaba páginas vacías —los N lugares
eran de lo borrado y no aparecía nada de lo que sí seguía guardado—: el filtro va
DENTRO de la etapa del ranking, y una contraprueba con la condición anulada rompe
las tres pruebas de saturación. El primer índice sobre `deleted_at` empeoró el
benchmark: sin estadísticas, SQLite creía selectiva la igualdad y recorría entero
un índice de diez mil entradas, todas nulas, volviendo a la tabla fila por fila.
Ahora es un índice PARCIAL —solo las filas borradas—, creado con SQL en
`beforeOpen` porque drift no modela los parciales. En la interfaz, borrar ya no
pregunta: avisa con un «Deshacer». Solo borrar para siempre y vaciar la papelera
piden confirmación, y dicen qué se pierde. La fusión de duplicados manda al
descartado a la papelera y ya no pierde su subtítulo ni sus notas.

**Cuatro complementos (tramo 3).** Cada repaso de una tarjeta deja un renglón en
`review_log` —la nota elegida y la calidad de SM-2, el intervalo y la facilidad
antes y después, cuándo y en qué dispositivo—, en la misma transacción que el
nuevo estado de la tarjeta; es solo un registro, sin pantalla. `RelationKind.indexes`
le da a una nota de mapa una forma de decir «esto es el índice de aquello»; se
guarda por su nombre, sin cambiar el esquema. Crear o renombrar un tema cuyo
nombre ya es una etiqueta avisa antes —son dos cosas distintas con el mismo
nombre—, pero no lo impide. Y una tarjeta dice de qué fragmento salió, y «Ver en
la fuente» lleva de vuelta usando el rango de caracteres, que es lo que sigue
valiendo cuando los chunks se rehacen; se crean desde la selección de la lectura
y desde la IA. La cita de la IA la escribió un modelo, y un modelo chico la cambia
sin avisar: se busca con una búsqueda EXACTA en el texto que abre la lectura, y si
no coincide la tarjeta se guarda sin fragmento. Mejor ninguno que uno equivocado.

**La fusión no destructiva (tramo 4).** `mergeBackup` reemplaza a `restoreBackup`,
que se retira con su caso de uso, su diálogo y sus textos. Una copia se abre en un
temporal y solo para leerla (`IncomingVault`): si su esquema es más nuevo que el de
la app se rechaza, si es anterior a v15 también, y si es intermedio se migra ELLA
—la copia, nunca esta bóveda—. Se adjunta a la conexión (`ATTACH`, que no admite
una transacción abierta), una vista previa en seco dice qué traería —usa el mismo
planificador que después escribe, y una prueba compara lo que anuncia con lo que
hace—, y con la confirmación corre UNA transacción. Primero las guardas:
disparadores temporales que existen solo mientras dura la fusión y hacen
IMPOSIBLE, no solo detectable, borrar un elemento o una forma de texto, reescribir
el texto o el archivo de una forma de una fuente, o tocar los chunks de lo que no
se marcó para reprocesar. Cualquier sentencia que lo intente, la escriba quien la
escriba, aborta todo en el acto.

Los campos se deciden uno a uno con `FieldMergeRule`, una función pura de las dos
versiones. (1) Si el valor es el mismo, nada. (2) Sin versión es el valor de
partida: si solo un lado la tiene, ese lo modificó y gana; si ninguno, gana el
elemento modificado más recientemente. (3) Un dispositivo `legacy` no tiene
conflicto con nadie: gana lo más reciente. (4) El mismo dispositivo de los dos
lados: una edición siguió a la otra. (5) Linaje: si una versión se escribió SOBRE
la otra, gana la que sigue, aunque su reloj marque una hora anterior —los relojes
de dos equipos no coinciden, y es lo que evita marcar como conflicto el uso
normal—. (6) Dos dispositivos conocidos que modificaron el campo sin que ninguno
partiera del otro: conflicto real. Queda en uso el más reciente —por hora y, si
empatan, por dispositivo, igual desde cualquiera de las dos bóvedas— y el otro se
guarda en `merge_conflict`. El linaje reconoce solo la descendencia directa: si
una edición pasó por un tercer dispositivo se trata como concurrente, un conflicto
de más y nunca una edición pisada de menos. Un borrado que llega junto a una
edición del otro lado NO se aplica: quien editó no sabía del borrado ni quien
borró de la edición, así que el elemento queda vivo y el borrado se guarda como
conflicto; uno que llega solo se aplica. Y un conflicto que ya se guardó —resuelto
o no— no se guarda otra vez: fusionar dos veces la misma copia da todo en cero.

El texto tiene su propia regla. Un elemento nuevo trae todas sus formas; una forma
que acá falta se agrega como no principal. Cuando el MISMO identificador tiene un
texto distinto, en una FUENTE nunca se pisa —ni con el linaje a favor ni con la
copia más reciente—: el de acá queda byte a byte y el de la copia entra como otra
forma del mismo elemento, con un conflicto que la señala. En una NOTA, que es lo
que el usuario escribe, manda el linaje; si se editó a la vez, queda lo de acá y lo
de la copia entra al lado con su conflicto, de modo que cada bóveda termina con
los dos textos. Vínculos, resaltados, tarjetas, repasos, procedencias y
conversaciones se UNEN: entra lo que acá no hay y nada se quita —sin lápidas, así
que una quita hecha acá puede reaparecer si la copia todavía lo tenía—. El
vocabulario se une por nombre de categoría y, dentro de ella, por identificador o
por etiqueta; una etiqueta que cambió de nombre en un lado queda como alias en el
otro. Lo derivado no viaja: los chunks y los enlaces en línea se rehacen con las
mismas funciones que usa guardar un elemento, solo para lo que llegó o recibió un
texto, y los embeddings los rehace el proceso de siempre. Los archivos originales
se copian al final, solo los que alguna fila referencia y no están en el disco,
sin pisar nunca uno que ya está —el disco no tiene transacciones, así que lo que
se copió se anota y se borra si algo falla después—.

Antes de confirmar se verifica el resultado: los elementos de antes siguen y los
nuevos entraron; ninguna tabla de lo que creó el usuario tiene menos filas, salvo
las versiones por campo; el texto de lo que se fragmentó de nuevo se reconstruye
exacto desde sus chunks (`verifyChunkInvariant`, ahora capaz de mirar solo unas
fuentes); y no hay referencias rotas que antes no había. Si algo falla, se
revierte la base y se borran los archivos copiados.

**Los conflictos, a la vista.** Ajustes → «Cambios para revisar», y un botón
«Revisar» en el resultado de una fusión que los dejó. Cada uno es una tarjeta con
las dos versiones lado a lado, cuál está en uso y un botón por versión. Elegir un
campo corto es una edición del usuario y se escribe como tal, por el único
escritor y con su linaje: por eso la otra bóveda recibe lo resuelto SIN que vuelva
a ser un conflicto —una prueba fusiona de vuelta y comprueba cero conflictos y el
mismo valor—. En un texto ninguna versión se borra: «usar el otro» intercambia
cuál de las dos formas es la principal, y como cambió el texto de la fuente se
rehacen sus chunks.

**Lo que este trabajo encontró de fondo.** Cuatro cosas. Primera: el índice común
sobre `deleted_at` hacía más lento todo lo demás, y solo lo dijo el benchmark
enchufado; el filtro nuevo no se dio por gratis. Segunda: `buildBackup`
nombraba su archivo temporal con el reloj en microsegundos, y en Windows, donde el
reloj avanza de a un milisegundo, dos copias casi simultáneas compartían archivo y
una fallaba con «database is locked». Apareció como una prueba intermitente; ahora
cada copia usa su propio directorio temporal. Tercera: una prueba de
atomicidad que fuerza un fallo cuando todavía no hay nada escrito pasa con o sin
transacción; la de la fusión trae un espacio bueno que se escribe ANTES del
elemento roto, así que solo pasa si todo se revierte. Cuarta, y la que solo
encontró el benchmark de escala, al cierre: la primera medición de traer una copia
de 10.000 elementos a una bóveda vacía dio 385 s —6,4 minutos—, trece veces lo que
cuesta armar la bóveda sintética entera. Un perfil por etapas lo puso en un solo
lugar: rehacer los enlaces `[[ ]]` de cada nota que llegaba armaba el índice de
títulos de TODA la bóveda, una vez por nota —2.800 recorridos completos—. Guardar
una nota hace lo mismo, pero una sola vez, y nadie lo nota. Ahora la fusión arma
el índice una vez y se lo pasa a cada nota; una prueba cuenta los recorridos y
falla —con 30 en vez de 1— si se vuelve a armar por nota. La misma importación
pasó de 385 s a 68 s. Con los 1.500 elementos que se habían medido antes
no se veía: el costo era cuadrático.

**Medido, en este mismo equipo** (el de F10). La migración de una copia de la
bóveda sintética de 10.000 elementos (esquema v19, 314.213 chunks) a v20 tarda
0,25 s, y 3,2 s con el respaldo previo del archivo entero; los 19 conteos,
iguales; las tablas nuevas, vacías; cero violaciones de claves;
`verifyChunkInvariant` en verde sobre las 7.200 fuentes. La fusión, con dos
dispositivos que parten de esa bóveda —`pc` edita cien títulos, cinco de los que
`tel` manda a la papelera, el texto de cinco fuentes y suma cien fuentes propias;
`tel` edita quinientos títulos, cincuenta en común con `pc`, manda treinta
elementos a la papelera, agrega un párrafo al texto de veinte fuentes y suma
doscientas fuentes, cincuenta notas, trescientos vínculos y cien tarjetas—: traer
la copia de `tel` a `pc` tarda 9,8 s (250 elementos nuevos, 475 con cambios, 300
vínculos, 100 tarjetas, 200 fuentes fragmentadas de nuevo, y 75 conflictos
guardados: 50 títulos editados a la vez, 5 borrados contra una edición y 20
textos de fuente que entran como otra forma); fusionar lo mismo otra vez, 1,6 s,
sin cambiar nada; y traer la copia entera, con sus 10.250 elementos y 320.229
chunks, a una bóveda vacía, 68 s, casi todo fragmentar de nuevo y reindexar. El
tiempo sigue a lo que cambia, no a lo que hay. Ningún texto de fuente de `pc`
cambió —un hash de todas sus formas, antes y después—, el de `tel` entró entero
como otra forma en las veinte fuentes en conflicto, y en la bóveda vacía el hash
de los textos es el de la copia. `verifyChunkInvariant`, sobre la bóveda entera,
se cumple: 7.500 fuentes y 323.217 chunks en `pc` (3,1 s), 7.400 y 320.229 en la
vacía (3,6 s); y no hay claves rotas. Los 13 escenarios del benchmark de F10
siguen dentro de su umbral con todo lo de F11 puesto, incluido el filtro de lo
borrado en cada lectura. Mediana, en ms: búsqueda de una palabra rara 33, mediana
42, en casi todo 56, dos palabras 24, prefijo 53 (F10 cerró en 29, 40, 56, 23 y
53); detalle de la fuente con más chunks 3 y de una nota con enlaces 16; grafo
local del elemento más conectado 40 en el panel y 119 en la pantalla (F10: 39 y
109); línea de tiempo 126; panel de salud 49; vocabulario 75. Este equipo varía
el doble o el triple de una corrida a otra según lo que esté haciendo: una
diferencia de unos pocos milisegundos no es una regresión.

**Lo que F11 no hace, dicho sin adornos.** No hay sincronización en tiempo real
ni fusión al abrir la app: se trae una copia cuando la persona lo pide. No hay
lápidas para lo que se une por conjuntos: una quita puede reaparecer. No se
corrigen los relojes entre dispositivos —el linaje lo mitiga y lo desempata la
hora y luego el identificador—. Lo escrito antes de F11 no tiene dispositivo ni
versión: entre dos valores de origen desconocido gana el del elemento modificado
más recientemente, sin aviso, y el otro no se guarda —el texto de una fuente
queda a salvo, esto es de los campos cortos—. Una edición que pasó por un tercer
dispositivo se marca como conflicto aunque descienda de la otra. Los embeddings no
se copian: se recalculan. `suggestions` y `migration_issues` no se importan. La
papelera no se vacía sola. La fusión no hace un respaldo del archivo antes de
empezar: su garantía es la transacción única y la compuerta; quien quiera una red
más, hace una copia antes. Un `.zip` se sigue leyendo entero en memoria. No hay
cifras de Android: nada de esto se corrió en un dispositivo. `review_log` guarda
datos y no tiene pantalla. Y las bóvedas medidas son sintéticas: en esta máquina no
había una base real.

**Actualización de F12.** Dos de las limitaciones de esta decisión se cerraron.
Un `.zip` ya no se lee entero en memoria, ni se arma entero: la copia pasa por
el zlib nativo por tandas en los dos sentidos, y guardar y elegir van por la
ruta y no por bytes; en el emulador, armarla crece la memoria de 24 a 43 MB con
una base de 683 MB, y abrirla, de 45 a 56 MB. Y hay cifras de Android, de un
emulador y no de un teléfono real: traer la copia de `tel` a `pc` tarda 19,8 s,
fusionar lo mismo otra vez 11,0 s y traer la copia entera a una bóveda vacía
68,2 s, con `verifyChunkInvariant` en verde en 2,2 s —ver la decisión 45—.

### 45. F12 de cierre de deuda: cifras de un Android, revisión en lote desde la Bandeja, una bóveda que se compacta y una copia que no pasa entera por la memoria

Primera fase del encargo F12–F17. Cierra los cuatro puntos que F11 dejó abiertos
—ninguna cifra de un Android; las sugerencias en lote, sin entrada cómoda desde
la Bandeja; el archivo que no se achica después de migrar; el `.zip` de fusión
leído entero en memoria— y fija una disciplina: cada commit compila y analiza
por sí solo. Son dieciocho commits.

**Dónde el encargo chocó con el código y con el entorno.** Se dijo antes de
resolver. Al empezar, `adb devices` estaba vacío: ningún Android conectado. El
usuario decidió medir en el emulador de su PC en lugar de conectar un teléfono
—se armó uno para esto: Android 17, x86_64, 4 GB de RAM y 16 GB de datos—, y eso
cambia lo que las cifras valen (más abajo). La Bandeja YA tenía la revisión en
lote (`ReviewSuggestionsAction`, desde F9): un resumen mío anterior dijo lo
contrario por un `grep` cortado; lo que faltaba era la oferta en la tarjeta, el
deshacer en bloque y probar que la Bandeja retoma donde estaba. El `.zip` no se
leía entero en memoria solo al abrirlo: también al armarlo (`buildBackup()`
devolvía los bytes y `FilePicker.saveFile(bytes:)` los pide así en un teléfono),
de modo que un teléfono que no puede recibir 900 MB tampoco puede hacer la
copia; el punto de streaming se amplió a los dos sentidos. `VACUUM` no se puede
cancelar una vez empezado —ni `sqlite3` ni drift exponen `sqlite3_interrupt`, y
matar el aislado no corta una llamada nativa— y pide más espacio que el tamaño
de la base. `flutter test integration_test` corre en debug, donde el Dart sale
de 5 a 10 veces peor: las cifras salen de `flutter drive --profile`. La bóveda
de 909 MB del criterio es de esquema v17 y el generador solo arma la actual. Y
la disciplina de commits no se podía afirmar: el ritual analizaba y probaba el
ÁRBOL DE TRABAJO, no lo que quedó en el commit —así salió `2fa6ae6`, que no
compilaba—; `tool/verify_commit.ps1` exporta el commit con `git archive` y lo
analiza solo.

**Lo que las cifras valen, y lo que no.** Las de abajo son de un EMULADOR en
modo profile, corriendo sobre la CPU y el disco de la PC que lo aloja —un
i5-10300H con NVMe—. Sus TIEMPOS no valen como los de un teléfono de gama media,
ni para bien ni para mal: dependen de la PC. La misma corrida, con la PC
funcionando a batería en lugar de enchufada, dio de 3 a 5 veces más: armar la
copia pasó de 45–68 s a más de 220 s y el arrastre de la línea de tiempo, de
8–12 ms de raster por cuadro a 31. Y aun enchufada, dos corridas iguales
difieren hasta un 50 %. La MEMORIA no varió, y esa sí vale —el sistema mata la
app en cuanto se pasa del límite— igual que el hecho de que el código, el arnés
y las dependencias nativas corren en Android. Los cuadros por segundo de un
emulador dependen además de cómo dibuje: no son los de la GPU de un teléfono.
Cada carpeta de `docs/benchmarks/` dice `emulador-…` en su nombre y en
`dispositivo.md`, que también anota si la PC estaba enchufada; la corrida a
batería (`2026-09-21-a-bateria`) y la primera, anterior al arreglo de la
búsqueda (`2026-09-21-antes-del-arreglo-de-la-ventana`), están aparte. F12
cierra con estas cifras; el encargo pedía un teléfono real, y esa medición sigue
pendiente.

**Medir encontró cuatro cosas que ninguna cifra de escritorio mostraba.**

*La línea de tiempo, con diez mil hechos* (`fcd6edd`): con 157 barras a la vista
y un arrastre sostenido, en modo profile y en una PC, 22 a 28 ms por cuadro en
armarse, 49 a 62 en pintarse y 233 de 299 cuadros pasados del presupuesto. Los
diez mil hechos NO eran el problema —el índice de intervalos y el reparto en
carriles cuestan 76 ms por mil ventanas—: eran los widgets, un subárbol con
`Tooltip`, `InkWell`, semántica y `CustomPaint` por evento, rehecho en cada
cuadro. Ahora un solo lienzo dibuja todas las barras desde `TimelineFrame`, el
modelo de lo que se ve, con los rótulos medidos una vez; lo que se ve, lo que se
toca y lo que lee un lector de pantalla salen del mismo modelo. En el emulador,
con la PC enchufada, el mismo arrastre en dos corridas —`2026-09-20` y
`2026-09-21`—: de 5,1 a 6,0 ms de promedio para armar y de 7,5 a 11,7 para
pintar —percentil 90 de pintar, 12,2 y 23,1—, con 18 de 578 y 123 de 528 cuadros
fuera del presupuesto de raster.

*La búsqueda de una palabra en casi todo* (`d15f2bf`): 640 ms contra un objetivo
de 300, el único de los trece escenarios que no cumplía, con el frío igual a la
mediana. La ventana de los 600 chunks más recientes se pedía con `ORDER BY rowid
DESC LIMIT 600`, y FTS5, con una palabra buscada como prefijo, no puede dar el
orden descendente sin leer TODA la lista de coincidencias antes de la primera:
300 ms con la palabra en 122.531 chunks, pidiera lo que se pidiera —`LIMIT 50`
costaba lo mismo— y desde donde se pidiera —una cota sobre el `rowid` tampoco lo
achicaba—; en la pantalla se pagaba dos veces, por la página y por las citas. En
un escritorio esa lectura cuesta 8 ms, y por eso las cifras de escritorio nunca
la mostraron. El prefijo de tres letras, que también pide ventana, pagaba lo
mismo: 183 ms. Ahora se busca hacia adelante desde una cota —`searchWindowFloor`
prueba tramos cada vez más largos desde el último chunk hasta juntar una ventana
de coincidencias vivas—, que FTS5 resuelve sin leer todo (5 ms), y el orden lo
pone SQLite con `ORDER BY rowid + 0`: a una tabla virtual solo se le pasan
columnas, y con una expresión el orden no puede volver a caerle encima. La
ventana es la misma chunk por chunk, y un test de plan lo vigila. De paso, el
plan del texto —cuántas coincidencias tiene, si pide ventana y desde dónde— se
decidía tres veces por búsqueda y ahora una; y `SELECT MIN(x), MAX(x)` en una
sola consulta recorre la tabla entera (30 ms con 314.000 chunks), mientras que
en dos subconsultas usa el índice.

*Memoria al compactar* (`71ee22a`): el SQLite del proyecto se compila con
`SQLITE_TEMP_STORE=2`, o sea que la copia de trabajo de `VACUUM` vive en RAM,
una vez el contenido útil. Medido en escritorio, con el disco libre y la memoria
del proceso sondeados cada milisegundo:

```
temp_store     útil     disco extra          memoria extra
por defecto    78,6 MB   78,6 MB (1,00×)      +92 MB
por defecto   188,2 MB  185–189 MB (1,00×)   +218 MB
FILE           78,6 MB  155,2 MB (1,98×)      +12 MB
FILE          188,2 MB  375,2 MB (1,99×)       +5 MB
```

Un `VACUUM` directo de la bóveda de 909 MB pediría cerca de 1 GB de memoria y el
sistema mataría la app. Con `PRAGMA temp_store = FILE` la memoria no crece, a
cambio de disco: el doble de lo ÚTIL —copia de trabajo más el diario de
reversión—, no del archivo, porque las páginas libres no se copian. De ahí la
regla del consejero: `2 × útil + 10 % + 16 MiB`; la compactación incremental, `2
× 2.048 páginas`.

*`archive` no hace streaming con entradas comprimidas* (`103ab2d`, `6d965a6`):
la versión 4.0.9 acumula en memoria todo lo descomprimido antes de escribirlo
(`ZLibDecoder.decodeStream` y `ArchiveFile.writeContent`: 95 MB de crecimiento
con una base de 164 MB) y comprime cada entrada a un `OutputMemoryStream` al
armar. Solo las entradas sin comprimir y `OutputFileStream.writeStream` (1 MiB)
van por tandas. La primera versión de `IncomingVault.openFile` suponía lo
contrario y se corrigió con una prueba de memoria que la desmintió. Ahora la
copia pasa por el zlib nativo de `dart:io` como `Stream`, con el CRC de cada
entrada verificado y el archivo parcial borrado si falla. Medir memoria pidió
cuidado: el RSS del proceso se infla si el fixture se arma en el mismo aislado
(una prueba «pasó» con +1 MB y era falso), así que el fixture se arma en otro
(`Isolate.run`) y el RSS se muestrea desde otro
(`test/support/rss_sampler.dart`).

**Del arnés**, tres cosas que costaron un rato. `flutter drive` desinstala la
app al terminar, y con ella se va lo que se empujó con `adb`: hay que empujar
antes de cada corrida. Lo que `adb push` deja en la carpeta de la app queda a
nombre de `shell` con permiso 660: la app ve la carpeta pero no puede abrir
ningún archivo, así que el guion les abre los permisos. Y `--no-dds` hace falta
para medir cuadros: sin él, `watchPerformance` intenta conectarse a un puerto de
la PC que en el dispositivo no existe. El guion (`tool/bench_android.ps1`)
reconoce un emulador, arma solo el APK de la ABI del dispositivo y deja las
cifras en `docs/benchmarks/`.

**Las cifras del emulador**, con la PC enchufada. Los trece escenarios del
benchmark de F10, sobre la bóveda sintética de 10.000 elementos y 314.213 chunks
armada en el propio emulador (683 MB), medianas en ms. La columna «escritorio»
es la referencia en modo profile de F12
(`escritorio-windows-i5-10300h/2026-09-20`, antes del arreglo de la ventana); «a
batería» es la misma corrida, tras reiniciar el emulador, con la PC
desenchufada; «ahora», la última con la PC enchufada:

| escenario | objetivo | escritorio | antes del arreglo | ahora | a batería |
|---|---:|---:|---:|---:|---:|
| búsqueda: palabra rara | 300 | 51 | 12 | 13 | 78 |
| búsqueda: palabra mediana | 300 | 90 | 25 | 26 | 46 |
| búsqueda: palabra en casi todo | 300 | 88 | **640** | 44 | 53 |
| búsqueda: dos palabras | 300 | 31 | 14 | 14 | 22 |
| búsqueda: prefijo | 300 | 83 | 183 | 41 | 60 |
| detalle: la fuente con más chunks | 200 | 1 | 0 | 0 | 0 |
| detalle: una nota con enlaces | 200 | 22 | 4 | 5 | 6 |
| grafo local: panel, elemento típico | 500 | 1 | 0 | 0 | 1 |
| grafo local: panel, el más conectado | 500 | 156 | 23 | 29 | 34 |
| grafo local: pantalla, el más conectado | 500 | 200 | 80 | 80 | 109 |
| línea de tiempo: leer los eventos | 1000 | 115 | 59 | 58 | 83 |
| panel de salud: todos los indicadores | 600 | 78 | 25 | 24 | 35 |
| vocabulario: estadísticas + candidatos | 3000 | 135 | 55 | 57 | 81 |

Los trece cumplen su objetivo en todas las corridas, con más de tres veces de
margen en la búsqueda; el primer cuadro de cada escenario, con la caché fría,
llega a 173 ms en la búsqueda y a 322 en el grafo local del más conectado. Que
el emulador dé menos que el escritorio en casi todo no dice que un teléfono sea
más rápido que una PC: dice que el emulador usa la PC, y que la excepción —lo
que en Android cuesta distinto— es justo lo que la búsqueda de arriba mostró.
`kDesktopFactor` (el umbral de escritorio es el objetivo dividido 3) sigue
siendo una estimación: un emulador que comparte la CPU con el escritorio no
puede medir el cociente con un teléfono.

Los cuatro escenarios sin objetivo del encargo, medidos, con un presupuesto
PROPUESTO —a confirmar con un teléfono— de entre dos y cuatro veces el emulador
enchufado:

- *Apertura en frío* con 10.000 elementos: de montar la app al primer cuadro, 73
  ms; a la primera lista, 430 ms; memoria residente de 205 a 211 MB. Propuesto:
  primera lista en menos de 1,5 s.
- *Fusión de una variante* (dos dispositivos que parten de la misma bóveda;
  `tel` edita 500 títulos, manda 30 a la papelera y suma 200 fuentes): traer la
  copia de `tel` a `pc`, 19,8 s; fusionar lo mismo otra vez, 11,0 s; traer la
  copia entera a una bóveda vacía, 68,2 s; `verifyChunkInvariant` en verde en
  2,2 s sobre 323.217 y 320.229 chunks. Propuesto: la variante en menos de 90 s
  y la copia entera en menos de 5 min.
- *Migración de v17 a v20 con el respaldo previo* de 896 MB: 22,8 s, con los 19
  conteos iguales, cero claves rotas y el invariante en verde. Propuesto: menos
  de 2 min.
- *Línea de tiempo*: árbol de 10.000 eventos en 5 ms, mil ventanas de arrastre
  en 83 ms, la pantalla abierta en 371 ms, y el arrastre sostenido de arriba.
  Propuesto: percentil 90 de armado y de raster bajo los 16,6 ms de un cuadro a
  60 Hz y menos del 5 % de los cuadros fuera del presupuesto. El armado lo
  cumple en todas las corridas enchufadas (percentil 90 de 8,3 y 10,7 ms);
  pintar lo cumplió en una (12,2 ms) y en la otra no (23,1 ms, el 23 % de los
  cuadros fuera), y a batería dio 30,8 ms de promedio y 210 de 268 cuadros
  fuera. Una cifra de emulador que dice más de la PC y de cómo dibuja el
  emulador que de la línea de tiempo: el presupuesto no se confirma sin un
  teléfono.

**La compactación, medida de punta a punta** (12.3). Tras migrar, el archivo
ocupa 1.140,8 MB y 463,0 son páginas libres; el consejero pide 1.507,2 MB de
disco y había 9.886. Compactar tarda 33,6 s en el emulador (31,3 reescribir y
2,1 comprobar): el archivo pasa a 669,8 MB, devuelve 471,0, y la memoria
residente sube 4,6 MB con 677,8 MB de contenido útil —contra los unos 790 MB que
la tabla de arriba predice para un `VACUUM` directo—. La comprobación cuenta las
filas de las veintidós tablas de datos, del modelo y de durabilidad, y corre
`verifyChunkInvariant` sobre las 7.200 fuentes. La PRIMERA compactación
reescribe todo (`auto_vacuum = INCREMENTAL` más `VACUUM`, la única forma de
cambiar ese modo en una base que ya existe) y no se puede detener una vez
empezada; las siguientes devuelven las páginas libres de a tramos de 2.048
(`incremental_vacuum`), con avance y cancelables entre tramos. Sin lugar en el
disco lanza `VaultCompactionNoSpaceException` sin tocar nada, con cuánto falta;
sin dato de disco lo intenta. El complemento de espacio libre
(`disk_space_plus`) solo existe en Android e iOS: en escritorio la sonda dice
«no se sabe» en vez de fallar. Se ofrece en Ajustes → Bóveda y, una sola vez,
como tarjeta sobre la Biblioteca cuando hay bastante para devolver (al menos 64
MiB y el 15 %).

**La revisión en lote desde la Bandeja** (12.2). `revertAcceptedMany` deshace un
lote entero o nada —misma regla que `revertAccepted`: quita solo la propiedad
que puso esa aceptación y la deja pendiente—; el aviso trae «Deshacer» y dura
diez segundos, porque deshacer un lote es una decisión y no un reflejo. La
tarjeta de la Bandeja dice «14 elementos más parecen ser `Región: Roma`» y abre
una hoja SOBRE la Bandeja, sin nada marcado: la cola, su orden y la tarjeta
quedan como estaban, y eso es lo que se prueba.

**La copia por tandas** (12.4), en los dos sentidos. Armar: `StreamingZipWriter`
comprime cada entrada con el zlib nativo a un archivo, sin pasar por la memoria;
abrir: `IncomingVault.openFile` descomprime por tandas y solo la base sale a un
temporal. Guardar y elegir van por la ruta y no por bytes: el usuario elige
DÓNDE antes de armar —armar lleva minutos y cancelar el selector no puede costar
eso—; en Android es una carpeta por el Storage Access Framework y
`pasteLocalFile` copia el archivo por tandas, y en escritorio `File.copy`. En el
emulador enchufado, sobre la bóveda de 683 MB más 49 MB de originales: armar la
copia tarda entre 45 y 68 s según la corrida, el `.zip` pesa 220,4 MB —el 30 %—
y la memoria residente crece de 24 a 43 MB; abrirla, de 23 a 28 s y de +45 a +56
MB; máximo del proceso, 397 MB, con la base abierta. Ni armarla ni abrirla crece
con lo que pesa la bóveda, y con la PC a batería los tiempos se multiplicaron
por 4 o 5 pero el crecimiento de memoria siguió entre 19 y 60 MB. La copia se
lee de vuelta con el CRC de cada entrada verificado: 10.000 elementos, los doce
originales y un PDF idéntico.

El camino de Android, con los dos selectores del sistema manejados por
`uiautomator` (`tool/bench_android_pick_folder.ps1`, que hace lo que haría una
persona: entrar a `Documents`, «Usar esta carpeta», «Permitir»): guardar los
220,4 MB con `pasteLocalFile` tardó 0,6 s y creció la memoria 0,3 MB; el archivo
quedó en `primary:Documents/`, se bajó a la PC y `zipfile` de Python lo dio por
bueno, con sus 13 entradas y el CRC de cada una. Elegirlo de vuelta con el
selector de archivos copia el `.zip` al almacenamiento temporal de la app en 5,8
s (+1,4 MB) enchufada y hasta 12 s a batería, se abre desde esa ruta con sus
10.000 elementos, y `discardPicked` deja el almacenamiento temporal sin él.

**Lo que F12 no hace, dicho sin adornos.** No hay cifras de un teléfono real:
las del emulador dependen de la PC que lo aloja, y los presupuestos de arriba
son propuestas hasta confirmarlos con uno. El guardado y la elección por los
selectores de Android se ejercieron sobre el gateway, con los selectores
manejados por un guion; no con una persona tocando la pantalla de la copia ni en
un teléfono. La compactación es una decisión del usuario y no corre sola; el
cambio a `auto_vacuum = INCREMENTAL` es persistente y no se deshace sin otro
`VACUUM`. `VACUUM` no es cancelable una vez empezado. La sonda de disco no
funciona en escritorio. El `.zip` armado por tandas se validó con `zipfile` de
Python; no se probó con otros descompresores. La pantalla del grafo completo
sigue cargando todos los elementos. Y las palabras de la bóveda sintética siguen
una distribución de Zipf: una bóveda real tiene otra, y por eso
`searchWindowFloor` no supone cuántos chunks hay entre coincidencias, los
cuenta.

### 46. F13 de jerarquía temática y Atlas: un vocabulario que se ordena en árbol, un índice que se genera solo y una consulta que se midió antes de creerla

Segunda fase del encargo F12–F17. Cambia el esquema (v21): un valor del
vocabulario puede colgar de otro, hasta cinco niveles, y sobre eso hay tres
cosas nuevas. Filtrar por un tema trae también lo de sus subtemas. El
vocabulario se ve y se reordena como un árbol. Y el Atlas —un destino de primer
nivel— muestra, para cada tema, cuántas fuentes y cuántas notas hay debajo,
hasta dónde llegó el trabajo, qué años cubre y qué le falta, generado solo desde
las propiedades y las notas. Son doce commits: los once del plan y uno que
apareció al medir.

**Dónde el encargo chocó con el código.** Se dijo antes de resolver, y el
usuario aprobó el plan con esas decisiones. Los nombres del vocabulario son
únicos POR CATEGORÍA (`UNIQUE (definition_id, value COLLATE NOCASE)`), no por
padre, y los alias, la resolución de etiquetas, la fusión de valores y la fusión
de bóvedas buscan por esa etiqueta: «Economía» bajo «Roma» y «Economía» bajo
«Grecia» no pueden convivir y se llaman «Economía romana» y «Economía griega».
Cambiar la unicidad tocaba cinco caminos; se mantuvo y se dijo. El vocabulario
tiene tres lectores además de su pantalla: el filtro de `LibraryQuerySql` —un
único lugar, así que la transitividad la heredan la Biblioteca, el Explorador,
la línea de tiempo y la salud—, las operaciones de F8 con deshacer, y la fusión
de bóvedas de F11, que escribe con SQL crudo y una lista de columnas explícita:
dos dispositivos pueden haber puesto A bajo B y B bajo A. Ocho destinos no caben
en una barra de celular. No hay un vínculo tema–nota aparte de las propiedades:
«notas mapa de una rama» son las que tienen un valor de esa rama o de sus
descendientes, y el eje temporal sale de «Fecha del hecho». Y la jerarquía solo
tiene sentido en categorías de texto.

**El esquema, y los ciclos en la base.** `property_values` gana `parent_id`
—clave a sí misma, `ON DELETE SET NULL`— y `depth` con un `CHECK` de 0 a 4
(cinco niveles). Cuatro triggers, y no solo la validación amable del
repositorio, porque la fusión de bóvedas escribe por debajo de él: dos rechazan
un ciclo, al insertar y al actualizar, y dos un padre de otra categoría o de una
que no es de texto. Un trigger de SQLite no admite `WITH`, así que el ciclo se
detecta con una cadena de `LEFT JOIN` de la profundidad máxima. La migración a
v21 lleva su respaldo previo y sus conteos como compuerta, y deja todo en la
raíz con `depth = 0`. `depth` se guarda y se recalcula en la misma transacción
que mueve una rama.

**Las operaciones de F8 respetan los subtemas.** Mover una rama tiene vista
previa —cuántos valores cambian de lugar— y deshacer, como fusionar y borrar.
Fusionar pasa los hijos del valor que desaparece al que queda; «borrar sin uso»
no borra un padre con hijos; deshacer un borrado reinserta de arriba abajo y
deshacer un movimiento suelta la rama entera antes de volver a colgarla —de a un
valor habría ciclos transitorios—. La fusión de bóvedas adopta el padre que trae
la otra copia solo si el valor local no tiene uno y no cierra un ciclo, no pasa
de cinco niveles, no cruza categorías y es de texto; si el valor ya tiene padre
acá, gana el local, porque el padre no se versiona por campo y no hay con qué
decidir cuál es más nuevo. Lo que no entra se cuenta en el resultado de la
fusión.

**El filtro transitivo y D3.** El filtro por un valor es una CTE recursiva sobre
`property_values` —los miles de valores, no los elementos—, dentro de
`LibraryQuerySql`. El plan pedía medirla contra un cierre materializado, una
fila por cada par (ascendiente, descendiente). Con la bóveda de 10.000 elementos
y 2.164 valores de «Tema» —la mayor rama, 303 valores y 4.934 elementos— las dos
tardan lo mismo: 16 y 15 ms en escritorio, 8 y 7 en el emulador. El cierre son
6.873 filas que se arman en 19 ms, y sería una tabla más que mantener en cada
movimiento, fusión, borrado, migración y fusión de bóvedas. Se quedó la CTE y el
cierre no se implementó. Asignar un hijo no asigna el padre: el padre lo ve
porque la consulta cuenta hacia abajo.

**El vocabulario, como árbol.** La pantalla de una categoría de texto tiene una
vista de árbol, plegada al arrancar, y se reordena de tres maneras para que
ninguna sea la única: el menú de la fila («Mover bajo…» con un buscador de SOLO
los destinos posibles, «Llevar al primer nivel»), arrastrar una fila sobre la
que va a ser su padre —o sobre una franja de arriba, al primer nivel— y el
teclado. Mover siempre pide confirmación y dice cuánto mueve, y el aviso trae
«Deshacer». Las tarjetas de candidatos a fusionar ganan una segunda salida:
«Roma» y «Roma republicana» pueden ser lo mismo o lo segundo un caso del
primero, y la tarjeta propone poner uno bajo el otro por palabras enteras
—«Arte» no es el padre de «Artesanía»—, el más específico si lo contienen
varios, sin ofrecer mover lo que alguien ya puso en otro lugar. El camino de
mover —vista previa, confirmación, aviso— es uno solo para el árbol y para la
tarjeta.

**El Atlas.** Un repositorio que cuenta, en cascada por la jerarquía, las
fuentes y las notas de cada rama —un elemento asignado a varios valores de la
misma rama cuenta una vez—, su estado de cobertura, el rango de años de «Fecha
del hecho», la última vez que se tocó algo de la rama, sus notas mapa —los
puntos de entrada— y los vacíos. La cobertura es el nivel más avanzado de la
rama entera: sin material, solo fuentes, fragmentos (notas sin ninguna viva), en
construcción, madura; se muestra como cuatro barras que se llenan, para que no
dependa del color, y con los conteos al lado, porque un estado alto puede
esconder un hueco. Los vacíos —un tema con cinco fuentes o más y ninguna nota
viva, una rama con un solo elemento, una rama que nadie tocó hace 183 días— se
avisan en la rama MÁS ALTA donde se cumplen, para no contar el mismo vacío en
cada descendiente. El resultado se guarda en memoria y se descarta con cualquier
escritura en las tablas que lee. La pantalla muestra una categoría a la vez, con
búsqueda, teclado y actualización sola, y cada rama, cada rango de años y cada
vacío llevan adonde se resuelve: el Explorador o la línea de tiempo, ya
filtrados por la rama, o la nota mapa. Se puede exportar como Markdown, con la
jerarquía, los conteos y las notas mapa como `[[enlaces]]`. La navegación
cambia: con ocho destinos, la barra del celular muestra cinco —Biblioteca,
Bandeja, Atlas, Grafo y Repaso— y un «Más» con el resto, y el riel de escritorio
los muestra todos.

**Medir encontró lo que ninguna prueba mostraba.** El Atlas del paso siete
pasaba sus pruebas y NO cumplía: con la bóveda de 10.000 elementos abría en 3,9
s, y el criterio es 500 ms. La consulta contaba parejas (rama, elemento) con un
`DISTINCT` sobre 60.000 pares de textos —210 ms— y una búsqueda por cada par
—300 ms—; ya con el conteo en Dart, cada fila que fabrica drift cuesta
(`QueryRow.read` unos 1,4 µs por columna), las notas mapa tardaban 205 ms porque
el plan empezaba por las 32.000 asignaciones de la categoría, y armar el árbol
tardaba 370 ms porque normalizaba el texto DENTRO del comparador de un `sort`.
Se corrigió de raíz, no se relajó el umbral: la cascada es una función pura que
sube desde cada valor de un elemento marcando lo visitado (13 ms), la base
entrega una fila por elemento con sus valores juntos, las notas mapa fijan el
orden con `CROSS JOIN` (196 a 10 ms) y las claves de orden se calculan una vez.
Con los 23 tests del repositorio escritos antes como red de seguridad: 191 ms en
escritorio, 124 en el emulador. La misma lección estaba en el primer plan de la
consulta, que recorría las asignaciones de todas las categorías hasta que el
`CROSS JOIN` fijó el orden: SQLite no sabe cuántas filas tiene una CTE. Y otra,
sobre la caché: el aviso de una escritura llega un instante DESPUÉS de que la
escritura termina, de modo que quien escribe y en seguida pide el Atlas veía el
de antes; `snapshot` cede un turno del bucle de eventos antes de mirar la caché.

Otras dos cosas salieron de medir. «Abrir el detalle de una nota con enlaces»
pasó de 16 a 101 ms sin que cambiara el código: el generador elegía la primera
nota que se escribía con enlaces y, con el sorteo nuevo, salió una de las que
más relaciones reciben —1.235—. Ahora es la de un elemento típico, y el peor
caso tiene su escenario (171 ms en escritorio, 77 en el emulador, sin objetivo).
Y `flutter drive -d windows` no corría: el arnés pedía
`getExternalStorageDirectory`, que solo existe en Android.

**Las cifras.** Modo profile, con 10.000 elementos, ~300.000 chunks y 2.164
valores de «Tema» (la bóveda sintética v5: la de F12 tenía 600 y sin jerarquía,
así que las de los escenarios que ya existían no son de la misma bóveda). El
emulador comparte la CPU y el disco de la PC, sus tiempos son optimistas y no
valen como los de un teléfono; la memoria sí vale. PC enchufada.

```
                                             escritorio   emulador   objetivo
filtrar por el tema raíz grande (4.934)         27 ms       15 ms     300 ms
filtrar por una hoja                             5 ms        3 ms     300 ms
los ids de todo el tema raíz grande             23 ms       16 ms
D3: CTE recursiva / cierre materializado    16 / 15 ms    8 / 7 ms
abrir el Atlas (2.164 ramas, 873 vacíos)       192 ms      124 ms     500 ms
  de ellos, leer de la base                    100 ms       73 ms
reabrirlo con la caché                           0 ms        0 ms
buscar un tema entre los 2.164                   4 ms        4 ms
exportar el Atlas (424 KB de Markdown)          31 ms       30 ms
búsqueda de texto, la más lenta                 59 ms       45 ms     300 ms
```

Migrar la bóveda de 683 MB de v20 a v21 en el emulador, con el respaldo previo
de 670 MB: 1,7 s (2,1 s la primera vez), con los 19 conteos iguales, ninguna
clave rota y el invariante de los chunks intacto sobre la bóveda entera;
después, la compactación de F12 —11 s, 273 MB de memoria residente máxima—. De
v17 a v21, los 909 MB del criterio, salió a 23,5 s, pero esa corrida fue a
BATERÍA: el cable se soltó entre una corrida y la siguiente sin que se notara, y
con la PC a batería los tiempos salen de 2 a 5 veces peores —la búsqueda de una
palabra rara pasó de 23 a 89 ms en la repetición de escritorio—. Las corridas
desenchufadas están aparte (`2026-09-21-f13-a-bateria`), con su explicación, y
no valen como referencia. Falta repetir esa migración enchufada; contra los 22,8
s de v17 a v20 enchufada en F12 no muestra un salto. Y el emulador, con 3,8 GB,
mató la aplicación una vez al empezar la compactación después de varias corridas
seguidas y 2,4 GB empujados por `adb`: memoria llena de caché de archivos y no
de la aplicación; reiniciado, la corrida terminó.

**Lo que F13 no hace, dicho sin adornos.** No hay cifras de un teléfono real:
las del emulador dependen de la PC que lo aloja, y la referencia de escritorio
se recuperó del registro de la corrida enchufada porque la carpeta que el guion
había llenado se sobrescribió con una repetición a batería. No versiona el padre
por campo ni resuelve conflictos de jerarquía entre copias: gana el local. No
permite el mismo nombre bajo dos padres de una categoría. El Atlas muestra una
categoría a la vez, y su caché se descarta con escrituras, no con el paso del
tiempo: un vacío «sin tocar hace 183 días» se reevalúa cuando algo cambia o al
reabrir la app, no a medianoche. Los umbrales de los vacíos son constantes, no
ajustes. La exportación es una foto. El grafo completo, que carga todos los
elementos, sigue igual: es de F14. Y la memoria que se mide al abrir el Atlas es
una cota —el montón ya viene calentado por los escenarios anteriores—, no el
costo de una primera apertura en frío.

### 47. F14 del mapa de conocimiento: un grafo de temas que se calcula aparte, tres vistas sobre él y lo que la medición encontró

Tercera fase del encargo F12–F17. No cambia el esquema de la base: todo lo nuevo
es derivado, se reconstruye y no es fuente de verdad. Reemplaza el «grafo
completo» por el Mapa, una pestaña con tres vistas —Tablero, Esquema y Grafo—
sobre los TEMAS: los valores de una categoría de texto, con la jerarquía de F13.
El mapa se calcula en otro isolate, se actualiza solo cuando algo cambia y
comparte motor, datos y filtros entre las tres vistas. Son quince commits: los
doce del plan —que ya cuenta el paso 5 en tres— y tres más: el paso 8 salió en
tres commits, y la medición del paso 9 pidió uno de arreglos antes de escribirse.
Cada commit compila y analiza por sí solo (`tool/verify_commit.ps1`); el analizador
quedó en 31 y la suite en 3.647 pruebas.

**Dónde el plan chocó con el código.** Se dijo antes de resolver, y el usuario
aprobó el plan con esas decisiones. El grafo completo de entonces pedía TODOS los
elementos y TODOS los vínculos y los acomodaba con un Fruchterman–Reingold
cuadrático en Dart: con 10.000 elementos no era una vista, era una espera; F14 lo
sustituye por vistas sobre temas con niveles de detalle, y el grafo de elementos
queda como el nivel de más zoom. «Incremental» no podía significar que el motor
supiera qué cambió: drift avisa por TABLA, no por fila. Lo que sí se puede
cumplir, y se cumplió, es recalcular por lotes, con arranque en caliente, con
identidades de comunidad estables y con la invalidación acotada a lo que el mapa
lee. Las notas mapa ya existían (`NoteKind.map`): son la entrada del esquema, no
un concepto nuevo. Y el tablero pide lo que ya existía en pedazos.

**El grafo de temas.** `buildTopicGraph` es puro: un nodo por valor de la
categoría —con su nombre sin acentos, su padre, su nivel y sus elementos
directos— y una unión entre dos temas si aparecen juntos en un elemento
(coocurrencia, peso 1) o si una relación une un elemento de uno con uno del otro
(peso 2); las contradicciones se cuentan aparte, pesan 3 y marcan la unión como
tensión, con las abiertas —las que nadie revisó— contadas aparte. Una relación
cuenta una vez por par de temas, y un elemento con más de 40 temas usa los
primeros 40 por orden alfabético para que el costo no crezca con el cuadrado. Se
cuenta en Dart sobre una fila por elemento y no con un agregado SQL como decía el
plan, porque en F13 el Atlas pasó de 3,9 s a 192 ms al hacer justo ese cambio;
con 10.000 elementos y 2.164 temas armar el grafo tarda 148 ms en el emulador. El
filtro es la `LibraryQuery` de la biblioteca —no hay un segundo motor de
filtros— y hereda la consulta transitiva de F13; respeta la papelera.

**Las comunidades.** Propagación de etiquetas ponderada, no Louvain: cada tema
adopta la etiqueta que más pesa entre sus vecinos. Es determinista, sin azar: los
temas se visitan en el orden de un hash de su valor con semilla fija —no de su
posición, que cambia cuando aparece un tema— y un empate lo gana la etiqueta que
el tema ya tiene. En caliente: con la memoria del cálculo anterior, indexada por
el valor, cada tema parte de su comunidad y solo se mueve lo que el cambio movió,
y las identidades de las comunidades que siguen existiendo se conservan —es lo que
hace que un color no salte al recalcular—; una comunidad que la propagación deja
partida se separa en sus componentes y la más grande conserva la identidad. Con
los temas con estructura del benchmark, una captura reasigna 0 temas de 2.164 y
una importación de 200 elementos también 0, y agrupar tarda 19 ms. **Una decisión
mía que no estaba en el plan:** un tema se pega a su padre de la jerarquía con
peso 1, lo mismo que un elemento compartido; sin eso una rama del vocabulario se
partiría en colores solo porque nadie asignó a la vez el padre y el hijo. No se
pudo verificar con datos reales que agrupe mejor —ver más abajo—.

**El motor.** `KnowledgeMapEngine` mantiene el mapa al día sin bloquear la
interfaz: espera 400 ms a que otro cambio reinicie la cuenta y, pasados 3 s desde
el primero, calcula igual; escucha solo lo que el mapa lee, así que repasar una
tarjeta no lo mueve; arma y agrupa en `Isolate.run`, y el isolate principal solo
lee de la base y entrega; guarda en caché los últimos cuatro mapas sin filtro,
validados por una cuenta de cambios, y descarta los filtrados al dejar de
mirarlos; y aísla el fallo —si algo falla, es un estado del mapa que conserva el
último bueno, sin bucle de reintentos—. Dos carreras que las pruebas encontraron
y se corrigieron en el motor: dos oyentes del mismo pedido pedían dos cálculos, y
volver a mirar un mapa fallado no lo reintentaba porque el motor lo daba por «al
día». Medido en el emulador: el primer mapa llega a los 247 ms de pedirlo y tras
una escritura a los 341, con 100 ms de espera —en la app la espera es de 400—.

**Los niveles de detalle.** El grafo nunca dibuja miles de nodos. Alejado, cada
comunidad es un nodo —hasta 60: los aislados van juntos en uno y las más chicas en
otro, sin perder ningún peso—; a distancia media, hasta 300 temas: la comunidad y
lo que la toca, no más saltos; de cerca, los 200 elementos más recientes de un
tema y de sus subtemas, con los vínculos entre ellos. El esquema dibuja a lo sumo
120 nodos y pide sus hijos a la base cuando el nodo se despliega, hasta 24 por
vez. Y desde la medición, en el nivel de temas cada tema conserva las cuatro
uniones más fuertes de las suyas, más todas las contradicciones, y el nivel avisa
cuántas dejó: entre trescientos temas hay miles de uniones —5.896 en el
benchmark— y dibujarlas no se lee ni se aguanta.

**Un defecto de fondo que las pruebas encontraron en el layout.** El «arranque en
caliente» no lo era: un layout de fuerzas ya calculado no está en equilibrio,
está congelado por el enfriamiento, y arrancar de él con una temperatura que le
permite moverse mandaba a los nodos entre 130 y 155 píxeles —casi la mitad de la
distancia ideal— en cada recálculo. Ahora cada nodo lleva su propia temperatura:
los que ya tenían lugar se mueven como mucho una décima de esa distancia, y los
nuevos nacen junto a sus vecinos. Y un conjunto de temas sin ninguna unión se
desparramaba por miles de píxeles porque la repulsión sin nada que atraiga no
tiene dónde parar: sin uniones y sin posiciones previas se acomoda en una
espiral compacta.

**Las tres vistas.** El Tablero tiene siete tarjetas: los temas con más
elementos, los pares más unidos —con un rayo en los que tienen una
contradicción—, los aislados, las contradicciones abiertas con sus títulos y un
botón a la pantalla de Tensión, el tamaño de la bóveda mes a mes y la madurez de
las notas. El Esquema parte del tema con más elementos, o de una nota mapa, y se
despliega nodo a nodo, en radial o en árbol, con cada vínculo rotulado con su
tipo y una punta hacia donde apunta. El Grafo tiene los tres niveles, un camino
de migas que lleva a cualquiera de los anteriores, y cambia de nivel al tocar o
al acercarse y alejarse. Los filtros —tipo de elemento, tema de la biblioteca,
etiqueta y texto— editan una `LibraryQuery` propia del mapa, así que filtrar el
mapa no cambia la lista de la biblioteca ni al revés, y rigen a las tres vistas.
Las etiquetas crecen por escalones al alejarse para seguir midiendo unos 11 px en
pantalla, y con mucho alejamiento se callan las de los temas chicos; las fuentes
y las notas se dibujan con la forma y el color de su rol (`EntityRole`) en
cualquier pantalla; entre vistas hay un fundido de 180 ms. El esquema y el grafo
se exportan como PNG o SVG sin dependencias nuevas: el SVG lo arma un escritor
mínimo con los mismos nodos, colores y uniones que se ven, y el PNG captura el
lienzo a doble resolución sin pasar de 4.096 píxeles por lado.

**El Mapa reemplaza al Grafo.** La pestaña «Grafo» de la barra pasa a llamarse
«Mapa» y abre esta pantalla; conserva el camino `/graph` porque de él cuelgan
Tensión y el grafo local de un elemento. El grafo completo se retira con lo que
solo él usaba. Antes de borrarlo, sus dos acciones se mudaron al Grafo del mapa:
agregar un vínculo entre dos elementos —el mismo flujo de tres pasos, en los tres
niveles— y pedirle a la IA que sugiera vínculos, acotado a los elementos del tema
que se mira, con el punto de partida elegido solo entre ellos. También el filtro
por tema de la biblioteca —lo que en la interfaz se llama «Tema» y en el código es
el espacio; los temas del mapa son las etiquetas de la categoría «Tema»—, que el
grafo viejo tenía y el mapa no. Lo que NO pasó al mapa: arrastrar los nodos a
mano; el selector de grado y los chips de «temas del grafo», que reemplazan los
niveles y las comunidades; colorear por tema de la biblioteca —ahora, por
comunidad, y las fuentes y notas por su rol—; las miniaturas dentro de los nodos;
los botones de acercar, alejar y encuadrar; el «Sin tema» del filtro, que
`LibraryQuery` no puede expresar; y —por construcción— los elementos sin tema: el
mapa se arma sobre temas, el grafo viejo mostraba cualquier elemento con algún
vínculo.

**Lo que la medición encontró.** Se midió en el emulador de Android, en modo
profile, con la PC enchufada, con 10.000 elementos y 2.000 temas
(`docs/benchmarks/`), y salieron tres cosas. La primera es del generador: la
bóveda sintética asigna los temas al azar, y su grafo es una maraña de 94.506
uniones entre 2.164 temas en UNA sola comunidad, con un panorama de un solo nodo.
Sirve como peor caso del coste de armarlo, pero medir comunidades y panorama con
eso no significaba nada: el benchmark del mapa usa además temas con estructura
—las mismas ramas, los elementos repartidos por áreas con puentes entre ellas—,
que dan 49 comunidades. La segunda es de dibujo: el nivel de temas costaba 47 a
54 ms de raster por cuadro en el escritorio. Se apagó cada parte para no
suponer: las uniones eran unos 32 ms; las etiquetas y los círculos, unos 7 cada
uno. Agrupar las uniones para dibujarlas con pocas llamadas ayudó poco (de 53,7 a
48,1 ms); lo que las bajó fue dibujar menos, y con el tope de cuatro por tema
quedó en 20,9 ms. La tercera es un defecto de gestos que ningún widget test había
visto: al soltar un gesto el grafo comparaba el zoom con el umbral de
alejamiento sin mirar si el gesto lo había tocado, y con 300 temas el encuadre
queda por debajo de ese umbral, así que arrastrar el mapa subía de nivel. Ahora un
gesto solo cambia de nivel si cambió el zoom, y acercarse a tres veces el
encuadre alcanza para bajar.

**Cifras del emulador** (`emulador-…/2026-09-21-f14/`). Lo que calcula, con 2.164
temas: armar el grafo 148 ms, comunidades en frío 19 ms, recalcular tras una
captura 158 ms, acomodar los 300 temas 69 ms en frío y 16 en caliente, y los 200
elementos 31 ms. Lo que tarda en verse: el tablero 1.019 ms, el esquema 784 ms, el
panorama 671 ms, los 300 temas 329 ms y los elementos de un tema 810 ms con la
lectura de la base. Cuadros de un gesto sostenido:

| gesto | armado p90 | raster p90 | fuera de presupuesto de raster |
|---|---|---|---|
| esquema, arrastre | 1,3 ms | 18,0 ms | 13,0 % |
| panorama, arrastre | 1,9 ms | 19,5 ms | 16,7 % |
| panorama, dos dedos | 0,9 ms | 24,1 ms | 42,9 % |
| temas (300 nodos), arrastre | 3,5 ms | 38,9 ms | 61,3 % |
| elementos, arrastre | 1,9 ms | 9,0 ms | 4,7 % |
| panorama, arrastre + recálculo de fondo | 2,1 ms | 18,5 ms | 15,4 % |

Memoria residente: 191 MB al empezar y 418 MB como máximo.

**El criterio de cierre, con lo que se cumple y lo que no.** Se cumple que las tres
vistas comparten motor, datos y filtros, que el agrupamiento es incremental y no
bloquea la interfaz —con diez recálculos en 18 s durante un arrastre, el raster no
empeora (p90 de 18,5 ms contra 19,5 sin recalcular)—, que se actualiza solo y que
el invariante de chunking sigue verde. **No se cumple «interacción fluida con 2.000
temas» en el emulador**: el armado no es nunca el problema —su p90 no pasa de 3,5
ms—, pero el raster pasa el presupuesto de un cuadro (16,6 ms) en todas las
vistas salvo en el nivel de elementos. El esquema y el panorama quedan cerca —18 y
19,5 ms—, algo por debajo de la línea de tiempo de F12 en el mismo emulador (23,1 ms
y 23 % de cuadros fuera); el zoom con dos dedos y el nivel de temas, peor. El nivel de
temas es el que más queda lejos: 300 nodos con sus etiquetas cuestan en cada
cuadro más de lo que un cuadro permite. F14 se cierra con esa excepción dicha,
porque arreglarla pide una decisión de quien aprobó el plan: dibujar menos temas a
la vez —el tope de 300 es una cifra aprobada; el costo crece con los nodos, así que
bajarlo a unos 120 lo llevaría cerca del presupuesto, como extrapolación y no como
medida— o guardar el nivel ya dibujado como imagen mientras dura un gesto, que es
rediseñar cómo se dibuja el grafo.

**Lo que F14 no hace, dicho sin adornos.** No hay cifras de un teléfono real: las
del emulador dependen de la PC que lo aloja, y sus tiempos son optimistas. La
referencia de escritorio tampoco es una cota de un teléfono: en esa máquina pintar
es caro. Las comunidades y el panorama se midieron con temas
estructurados por un generador cuyas áreas son las ramas de primer nivel —justo lo
que el peso que la jerarquía suma a las uniones favorece—: con esos datos no se
puede saber si ese peso agrupa mejor o peor con los temas de una bóveda real, y
sigue sin verificarse. Las sugerencias de vínculos con IA se probaron con el doble
del servicio, no con un modelo real en el dispositivo, y su tope de 30 candidatos
por pedido sigue como estaba. La exportación guarda el nivel que se mira, no los
tres juntos; el PNG toma los colores del tema en uso, y el SVG se comprobó por su
estructura y no se abrió en un visor externo. No se midió en pantallas de otro
tamaño ni con el tema oscuro. Y falta repetir enchufada la migración de v17 a v21,
que quedó de F13.

**Hallazgos que conviene tener a mano.** SQLite compara con `COLLATE NOCASE` solo
en ASCII —«Ágora» quedaba después de «Zama»—: los nombres se ordenan en Dart, por
su forma sin acentos, como todo el vocabulario. Un `Isolate.run` no termina bajo
el reloj simulado de las pruebas de widgets, y toda prueba que llegue a la
pestaña del Mapa necesita reemplazar el motor y el acomodo por versiones que
calculan en el mismo isolate (`mapInlineOverrides`). Una prueba de widgets que
llama a `onInteractionEnd` a mano no ve lo que hace un gesto de verdad: el defecto
del arrastre solo apareció con un nivel de 300 nodos en una pantalla real. Y medir
apagando cada parte antes de arreglar evitó optimizar lo que no era: agrupar
las uniones, que parecía lo obvio, casi no movió el costo.

### 48. F15 de biblioteca académica: metadatos completos, cinco estilos de cita, y BibTeX/RIS en los dos sentidos

Cuarta fase del encargo F12–F17. Cambia el esquema de forma aditiva (v21 → v22): `source_reference`
y `source_contributor`, tres columnas de persona en `property_values`, la categoría de sistema
«Autor» y `PropertyValueType.person`. F15 no toca el texto de ninguna fuente ni un chunk, no usa
modelos de lenguaje —todo es determinista— y no agrega dependencias. Son 29 commits: los 17 del plan
original, con el 5, el 10, el 11, el 12 y el 15 partidos en más de uno según hacía falta —el mismo
criterio que F9 a F14—. Cada commit compila y analiza por sí solo (`tool/verify_commit.ps1`); el
analizador quedó en 31 y la suite en 4.809 pruebas.

**Dónde el plan chocó con el código.** Se dijo antes de resolver, y el usuario aprobó el plan con esas
decisiones (D1 a D14). Extender `source` con quince columnas hubiera sido quince campos de linaje con
su regla de conflicto propia: `source_reference` y `source_contributor` cuentan como UN campo
(`reference`) en la fusión de F11, con su conflicto mostrado como la cita ya armada y no como un JSON
—D1, D3—. El nombre de una persona se guarda partido (`name_family`/`name_given`/`is_institution`),
pero terminó en CUATRO columnas y no en las tres que decía D2: se agregó `name_suffix` («Jr.», «III»)
porque BibTeX y RIS lo traen y perderlo hubiera sido un dato menos de lo que el archivo original tenía.
Una referencia sin texto necesitaba un `SourceKind` nuevo —D5—: nace «triada» (importar una
bibliografía es una decisión deliberada, no inunda la Bandeja) y, si se le adjunta el archivo, pasa a
`document` y sigue el camino de siempre. El motor de duplicados de F7 compara hash y simhash del
TEXTO, que una referencia no tiene: D9 es un motor de identidad nuevo (DOI/ISBN/URL, con índices) que
solo reusa de F7 la pantalla de duplicados y su fusión, para las coincidencias difusas.

**El escritor único y el modelo.** `KnowledgeEntryWriter.setReference` es el único camino para guardar
una referencia; `ReferenceReader` la lee por lotes, nunca por fuente. `PersonVocabulary.resolve` busca
al autor por su id, por su etiqueta «Apellido, Nombre» o por alias —sin distinguir mayúsculas ni
acentos, el mismo criterio que el resto del vocabulario— y si no existe lo crea con el nombre partido;
la asignación en `item_property_values` queda espejada con `ItemPropertyOrigin.reference` para que los
conteos, el Explorador y la línea de tiempo no tengan que conocer `source_contributor`. `PersonName`
sigue el algoritmo de nombres de BibTeX (apellido con su partícula, «von»/«de la», y sufijos «Jr.»);
DOI, ISBN (con dígito de control) e ISSN se normalizan y no son `UNIQUE` a propósito —dos dispositivos
pueden cargar la misma obra por separado sin que una fusión falle—.

**Los autores, como vocabulario.** Un valor de la categoría «Autor» se renombra, se fusiona con
deshacer y tiene candidatos por variantes de escritura, igual que cualquier otro valor; lo que un valor
no tenía —orden y rol (autor, traductor, editor, director)— lo agrega `source_contributor`. Fusionar
dos personas re-apunta las obras (`KnowledgeEntryWriter.repointContributors`/`restoreContributors`,
con su deshacer): nada fuera del escritor único toca esa tabla.

**El motor de citas.** Cinco estilos —APA 7, MLA 9, Chicago notas-bibliografía, Chicago autor-fecha e
IEEE— sobre una interfaz (`ReferenceStyle`) que devuelve CORRIDAS (texto plano, cursiva, hueco) y no un
`String`: el mismo resultado sale como texto, Markdown y `.docx` con cursivas y sangría francesa, y un
dato que falta se marca en pantalla en vez de inventarse. Los términos («y», «Ed.», «pp.», «s. f.»,
«En») son datos en español e inglés, no ARB: el dominio no conoce el idioma de la interfaz. La
bibliografía de un conjunto ordena alfabético por apellido sin acentos, con sufijos a/b/c para el mismo
autor y año en los estilos autor-fecha, e IEEE numera por el orden en que se muestra. `citeFragment`
cita un fragmento —de una nota atómica o de un resaltado— con su página o su minuto, resolviendo el
chunk por el offset.

**La extracción, como sugerencia.** PDF (Info y XMP propios, sin `pdfrx`), `<meta>` de una página
(`citation_*`, JSON-LD, Dublin Core, `og:`) y YouTube alimentan una sugerencia `metadata` por fuente,
que solo completa lo que la referencia no tenía —mismo criterio que reimportar un `.bib`—: nunca pisa
lo que alguien ya confirmó, incluido el título. El transformador de documentos deja de pisar el título
y el autor de una referencia que ya tiene algo confirmado.

**Importar y exportar, en los dos sentidos.** `parseBibtex`/`writeBibtex` y `parseRis`/`writeRis` se
probaron con ida y vuelta antes de cablearlos a la app —tres bugs reales atrapados así: el mes/día de
la fecha, la diéresis (un patrón que no podía llevar `'` y `"` juntas en la misma cadena cruda de
Dart) y `\'\i`—. La identidad al importar es DOI → ISBN → URL canónica → recién entonces una
coincidencia difusa (título + año + primer autor) que SIEMPRE propone, nunca fusiona sola: crea la
fuente primero y la propone como posible duplicado del existente, el mismo camino que cualquier otro
duplicado de la app, porque `createDuplicateSuggestion` exige dos elementos que ya existen. Los índices
de identidad y de coincidencia difusa se arman UNA vez por corrida, nunca una consulta por entrada. Un
PDF se vincula por el nombre que trae `file`/`L1`, entre los archivos elegidos junto con el `.bib`; la
promoción `reference` → `document` es un `save()` normal —`source_type` no es un campo versionado, no
hace falta un método nuevo del escritor—. Un `.bib`/`.ris` de más de 30 MB no se analiza: el árbol de
entradas en memoria pesa varias veces el texto. La pantalla «Importar referencias» y el botón de
exportar en lote —BibTeX o RIS, con la referencia ENTERA de cada fuente, no formateada en un estilo—
viven en el menú de la Biblioteca.

**Lo que la medición encontró.** El benchmark de referencias (capa aparte sobre una bóveda de 15.000
elementos, con su propia semilla) mostró un problema de fondo, no un ajuste de cifra: importar 5.000
entradas de un `.bib` tardaba 22 s en escritorio —más que el objetivo de 20 s para un TELÉFONO— porque
cada entrada abría al menos dos transacciones SQLite propias. Se agregó `LibraryRepository.
runInTransaction<T>` —mismo criterio que `deleteMany`/`restoreMany`/`assignSpaceMany`, «todos juntos o
ninguno», pero como primitiva para quien tiene lógica propia entre cada guardado— e
`ImportReferencesFileUseCase` corre el archivo entero en una sola transacción: bajó a ~20 s, una mejora
real, pero **no alcanza el objetivo propuesto ni de cerca**, porque el costo dominante no es el número
de transacciones sino el trabajo por entrada del escritor único —índice de texto completo, versionado,
tablas espejo—, el mismo que paga cualquier guardado normal de la app. Bajarlo de verdad exigiría
suspender esos triggers durante una importación masiva y rearmar el índice al final, como hace el
generador sintético con datos propios; sobre datos reales de un usuario es un rediseño del escritor
único, con más riesgo de dejar el índice inconsistente si algo falla a mitad de camino. **Se consultó
antes de decidir** (como en F12-F14 con lo que la medición pide): queda como límite conocido para una
fase futura, y el objetivo sube a la cifra real medida, con margen —90 s crear, 30 s reimportar—, no al
mínimo que alcanza.

**Cifras del emulador** (`Sinapsis_Bench`, 16 GB de disco —`Pixel_9_Pro` con 6 GB no alcanza para esta
bóveda—; `docs/benchmarks/emulador-…/2026-09-24-f15/`). Los diez escenarios pasan, todos con margen:

| escenario | medido | objetivo |
|---|---|---|
| detalle con referencia y cita | 0-2 ms | 200 ms |
| buscar por DOI / por ISBN | 0 ms | 10 ms |
| bibliografía APA de la rama mayor (~4.900 fuentes) | 432 ms | 3.000 ms |
| esa bibliografía a `.docx` | 187 ms | 4.000 ms |
| candidatos a fusionar entre 2.000 autores | 204 ms | 1.000 ms |
| exportar 10.000 a BibTeX / a RIS | 649 / 633 ms | 5.000 ms |
| importar 5.000 entradas (crear) | 4,9 s | 90 s |
| reimportar 5.000 (sin cambios) | 2,2 s | 30 s |

El emulador comparte la CPU de la PC que lo aloja y sale más rápido que el propio escritorio en el
import —cifras optimistas, rotuladas como tales—. Memoria residente de importar: 41-81 MB en
escritorio, 78 MB en el emulador. Que buscar por DOI/ISBN entre por su índice —`SEARCH source_reference`,
nunca un recorrido— se comprueba siempre, sin `--dart-define=BENCH=true`, en `query_plans_test.dart`.

**El criterio de cierre, con lo que se cumple y lo que no.** Se cumple: metadatos bibliográficos
completos y editables por fuente, con autores que se fusionan y renombran; cita en los cuatro estilos
—las dos variantes de Chicago—, copiable en un toque, con huecos marcados y no inventados; bibliografía
de un espacio, de una rama del Atlas, de una nota y de una selección, ordenada por estilo; BibTeX y RIS
entran y salen, reimportar no duplica, una entrada que no se entiende se reporta y se salta sin
guardarse a medias, y exportar y reimportar el mismo `.bib`/`.ris` devuelve lo mismo (prueba de ida y
vuelta, commits 13 y 14); invariante de chunking verde sobre la bóveda entera y los dos censos
cubriendo las tablas nuevas. **No se cumple sin reserva** el objetivo propuesto de importar 5.000
entradas en 20 s: la cifra real, con margen, quedó en 90 s —ver arriba—.

**Lo que F15 no hace, dicho sin adornos.** No es un motor CSL: son cinco variantes escritas a mano y
probadas contra los ejemplos de cada guía, no todos los tipos de obra ni todas las particularidades
—patentes, leyes, colecciones de una fuente primaria—; lo que no entra en los ocho tipos sale con la
plantilla genérica y sus huecos, y un `@patent`/`@software` de un `.bib` se reporta y se salta. No mide
en un teléfono real: solo hay emulador, y sus tiempos son optimistas. No convierte de golpe las fuentes
que ya existen: su `authorName` sigue siendo texto hasta que alguien completa la referencia. Importar
miles de entradas de un `.bib` paga el mismo costo por entrada que cualquier guardado normal de la
app —ver arriba—: no hay un camino rápido para un lote grande. Un `.bib`/`.ris` de más de 30 MB no se
analiza en absoluto, ni siquiera parcialmente.

**Hallazgos que conviene tener a mano.** `mergeExtractedMetadata` (de F11c) no sirve para fusionar al
reimportar: su `ReferenceData` de salida omite `edition`/`accessedAt`/`citationKey`/
`publicationPrecision` —campos que `ExtractedMetadata` nunca tiene pero un `.bib`/`.ris` sí—, y
reusarlo hubiera borrado esos cuatro campos en cada reimportación; se escribió `mergeReferenceOnImport`
aparte. Encolar el procesamiento tras adjuntar un PDF es de la capa de presentación, no del caso de
uso de dominio —mismo precedente que `CaptureNotifier`—. El campo `file` de BibTeX puede traer una
unidad de Windows (`C:\...`) dentro de un valor que ya usa `:` como separador: se resuelve buscando la
porción que TERMINA en una extensión de documento conocida, no parseando la convención de JabRef a
mano. Un benchmark que ESCRIBE no puede compartir la base cacheada de los que solo leen: dejaba miles
de fuentes de más para la corrida siguiente —corre sobre una copia (`VACUUM INTO`), mismo criterio que
`vault_merge_benchmark.dart`—.

### 49. F16 de cuadernos, consulta enfocada y vistas: un subconjunto con nombre, cuatro derivados anclados a su fuente, y vistas y plantillas guardadas

Quinta fase del encargo F12–F17. Cambia el esquema de forma aditiva, en cuatro pasos (v22 → v26):
`saved_view`/`note_template` (v23), `notebook`/`notebook_item` (v24), `conversations.notebook_id`
(v25), y `generated_by_model`/`generated_at`/`derived_edited` en `note` (v26). F16 no toca el texto de
ninguna fuente ni un chunk: un derivado nace SIEMPRE como una nota nueva, nunca una edición de lo que
ya existe. Son 17 commits: los 14 del plan original, con el 12 partido en tres (12a/b/c) y el 13 en dos
(13a/b) según hacía falta —el mismo criterio que F9 a F15—. Cada commit compila y analiza por sí solo
(`tool/verify_commit.ps1`); el analizador quedó en 31 y la suite en 4.954 pruebas.

**Orden interno, al revés del que nombra el encargo (D8).** El plan hizo vistas y plantillas primero
(16.3), cuadernos después (16.1) y derivados al final (16.2): 16.3 es la pieza más autocontenida y de
menor riesgo, 16.1 reusa directamente su mecanismo de «consulta guardada» (un cuaderno «por consulta» y
una vista guardada son el mismo dato, `LibraryQuery` con nombre, aplicado a dos pantallas distintas), y
16.2 es lo más nuevo —cambios al chat, esquema de notas, generación con IA que hay que anclar bien—, así
que convenía dejarlo para cuando lo demás ya estuviera probado. El encargo solo exige que F15 y F16 sean
independientes entre sí, no fija un orden interno.

**Un cuaderno, y por qué no es `Space`.** `Notebook` —manual (`notebook_item`, pertenencia por
referencia, mismo criterio que `item_property_values`) o por consulta (una `LibraryQuery` con nombre,
resuelta en el momento)— acota el chat a un subconjunto sin exigir que cada elemento viva en un solo
lugar, a diferencia de `Space`. `NotebookRepository.resolveQuery` unifica los dos modos en una sola
`LibraryQuery`, así que quien consume un cuaderno —el chat, un derivado— no necesita saber en qué modo
está. Sirve como buscador acotado incluso SIN el modelo de lenguaje descargado: acotar es solo FTS5,
generar es lo único que de verdad necesita el modelo.

**El chat resuelve el chunk real, no un recorte de 400 caracteres.** `ChatSource` gana
`sourceCharStart`/`sourceCharEnd` —las mismas coordenadas que `Relations`/`Chunks`—, replicando en Dart,
sobre lo que `LibraryRepository` ya trajo cargado, la regla de F10 (texto principal, o el más viejo si
ninguno es principal): sin consulta nueva, sin dependencia nueva. Un elemento sin forma que se
fragmente —una nota manual, o algo sin procesar— sigue mostrando su fragmento como siempre, con offset
`null`: sin nada a lo que anclar una cita, no sin cita.

**`DerivedNoteGenerator`, un generador único para los cuatro tipos (D5).** Guía de estudio, preguntas
abiertas, esquema y cronología comparten una sola interfaz, parametrizada por un enum, con una plantilla
de instrucción por tipo y el mismo formato de respuesta —mismo patrón que `FlashcardGenerator`—. Cada
afirmación se ancla buscando la cita del modelo, TEXTUAL, dentro del `excerpt` de la fuente y corriendo
el rango por su `sourceCharStart` (D6): lo que no se pueda anclar así no se escribe en el derivado —
«mejor ninguno que uno equivocado», el mismo criterio que una tarjeta de F11 sin cita verificable, un
paso más estricto—. Cada fuente ancla como mucho UNA afirmación por derivado: `RelationKind.
extractedFrom` tiene `UNIQUE(from_item_id, to_item_id, kind)`, así que una segunda afirmación sobre la
misma fuente no tendría dónde guardar su propio rango; se descarta, no se junta con la primera. Es una
limitación real y deliberada, no un defecto: un derivado que sale de UN SOLO elemento nunca puede tener
más de una afirmación anclada.

**Generar, guardar y marcar, todo o nada.** `GenerateDerivedNoteUseCase` resuelve las fuentes —todo lo
que resuelve un cuaderno, o un único elemento—, genera el borrador, arma el contenido como bloques
(un encabezado por sección, un ítem por afirmación) y guarda la nota, su marca
(`generated_by_model`/`generated_at`, escrita una sola vez, nunca versionada: no hay ninguna pantalla
donde el usuario la elija a mano) y una relación `extractedFrom` por afirmación, dentro de una sola
transacción. Sin fuentes o sin nada anclado, no se crea nada. Editar el contenido de un derivado lo
marca `derived_edited` la primera vez —«pasa a ser suyo»—, sin fecha ni historial propios:
`field_versions` ya anota cuándo se tocó el contenido. La insignia «Generado por IA» —con el modelo y
la fecha en el tooltip— vive en el mismo lugar que la madurez de una nota; el botón de generar, en el
cuaderno y en cualquier elemento, con el mismo aviso de «modelo requerido» que ya usa resumir.

**Vistas guardadas y plantillas.** Una vista guarda `LibraryQuery` —filtro y orden, no `ids` ni
`limit`/`offset`: eso es de la sesión o de la página, no del filtro que se nombra y guarda—, con su modo
de vista y si está fijada en la navegación. Una plantilla de nota precarga bloques y propiedades; una
propiedad de plantilla se guarda por categoría y etiqueta, no por el id del valor, así que aplicarla
sigue el mismo camino que escribirla a mano —crea el valor si hace falta, sin referencia colgando si el
original se borra o se fusiona—. La vista de calendario agrupa por Fecha del hecho (por defecto) o por
fecha de captura, reusando `LibraryQuery` tal cual.

**Dos censos de fusión que una columna nueva puede dejar atrás.** `lib/features/vault/data/merge/`
tiene DOS mecanismos de fusión con su propio censo de columnas —`SetUnionMerge.kConversationColumns`
(conflicto por conflicto) y `EntryMergeApplier.kNoteColumns` (copia entera de un elemento nuevo)—, y
NINGUNO de los dos lo agarra `flutter test` de área, solo la suite completa. Dos columnas nuevas de esta
fase cayeron en ese hueco y se corrigieron en el mismo commit que las agregó: `notebook_id` en
`conversations` (v25, degrada a `null` si el cuaderno no existe del lado que recibe —los cuadernos son
de un dispositivo, no viajan en la fusión—) y las tres columnas de la marca de generado en `note` (v26,
viajan enteras: la marca es del elemento mismo). Queda como lección permanente: ante cualquier columna
nueva, `grep` en esa carpeta por una columna hermana de la misma tabla antes de dar el commit por
cerrado.

**Lo que la medición encontró.** El benchmark de la bóveda sintética sumó tres escenarios —un cuaderno
manual de 500 elementos, el tamaño que propone el propio plan— que miden lo que hace el chat de verdad
por cada pregunta: resolver el alcance del cuaderno de nuevo —no se cachea entre preguntas— y buscar
dentro de él. La primera corrida mostró 126–186 ms, sobre el umbral de escritorio: `_resolveScopeIds`
armaba cada uno de los 500 elementos ENTERO —renditions, etiquetas, propiedades— solo para sacarle el
id. Se cambió a `LibraryRepository.matchingIds`, la misma consulta que `list()` ya hace por dentro, sin
ese segundo paso —un `perf(...)` aparte, antes del commit que mide, mismo criterio que F13 y F14—.

**Cifras del emulador** (AVD `Pixel_9_Pro`, Google sdk_gphone16k_x86_64, Android 17, PC enchufada;
`docs/benchmarks/emulador-…/2026-09-24-f16/`):

| escenario | medido (mediana) | objetivo |
|---|---|---|
| cuaderno de 500: palabra rara | 23 ms | 300 ms |
| cuaderno de 500: palabra mediana | 54 ms | 300 ms |
| cuaderno de 500: dos palabras | 101 ms | 300 ms |

Los otros 25 escenarios del mismo archivo —búsqueda sin acotar, detalle, grafo local, línea de tiempo,
salud, filtro jerárquico, Atlas, vocabulario— siguen verdes, sin cambios propios de esta fase.

**El criterio de cierre (16.4 del encargo), con lo que se cumple.** El chat se acota a un cuaderno y
cita solo dentro de él, con o sin modelo descargado. Los derivados cumplen las cuatro condiciones de la
sección 1 del encargo: nacen como un elemento nuevo, marcados con el modelo y la fecha, cada afirmación
citada a su chunk real, y ninguna pantalla muestra un derivado en lugar del texto original —una nota
generada se ve, se edita y se cita exactamente como cualquier otra, solo con su insignia de más—. Vistas
guardadas y plantillas funcionan de punta a punta. El invariante de chunking sigue en verde sobre la
bóveda entera: F16 nunca tocó un chunk ni el texto de una fuente.

**Lo que F16 no hace, dicho sin adornos.** No sincroniza con el NotebookLM real de Google —comparten
nombre por la función, no el producto—. Un derivado no ancla una afirmación a más de un chunk, y un
derivado de un solo elemento nunca puede tener más de una afirmación anclada —ver arriba—. La
generación no funciona sin el modelo descargado, a diferencia de un cuaderno, que sí sirve como buscador
acotado sin él. No hay comentarios ni nada multiusuario en un cuaderno: la bóveda sigue siendo de un
dispositivo. Las plantillas no son un motor de bloques nuevo: predefinen una estructura con los bloques
que ya existen. No convierte de golpe las notas que ya existen en «generadas»: la marca solo la llevan
las que nazcan desde un derivado de acá en adelante. No mide en un teléfono real: solo hay emulador, y
sus tiempos son optimistas.

### 50. F17 de Anki y hábito: exportar completo a Anki —subdecks, procedencia, incremental, TSV/CSV— y una racha, insignias e historial que premian destilar y consolidar, nunca capturar

Sexta y última fase del encargo F12–F17. Cambia el esquema de forma aditiva, en dos pasos
(v26 → v28): `last_exported_at` nulo en `flashcards` (v27) y `habit_event` (v28). F17 no toca el
texto de ninguna fuente ni un chunk: el invariante de chunking siguió en verde en cada corrida de
la suite completa, de principio a fin. Son quince commits reales sobre los doce del plan original:
el 7 (cálculo de racha) se partió en tres (7a/b/c), el 9 (insignias) y el 10 (historial de
repasos) en dos cada uno (9a/b, 10a/b) —mismo criterio de partir que F9 a F16 ya usaron cuando el
trabajo real resultaba más grande que un commit—; el 6 (prueba real en Anki) queda BLOQUEADO, sin
cerrar. Cada commit compila y analiza por sí solo (`tool/verify_commit.ps1`); el analizador quedó
en 31 y la suite en 5.135 pruebas.

**Bloque A (17.1), completando lo que ya existía.** `AnkiPackageBuilder` ya armaba un `.apkg`
clásico desde antes de F17 (esquema legacy, `guid = card.id`, SM-2 mapeado); F17 sumó lo que
faltaba: subdecks por la jerarquía de Temas del Atlas (`ankiDeckPathOf`, puro, recorre
`VocabularyTree.ancestorsOf` con el mismo patrón que `atlas_builder.dart`; una tarjeta con varios
temas va al subdeck de su PRIMER tema asignado, D1, para no inflar «cien tarjetas repasadas»
contando la misma tarjeta varias veces), procedencia en el reverso (el caso de uso resuelve la
cita ANTES de llamar al builder, con `BibliographyRepository.sourcesOf` por lotes en vez de la
`citationSourceOf` que nombraba el plan —mismo motivo que ya corrigió 13a en F15: una consulta por
elemento sale cara cuando son muchos—), exportación incremental (`last_exported_at`, incremental
por defecto con «exportar todo» como interruptor aparte, D4) y un exportador TSV/CSV como camino
alternativo (D5, encabezados de Anki 2.1.54+ verificados por búsqueda web antes de escribir
código, no adivinados).

**Commit 6, bloqueado, no cerrado.** La prueba real en Anki y AnkiDroid —reimportar actualiza,
ver los subdecks, ver la procedencia— exige ojos humanos sobre una instalación real. Ni Anki de
escritorio ni AnkiDroid están instalados en esta máquina, e instalar software no pedido no es una
decisión que tomar sola. Reportado y dejado abierto, tal como el propio plan ya anticipaba («si no
está disponible, F17 avanza hasta el paso 5 y NO se declara cerrada» —en la práctica avanzó mucho
más, hasta el 12, porque el resto del plan no depende de esto—). Pendiente real: instalar Anki o
AnkiDroid y verificar a mano, o aceptar F17 sin el criterio 17.3 cumplido del todo.

**Bloque B (17.2), racha, insignias e historial.** La racha (D6) junta cuatro orígenes en
`calculateStreak` (puro, gracia deslizante de 2 días por semana por defecto): `review_log`
(repasar), `field_versions` de una nota viva (editarla), `item.created_at` de una nota atómica
(extraerla) y una tabla nueva, `habit_event` —triar la Bandeja y resolver Vocabulario no tenían
ningún rastro con fecha donde leer eso, a diferencia de los otros tres—. Las insignias (D7): de
las seis, «una contradicción resuelta» resultó tener solución YA EXISTENTE en la columna
`reviewed_at` de `relations` (F9, la pantalla de Tensión) —no hizo falta inventar nada—, y «un
tema completo de punta a punta» —la única cara— se resolvió con un recorrido bottom-up en Dart sobre
`VocabularyTree`, no una consulta SQL por rama. El historial de repasos (D8): `ReviewHistoryRepository`
junta retención semanal, calendario de constancia y tarjetas difíciles en una sola lectura;
tarjetas difíciles usa SQL escrito a mano —mismo criterio que `atlas_query_sql.dart`— porque un
`GROUP BY`/`HAVING`/`ORDER BY` sobre una proporción calculada no tiene forma limpia en el
constructor tipado de drift. El interruptor único (D9): `SharedPreferences`, sin ningún estado de
pausa que mantener —`review_log`/`habit_event` siguen registrando lo de siempre pase lo que pase
con el interruptor; apagarlo solo deja de MOSTRAR racha, insignias e historial, nunca de
registrar—, así que encenderlo de nuevo no «reconstruye» nada: no hay nada guardado aparte que
reconstruir.

**Un tercer censo de columnas, el mismo hallazgo que ya dejó F11.** El paso de v18 para una base
MUY vieja (`repoint_item_references_v18.dart`) reconstruye `flashcards` con la definición de HOY
de la tabla: una base que pasa por v18 en la misma actualización ya trae `last_exported_at` antes
de llegar al paso v27, y migrar así tiraba «duplicate column name» sin el mismo `_columnExists`
guard que ya protegía las tres columnas de F11 en el paso v20.

**Lo que la medición no hizo, dicho sin adornos.** El plan proponía objetivos de rendimiento
—exportar 1.000 tarjetas nuevas < 5 s, reexportar de forma incremental < 1 s, calcular la racha y
las insignias al abrir la app < 100 ms, abrir el historial con 10.000 filas en `review_log` <
300 ms—, pero el propio plan, ya aprobado, no incluía un paso de medición en Android para 17.2 (el
único paso de medición del plan es el 6, bloqueado, y es una verificación humana, no una cifra).
Sin banco de pruebas dedicado ni cifras de emulador para F17: queda para una fase futura, mismo
criterio que F14 dejó el criterio de fluidez del mapa sin resolver y F15 dejó el límite de
importar un lote grande.

**El criterio de cierre (17.3, del encargo), con lo que se cumple y lo que no.** Cumplidos: la
procedencia viaja en la tarjeta; la racha no cuenta capturas —D6 solo cuenta repasar, editar una
nota viva, extraer una nota atómica, triar la Bandeja y resolver Vocabulario—; la gamificación es
desactivable por completo (D9); el invariante de chunking siguió en verde sobre la bóveda entera
en cada corrida. Sin cumplir, los dos que dependen de Anki real: que un `.apkg` exportado importe
limpio en AnkiDroid y en Anki de escritorio, y que reimportar actualice en vez de duplicar
verificado a mano —los dos caen en el mismo bloqueo del commit 6—.

**Lo que F17 no hace, dicho sin adornos.** No sincroniza en vivo con Anki (entra y sale por
archivo, como BibTeX/RIS en F15). No compara ni compite con otros usuarios, ni publica nada. Los
subdecks no migran solos si la jerarquía de Temas cambia después de exportar. No manda
notificaciones del sistema operativo (D3: un indicador dentro de la app alcanza). No inventa una
insignia por volumen puro: las seis están ligadas a destilar, consolidar o repasar, nunca a
capturar. No mide en Android —ni emulador ni teléfono— ninguno de los cuatro objetivos de
rendimiento que el propio plan proponía. No verificó a mano en Anki ni AnkiDroid reales —commit 6,
BLOQUEADO—.

Con esto se cierra el encargo F12–F17 entero.

### 51. F18 del Mapa de conocimiento: medir antes de rediseñar —la distribución realista y el caché de rasterizado durante el gesto

Primera fase del encargo F18–F20 (`docs/planes/F18-mapa-medir-antes-de-redisenar.md`), que cierra
dos puntos abiertos al final de F12–F17 y agrega una función. No cambia el esquema ni toca el texto
de ninguna fuente. Cuatro commits: dos de medición (18.1), uno de rediseño (18.2) y este de cierre.

**El hallazgo que cambió la premisa del propio encargo.** F14 cerró con el nivel de temas del Mapa
fuera del presupuesto de un cuadro (16,6 ms de p90, menos del 5 % de cuadros fuera) con 2.000 temas
sintéticos, y quedó pendiente decidir entre bajar el tope de 300 temas visibles o cachear el nivel
durante el gesto —la segunda, ya decidida al aprobar este plan—. Antes de tocar el renderer, 18.1
investigó si el caso que fallaba era artificial. No lo era del todo: las cifras que fallaron ya
salían de `structuredTopicInput` (F14), un generador con jerarquía real y ley de potencias, no de
una asignación al azar —pero agrupaba por RAMA DE PRIMER NIVEL entera («Historia» completa), no por
una sub-rama más angosta («Historia › Roma»), que es lo que un usuario navega de verdad—. Medido en
el emulador dos veces, agrupar por sub-rama (`areaDepth: 2`, nuevo parámetro del generador) bajó el
p90 de raster de 18,4–28,4 ms a 15,8–15,9 ms —ya dentro del presupuesto— y los cuadros fuera de
presupuesto de ~32 % a ~10 %, con el mismo número de nodos visibles (300, el tope, sin cambios) en
los dos casos. No alcanzaba para cerrar el criterio solo: cayó en el segundo de los tres desenlaces
que el plan había previsto, «entra justo o queda cerca del límite → hacé 18.2 igual».

**18.2, el caché de rasterizado durante el gesto.** Al empezar un arrastre o un zoom,
`MapGraphView` captura el nivel ya dibujado (`RenderRepaintBoundary.toImage`, con el mismo tope de
tamaño que ya usaba la exportación a PNG de F14) y pinta esa imagen en vez de recorrer el `Stack` de
hasta 300 nodos y el `CustomPaint` de sus uniones: `InteractiveViewer` sigue transformando esa
imagen igual que transformaría el dibujo vectorial, así que mover un bitmap reemplaza recorrer el
grafo entero en cada cuadro. Al soltar, vuelve el dibujo vectorial de siempre, idéntico —la imagen
es una captura exacta de esa misma caja—; si el zoom se aleja más del doble desde la última
captura, recaptura una vez a mitad de gesto para que no se vea borroso. **Bug real encontrado y
corregido antes de cerrar el commit** (no por un test ajeno, por cuatro que ya existían y que
simulan un gesto entero de una sola vez): si el gesto termina antes de que la captura asíncrona
resuelva, la imagen vieja podía quedar pegada en pantalla para siempre; corregido con una bandera
de «gesto en curso» que descarta sin mostrar una captura que ya no le corresponde a nada.

**El resultado, medido limpio** (con la suite de escritorio ya terminada: medirlo con las dos cosas
corriendo a la vez contaminó una primera corrida —mismo problema de contención de CPU del host que
ya se conocía al revés, descartada—). Mejora sustancial y consistente en los siete escenarios de
pantalla: el esquema pasa del todo (1,2 % de cuadros fuera de presupuesto, antes 32,1 %); el zoom
con dos dedos baja de 36–43 % a 6,5 %; el nivel de temas por rama entera baja de ~32 % a 18,1 %; por
sub-rama, de 9,8 % a 7,1 %, con el p90 ya bajo presupuesto (14,7 ms); el recálculo de fondo baja de
~15–20 % a 6,9 %. **No todos los escenarios entran todavía bajo el 5 % estricto** —quedan cerca,
entre 6,5 % y 8 % la mayoría, salvo el nivel de temas por rama entera (18,1 %)—: es una mejora real
y medida, con la causa de raíz atacada de frente, pero no un cierre completo del criterio de F14
para cada escenario. Cifras en `docs/benchmarks/emulador-…/2026-09-25-f18-caching-clean/`.

**El criterio de cierre (18.3, del encargo), con lo que se cumple y lo que no.** Cumplidos: hay
cifras del nivel de temas con distribución realista y se sabe cuántos temas visibles simultáneos es
el caso plausible (300, el tope, sin cambios); el escenario de 2.000 sigue etiquetado como el peor
caso, no el esperado; el tope de temas visibles NO se bajó; el dibujo tras soltar el gesto es
idéntico al vectorial de siempre (verificado por test); invariante de chunking verde —F18 no tocó
ningún chunk—. Sin cumplir del todo: el p90 del nivel de temas entra por sub-rama pero no por rama
entera, y el 5 % de cuadros fuera de presupuesto no se alcanza en la mayoría de los escenarios,
aunque quedaron mucho más cerca. **Decisión propia, señalada, no en silencio:** no se construyeron
los cuatro escenarios de estrés (400/800/1.200/2.000 fuera del tope real) que proponía la decisión
B del plan —el tope real de 300 no cambia con esta fase, y tanto la necesidad de 18.2 como su
alcance ya quedaron confirmados sin ellos—; quedan como pieza opcional si algún día se revisita el
tope de 300.

**Lo que F18 no hace, dicho sin adornos.** No baja el tope de 300 temas visibles. No lleva ningún
escenario del Mapa a cumplir el 5 % estricto en la sub-rama ni en el zoom, aunque los acerca mucho.
No mide en un teléfono real —sigue siendo emulador, como todo este encargo y el anterior—. No
construye los escenarios de estrés de la decisión B, por la razón ya dicha.

### 52. F19 de modo lote transaccional: suspender el índice de texto acotado a lo tocado, no la bóveda entera

Segunda fase del encargo F18–F20 (`docs/planes/F19-modo-lote.md`), que cierra el límite que dejó
F15: importar miles de referencias, o traer una copia entera con `mergeBackup`, pagaba el mismo
costo por fila que cualquier guardado normal —el índice de texto completo, el versionado por
campo— en vez de uno acotado al lote. No cambia el esquema ni toca el texto de ninguna fuente.

**La utilidad de bajo nivel, genérica a propósito (decisión A).**
`withSuspendedSearchIndexes` (`lib/core/database/bulk_write_scope.dart`) suspende los triggers
reales de `item_search`/`chunk_search` mientras dura un lote, y los repuebla al cerrar —incluso si
el lote falla, antes de propagar el error—. No está atada al escritor único: la usan tanto
`KnowledgeEntryWriter.runBulk` (decisión B) como `VaultMerger` alrededor de `DerivedRebuild.apply()`
(decisión D), que no pasa por el escritor único y por eso no podría usar `runBulk`.
`KnowledgeEntryWriter` gana un modo lote interno: mientras dura, no escribe cada `field_version` al
toque —guarda el último valor por (elemento, campo) en memoria y lo vuelca una vez por campo al
cerrar—.

**La regresión real que la propia medición encontró y corrigió, no una que se hubiera anticipado.**
La primera versión de `withSuspendedSearchIndexes` rehacía `item_search`/`chunk_search` ENTEROS al
cerrar cualquier lote —el mismo camino que ya usaba una migración—, un costo proporcional al tamaño
de TODA la bóveda, no al del lote. Medido contra la bóveda sintética de referencias (15.000
elementos): importar 5.000 con esa primera versión tardó 64 s, PEOR que los ~20 s de antes de F19.
Corregido con dos parámetros nuevos en la utilidad: `touchedItemIds` (una función, llamada después
del lote, con los ids que cambiaron) repuebla `item_search` acotado a esas filas en vez de la tabla
entera —`KnowledgeEntryWriter.runBulk` ya tiene esos ids gratis, son las claves de su
`field_version` diferido—; y `chunks` (`true` por defecto) decide si se suspende `chunk_search` —el
escritor único lo pone en `false`, porque nunca escribe chunks, y suspenderlo para no usarlo solo
pagaría el `rebuild` completo de FTS5 sobre cientos de miles de filas sin ninguna razón—.
`VaultMerger` sigue con el `chunk_search` sin acotar —ahí SÍ hace falta rehacerlo, es donde está el
costo real que midió F15— y con la tabla `item_search` acotada, aprovechando que `MergeWork.
touchedItems` ya estaba disponible sin costo extra.

**Medido antes y después, máquina enchufada y sin ruido, con la corrección puesta.**
`ImportReferencesFileUseCase` migrado de `runInTransaction` a un `LibraryRepository.runBulk` nuevo
—que convive con `runInTransaction`, que sigue sirviendo para guardar UN elemento, donde suspender
el índice entero costaría más de lo que ahorra—: importar 5.000 referencias, 21,7 s en escritorio
—a la par de los ~20 s de antes de F19, dentro del margen normal entre corridas— y 4,5 s en el
emulador, muy por debajo del objetivo de 90 s. `VaultMerger.merge` envuelve `DerivedRebuild.apply()`
con la misma utilidad: fusionar una variante de 250 elementos sobre una bóveda ya de 10.000 bajó de
19,8 s a 16,2 s, refusionar lo mismo de 11,0 s a 8,4 s, y traer la copia entera a una bóveda vacía
—el escenario de la decisión 45— de 68,2 s a 59,7 s. Mejora real en los cuatro números medidos, con
`verifyChunkInvariant` y los conteos por tabla en verde. El beneficio de F19 en el caso de
importación no es bajar un número que ya estaba lejos del techo —el objetivo original de F15 ya era
20 s—, sino corregir la regresión propia y dejar lista la misma utilidad para `mergeBackup`, donde
sí se nota.

**Dos puntos del plan, salteados y señalados, no en silencio, por la misma razón: investigados
antes de construir nada, ninguno tiene hoy un llamador real que se beneficie.** La decisión C
—diferir y disparar una sola vez las cuatro generadoras de sugerencias/embeddings— no aplica a
ninguna operación de este plan: `ImportReferencesFileUseCase` crea fuentes de referencia, y el
único gancho de sugerencias que dispara `LibraryRepositoryImpl.save` actúa solo sobre notas;
`mergeBackup` ya no las dispara, por diseño, desde F16. El commit 6 —sugerencias en lote y
reconstrucción de chunks tras fusionar duplicados— tampoco: `SuggestionRepositoryImpl.acceptMany`
escribe únicamente en `item_property_values`, que ningún trigger de `item_search`/`chunk_search`
mira; y `MergeDuplicateItemsUseCaseImpl` fusiona UN par de elementos por llamada, sin ningún
llamador que lo invoque en lote sobre muchos pares a la vez. Los dos quedan documentados acá para
si algún día un llamador real los necesita —no se descartan, se posponen hasta que haga falta—.

**Lo que F19 no hace, dicho sin adornos.** No toca la aceptación de sugerencias en lote ni la
fusión de duplicados —investigado, no hace falta hoy—. No difiere las cuatro generadoras de
sugerencias/embeddings —mismo motivo—. No mide `mergeBackup` en el emulador —el plan no lo pedía
para este commit, a diferencia de la importación de referencias—.

### 53. F20 de quizzes generados y anclados: opción múltiple con distractores reales, nunca inventados

Tercera y última fase del encargo F18–F20 (`docs/planes/F20-quizzes-generados.md`), que agrega una
función nueva: preguntas de opción múltiple generadas por el modelo, cada opción —la correcta y las
incorrectas— anclada a un fragmento real de la bóveda, nunca inventada, integradas a la programación
espaciada SM-2. Nueve commits reales.

**Esquema aditivo, en dos pasos (decisión B).** `flashcards` gana `kind` (`FlashcardKind`:
`freeRecall`/`multipleChoice`/`trueFalse`, `freeRecall` por defecto para toda tarjeta que ya
existía); `flashcard_options` nace vacía, una fila por opción con su propio texto, si es la correcta
y su propia procedencia (`sourceChunkId`/`sourceCharStart`/`sourceCharEnd`, mismo patrón que
`Flashcard` ya usa) —esquema v29—. El programador SM-2 y `review_log` no cambiaron: ya eran
agnósticos a la forma de la tarjeta, confirmado leyendo `sm2_scheduler.dart` antes de escribir nada.
Las opciones NO se anclan por `relations`/`extractedFrom` (decisión A): esa tabla tiene
`UNIQUE(from_item_id, to_item_id, kind)`, y dos opciones de la MISMA pregunta citando el mismo
elemento fuente es esperable, no un caso raro —un distractor «hermano del Atlas» o «el otro lado de
un `contradicts`» cae ahí con normalidad—.

**Un segundo bug de esquema real, encontrado recién al necesitarlo (v30).** `FlashcardOption.
sourceItemId` —de qué elemento sale la procedencia de una opción, no necesariamente el mismo que el
de la tarjeta— se resolvía al principio con un `JOIN` a `chunks`, así que se perdía cada vez que el
chunk no estaba resuelto. A diferencia de `Flashcard.itemId`, un campo PROPIO e independiente de su
chunk, ese `sourceItemId` derivado dependía enteramente de que el chunk existiera —el mismo caso ya
documentado de `sourceChunkId` cuando el texto de la fuente se rehace—. Corregido de raíz: columna
propia, poblada al guardar, con relleno para lo que ya tuviera `sourceChunkId` de antes de v30.

**La generación, en piezas separadas que se combinan recién al guardar.** `QuizQuestionGenerator`
(reusa `FlashcardDraft` tal cual: front=pregunta, back=respuesta, quote=cita sin anclar) solo
sugiere pregunta y respuesta, nunca opciones incorrectas —el modelo nunca inventa un distractor,
restricción inalienable del encargo—. `DistractorSourcer` los trae de la bóveda real, en el orden de
la decisión C: hermanos del elemento semilla en el árbol de Temas, el otro lado de una relación
`contradicts`, cercanía por embedding (`RelationCandidateSelector`, ya existía) —la cuarta fuente de
la decisión C, «misma comunidad del Mapa», queda deliberadamente afuera: investigado antes de
construir nada, `KnowledgeMapEngine` no expone ningún método de solo lectura para «la comunidad ya
calculada en esta sesión, sin forzar nada», y las otras tres ya alcanzan—. `GenerateQuizUseCase`
junta las dos piezas: `generate()` ancla la respuesta correcta con `locateQuote` contra el texto
real y descarta la pregunta si no ancla o si `DistractorSourcer` no encontró ningún distractor real
—nunca completa con nada inventado—; `save()` guarda todas las preguntas confirmadas en UNA
transacción (decisión D). Con un solo distractor real, la pregunta se ofrece igual, como opción
múltiple de dos opciones, en vez de forzar un tipo de tarjeta que no tiene la forma que hace falta
—ver el desvío señalado más abajo—.

**Un desvío real del texto del plan, señalado, no en silencio: el quiz nunca pasa por
`DerivedNoteType`.** Investigado antes de escribir nada (`derived_claim_anchor.dart`,
`anchorDerivedClaims`, F16 D6): esa función ancla como mucho UNA afirmación por elemento fuente en
TODA la generación, restricción que existe específicamente porque `RelationKind.extractedFrom` no
admite dos vínculos del mismo par —la misma colisión que la decisión A del propio plan ya identificó
y resolvió para las opciones—. Reusar `DerivedNoteType.quiz` tal como sugería la letra del plan
habría reintroducido, por otra puerta, el problema que la decisión A ya resuelve: una pregunta cuya
respuesta correcta y un distractor citan el mismo elemento —esperable con un hermano del Atlas o un
`contradicts` cercano— habría perdido una de las dos afirmaciones en silencio. Por el mismo motivo,
tampoco degrada nunca a `FlashcardKind.trueFalse`: esa forma necesita una afirmación redactada a
mano, y convertir una pregunta con su respuesta en una la inventaría —exactamente el material que
`DistractorSourcer` ya no encontró—. Consecuencia: el quiz no crea ningún elemento nuevo ni lleva
marca de modelo/fecha —ver el criterio de cierre, más abajo—.

**Revisión obligatoria antes de guardar, con procedencia visible por opción.** `QuizReviewScreen`
(pantalla completa, no diálogo —una pregunta trae varias opciones con su propia procedencia cada
una, más contenido del que entra cómodo en un `AlertDialog`—) deja incluir o descartar cada pregunta
por separado; ninguna se guarda a ciegas. Sin edición de texto, mismo criterio que la revisión de
tarjetas comunes y de sugerencias de propiedad: editar el texto de una opción la dejaría citando un
fragmento que ya no dice eso. `MultipleChoiceOptions` (mezcla las opciones una vez por pregunta,
revela al tocar, con «ver en la fuente» por opción —puede apuntar a un elemento distinto al de la
tarjeta—) se reusa tal cual en dos lugares: una tarjeta de opción múltiple que ya toca repasar en
`ReviewScreen` —sigue tocando la programación SM-2 igual que cualquier tarjeta— y una sesión SUELTA
(`QuizSessionScreen`, para practicar un quiz recién generado sin esperar a que «toque»), que nunca
llama a `review()` —adelantaría la programación de una tarjeta recién creada por una sesión que no
es un repaso espaciado real—. Al terminar una sesión suelta, un solo
`HabitEventRecorder.record(HabitEventKind.quiz)` cuenta para la racha, investigado antes de escribir
nada: `habit_event` ya es un mecanismo independiente de `review_log`, el mismo que usan `triage` y
`vocabulary` para lo mismo. `QuizSessionSummaryService` agrupa las preguntas falladas por tema del
Atlas (`AnkiTopicResolver`, el tema de la PREGUNTA es el de `Flashcard.itemId`) con la nota viva de
cada tema si tiene una —investigado: no hay relación 1:1 tema↔nota, «la» nota viva es la de `rowid`
menor, mismo criterio que `AnkiTopicResolver` ya usa para «el primer tema» de un elemento—.

**Exportación a Anki, un segundo tipo de nota, nunca a medias.** El esquema clásico de Anki
(`col.models`) ya admite varios modelos de nota en la misma colección —cada nota declara el suyo en
`notes.mid`, no hizo falta tocar el esquema SQL—: `AnkiPackageBuilder` arma uno nuevo
(`Question`/`Answer`/`Distractor1-3`) para `multipleChoice`, con los distractores reales cada uno en
su propio campo. Una pregunta mal formada —nunca pasa hoy, pero el esquema no lo impone— queda
afuera del mazo, nunca exportada a medias, y afuera de `markExported` también —bug real arreglado de
paso: antes marcaba exportadas TODAS las tarjetas pedidas, no solo las que de verdad entraban al
archivo—. El camino de texto plano (TSV/CSV) no admite dos modelos —su `#columns:` es uno solo para
todo el archivo—: los distractores van como lista legible dentro del mismo campo `Back`, sin perder
ninguna información, solo un modelo de Anki propio menos que en el `.apkg`.

**Alcance reducido de la entrada, señalado.** Solo la entrada desde UN elemento
(`GenerateQuizButton`, en `item_detail_screen.dart`, mismo patrón que `GenerateDerivedNoteButton`).
Las otras cuatro del plan —una rama del Atlas, un cuaderno, una vista guardada, la pantalla de
Repaso— resuelven a VARIOS elementos, y `GenerateQuizUseCase` genera y guarda para uno solo por
llamada, a diferencia de `GenerateDerivedNoteUseCase`, que ya sabe resolver un cuaderno entero;
investigado antes de escribir nada, no hay orquestación multi-elemento hoy, haría falta construirla
de cero. Quedan para una fase futura si hace falta.

**El criterio de cierre (20.6, del encargo), con lo que se cumple y lo que se cumple distinto de la
letra.** Cumplidos: ninguna opción de ningún quiz existe sin un chunk real que la respalde —cubierto
por los tests de `DistractorSourcer`, `FlashcardRepositoryImpl.createMultipleChoice` y
`GenerateQuizUseCase`, cada uno en su capa—; las preguntas confirmadas entran en la programación
SM-2 y en `review_log` igual que cualquier tarjeta, desde el momento en que se guardan; ninguna
pregunta llega al repaso sin pasar por `QuizReviewScreen`; la sesión suelta cuenta para la racha,
capturar sigue sin contar —sin cambios—; invariante de chunking verde —F20 nunca escribe un chunk,
solo lee los que ya existen, y la suite completa corrió verde antes de cada uno de los nueve
commits—. **Cumplido distinto de la letra, señalado:** «una pregunta sin distractores suficientes
degrada o se descarta» se implementó SOLO como descarte —nunca degrada a `trueFalse`, por el motivo
ya explicado más arriba—; «las cuatro condiciones de generación por IA, como en F16» aplican tal
cual a una nota derivada, no a una tarjeta —una tarjeta, común o de opción múltiple, nunca creó un
elemento nuevo ni llevó marca de modelo/fecha, ni antes de F20 (F11) ni ahora—: lo que SÍ aplica —
nunca sustituye al original, cada opción anclada a su propio chunk real— se cumple.

**Lo que F20 no hace, dicho sin adornos.** No genera un quiz desde una rama del Atlas, un cuaderno,
una vista guardada ni la pantalla de Repaso —solo desde un elemento—. No degrada nunca a
`FlashcardKind.trueFalse`. No usa «misma comunidad del Mapa» como fuente de distractores. No mide
nada en un teléfono real —sigue siendo emulador, como todo este encargo y el anterior—.

Con esto el encargo F18–F20 queda CERRADO entero.

### 54. F21 de procesamiento confiable y rápido: nada queda "Procesando" para siempre, y lo largo va por partes, con avance y retomable

Nace del uso real en el teléfono (Xiaomi, HyperOS): un short de YouTube de dos minutos, una página
web y un libro quedaban "Procesando" para siempre, todo lo que se guardaba después quedaba "En
espera" detrás, y borrar lo trabado no destrababa nada. Plan: `docs/planes/F21-procesamiento-
confiable.md`, con la escala subida por el usuario a libros de cientos de páginas y videos de hasta
cuatro horas. Diecisiete commits numerados, más tres correcciones sueltas: dos de pruebas y una de la
versión release —que nunca se había compilado y frenaba en R8 por reconocedores de ML Kit que la
app no usa (`android/app/proguard-rules.pro`)—.

**Las causas, medidas en la app en vivo, no supuestas.** El estado interno de la cola se leyó de la
memoria del proceso por el servicio de depuración de Dart. Lo que quedaba `processing` cuando la app
se cerraba nunca se retomaba —solo se encolaba lo `pending`—; el cliente de YouTube no tenía tiempo
límite y la cola era una sola fila sin vigilante; borrar no cancelaba; el guardado final escribía la
foto del elemento tomada al empezar (pisaba lo editado mientras tanto); la cola observaba unos veinte
proveedores y una reconstrucción la vaciaba; archivar la página de vaticannews bajaba 335 recursos
(13,8 MB) para 1,5 KB de artículo; el audio de YouTube, el WAV de una transcripción y cada archivo
capturado pasaban enteros por memoria; Whisper corría con un hilo.

**Lo que no se traba.** El estado técnico del procesamiento vive en las columnas de `source`
(`processing_status`, `processing_error`, `processing_attempts`), escritas por
`ProcessingStateRepository` con actualizaciones puntuales, nunca guardando el elemento entero —lo
editado mientras tanto sobrevive; el guardado final es una fusión de tres vías sobre la versión
actual, `mergeTransformResult`—. Al abrir, lo interrumpido se retoma, con un tope de tres intentos
para que algo que hace caer la app no la haga caer en cada arranque. Cada pedido a la red tiene su
tiempo límite, y un vigilante por elemento: en el carril corto, un tope fijo (3 minutos); en el
largo, que no deje de avanzar (10 minutos sin avance). Borrar cancela en el acto
(`CancellationSignal`, `cancellableStream`): la cola sigue a la base (`watchRemoved`,
`watchPendingIds`) y no depende de que el trabajo cancelado colabore. El motivo real de cada fallo
se guarda (`ProcessingFailureReason`) y se muestra con qué hacer —"Descargar el modelo" si falta el
de transcripción, y al bajarlo lo que lo esperaba se retoma solo—.

**Dos carriles.** Lo corto (una página, un video con subtítulos) no espera a lo largo (transcribir,
reconocer páginas escaneadas): cada carril es de a uno, y un trabajo pasa al largo cuando descubre
que lo es (`TransformContext.enterLongLane`), con avance por elemento en la tarjeta y en el detalle
—"Reconociendo páginas escaneadas: 12 de 400", "Transcribiendo… 40 %"—. En Android, mientras hay
algo en el carril largo, un servicio en primer plano (`LongWorkService`, Kotlin, sin dependencias
nuevas; tipo `mediaProcessing` en Android 15, `dataSync` antes) mantiene viva la app con una
notificación de avance: sin él, HyperOS la congelaba a los pocos minutos en segundo plano. No hace
el trabajo —lo hace Dart—; si se cierra la app desde "recientes", se va con ella, y lo hecho ya quedó
guardado.

**Nada entero en memoria, y lo largo retomable (esquema v31).** Capturar copia por partes al almacén
(`FileStore.saveStream`), sin el tope de 500 MB —el límite pasa a ser el espacio libre—. Los
documentos se abren desde el disco (`DocumentSource`, `PdfDocument.openFile`); los metadatos de un
PDF se leen del principio y del final, siguiendo la tabla de referencias si el `Info` está en el
medio. La tabla nueva `processing_checkpoint` guarda cada página reconocida y cada tramo transcrito:
al retomar no se repiten, y guardar una parte nueva pone los intentos en cero —un libro que se
interrumpe varias veces avanzó cada vez; uno que revienta siempre en la misma página, no—. Es estado
de trabajo: se borra al terminar bien y la fusión de bóvedas no la copia.

**Las decisiones del usuario.** A, en una variante propia: el texto que el documento ya trae se saca
rápido, y las páginas escaneadas se reconocen siempre, solas, en el carril largo, página por página
—solo las que no traen texto, y no las que están en blanco de verdad, que se detectan
renderizándolas a 64 px—, con la compresión de cada imagen fuera del hilo principal. En el detalle
de un documento lo principal es el original en su visor; el texto extraído queda plegado, porque
existe para la búsqueda, el chat, las tarjetas y el quiz. B: el audio de YouTube ya no se baja solo
—el video queda listo en segundos con su transcripción, dure lo que dure—; se baja a pedido, directo
a disco, con avance y cancelable, y se escucha debajo de la vista previa del video, que sigue siendo
lo principal. C: el servicio en primer plano, de arriba.

**La transcripción, por tramos.** El WAV convertido queda en disco con una marca de "conversión
terminada" (al retomar no se reconvierte); un isolate propio lee de a un tramo, con hasta cuatro
hilos de Whisper, y cada tramo vuelve apenas termina, se guarda y avisa el avance. La medición en el
emulador destapó un defecto que venía de antes: sherpa-onnx se reserva medio segundo de relleno y
descarta lo que pasa de 29,5 s de cada ventana, así que con tramos de 30 s se perdía medio segundo
cada medio minuto. Los tramos pasaron a 29 s.

**Lo que viene después, medido a escala.** En el PC, guardar un libro de 500 páginas (1,77 millones
de caracteres, 999 fragmentos) tarda 569 ms —fragmentar, 68; el resto es la base, que en la app
corre en su propio isolate—. Dos cosas no escalaban y se corrigieron: los vectores de un elemento se
pedían todos juntos, todo o nada —ahora van por tandas de 32, cada una guardada, y se retoman—, y
elegir candidatos a relación cargaba el texto de todos los fragmentos de la bóveda y promediaba
diez mil vectores en el hilo de la interfaz —ahora lee solo identificadores y vectores, hace la
matemática en un isolate y trae el extracto solo de los que quedaron—.

**Cifras** (`docs/benchmarks/`): vaticannews, archivar de 11,5 s y 335 pedidos a 1,1 s y 60 (PC). En
el emulador Pixel 9 Pro (x86_64, 4 núcleos, Android 17): reconocer 20 páginas escaneadas, 14-31 s
(0,7-1,6 s por página, según la carga del PC que corre el emulador), retomando desde la mitad, entre
un tercio y la mitad de eso;
transcribir 9,5 minutos de voz con Whisper "small" y cuatro hilos, 9,6-11,7 minutos —alrededor de
un minuto por minuto de audio: cuatro horas serían unas cuatro o cinco en el emulador—, retomando
desde la mitad, algo más de la mitad; memoria pico del proceso, 1,65 GB, casi toda del modelo; con
tramos de 29 s, ningún aviso de recorte (28 en 30 tramos antes); el servicio en primer
plano aparece con el trabajo y se suelta 15 s después de terminar, comprobado con
`dumpsys activity services`.

**Lo que F21 no hace, dicho sin adornos.** No hay cifras de un teléfono real: todo lo de Android es
del emulador, que no representa la velocidad del teléfono del usuario. No se midió un video de
YouTube de cuatro horas de punta a punta —el camino ya no baja audio, solo la transcripción—, ni la
captura de un video de varios GB en el dispositivo. El modelo "base", más rápido que "small", no se
sumó: queda como opción si las cifras del teléfono lo piden. Si se cierra la app desde "recientes",
el trabajo largo se detiene —se retoma al volver—; no sigue sin la app.

### 55. F22 de fidelidad del texto: lo que se guarda es el original, carácter por carácter

Nace del uso real de la versión release en el teléfono, el día después de cerrar F21: una alabanza
transcrita con "es tu maquillaje, es tu maquillaje…" decenas de veces, un audio de tres minutos que
tardaba mucho, y un libro PDF que se ponía gris entero al mantener apretado para copiar. Y un pedido
general del usuario: que ninguna transcripción ni extracción cambie, borre ni altere nada. Plan:
`docs/planes/F22-fidelidad-del-texto.md`, aprobado entero con las cuatro decisiones como se
recomendaron.

**El principio.** Lo que se guarda es el original, carácter por carácter, estructura incluida
(párrafos, renglones, títulos, listas). Lo que necesita otra forma —la búsqueda que encuentra
"explicaciones" aunque el libro diga "ex-⏎plicaciones"— la deriva del original sin tocarlo. Y lo que
el motor no pudo reconocer queda marcado como hueco, nunca inventado.

**El audio que llegaba estirado —la causa real de los disparates—.** Con la versión nueva instalada,
la alabanza del usuario volvió a salir sin sentido. Medido en su teléfono: `audio_decoder`, el
paquete que pasaba cada audio al formato de Whisper, tomaba la frecuencia que DECLARA el archivo, no
la que ENTREGA el decodificador, e ignoraba el aviso de cambio de formato. Un AAC eficiente (HE-AAC,
el de muchos audios de YouTube y de apps de mensajes) declara 22.050 Hz y se decodifica a 44.100: el
WAV salía de 598,9 s para un audio de 299,4 s, estirado una octava más grave. En las pruebas no
aparecía porque usaban WAV. Además remuestreaba por interpolación lineal sin filtrar y muestra por
muestra en Kotlin interpretado: 113 s por cada 5 minutos de AAC. En Android ahora `AudioToPcm.kt`
decodifica con el formato real y vuelca el PCM crudo sin tocar una muestra, y `pcm_resampler.dart`,
en un isolate, mezcla a mono y pasa a 16 kHz con un filtro sinc polifásico (un tono de 10 kHz
desaparece en vez de volver como ruido en 6 kHz). HE-AAC, AAC y Opus dan la duración exacta y la
letra correcta; convertir 5 minutos de AAC pasó a unos 65 s, casi todo en el decodificador del
sistema (5 ms por bloque, igual con el de software y leyendo de almacenamiento privado), y 2 s de
remuestreo.

**Audio de todo tipo, también sin subtítulos.** Un video de YouTube sin subtítulos ya no se queda
con la descripción: pasa al carril largo, baja su audio a un archivo temporal y lo transcribe con
Whisper, retomable como cualquier audio; el archivo se borra al terminar (guardarlo sigue siendo
"Descargar el audio", a pedido).

**El PDF gris.** `pdfrx` 2.6.1 arma sus widgets con `material_ui`, una copia de Material con clases
propias; la app solo registra las traducciones de `flutter/material`. La selección funcionaba, pero
el menú "Copiar" reventaba al pedir su etiqueta y la versión release lo reemplazaba por el recuadro
gris de error de Flutter, del tamaño del visor. `PdfrxMaterialBridge` le da al visor, en su borde,
las traducciones y un tema con los colores de la app. Probado en el teléfono, el usuario pidió
tiradores más prolijos que los triángulos de `pdfrx`: ahora son una gota, como los de Material y
Google Lens, con un área táctil de 40 px.

**La transcripción, medida contra transcripciones humanas.** Con el mismo motor y versión que la app
(sherpa-onnx 1.13.8, Whisper small int8), sobre una alabanza cantada y diez minutos de una charla
con subtítulos hechos por personas:

- El texto inventado era un **bucle** de Whisper sin ninguna defensa: "oh, oh…" 90 veces en un tramo
  (índice de compresión 9,4; lo normal, 1 a 2), que además tardaba cinco veces más que un tramo
  normal. Ahora un tramo cuyo texto se comprime más de 2,4 veces —el criterio de Whisper original—
  se vuelve a transcribir en mitades, hasta en cuartos; lo que siga en bucle queda como
  "[fragmento no reconocido 3:15–3:29]".
- Los tramos pasaron de 29 s fijos a **hasta 14,5 s cortados en la pausa más cercana**, por energía:
  15,0 % de diferencia con los subtítulos humanos contra 16,2 %, 64 palabras perdidas contra 79, sin
  bucles, y en habla 18-19 % más rápido (comparación alternada en la misma PC). El silencio puro
  (-50 dBFS) no llega al motor: es donde Whisper inventa frases.
- Se compararon otros motores y se descartaron con cifras: Parakeet v3 empata en habla y es 4 veces
  más rápido, pero con canto pierde versos y mete portugués; Qwen3-ASR tradujo la letra al inglés; un
  detector de voz (Silero) descartaba 186 de 299 segundos cantados. Después, a pedido del usuario
  —"aunque haya música, lo más perfecto posible"—, Whisper "turbo": reconoce mejor la letra cantada
  pero inventa frases ("¡Suscríbete al canal!"), entra en más bucles y es 3 a 4 veces más lento; y
  un limpiador de voz (GTCRN), que borra el canto como si fuera ruido. Tampoco se adoptaron.
- **El idioma** es un dato de la fuente (`Source.language`, esquema v32): Whisper detectándolo solo
  confunde el español con el gallego y quita las tildes, y fijado en español traduce un audio en
  inglés. Se transcribe en el idioma elegido, o en español.
- Una marca de tiempo por tramo, "[3:15] …", como las de YouTube.

**Los lectores.** Cada uno se revisó contra el original y después pasó por una revisión
independiente, que encontró más defectos; todos corregidos, con pruebas que comparan el texto
guardado carácter por carácter:

- *PDF*: se guardan los renglones, los guiones de corte y los espacios de las columnas (antes una
  página quedaba como un párrafo, y "1990-⏎1995" como "19901995"). La búsqueda encuentra la palabra
  cortada porque el índice de los chunks lee de una vista, `chunk_search_text`, que agrega la versión
  unida —solo el índice; la app usa `MATCH` y `rank`, no `snippet()`—. Las páginas escaneadas con un
  número de página como texto ahora se reconocen, y un reconocimiento fallido queda marcado.
- *Word*: controles de contenido, encabezados y pies, notas al pie y comentarios, numeración real
  (también la de listas por estilo), ecuaciones en notación lineal, campos anidados, celdas
  combinadas, SmartArt, símbolos y cuadros de texto sin duplicar.
- *EPUB y web*: un conversor propio de HTML a Markdown sin barras invertidas (html2md salió del
  proyecto), sin volcar el `<head>`, con superíndices, tachados, MathML y tablas en su orden; la
  codificación que declara la página (y Windows-1251, ISO-8859-2, KOI8-R); un artículo corto se
  guarda en vez de descartarse.
- *Texto plano*: su codificación, byte por byte. *YouTube*: los subtítulos del idioma en que se
  habla, no una traducción.
- *En pantalla*: Markdown solo donde el texto lo es; una transcripción, un PDF o una foto se ven tal
  cual. "Quitar marcas de tiempo" solo en transcripciones, y sin juntar las líneas.

**Lo que ya estaba en la bóveda.** "Volver a extraer el texto" (audio, video, documento, foto,
YouTube) lee el original otra vez con la versión de hoy. La intención queda en la base y nada se
borra antes: el texto nuevo toma el lugar del viejo —la misma forma, el mismo identificador—, y los
subrayados, las tarjetas y las notas extraídas se buscan en él por su fragmento, sin mirar cómo se
cortan los renglones. Un subrayado que ya no aparece queda en la nota del elemento, con su nota.

**Cifras en el teléfono** (Xiaomi 23090RA98G, Dimensity 7200, Android 16; `docs/benchmarks/xiaomi-
23090RA98G-android16/2026-09-30-f22/`, medido con la app de pruebas `staging`, sin tocar la bóveda
del usuario): la charla, 11,2 % de diferencia con sus subtítulos humanos; la alabanza, sin bucles ni
huecos. Transcribir tarda 0,36 veces la duración del audio con canto y 0,68 con habla densa —una
hora de charla, unos 40 minutos—, más la conversión si el audio no es WAV. Entre 2 y 6 hilos no hay
diferencia que supere la variación entre corridas: el procesador tiene dos núcleos rápidos; la app
sigue con 4.

**Actualización (2026-10-01): tramos solapados.** Ya instalado, el usuario vio sus notas de voz
"cortadas o resumidas". Se midió con sus propios audios —255 del teléfono, 4 h, en la PC con el
mismo código; 24 convertidos en el teléfono—: la conversión no pierde nada (cada WAV dura lo que el
original) y ninguna pantalla recorta el texto. Lo que se perdía era **la palabra donde cae cada
corte**: en el habla de corrido no hay pausas, y Whisper deformaba o callaba lo que quedaba en el
borde de los dos tramos —en una nota de 1:52, "no hay intervención docente ahí" salía "no hay
intervención 2C. / de ahí", y "no es una tarea que" salía "no es una... / que"—. Este modelo no da
tiempos por palabra (`enableTokenTimestamps` vuelve vacío), así que no se puede retomar donde
terminó la última palabra, como hace Whisper original. Ahora cada tramo se transcribe desde 3 s
antes de su corte, y los dos textos se unen por la tira de palabras más larga que comparten,
cortando por su mitad (`stitchOverlappingTexts`): en la misma nota salen enteras "docente ahí" y
"una tarea que", y en la charla con música, "mucho más" (antes "muy / más"). Los cortes y las
marcas de tiempo son los mismos de antes; se guarda lo que dijo el motor y se une al final, así
retomar une igual. Cuesta unos 3 s más de audio por tramo de 14,5.

**Lo que F22 no hace, dicho sin adornos.** Ningún motor transcribe perfecto una canción con música:
lo garantizado es que la app no altera, que no queda texto inventado por bucles, y que la precisión
está medida. El OCR de fotos sigue siendo solo de alfabeto latino. Readability puede limpiar tablas y
listas que parecen navegación en artículos largos; el resguardo es la página archivada completa.

### 56. F23: el texto sigue al audio, palabra por palabra, con tiempos medidos

Pedido del usuario: que mientras suena un audio la palabra que se dice se vea en amarillo en su
transcripción, y —ante la primera idea de repartir el tiempo de cada renglón entre sus palabras—
"hazmelo profesionalmente". Plan: `docs/planes/F23-resaltado-sincronizado.md`, aprobado con la
decisión A como se recomendó y la B con un agregado del usuario (el mini reproductor flotante).

**Los tiempos los mide Whisper.** sherpa-onnx calcula cuándo se dice cada pieza del texto con la
técnica de OpenAI —los cabezales de atención del decodificador y DTW—, pero solo con una exportación
que conserve esa salida; la de quien mantiene sherpa-onnx no la trae (`enableTokenTimestamps`
volvía vacío). Se adoptó la de `clairemcw/sherpa-onnx-whisper-small-attention`: los mismos pesos y
el mismo texto, comprobado tramo por tramo. Es de un tercero, así que va **fijada a un commit** y
cada archivo se comprueba por su tamaño y su huella SHA-256 antes de usarse (`WhisperModelSpec`);
el modelo anterior se borra recién cuando el nuevo quedó entero. Medido contra una voz con los
tiempos reales de sus 160 palabras: error mediano de 60 ms, el 90 % a menos de 155 ms, todas a menos
de medio segundo; en el teléfono cuesta alrededor de 1 % más de tiempo
(`docs/benchmarks/xiaomi-23090RA98G-android16/2026-10-01-f23/`).

**Los tiempos no se pierden en el camino.** Las piezas de Whisper unidas dan el texto exacto, y cada
palabra toma el momento de la que la empieza (`timedTextFromTokens`); si las piezas no forman el
texto, sale sin tiempos —nunca uno inventado—. La guardia contra bucles los lleva a su lugar al
partir un tramo, el cosido de los tramos solapados conserva el de cada palabra que queda, y un tramo
guardado para retomar se guarda con ellos. Se guardan junto al texto (`renditions.word_timings`,
esquema v33): el paso v18, que reconstruye la tabla, la nombra en `newColumns`, y la fusión de
bóvedas la copia —con un censo que compara su lista de columnas contra la tabla real, que antes no
existía—.

**En pantalla.** Un solo reproductor por archivo (`playbackSessionProvider`) para el del detalle,
el mini reproductor, el texto y la pantalla completa. El texto ubica cada palabra medida por sí
misma, sin las marcas de cada renglón, así que sigue sirviendo después de "Quitar marcas de tiempo"
(`TranscriptSync`); una transcripción de antes de F23 se sigue renglón por renglón, con sus marcas.
Tocar una palabra con el audio en marcha lo lleva ahí. La pantalla no se mueve sola; cuando el
reproductor sale de la vista aparece el mini reproductor flotante, con "Volver al audio".

**Lo pendiente.** La prueba del usuario en su teléfono, que pidió dejar para el final.

### 57. F24: el audio de cada video, siempre a mano

Pedido del usuario: que debajo de la vista previa de un video, un short, un TikTok o un reel esté
siempre el mismo reproductor que el de un audio del teléfono, con el audio bajado sin que haya que
pedirlo. Plan: `docs/planes/F24-audio-de-los-videos.md`, aprobado con las **alternativas** de las
dos decisiones: el audio de YouTube en la mejor calidad que ofrece (~72 MB por hora), y además del
video un reproductor solo de audio debajo de él.

- **YouTube:** el audio se baja solo, sin botón —el que había se quitó a pedido—, apenas el video
  queda listo (la cola avisa lo que terminó bien, `onProcessed`), o al abrirlo si todavía no lo
  tiene. No entra en el procesamiento: el video sigue quedando listo en segundos, como en F21; la
  bajada es aparte, directo a disco y con avance. Un video sin subtítulos ya bajaba su audio para
  transcribirlo: ese archivo se conserva como el audio del video, aunque no se haya dicho nada, en
  vez de bajarlo dos veces. Debajo de la miniatura, el mismo reproductor, el mini reproductor y el
  texto que sigue al audio (renglón por renglón con los subtítulos, que traen su momento).
- **TikTok y reels:** su video ya se guardaba entero; ahora su audio se transcribe, y lo dicho pasa
  a ser el texto principal —la descripción queda al lado, buscable—, con sus tiempos por palabra.
- **Videos (del teléfono, TikTok, reels):** debajo del video, un segundo reproductor solo con su
  audio (`MediaPlayerView.audioOnly`). Los dos manejan el mismo audio: un solo reproductor por
  archivo (decisión 56).
- Cuál es el archivo que suena en un elemento lo dice un solo lugar (`itemPlaybackPathProvider`):
  el audio o el video mismo, o el audio bajado de un video de YouTube.

Al medir la fusión de bóvedas con esto apareció un defecto de F23: la consulta que completa los
tiempos por palabra comparaba cada forma con todas las de la copia. Se reescribió para buscar por
identificador.

### 58. F25: el lector flotante lee en voz alta cualquier texto

Pedido del usuario: un botón flotante abajo a la derecha que abra un mini reproductor para leer el
texto en voz alta —voz, acento, velocidad, ±10 s, pausa, minimizar y cerrar—, con la línea que lee
en amarillo, en todas las pantallas con texto y no en ajustes, papelera ni biblioteca. Plan:
`docs/planes/F25-lector-flotante.md`, aprobado con **A como se recomendó** (10 s de habla) y **B
con la alternativa** (también el chat y el repaso de tarjetas). Reemplaza al botón "Escuchar" que
había debajo de cada texto, que se quitó a pedido.

- **Cada pantalla declara su texto** (`ReadableRegion`): un documento partido en pedazos —una
  línea, o una oración si la línea pasa de 280 caracteres—, cada uno con **dónde está en
  pantalla** (qué texto y entre qué posiciones) y con lo que se dice, sin las marcas "[3:15]" de
  las transcripciones ni los símbolos de Markdown. Lo ofrece solo mientras se ve (`TickerMode`):
  una pestaña de atrás o una pantalla tapada retiran lo suyo, y el botón aparece solo donde hay
  texto. Lo ofrecen el detalle de un elemento (la nota del usuario, cada forma de texto, cada
  bloque de una nota de bloques), el modo lectura, el lector de libros y documentos (la página que
  se ve y las 19 siguientes; da vuelta la página solo), el editor de notas (sin resaltado: son
  campos que se editan), el chat y el repaso de tarjetas.
- **Un solo lector para toda la app** (`ReadAloudController`), que sigue leyendo al cambiar de
  pantalla hasta que se cierra. Le pasa al motor de voz un pedazo por vez —nunca el texto entero— y
  la pantalla se redibuja solo cuando cambia de pedazo; el anillo y el hilo de avance, por palabra.
- **Pausa de verdad y ±10 s de habla.** Android avisa qué palabra dice (`setProgressHandler`,
  desde Android 8): pausar es cortar y retomar en esa palabra. Los saltos usan los caracteres por
  segundo **medidos** con esa voz y esa velocidad (promedio con decaimiento, descartando pausas de
  más de 3 s); antes de medir, una estimación de 14 caracteres por segundo a velocidad 1. Siempre
  caen al comienzo de una palabra. Avisos atrasados de una lectura ya cortada se descartan por
  generación.
- **El reproductor** sigue el diseño del de audio (F23): una tarjeta con título, estado, avance,
  velocidad (0,5× a 2×, el mismo panel), ±10 s, reproducir/pausar y el panel de voz. El acento es
  el idioma y la región de las voces instaladas, cada uno con su nombre en su idioma ("Español
  (Argentina)", "English (United States)"); las voces con nombre-código de Android se muestran como
  "Voz N", locales primero. Minimizado queda el botón redondo con un anillo de avance. El botón se
  corre por encima de la barra de navegación, del teclado y de las barras fijas de abajo
  (`ReadAloudClearance`: el campo del chat, el mini reproductor de audio) y se esconde bajo un
  diálogo o un panel.
- **Uno a la vez con el audio** (`audioFocusProvider`): si se empieza a leer, el audio o video que
  suena se pausa, y al revés.
- **El menú de selección de texto** quedó igual en toda la app y en el orden pedido por el usuario:
  Copiar, Compartir, Seleccionar todo, Leer en voz alta, Resaltar, Extraer como nota, Crear tarjeta
  y Buscar en la Web (`selectionMenuItems`). Fuera quedan las opciones que Android le suma por cada
  app instalada que acepta texto (ChatGPT, Gemini…). "Leer en voz alta" lee las líneas que toca la
  selección, con su resaltado, y se detiene; "Buscar en la Web" la hace la app, porque Flutter la
  ofrece solo en iOS.

**Actualización (2026-10-03, pedido del usuario):** en el detalle de un elemento con su propio
audio —un audio, un video, un reel, un YouTube con el audio bajado— el lector no se ofrece: el
texto ya se escucha con la voz original y se resalta solo (F23), y el lector era un segundo audio
de lo mismo. Sigue ofreciéndose donde no hay qué escuchar, también en un YouTube cuyo audio no se
pudo bajar.

**Retiro (2026-10-03):** el reproductor de narración anterior (`NarrationPlayer`, el botón
"Escuchar" de cada texto) se borró con sus 15 textos: ya no lo usaba ninguna pantalla desde que
el lector flotante lo reemplazó. El corte en oraciones (`speech_segmentation.dart`) sigue: lo usa
el lector.

Al construirlo aparecieron dos defectos viejos de la narración, corregidos de raíz: volver a "Voz
del sistema" no cambiaba la voz (`setVoice(null)` no hacía nada) y borraba la voz guardada pero no
la del estado.

### 59. F26: el panel de la fuente, y la Biblioteca más simple

Pedidos del usuario: ordenar en un panel "elegante, interactivo y atractivo" los botones sueltos
entre la vista previa y el texto; elegir el tema al guardar en vez de desde la Biblioteca; filtrar
por tema; y sacar opciones que no usa. Plan: `docs/planes/F26-panel-de-la-fuente.md`, aprobado con
las recomendadas (cuatro mosaicos; el audio dentro del panel).

- **Un solo panel por elemento** (`SourcePanel`), con el lenguaje del marco del visor (radio 16,
  borde suave): arriba el audio del video —el reproductor compacto, el mismo audio que el de
  arriba—; después lo que está pasando, siempre con la misma forma (ícono, texto, barra y un único
  botón tonal: "Reintentar" o "Descargar el modelo"); abajo cuatro mosaicos iguales —Leer,
  Resumir, Copiar, Más— que nunca pasan a dos renglones. "Más" abre una hoja con lo de vez en
  cuando (volver a extraer, quitar marcas de tiempo, borrar el archivo, organizar con IA), solo con
  lo que aplica. Antes eran hasta ocho controles de cinco estilos distintos, alineados a uno y
  otro lado, y en los documentos escondidos bajo el texto plegado; con varias formas de texto la
  fila se repetía.
- **El tema se elige al guardar**: cada formulario de captura tiene "Tema (opcional)", con crear
  uno nuevo y buscar; se asigna en la misma transacción del guardado (`CaptureRequest.spaceId`).
  La fila de temas de la Biblioteca pasa a ser la sección "Tema" de Filtros, arriba de "Tipo", con
  una barra de desplazamiento cuando son muchos; el tema elegido se ve debajo de la búsqueda.
- **Menos opciones**: exportar un elemento ofrece solo PDF y Word (`offeredItemExportFormats`; los
  exportadores siguen para la bibliografía y NotebookLM); la cita se copia solo como texto plano.
- **El menú de selección de texto** quedó en la decisión 58.

Al construirlo se corrigió que elegir "Sin clasificar" en el selector de tema del detalle no
hiciera nada.

### 60. F27: la IA organiza sola, y todo se puede corregir

Pedido del usuario: que las tarjetas, los vínculos, el Atlas "y demás cosas", además de a mano, los
haga la IA automáticamente, "de manera inteligente", pero que si ve un error pueda borrarlo o
editarlo. Plan: `docs/planes/F27-la-ia-organiza-sola.md`, aprobado con las recomendadas: A —aplica
sola todo salvo la madurez, que se sugiere, y los duplicados, que siguen como aviso—; B —lo seguro
se aplica y lo dudoso va a "Para revisar"—; C —la biblioteca existente se recorre solo con el
cargador—; D —de 3 a 12 tarjetas según el largo—.

**Esto revisa a propósito las decisiones 21, 38 y 53** ("nunca se guarda nada sin que la persona lo
revise"): ahora la IA guarda sola, pero nada queda sin dueño ni sin vuelta atrás.

- **Procedencia** (esquemas v34 y v35): cada vínculo, tarjeta y propiedad sabe si lo hizo la persona
  o la IA, con la confianza, el motivo y la pasada (`ai_runs`); lo que la IA completó en columnas del
  elemento —el tema, los datos de la referencia— queda en `ai_field_changes` con su valor anterior.
  Deshacer una pasada devuelve todo a como estaba, salvo lo que la persona cambió o adoptó después:
  **editar algo de la IA lo vuelve de la persona**. "No era" borra y recuerda (`ai_rejections`,
  por huella: un vínculo como par sin orden más el tipo, una propiedad sin mayúsculas ni acentos,
  una tarjeta por su pregunta normalizada), para que no vuelva.
- **La cola de la IA** (`AiOrganizeQueue`) es aparte de la de procesamiento: el elemento queda listo
  como antes y la IA trabaja después, de a uno. Lo pendiente sale de la base, no de una lista en
  memoria, así que se retoma tras reiniciar; lo deshecho no se vuelve a organizar solo. Toma, en
  orden, lo pedido a mano, lo nuevo, las notas que cambiaron de contenido (simhash de la decisión
  40, 16 bits) y la biblioteca existente con el cargador, pidiendo el servicio en primer plano
  —ahora de varios dueños— para seguir con la pantalla apagada.
- **El modelo es uno solo** (Gemma, en el teléfono) y lo usan el chat, resumir y la cola: un turno
  (`LanguageModelGate`) que da prioridad a la persona; una charla retiene el modelo mientras se usa
  y lo suelta a los 2 minutos sin uso. Nada le llega entero: los textos van por partes y el
  vocabulario, acotado a lo pertinente por vectores y uso (2000 caracteres).
- **Qué hace sola**: vínculos —también entre notas, que ahora tienen vectores— con confianza
  = 0,6 × la certeza que declara el modelo + 0,4 × el coseno normalizado; desde 0,75 se crea, entre
  0,45 y 0,75 va a "Para revisar". Tarjetas ancladas a una cita textual (lo que no ancla se
  descarta). Valores del vocabulario existente; uno nuevo, a revisar. El tema de cada elemento,
  solo con certeza alta y si no tenía. Los datos vacíos de la referencia. En el Atlas: los temas
  nuevos se ubican en el árbol (los viejos solo se proponen: pudieron quedar en la raíz a
  propósito) y cada tema con cinco elementos o más recibe su nota mapa, con los enlaces sacados de
  la base, nunca del modelo, y sus títulos en el idioma de la app; editada, es de la persona, y
  deshacer su pasada la manda a la papelera. La madurez solo se sugiere.
- **Lo que se ve**: la marca ✨ en lo de la IA; "Lo que hizo la IA" (el estado de la cola, "Para
  revisar" y la actividad con deshacer); la línea "La IA organizó esto…" en cada elemento;
  "Organizar con IA" en la hoja Más; Ajustes › IA con un interruptor general, uno por tipo y el
  avance de la biblioteca existente. Sin los dos modelos descargados, la IA no hace nada y lo dice.

Los umbrales son un punto de partida medido en escritorio: se calibran con la prueba en el
teléfono. Android 12 o más no deja arrancar el servicio en primer plano desde segundo plano: si se
enchufa el cargador con la app cerrada, la pasada sigue al abrirla. Las sugerencias no viajan en
la fusión de bóvedas, así que otro dispositivo no sabe lo que la IA ya propuso sobre un tema.

Al construirlo se corrigieron de raíz: un lote de "Para revisar" que nunca se aplicaba (en
Flutter 3.47 un aviso con acción no se cierra solo), la pantalla del modelo de lenguaje que
mostraba "listo" después de una descarga fallida, una obra marcada "sin fecha" que podía recibir
una fecha de la IA, aceptar a mano los datos de una referencia —borraba la edición, la clave de
cita, la fecha de consulta y la exactitud de la fecha: ahora usa la misma regla que la IA, solo
lo vacío—, y las pruebas de memoria de la copia y la fusión, que medían la memoria
residente —el sistema la recorta con la máquina cargada— en vez de la comprometida.

### 61. F28: el Mapa muestra lo que hacés, y un solo «tema»

Pedido del usuario: vincular dos cosas "no aparece nada en grafos ni en mapa conceptual". Plan:
`docs/planes/F28-nada-se-pierde.md`, aprobado con la recomendada A —«Tema» es lo que se elige al
guardar; el Mapa y el Atlas se arman también con los temas; lo que hoy llaman «Tema» pasa a
«Etiquetas»—. Esta decisión cubre el Mapa y el «tema»; la Bandeja y lo procesado (B) van aparte.

**Revisa a propósito las decisiones 46 y 47**: el Atlas y el Mapa ya no miran solo categorías de
propiedades.

- **La vista «Vínculos»** dibuja los elementos y sus relaciones sin temas de por medio
  (`readLinkGraph`, `selectLinkGraph`, `MapLinksView`), con el lenguaje del nivel de elementos del
  grafo. Escala como el resto del Mapa: los sueltos no se dibujan y se cuentan; de los vinculados,
  a lo sumo 200, en este orden: el foco y su vecindario, los extremos de los 40 elementos de los
  vínculos más recientes —lo recién vinculado se ve aunque haya cientos más vinculados— y lo más
  vinculado. Se lee con un `watchReads` (lo de `watchQuery`, con los avisos del repositorio) y no
  pasa por el motor del mapa: no hay comunidades que recalcular, y vincular se ve sin la espera
  por lotes.
- **Sin vacíos mudos**: el motor entrega con cada cálculo los elementos sin ningún valor de lo que
  se mira; el Mapa los cuenta y ofrece «Organizar con IA» (`organizeAllNow`, que pide miles de una
  vez). Sin temas, el tablero se ve, y el esquema y el grafo lo dicen y llevan a «Vínculos».
  «Ver en el Mapa» es un pedido en un proveedor (`mapLinksFocusRequestProvider`) y no un parámetro
  de la ruta: el Mapa es un destino del shell que sigue vivo, y pedir dos veces el mismo elemento
  tiene que volver a enfocarlo.
- **Un solo «tema»: la dimensión.** El Mapa y el Atlas agrupan por una `TopicDimension`: los temas
  (los espacios), las etiquetas (la categoría de sistema) o cualquier categoría de texto. Viaja por
  el mismo id con que antes viajaba la categoría; los temas tienen uno propio, `kSpacesDimensionId`
  (`@temas`), que no es el de ninguna fila. Así el pedido del mapa, su caché, sus recuerdos de
  comunidades y la caché del Atlas sirven igual, y los repositorios solo cambian de dónde leen: el
  tema de un elemento es `item.space_id`, una columna, sin tabla de asignaciones.
- **Cómo conviven temas y etiquetas en el Atlas**: son dos dimensiones, no un árbol mezclado. Los
  temas son planos y uno por elemento, así que su Atlas es una lista de ramas del primer nivel —con
  los mismos conteos en cascada, cobertura, vacíos, eje de años y notas mapa (las que están en el
  tema)—; la jerarquía vive en las etiquetas, a un toque del selector. Se descartó colgar el árbol
  de etiquetas debajo de cada tema: repetiría las mismas ramas en varios temas, sus conteos ya no
  serían «todo lo de esta rama» y los vacíos se avisarían varias veces. Por defecto se muestran los
  temas si hay alguno —poner un tema al guardar ya ubica el elemento— y si no, las etiquetas; lo
  elegido queda fijo mientras se mira, así un tema que crea la IA no cambia la pantalla de golpe.
  Un tema abre el Explorador parado en él (`?space=`), la línea de tiempo filtrada por él y su
  bibliografía (`sourcesOfSpace`). La IA (F27) sigue ordenando el árbol de etiquetas: sus textos
  ahora lo dicen.
- **«Etiquetas» en la interfaz, «Tema» en la base.** La categoría de sistema se sigue llamando
  «Tema» (`kTemaCategoryName`, `isTema`, `temaDefinitionId`): lo usan búsquedas por nombre, la IA,
  las copias y la fusión, y renombrar una categoría de sistema rompería las bóvedas existentes. La
  interfaz la muestra con `categoryLabel`/`categoryValueLabel` («Etiquetas», «Etiqueta: Roma») y los
  textos del Mapa y el Atlas que dependen de lo que se mira usan un `select` del .arb (temas,
  etiquetas o valores). El editor de propiedades ya no la ofrece: tiene su editor propio. Los
  «subtemas» del vocabulario quedan: nombran lo que cuelga de un valor en cualquier categoría, y los
  temas no tienen.
- **El grafo local del detalle** sube, debajo del panel del elemento: arriba del texto y de las
  tarjetas, a la vista.

### 62. F29: el trabajo sigue con la app cerrada

Pedido del usuario: *"que el contenido se siga descargando o procesando los documentos en segundo
plano si minimizo la app o, si se puede, si la cierro"*. Minimizar ya estaba resuelto (el servicio
en primer plano de cada trabajo largo); este es cerrarla, deslizándola fuera de las recientes. Plan:
`docs/planes/F29-seguir-con-la-app-cerrada.md`, aprobado con la recomendada: las descargas de los
modelos con el gestor del sistema, el procesamiento y la IA siguen mientras Android no mate la app,
y una ayuda para "Inicio automático" y "Sin restricciones". Se descartó un proceso aparte con su
propia copia de la base: mucho más riesgo, y en HyperOS tampoco garantiza nada sin esos dos ajustes.

- **Por qué moría todo al cerrar**: no era solo el `stopSelf()` del servicio en `onTaskRemoved`.
  `FlutterActivity` destruye con ella el motor que crea, y con el motor se iba todo Dart —la cola
  de procesamiento, la transcripción, la IA— aunque el proceso siguiera vivo. Ahora el motor es
  uno por proceso (`SinapsisEngine`, en `FlutterEngineCache`) y la actividad lo usa sin ser su
  dueña: al cerrarla, Dart sigue; al volver a abrir, la actividad nueva se engancha al mismo motor
  con Dart andando —no se vuelve a ejecutar `main`, no se duplica ninguna cola ni estado, la
  pantalla está donde quedó—. Si el proceso murió, no hay motor guardado y todo arranca como
  siempre, retomando desde la base. Los canales (trabajo largo, audio, descargas, ajustes) se
  instalan con el motor y el contexto de la aplicación, porque tienen que funcionar sin
  actividad; lo único que necesita una —pedir permiso para notificar, abrir ajustes— la usa si hay.
  Los plugins con actividad se desenganchan y vuelven a engancharse, que es lo que ya soportan
  (lo compartido desde otra app llega por el stream de `receive_sharing_intent`).
- **El servicio sigue mientras haya trabajo** y se va con `idle`, como siempre; respeta el tope de
  6 horas de Android 15 (`onTimeout`, decisión de F21) y su aviso llega a Dart por el canal del
  motor. No se pide que el sistema lo reviva (`START_NOT_STICKY`): sin la app no hay motor que
  trabaje, y Android 12 en adelante no deja volver a primer plano desde segundo plano. Si HyperOS
  mata el proceso igual, lo pendiente se retoma al abrir.
- **Las descargas de los modelos, con `DownloadManager`** (`SystemModelFileTransfer`, por el canal
  `app.sinapsis/system_downloads`), sin dependencias nuevas. Baja en el proceso del sistema: sigue
  aunque se cierre la app —también si HyperOS la mata—, tras reiniciar el teléfono, espera la red y
  tiene su notificación. Se descartó `background_downloader` (ya viene con `flutter_gemma`): corre
  en el proceso de la app con WorkManager, así que HyperOS lo mata igual, y fue lo que la decisión
  sobre F21 ya había dejado de usar. En el escritorio y en las pruebas sigue
  `InAppModelFileTransfer` (`ResumableDownload`), detrás de la misma interfaz
  (`ModelFileTransfer`), y también en un Android con el gestor deshabilitado.
- **Hugging Face, medido el 2026-10-03**: `resolve/` redirige (302, o 307 relativo) a
  `us.aws.cdn.hf.co` con una dirección firmada que vence en una hora; el CDN acepta rangos, da un
  ETag fuerte (lo que el gestor necesita para retomar: sin ETag no retoma) y respeta `If-Match`, y
  `huggingface.co` con `If-Match` sigue redirigiendo. Por eso al sistema se le da la dirección de
  Hugging Face, no la del CDN: cada vez que retoma pide una firma nueva; con la del CDN, un corte
  después de la hora obligaba a empezar de cero. El token va en `Authorization` en cada salto —el
  gestor no deja elegir— y el CDN lo ignora (comprobado con uno falso); llega solo a dominios de
  Hugging Face. El repositorio del modelo de relaciones está protegido y no se pudo probar con un
  token real en esta máquina.
- **Dónde viven los modelos**: el gestor solo escribe en la carpeta propia de la app en el
  almacenamiento compartido (`Android/data/<app>/files`), no en la interna. Los modelos nuevos van
  ahí; lo que se bajó entero antes en la interna se sigue reconociendo y usando donde está
  (`earlierRoots`), sin moverlo —copiar 3,7 GB pediría el doble de lugar—; lo que quedó a medias
  ahí se borra, porque no se puede seguir desde la carpeta nueva. Se borran con la app, como antes.
- **Reengancharse**: el número de la descarga queda junto al destino (`<destino>.descarga`). Al
  abrir la app (`resumeModelDownloads`) cada pantalla de modelo se engancha a la que sigue, recoge
  la que terminó con la app cerrada —la comprueba, le da su nombre, la instala— o muestra por qué
  falló; tocar "Descargar" dos veces, o abrir la app a mitad, nunca pide otra. Los archivos de un
  modelo (dos del de relaciones, tres de Whisper) se piden a la vez, porque lo que no se pidió no
  sigue con la app cerrada. Cancelar la olvida en el sistema y borra lo bajado —en un modelo de
  varios archivos que no quedó entero, también los que ya habían terminado—; sin lugar, se dice
  cuánto hace falta antes de pedir nada. Con el sistema bajando no se pide el servicio en primer
  plano: sería una segunda notificación para lo mismo. Si no se puede mirar una descarga al abrir,
  el error llega a la telemetría y las otras se enganchan igual; un error del canal del gestor no
  se toma por "no hay gestor".
- **La ayuda "Que siga con la app cerrada"**: en Xiaomi (MIUI, HyperOS, Redmi, POCO) deslizar la
  app la mata salvo con "Inicio automático" y la batería "Sin restricciones", y ninguna app puede
  activarlos sola. Se ofrece una vez —la primera vez que la app vuelve al frente con un trabajo
  largo en curso— y queda en Ajustes › Segundo plano. No cuando el trabajo empieza: el primer
  trabajo largo es también cuando Android pide permiso para notificar, y en el emulador las dos
  preguntas salieron encimadas; el diálogo del sistema saca a la app del frente y al cerrarlo
  aparece la oferta, una después del otro. Abre las pantallas de Xiaomi
  (`AutoStartManagementActivity`, `HiddenAppsConfigActivity` con el paquete) y, si no están o no se
  dejan abrir, la ficha de la app en Android o la lista de optimización de batería, diciendo qué
  tocar —en Android 15 y 16 es "Uso de batería de la app" › "Permitir el uso en segundo plano" ›
  "Sin restricciones", medido en el emulador—. Se abren sin preguntar antes si existen: desde
  Android 11 la app no ve los paquetes de otros. Lo único que se puede leer es la batería de
  Android; "Inicio automático" no lo publica Xiaomi.

Probado en el emulador (Pixel 9 Pro, Android 16, versión release de staging): el modelo de
transcripción, pedido y con la app cerrada desde recientes —el proceso murió—, terminó de bajar
en el sistema; al reabrir, la app lo comprobó, le dio su nombre y olvidó los pedidos sin borrar
nada. Reabierta a mitad, la pantalla mostró la descarga en curso (47 %) y cancelarla dejó la
carpeta vacía. Una transcripción a mitad (57 %) siguió con la app cerrada —la actividad
destruida, el mismo proceso, el servicio con su notificación—, el servicio se soltó solo al
terminar, y al reabrir la actividad se enganchó al mismo motor, sin pedir el PIN, con el texto
completo. Sin probar: un Xiaomi real (las pantallas de MIUI/HyperOS solo se abren ahí), el
reinicio del teléfono a mitad de una descarga, y el modelo de relaciones, cuyo repositorio pide
un token que no había en esta máquina. Los avisos "FlutterJNI.loadLibrary/init called more than
once" del registro son del plugin `large_file_handler`, que crea su propio `FlutterLoader` al
registrarse; pasan con cualquier motor.

## Estado y orden de construcción

### Construido

- Arquitectura por capas, tres flavors con sus equivalentes nativos en
  Android, integración continua que analiza, formatea, prueba, exige 80% de
  cobertura y compila.
- Bóveda local con clave: PBKDF2 en el almacén seguro del sistema, límite de
  intentos con espera creciente, migración de parámetros del KDF sin
  invalidar bóvedas existentes.
- Español e inglés, tema claro y oscuro, manejo de errores de punta a punta y
  telemetría opcional sin datos personales.
- **Fase 1, la fundación de datos.** Las siete tablas con sus cascadas y sus
  restricciones, la búsqueda de texto completo sincronizada por triggers, y
  el repositorio de la biblioteca con guardado atómico, filtros combinables,
  orden por relevancia y streams que se actualizan solos. Probado contra
  SQLite real: un doble respondería lo que se le pida sin ejercitar ninguna
  cascada ni ningún trigger.
- **Fase 2, capturar y leer.** Los adaptadores de nota, enlace web y YouTube;
  el caso de uso de captura como única puerta de entrada; las tres pantallas
  —biblioteca con búsqueda y filtros, captura con reconocimiento en vivo, y
  detalle con la procedencia completa—; y la entrada desde el sistema
  operativo: compartir un enlace o un archivo desde otra app en Android, o
  soltarlo directamente sobre la ventana en web. Los dos casos llevan solos a
  la pantalla de captura, ya cargados, sin que el usuario tenga que ir a
  buscarlos.
- **Fase 4, los documentos.** PDF, EPUB, Word, texto suelto y Markdown, con
  el archivo original guardado fuera de la base y reconocido por sus bytes en
  vez de por su extensión. Un solo transformador para todos los formatos
  —lo único que cambia es cómo se interpretan los bytes— y el selector de
  archivos en la pantalla de captura. Borrar un elemento ahora borra también
  su archivo: el disco no tiene cascadas.
- **Fase 3, las dos transformaciones que más rinden.** Subtítulos de YouTube
  sin clave ni cuota, con título y canal reales; y artículo limpio de páginas
  web en Markdown, con el autor y el sitio. Más la cola que las ejecuta: de a
  uno para no disparar diez descargas a la vez, retomando sola lo que quedó
  pendiente de sesiones anteriores, sin repetir lo que ya está en curso, y sin
  que un enlace roto corte lo que sigue. Lo que falla conserva su enlace y su
  título, y se reintenta a pedido desde el elemento.
- **Fase 5, organizar.** Etiquetas globales con autocompletado, filtro por
  etiqueta en la biblioteca, relaciones tipadas entre elementos —vistas desde
  los dos lados, con el sentido correcto según cuál se esté mirando— y
  resaltados con nota, incrustados en el texto y listados aparte. La bóveda
  deja de ser una pila y pasa a ser una red.
- **Fase 6, exportar.** Markdown con cabecera de procedencia, PDF armado como
  texto corrido con pie de página, y texto plano puro, para cualquier item.
  Página web archivada entera en un solo HTML con sus imágenes y estilos
  incrustados, al modo de SingleFile; el archivo original de un documento se
  abre con la app que el sistema tenga asociada. Paquete completo para
  NotebookLM —los items elegidos más un índice con las fuentes—, armado desde
  el detalle de un item o desde una selección múltiple en la biblioteca.
- **Fase 7, lo pesado.** Reconocimiento de texto en imágenes con Google ML
  Kit. Transcripción de audio y video con Whisper "base" multilingüe,
  corriendo enteramente en el dispositivo: el modelo se descarga aparte, una
  sola vez y con permiso explícito —nunca junto con la app, y nunca en
  silencio— desde una pantalla propia que muestra tamaño y progreso. Las
  llamadas de Whisper son FFI síncronas y bloqueantes, así que corren en un
  isolate aparte para no congelar la interfaz mientras dura una
  transcripción larga. Sin diálogo reconocible —música, silencio, una foto
  sin texto— no es un fallo: el elemento queda listo igual, tal como llegó.
- **Fase 8, la web de verdad.** Base de datos con drift-wasm, CanvasKit
  servido con la propia app en vez de la CDN de Google, almacenamiento de
  archivos sobre OPFS, captura y exportación adaptadas donde la web no
  tiene equivalente nativo, OCR con Tesseract en WebAssembly y
  transcripción con Whisper también en WebAssembly —con un defecto real de
  `sherpa_onnx_web` 1.13.8 encontrado y arreglado en el camino—. Integración
  continua que compila la web en cada cambio, los tres entry points, igual
  que ya hacía con Android. Validado de punta a punta en un Chromium real,
  no solo pieza por pieza: crear la bóveda, guardar una nota, encontrarla
  por búsqueda de texto completo, y que siga estando después de recargar la
  página desde cero. Esa misma validación encontró y corrigió un defecto
  que ninguna prueba unitaria podía ver —`google_fonts` dejaba toda la
  interfaz sin texto visible cuando no podía bajar la tipografía en tiempo
  de ejecución, ver la decisión 12— y confirmó que la Share Extension de
  iOS queda pospuesta a propósito (decisión 7): no hay ningún dispositivo
  iOS de por medio para esta app.
- **Windows, como tercera plataforma real.** El target de escritorio de
  Flutter, con la cadena de herramientas nativa que pide (Modo de
  Desarrollador, Visual Studio Build Tools con ATL, un JDK con cabeceras
  JNI), y `TesseractCliImageTextExtractor` como motor de OCR ahí, sobre el
  Tesseract del sistema en vez de uno bundleado —ver la decisión 15—.
  Compilado y ejecutado de punta a punta en un Windows real, reconociendo
  texto en español e inglés. Sin sincronización propia entre dispositivos
  a propósito (decisión 1): la bóveda de la compu y la del celular son
  independientes, y pasar una a la otra es una operación manual.
- **Copia de seguridad completa de la bóveda.** `VaultBackupService`
  empaqueta la base entera —vía `VACUUM INTO`, consistente sin necesidad de
  cerrar nada— y todos los archivos originales en un `.zip`, y lo
  restaura del otro lado reemplazando ambos —hasta F10; desde F11 lo
  fusiona, ver la decisión 44—. Es el mecanismo manual que
  permite usar la misma bóveda en dos dispositivos —ver la decisión 16—,
  accesible desde el ícono de backup en la biblioteca. Probado contra
  SQLite y un sistema de archivos reales, igual que la fundación de datos
  de la fase 1.
- **Espacios: carpetas para organizar.** Una tabla `Spaces` y una columna
  `spaceId` nullable en `Items` —ver la decisión 17—, con su fila de chips
  en la biblioteca (crear, elegir, renombrar y borrar) y su selector en el
  detalle de cada elemento. Primera migración real del esquema
  (`schemaVersion` 1 → 2): las bóvedas que ya existen suben sin perder
  nada, con todo lo que tenían sin clasificar.
- **Editor de bloques, al estilo Notion.** Encabezados, párrafos, listas
  con viñeta o numeradas, casilleros y citas, cada uno editable,
  reordenable y con su propio tipo —ver la decisión 18—. Ningún cambio de
  esquema: es un `RenditionKind.blocks` nuevo y JSON dentro del `content`
  que ya tenía cada rendition de texto. Accesible desde "Nota con bloques"
  en la captura, y con edición in situ desde el detalle de cualquier
  elemento que ya tenga una.
- **Grafo de relaciones.** La bóveda como una red interactiva —pan y
  zoom—, con un nodo por elemento vinculado y una línea con flecha por
  vínculo, dispuestos con un layout de fuerzas (Fruchterman-Reingold)
  propio y determinístico —ver la decisión 19—. Solo entran los elementos
  con al menos un vínculo puesto; tocar un nodo lleva a su detalle.
- **Preguntarle a la bóveda.** RAG local con `flutter_gemma`: `VaultRetriever`
  encuentra los fragmentos relevantes por búsqueda de texto completo y
  `ChatModel` redacta la respuesta citando de dónde sale cada dato —ver la
  decisión 20—. El modelo (Gemma 3 1B) se descarga aparte, con permiso
  explícito y una pantalla propia que muestra tamaño y progreso.
- **Flashcards con repetición espaciada.** SM-2, el mismo algoritmo de
  Anki, con una pantalla de repaso diario y una insignia en la biblioteca
  que muestra cuántas tocan hoy —ver la decisión 21—. Tarjetas a mano
  desde el detalle de cualquier elemento, o generadas por IA a partir de
  su contenido, siempre con revisión antes de guardarse.
- **Navegación adaptativa.** Biblioteca, Explorador, Grafo, Chat, Repaso y
  una pantalla de Ajustes como los seis destinos principales, cada uno con
  su propio `Navigator` —ver la decisión 22—. `NavigationBar` abajo en
  celular, `NavigationRail` al costado en escritorio, con el mismo punto
  de quiebre que define Material 3. Idioma, tema, modelo de transcripción,
  copia de seguridad y bloqueo de la bóveda —antes nueve íconos amontonados
  en un solo AppBar— quedan agrupados en Ajustes.
- **Enlaces `[[ ]]` en el editor de bloques.** Escribir `[[Título]]` en
  una nota —a mano, o con el botón de enlazar— crea, al guardar, un
  vínculo real hacia ese elemento —ver la decisión 30—, resuelto por
  título contra toda la biblioteca. Reutiliza el mismo `Relations`/Grafo
  que ya existía, no una red de conexiones aparte.
- **Propiedades tipadas.** Categorías con valor —"Época: Siglo I a.C.",
  "Región: Roma"—, junto a las etiquetas de siempre y no en su lugar —ver
  la decisión 31—: un elemento puede tener varios valores bajo la misma
  categoría a la vez, editables desde su propio panel en el detalle, con
  sugerencias de categorías y valores ya usados mientras se escribe uno
  nuevo.
- **El Explorador, de carpetas a filtros.** Lo ya procesado, filtrable
  por tipo, etiqueta y propiedad —ver la decisión 32—, sin ninguna
  carpeta que crear ni mantener a mano: la organización sale sola de lo
  que cada elemento ya tiene puesto.
- **Notas atómicas, extraídas a mano.** Seleccionar un fragmento de
  cualquier forma de texto y elegir "Extraer como nota" en el mismo menú
  de Resaltar/Copiar/Compartir —ver la decisión 33— crea una nota nueva
  con ese fragmento, vinculada al original con el tipo de relación
  `extractedFrom`.
- **F1 del modelo Fuente/Nota: esquema y migración.** Las tablas nuevas
  —ver la decisión 34— conviven con las viejas, con lo ya capturado
  clasificado y fragmentado en chunks con reconstrucción verificada. Sin
  ningún cambio visible todavía: es la base sobre la que se construyen
  las fases siguientes del refactor de organización.
- **F2 del vocabulario controlado: tipo, alias y fusión.** Categorías con
  tipo (texto/número/fecha) y alias que resuelven a un valor real, sobre
  las mismas tablas `PropertyDefinitions`/`PropertyValues` de siempre
  —ver la decisión 35—, con "Tema" y "Fecha del hecho" como categorías de
  sistema sembradas desde el arranque y las etiquetas existentes migradas
  por abajo a valores de propiedad. Sin ningún cambio visible todavía: el
  vocabulario controlado llega antes que su UI.
- **F3 de estados y Bandeja de entrada.** El espejo `item`/`source`/`note`
  ya vivo —F1 lo dejaba solo poblado una vez—, y su primer lector real:
  la Bandeja de entrada, un elemento a la vez, con tres acciones de un
  toque —ver la decisión 36—. Primera superficie visible de todo el
  refactor de organización: un séptimo destino en la navegación
  principal, con insignia de pendientes, y la madurez de una nota
  visible en su detalle.
- **F4 de clasificación asistida: herencia y sugerencias del modelo.**
  Propiedades heredadas al extraer una nota, una quinta interfaz de
  `GemmaChatModel` para sugerir propiedades sobre el vocabulario
  existente, generación automática al terminar de procesar un elemento
  —ver la decisión 37— y la cuarta acción de la Bandeja, "revisar
  sugerencias", cerrando lo que F3 había dejado pendiente. Circuito de a
  un elemento por vez; sugerencias en lote sobre varios a la vez quedan
  para una sub-fase aparte.
- **F5 del motor de relaciones: embeddings, preselección y Tensión.**
  `Suggestion` generalizada a `property`/`relation`, un modelo de
  embeddings propio (`EmbeddingGemma 300M 8-bit`) que se descarga
  aparte, preselección de candidatos por similitud coseno de
  centroides antes de que el LLM juzgue el tipo de vínculo, generación
  automática al procesar una fuente nueva, backfill bajo demanda para
  lo ya capturado, y la pantalla de Tensión —ver la decisión 38—. Los
  embeddings son solo preselección; el diálogo manual del grafo queda
  intacto como vía aparte.
- **F6 del grafo local y notas mapa: panel embebido, pantalla con pan y
  zoom.** Un panel embebido en el detalle de cualquier elemento —fuente
  o nota— con los vecinos directos, y una pantalla completa navegable
  con pan y zoom real a la que se llega tocándolo —ver la decisión 39—.
  Marcar una nota como mapa a mano desde su propio detalle le da tres
  cosas: insignia en la biblioteca y el Explorador, punto de entrada
  preferido al grafo local desde cualquier vecino, y una vista propia
  de sus vínculos agrupada por tipo en vez de la lista cronológica de
  siempre.
- **F7 de deduplicación: hash, simhash y fusión, sin ningún modelo de
  IA.** `content_hash`/`simhash` calculados y persistidos al capturar
  o guardar una nota, un diálogo interactivo que avisa ANTES de
  guardar cuando el texto ya está completo, y una `Suggestion.
  duplicate` pendiente cuando recién se completa después de procesar
  una fuente —ver la decisión 40—. Fusionar conserva un solo elemento
  con las dos renditions de texto —ninguna se pierde—, reasigna
  relaciones, etiquetas, propiedades y tarjetas del descartado, y
  congela su procedencia antes de borrarlo de verdad. Su propia
  pantalla, "Posibles duplicados", con confirmación explícita por
  fila: fusionar es irreversible, así que no entra al diálogo genérico
  de revisión de sugerencias.
- **F8 de higiene: etiquetas unificadas y mantenimiento del
  vocabulario.** Una etiqueta es ahora un valor de la categoría Tema —una
  sola fuente de verdad—, con la interfaz de etiquetas intacta por encima;
  una migración reconcilia lo que F2 dejó separado, con respaldo previo de
  la base. La pantalla de Vocabulario: valores parecidos para fusionar,
  de un solo uso, sin uso, categorías vacías y un explorador por categoría
  con alias, todo reversible —ver la decisión 41—. Primera fase del
  encargo de cierre F8 a F11.
- **F9 de consolidación: salud, línea de tiempo y bandeja como mazo.** Un
  panel de salud al tope de la Biblioteca; los enlaces rotos de toda la
  bóveda con creación en lote; sugerencias de propiedad en lote con deshacer;
  la línea de tiempo sobre "Fecha del hecho" —eje continuo sin salto en el
  cero, imprecisión que se ve, 10.000 hechos con costo proporcional a la
  ventana— con su formulario de fecha; la Bandeja como mazo de tarjetas con
  gestos, teclas y deshacer; la vista de lectura para destilar con el salto al
  fragmento del que salió cada nota; las fuentes citadas de una nota viva y su
  madurez editable; y la distinción visual entre fuente y nota en todas las
  pantallas —ver la decisión 42—. Un cambio de esquema aditivo (v15).
- **F10 de unificación: un solo modelo de datos.** Los chunks se mantienen al
  guardar y la búsqueda de la Biblioteca va sobre ellos y cita el minuto o la
  página; las lecturas, las claves foráneas y la escritura pasan al modelo
  nuevo, y se retiran `Items`, `Sources`, `Tags`, `ItemTags` y `source.fullText`,
  con el texto de una fuente guardado en su forma principal y en sus chunks, no
  en tres lugares. Cuatro cambios de esquema (v16 a v19), cada uno con respaldo
  previo, un plan en seco y conteos como compuerta, y todos los pasos de una
  migración en una sola transacción —cosa que antes no era cierta—. Una
  bóveda de 10.000 elementos migra en 6 s y la búsqueda más lenta tarda 56 ms
  —ver la decisión 43—.
- **F11 de durabilidad: papelera, versión por campo y una restauración que
  fusiona.** Borrar manda a la papelera y se deshace; solo la persona, sobre algo
  que ya estaba ahí, lo borra de verdad. Cada campo de un elemento lleva quién lo
  modificó y cuándo, con el linaje de la edición, y cada instalación tiene su
  identidad de dispositivo. «Restaurar copia» pasó a ser «Traer otra copia»: se ve
  qué traería, se confirma, y una sola transacción une la copia con la bóveda sin
  pisar nada —el texto de una fuente queda intacto—, deja para revisar lo que las
  dos bóvedas modificaron a la vez y se comprueba antes de confirmarse; la app no se
  cierra. Además, el historial de repasos, el tipo de vínculo «indexa», el aviso de
  un tema que se llama como una etiqueta y tarjetas que llevan de vuelta al
  fragmento del que salieron. Un cambio de esquema aditivo (v20). Última fase del
  encargo de cierre F8 a F11 —ver la decisión 44—.

- **F12 de cierre de deuda: cifras de un Android, revisión en lote, compactación
  y copia por tandas.** Se midió en un emulador de Android en modo profile —los
  tiempos dependen de la PC que lo aloja; la memoria, y que el código corre en
  Android, no—, y esa medición encontró lo que ninguna cifra de escritorio
  mostraba: la línea de tiempo con diez mil hechos se dibuja ahora en un solo
  lienzo, y la búsqueda de una palabra en casi todo se pide desde una cota en
  vez de ordenar el índice de FTS5 (640 ms a 44). La revisión en lote de
  sugerencias se ofrece desde la tarjeta de la Bandeja, con deshacer en bloque.
  La bóveda se compacta —una pantalla en Ajustes y una oferta única— sin subir
  la memoria (`VACUUM` con `temp_store = FILE`). La copia se arma, se guarda, se
  elige y se abre por tandas, en los dos sentidos, con el CRC de cada entrada
  verificado. Cada commit compila y analiza por sí solo
  (`tool/verify_commit.ps1`). Sin cambios de esquema. Primera fase del encargo
  F12–F17 —ver la decisión 45—.

- **F13 de jerarquía temática y Atlas: un vocabulario en árbol y un índice de
  lo que se sabe.** Los valores del vocabulario cuelgan unos de otros, hasta
  cinco niveles, con los ciclos impedidos en la propia base; filtrar por un tema
  trae lo de sus subtemas; el vocabulario se ve y se reordena como árbol, con la
  sugerencia de poner «Roma republicana» bajo «Roma»; y la fusión de bóvedas
  trae la jerarquía. El Atlas —destino de primer nivel, con la barra del celular
  reducida a cinco más un «Más»— muestra por tema cuántas fuentes y notas hay
  debajo, cuánto está trabajado, qué años cubre, sus notas mapa y los vacíos, y
  se exporta como Markdown. Medirlo mostró que abría en 3,9 s: se rehízo y abre
  en 124 ms en el emulador. La consulta transitiva se resolvió con una CTE, no
  con un cierre materializado: tardan lo mismo. Un cambio de esquema aditivo
  (v21). Segunda fase del encargo F12–F17 —ver la decisión 46—.

- **F14 del mapa de conocimiento: una pestaña «Mapa» con un tablero, un esquema
  y un grafo de temas.** El mapa se calcula en otro isolate, por lotes y en
  caliente, y se actualiza solo: las comunidades de temas conservan su identidad
  y su color al recalcular, y el grafo nunca dibuja miles de nodos —comunidades,
  temas y elementos según el zoom—. Comparte filtros con la biblioteca, parte de
  un tema o de una nota mapa y se exporta como PNG o SVG. Reemplaza al grafo
  completo, que cargaba todos los elementos; agregar un vínculo, las sugerencias
  con IA y el filtro por tema se mudaron a él. Se midió en un emulador con 10.000
  elementos y 2.000 temas, y la medición encontró tres cosas —un generador sin
  estructura, un nivel de temas demasiado caro de dibujar y un arrastre que
  subía de nivel—; el criterio de fluidez NO se cumple en el emulador salvo en
  el nivel de elementos y queda dicho. Sin cambios de esquema. Tercera fase del
  encargo F12–F17 —ver la decisión 47—.
- **F15 de biblioteca académica: metadatos completos, cinco estilos de cita, y
  BibTeX/RIS en los dos sentidos.** Autores como vocabulario —se fusionan y
  renombran como cualquier valor—, con orden y rol propios
  (`source_contributor`). Cita copiable en APA 7, MLA 9, Chicago (notas y
  autor-fecha) e IEEE, con los huecos marcados en vez de inventados;
  bibliografía de un espacio, una rama del Atlas, una nota o una selección.
  BibTeX y RIS entran y salen: identidad por DOI/ISBN/URL, reimportar no
  duplica, los duplicados difusos se proponen y nunca se fusionan solos, un
  PDF se vincula por su nombre. Un cambio de esquema aditivo (v22). Cuarta
  fase del encargo F12–F17 —ver la decisión 48—. Medir encontró que importar
  miles de entradas de golpe paga el mismo costo por entrada que cualquier
  guardado normal de la app: queda como límite conocido, sin camino rápido
  para un lote grande.
- **F16 de cuadernos, consulta enfocada y vistas: un subconjunto con nombre
  para el chat, cuatro derivados anclados a su fuente, y vistas y plantillas
  guardadas.** Un `Notebook` —manual o por consulta guardada— acota el chat a
  un subconjunto sin exigir que cada elemento viva en un solo lugar, y sirve
  como buscador acotado incluso sin el modelo de lenguaje descargado.
  `DerivedNoteGenerator` propone una guía de estudio, preguntas abiertas, un
  esquema o una cronología desde un cuaderno o un elemento; cada afirmación se
  ancla con `RelationKind.extractedFrom` a un fragmento real de su fuente —lo
  que no se pueda anclar textual no se escribe—, y el derivado nace como una
  nota nueva, marcada con el modelo y la fecha, nunca reemplazando el
  original. Vistas guardadas (filtro + modo + orden, fijables en la
  navegación) y plantillas de nota (bloques y propiedades precargados)
  completan lo que faltaba de Notion. Un cambio de esquema aditivo, en cuatro
  pasos (v23 a v26): `saved_view`/`note_template`, `notebook`/`notebook_item`,
  `conversations.notebook_id`, y la marca de generado en `note`. Quinta fase
  del encargo F12–F17 —ver la decisión 49—. Medir encontró que resolver el
  alcance de un cuaderno armaba cada elemento entero solo para sacarle el id:
  se corrigió antes de cerrar la fase.
- **F17 de Anki y hábito: exportar completo a un `.apkg` que organiza por subdecks, con la
  procedencia en el reverso, exportación incremental y TSV/CSV como camino alternativo; y una
  racha, insignias e historial que premian destilar y consolidar, nunca capturar, con un
  interruptor único que apaga los tres de una vez.** `AnkiPackageBuilder` ya armaba el `.apkg`
  clásico desde antes; F17 completó lo que faltaba. La racha junta cuatro orígenes —repasar,
  editar una nota viva, extraer una nota atómica, y una tabla nueva (`habit_event`) para triar la
  Bandeja y resolver Vocabulario, que no tenían dónde leerse—. De las seis insignias, «una
  contradicción resuelta» reusa `relations.reviewed_at` (ya existía desde F9) y «un tema completo
  de punta a punta» se resuelve con un recorrido en Dart, no una consulta por rama. El interruptor
  de Ajustes no mantiene ningún estado de pausa: apagado, solo deja de mostrarse. Un cambio de
  esquema aditivo en dos pasos (v27/v28). Sexta y última fase del encargo F12–F17 —ver la decisión
  50—. Los dos criterios de cierre que dependen de Anki real —importar limpio, reimportar sin
  duplicar— quedan sin verificar: ni Anki de escritorio ni AnkiDroid están instalados en esta
  máquina, y verificarlo a mano queda pendiente. Con esto se cierra el encargo F12–F17 entero.
- **F18 del Mapa de conocimiento: medir antes de rediseñar.** Las cifras que fallaron al cerrar F14
  ya salían de un generador con jerarquía, no plano, pero agrupaban por rama de primer nivel entera
  en vez de por sub-rama; agrupar más fino bajó el p90 de raster del nivel de temas de ~18–28 ms a
  ~16 ms, y el caché de rasterizado durante el gesto (18.2) bajó los cuadros fuera de presupuesto de
  entre 32 % y 43 % a entre 1,2 % y 18,1 % según el escenario, con el tope de 300 temas visibles
  intacto. Primera fase del encargo F18–F20 —ver la decisión 51—. No todos los escenarios entran
  todavía bajo el 5 % estricto: queda como mejora real y medida, no como cierre completo del
  criterio de F14.
- **F19 de modo lote transaccional: `withSuspendedSearchIndexes` suspende el índice de texto
  acotado a lo tocado, no la bóveda entera.** Cierra el límite que dejó F15 —importar miles de
  referencias, o traer una copia entera con `mergeBackup`, pagaba el costo de un guardado normal
  por fila—. La primera versión rehacía el índice ENTERO al cerrar cualquier lote y eso midió PEOR
  que antes de F19 (64 s contra ~20 s); corregida para acotarse a los elementos tocados, importar
  5.000 referencias volvió a los ~20 s de antes en escritorio y bajó a 4,5 s en el emulador, y
  `mergeBackup` a una bóveda vacía bajó de 68,2 s a 59,7 s. Segunda fase del encargo F18–F20 —ver la
  decisión 52—. Dos puntos del plan quedan sin construir, investigados y señalados: ni la
  aceptación de sugerencias en lote ni la fusión de duplicados tienen hoy un llamador que se
  beneficie del modo lote.
- **F20 de quizzes generados y anclados: opción múltiple con distractores reales, nunca
  inventados.** El modelo solo propone pregunta y respuesta; los distractores salen de la bóveda
  real —hermanos del Atlas, el otro lado de un `contradicts`, cercanía por embedding, en ese
  orden—, cada uno anclado a su propio chunk. Revisión obligatoria antes de guardar, integrada a la
  programación SM-2, con una sesión suelta que cuenta para la racha sin tocarla, y un segundo tipo
  de nota de Anki para exportarla. Tercera y última fase del encargo F18–F20 —ver la decisión 53—.
  Solo la entrada desde un elemento; nunca degrada a verdadero/falso, se descarta en vez de
  inventar. Con esto el encargo F18–F20 queda CERRADO entero.
- **F21 de procesamiento confiable y rápido.** Nada queda "Procesando" para siempre: lo
  interrumpido se retoma, lo colgado vence, borrar cancela y la cola no se frena. Dos carriles,
  corto y largo, con avance visible y el motivo real de cada fallo. Libros de cientos de páginas y
  videos de horas: nada entero en memoria, las páginas escaneadas y los tramos de audio se guardan
  a medida que salen (esquema v31) y se retoman, con un servicio en primer plano en Android. El
  audio de YouTube, solo a pedido. Ver la decisión 54.
- **F22 de fidelidad del texto.** Lo que se guarda es el original, carácter por carácter: los
  lectores de PDF, Word, EPUB, web, texto plano y YouTube dejaron de unir, borrar, escapar y
  traducir; la búsqueda encuentra las palabras cortadas por guion desde un índice derivado. La
  transcripción, cortada en pausas, con protección contra bucles, en el idioma elegido y con la
  frecuencia real del audio (el conversor de antes lo estiraba al doble). YouTube sin subtítulos se
  transcribe por su audio. Copiar del PDF funciona, y "Volver a extraer el texto" rehace lo viejo
  conservando los subrayados (esquema v32). Ver la decisión 55.
- **F23, el texto sigue al audio.** Mientras suena, la palabra que se dice se ve en amarillo, con
  tiempos medidos por Whisper (60 ms de error mediano) y guardados junto al texto (esquema v33);
  un mini reproductor flotante para pausar o volver a lo que suena sin subir. Ver la decisión 56.
- **F24, el audio de cada video.** El de YouTube se baja solo en la mejor calidad y se escucha
  debajo de su vista previa; TikTok y reels transcriben lo dicho; todo video tiene debajo un
  reproductor solo de audio. Ver la decisión 57.
- **F25, el lector flotante.** Un botón abajo a la derecha, en las pantallas con texto, lee en voz
  alta con pausa real, ±10 s de habla medidos, voz, acento y velocidad, y la línea que lee en
  amarillo; el menú de selección, limpio y en el orden pedido. Ver la decisión 58.
- **F26, el panel de la fuente.** Los botones entre la vista previa y el texto, en un solo panel
  con cuatro mosaicos; el tema se elige al guardar y se filtra; exportar en PDF o Word. Ver la
  decisión 59.
- **F27, la IA organiza sola.** Vínculos, tarjetas, temas, propiedades, el tema de cada elemento,
  la referencia y el Atlas, en segundo plano; todo marcado, editable y reversible, con "Para
  revisar" y "Lo que hizo la IA". Ver la decisión 60.
- **F29, que siga con la app cerrada.** Las descargas de los modelos, con el gestor del sistema;
  el procesamiento y la IA, en un motor que sobrevive a la actividad; y una ayuda para "Inicio
  automático" y la batería en Xiaomi. Ver la decisión 62.

### Por construir

Las ocho fases originales están construidas, probadas y documentadas.
Android y la web —las dos plataformas reales de quien construye esta
app, sin ningún dispositivo iOS de por medio— funcionan a fondo.

El refactor de la capa de organización (ver la decisión 34) llegó a
F1-F7, y su encargo de cierre (F8 a F11) está completo: F8 —la higiene del
vocabulario, ver la decisión 41—, F9 —la consolidación, ver la decisión 42—,
F10 —la unificación del modelo de datos, ver la decisión 43— y F11 —la
durabilidad: papelera, versión por campo y fusión no destructiva, ver la
decisión 44—.

Después vino un segundo encargo, F12 a F17. F12 —el cierre de deuda: cifras de
un Android, compactación y copia por tandas, ver la decisión 45—, F13 —la
jerarquía temática y el Atlas, ver la decisión 46—, F14 —el mapa de
conocimiento, ver la decisión 47—, F15 —la biblioteca académica, ver la
decisión 48—, F16 —cuadernos, derivados marcados y vistas, ver la decisión
49— y F17 —Anki y hábito, ver la decisión 50— están construidas. Con esto
el encargo F12–F17 queda CERRADO entero. F14 se cerró con una excepción
dicha: en el emulador el dibujo del mapa no cumple el presupuesto de un
cuadro salvo en el nivel de elementos, y arreglarlo pide decidir entre
dibujar menos temas a la vez o rediseñar cómo se dibuja el grafo. F15 se
cerró con otra: importar miles de entradas de golpe paga el mismo costo por
entrada que cualquier guardado normal de la app, y bajarlo de verdad pide
suspender el índice de texto durante el lote y rearmarlo al final, un
rediseño del escritor único sobre datos reales que queda para una fase
futura. F17 se cerró con dos: los dos criterios de cierre que dependen de
Anki real —importar limpio, reimportar sin duplicar— quedan sin verificar
(commit 6, BLOQUEADO, sin Anki ni AnkiDroid instalados en esta máquina), y
ninguno de los cuatro objetivos de rendimiento que el propio plan proponía
para 17.2 se midió en Android —el plan ya aprobado no incluía ese paso—.

Lo que queda son las cosas que las decisiones 44 a 50 dicen, sin adornos,
que no hacen: una sincronización que no dependa de traer una copia a mano,
lápidas para lo que se une por conjuntos, la medición en un teléfono real
—todo F12 a F17 midió, cuando midió, en un emulador—, un camino rápido para
importar un lote grande de referencias, y la verificación a mano en Anki y
AnkiDroid reales que F17 dejó pendiente. Ninguna está planeada; se planean
—plan breve, aprobado, después código— cuando le toquen.

Después vino un tercer encargo, F18 a F20, que cierra dos de esas cosas
—el criterio de fluidez del Mapa que dejó F14, el límite de importar un
lote grande que dejó F15— y agrega una función: quizzes generados por IA,
anclados a chunks reales, integrados a la programación espaciada. F18 —el
Mapa, ver la decisión 51— está construida, con una mejora real y medida
pero sin cerrar del todo el criterio estricto de F14 en cada escenario.
F19 —modo lote transaccional, ver la decisión 52— también está construida:
corrigió una regresión real que su propia primera versión introdujo, y
midió mejoras reales en la importación de referencias y en `mergeBackup`.
F20 —quizzes generados y anclados, ver la decisión 53— también está
construida: preguntas de opción múltiple con distractores reales de la
bóveda, nunca inventados, revisadas antes de guardar e integradas a SM-2,
con una sesión suelta que cuenta para la racha y un segundo tipo de nota
de Anki para exportarlas —solo desde un elemento, nunca degrada a
verdadero/falso—. Con esto el encargo F18–F20 queda CERRADO entero.
