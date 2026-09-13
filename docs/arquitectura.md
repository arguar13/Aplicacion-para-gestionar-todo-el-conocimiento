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

### 8. Whisper "base" multilingüe, traído aparte y con permiso explícito

Transcribir voz en el dispositivo, sin mandar audio a ningún servidor, es
justamente lo que pide el principio 1 — pero exige tres decisiones propias
que no se resuelven solas.

**Qué tamaño de modelo.** [`sherpa_onnx`](https://pub.dev/packages/sherpa_onnx)
(Apache 2.0) corre Whisper en el dispositivo vía FFI, y ofrece varios
tamaños ya exportados a ONNX. Se eligió "base" multilingüe —unos 160 MB
entre encoder, decoder y vocabulario, cuantizados a int8— en vez de "tiny"
—bastante más chico—: en español, que es el idioma principal de quien usa
esta app, "tiny" pierde precisión de forma notoria, y "base" sigue siendo
liviano para lo que es un modelo de reconocimiento de voz. Los tres
archivos se traen sueltos de Hugging Face (el repositorio de quien mantiene
`sherpa-onnx`), no el paquete `.tar.bz2` de sus releases de GitHub: es la
misma fuente, sin tener que descomprimir bzip2 en el dispositivo.

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

**Cuándo se descarga.** 160 MB es demasiado para bajarlos solos la primera
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

**Lo que tienen en común los cinco.** Ninguno lo iba a encontrar
`flutter analyze` ni una prueba con un doble: el primero necesitaba HTML
de una página real con años de historia; el segundo, un permiso de
Android real, mal otorgado; el tercero, una transcripción más larga que
una pantalla; el cuarto, leer el mismo botón en dos contextos distintos
de la misma pantalla; el quinto, una carpeta real de Android con reglas
de almacenamiento propias. Es la razón concreta detrás de "nunca des algo
por probado si se puede probar de verdad": los cinco pasaron
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

---

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

### Por construir

Las ocho fases están construidas, probadas y documentadas. Android y la
web —las dos plataformas reales de quien construye esta app, sin ningún
dispositivo iOS de por medio— funcionan a fondo: no queda ninguna fase
nueva planeada, solo lo de siempre entre una fase y la próxima que aparezca
—una migración de esquema, un paquete que sube de versión, un detalle que
una prueba nueva encuentre—.
