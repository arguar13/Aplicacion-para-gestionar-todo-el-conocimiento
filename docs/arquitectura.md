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
| `WebArticleTransformer` | HTML → artículo en Markdown | [`reader_mode`](https://pub.dev/packages/reader_mode) (Readability de Mozilla) + [`html2md`](https://pub.dev/packages/html2md) | Dispositivo | Construido |
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
`ItemTags` quedaron marcadas obsoletas en el código: las retira F10.

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

**Lo que F8 no hace.** No retira `Tags`/`ItemTags` (F10). No hay panel de
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
`Items` como `Relations`: F10 las repunta juntas.

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
el modelo viejo sigue de fuente de verdad: unificarlo, y retirar `Tags`/`ItemTags`
y el espejo, es F10; el borrado suave y la fusión no destructiva al restaurar son
F11.

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
  restaura del otro lado reemplazando ambos. Es el mecanismo manual que
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

### Por construir

Las ocho fases originales están construidas, probadas y documentadas.
Android y la web —las dos plataformas reales de quien construye esta
app, sin ningún dispositivo iOS de por medio— funcionan a fondo.

El refactor de la capa de organización (ver la decisión 34) llegó a
F1-F7, y su encargo de cierre (F8 a F11) va en orden estricto: F8 —la
higiene del vocabulario, ver la decisión 41— y F9 —la consolidación, ver la
decisión 42— están construidas. Quedan F10 (unificar el modelo de datos:
retirar el modelo viejo y el espejo, y con ellos `Tags`/`ItemTags`) y F11
(durabilidad: borrado suave con papelera, versionado por campo, fusión no
destructiva al restaurar). Cada una se planea —plan breve, aprobado, después
código— cuando le toca.
