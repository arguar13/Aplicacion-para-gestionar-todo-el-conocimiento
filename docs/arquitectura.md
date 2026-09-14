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

### Por construir

Las ocho fases están construidas, probadas y documentadas. Android y la
web —las dos plataformas reales de quien construye esta app, sin ningún
dispositivo iOS de por medio— funcionan a fondo: no queda ninguna fase
nueva planeada, solo lo de siempre entre una fase y la próxima que aparezca
—una migración de esquema, un paquete que sube de versión, un detalle que
una prueba nueva encuentre—.
