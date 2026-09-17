# Sinapsis

Un gestor de conocimiento multi-fuente. Todo lo que leés, mirás y escuchás
en un solo lugar, convertido en texto que podés buscar, relacionar y llevarte
—sin perder de dónde salió.

Funciona enteramente en tu dispositivo. Sin cuenta, sin servidor, sin
suscripción.

---

## El problema

El conocimiento que vale la pena llega en formatos que no se hablan entre sí
y desde lugares que no dejan sacarlo: un reel sin transcripción, un hilo de X
que mañana puede no estar, un short con una idea de treinta segundos, un PDF
de trescientas páginas, una página que en seis meses da 404.

La respuesta habitual es una pila de herramientas sueltas —una para bajar
subtítulos, otra para transcribir audio, otra para limpiar páginas, otra para
guardar recortes, otra para tomar notas— cada una con su cuenta, su límite
gratuito y su formato propio. El trabajo de pegarlas queda del lado de uno, se
hace a mano cada vez, y lo guardado termina desperdigado entre cinco servicios
que no se conocen.

Sinapsis hace ese trabajo: recibe cualquier cosa, la convierte en texto
buscable, conserva el rastro de su origen y la conecta con el resto.

## Cómo funciona

```
  CAPTURA            TRANSFORMACIÓN          ORGANIZACIÓN          SALIDA
                                                              
  compartir     →    audio → texto      →   categorías     →   Markdown
  pegar enlace       imagen → texto         etiquetas          PDF
  soltar archivo     página → artículo      relaciones         texto plano
  escribir           PDF/EPUB → texto       búsqueda           HTML original
                     video → transcripción  filtros            NotebookLM
                                                              
  ───────────────────────────────────────────────────────────────────────
  La procedencia viaja con el contenido en todo el recorrido: enlace
  original, autor, perfil, fecha de captura y copia del formato de origen.
```

Nada se pierde en la conversión. Si era un video de YouTube, queda la
transcripción **y** el enlace. Si era un tweet, el texto **y** el perfil de
quien lo escribió. Si era una página, el artículo limpio **y** una copia de la
página tal como estaba el día que la guardaste.

## Qué acepta, y en qué lo convierte

| Entra | Sale |
|---|---|
| Video o short de YouTube | Transcripción, con marcas de tiempo y enlace |
| Reel, TikTok, nota de voz, podcast | Transcripción del audio (Whisper, en el dispositivo) |
| Captura de pantalla, foto de un libro | El texto de la imagen (OCR), con la imagen al lado |
| Publicación de X, Bluesky, Mastodon | Texto, autor, enlace al perfil y a la publicación |
| Artículo o página web | Artículo limpio, sin banners, y copia del original |
| PDF, EPUB, DOCX | Texto con su estructura, capítulos e imágenes |
| Un apunte propio | Texto, igual que todo lo demás |

Y de ahí sale en el formato que quieras: Markdown, PDF, texto plano, HTML, o
empaquetado para llevarlo a NotebookLM.

## Las herramientas que reemplaza

El plan inicial de este proyecto era encadenar a mano DownSub, SingleFile,
Glasp, PrintFriendly, TurboScribe, Whisper y Notion. Casi ninguna tiene API
pública gratuita, así que integrarlas significaría scraping frágil o cuentas
de pago. Pero la capacidad de cada una es replicable con librerías de código
abierto, y así queda mejor: sin cuentas, sin cuotas, sin conexión, y sin
romperse cuando un servicio cambia su HTML.

| Herramienta | En su lugar |
|---|---|
| DownSub | `youtube_explode_dart` — subtítulos sin API key ni cuotas |
| Whisper | Integrado de verdad, corriendo en el dispositivo |
| TurboScribe | Cubierto por lo anterior |
| SingleFile | Su enfoque: HTML con los recursos incrustados en un solo archivo |
| PrintFriendly | Readability de Mozilla, más generación de PDF |
| Glasp | Resaltados propios — es el núcleo de la app, no un anexo |
| NotebookLM | No tiene API pública (solo Enterprise, de pago). Se exporta en el formato que mejor ingiere y se abre el notebook |

## Estado

La base está construida y verificada. El producto, no todavía.

**Listo**

- Arquitectura por capas, con tres flavors (dev / staging / prod) y sus
  equivalentes nativos en Android.
- Bóveda local protegida con clave: PBKDF2 en el almacén seguro del sistema,
  límite de intentos con espera creciente, y migración de parámetros del KDF
  sin invalidar bóvedas existentes.
- Español e inglés, tema claro y oscuro, ambos recordados entre arranques.
- Manejo de errores de punta a punta: captura de fallos no manejados,
  telemetría opcional sin datos personales, y mensajes traducidos por tipo.
- Integración continua que analiza, formatea, prueba, exige 80% de cobertura
  y compila los tres flavors de Android.
- La fundación de datos: siete tablas con sus cascadas y restricciones,
  búsqueda de texto completo con FTS5 sincronizada por triggers, y el
  repositorio de la biblioteca con filtros, orden, paginación y streams que
  se actualizan solos. Probado contra SQLite real, no contra dobles.
- **Capturar y leer.** Pegás un enlace o escribís una nota y la app reconoce
  sola de qué se trata —YouTube, página web, apunte propio— y lo guarda con
  su procedencia. También entra compartiendo desde otra app —el botón de
  compartir del teléfono, en Android— o soltando un archivo sobre la
  ventana, en la versión web. La biblioteca lista todo con búsqueda por
  contenido, filtros por tipo y orden por relevancia, y se actualiza sola
  cuando entra algo nuevo. El detalle muestra el contenido junto a de dónde
  salió.
- **Las dos transformaciones que más rinden.** Pegás un enlace de YouTube y
  aparece la transcripción con sus marcas de tiempo, el título real y el
  canal — sin clave de API, sin cuotas y sin abrir otra página. Pegás una
  página web y queda el artículo limpio en Markdown, sin menús ni avisos, con
  su autor y su sitio. Las trae una cola que trabaja de a uno para no
  disparar diez descargas a la vez, retoma sola lo que quedó pendiente de
  otras sesiones y sigue con lo que viene aunque un enlace se caiga. Lo que
  falla conserva su enlace y se reintenta con un botón.

- **Documentos.** Elegís un PDF, un EPUB, un Word, un `.txt` o un `.md` y
  queda su texto, con el título y el autor que traiga adentro — y el archivo
  original guardado aparte, porque en un documento el archivo *es* la fuente
  y no hay ningún enlace al que volver. El formato se reconoce por los bytes
  y no por la extensión, así que un PDF renombrado sigue siendo un PDF.

- **Organizar.** Etiquetas con autocompletado —escribir el nombre de una que
  ya existe reutiliza esa, no crea una segunda— y filtro por etiqueta en la
  biblioteca, al lado del filtro por tipo. Espacios: carpetas donde cada
  elemento vive en una sola a la vez, para separar por proyecto o por tema
  sin que compita con las etiquetas, que se combinan. Vínculos tipados entre
  elementos (relacionado, continúa, contradice, cita, resume), visibles
  desde los dos lados con el sentido de la frase correcto según cuál se esté
  mirando. Resaltados con nota sobre cualquier texto, incrustados en el
  propio contenido y listados aparte para repasar sin releer todo.

- **Notas con bloques.** Encabezados, párrafos, listas con viñeta o
  numeradas, casilleros y citas, cada uno con su tipo, editable y
  reordenable — el mismo estilo de armar una nota que Notion. Se abre desde
  "Nota con bloques" en la pantalla de captura, y se edita in situ desde el
  detalle de cualquier elemento que ya tenga una.

- **Grafo de relaciones.** Toda la bóveda como una red que se recorre con
  pan y zoom: un nodo por cada elemento vinculado, conectados por los
  mismos vínculos que ya se arman a mano en el detalle. Tocar un nodo lleva
  directo a ese elemento.

- **Preguntarle a la bóveda.** Escribís una pregunta y la app busca qué
  elementos guardados se relacionan, con un fragmento de cada uno. Con el
  modelo de lenguaje descargado —Gemma, corriendo en el dispositivo,
  gratis y sin conexión, igual que Whisper— además redacta una respuesta
  que cita esas mismas fuentes. Sin él, ya sirve como buscador: nada obliga
  a bajar el modelo para empezar a usarlo. Funciona igual en Android y en
  Windows. El repositorio de Gemma en Hugging Face pide una cuenta
  gratuita antes de dejar bajar el archivo: la pantalla de descarga
  explica los dos pasos (aceptar la licencia y generar un token) y guarda
  el token para la próxima vez.

- **Flashcards con repetición espaciada.** El mismo algoritmo de Anki
  (SM-2): cada tarjeta vuelve a aparecer justo antes de que se te olvide,
  cada vez más espaciada si la recordás bien. Las cargás a mano desde el
  detalle de cualquier elemento, o le pedís al modelo de lenguaje que
  proponga preguntas y respuestas a partir del contenido — siempre las
  revisás antes de que se guarden. Una insignia en la navegación avisa
  cuántas tocan repasar hoy.

- **Navegación por pestañas, ajustes en un solo lugar.** Biblioteca, grafo,
  chat, repaso y ajustes tienen cada uno su propio ícono en una barra
  (celular) o un riel (ventana ancha en Windows), en vez de competir por
  espacio en un solo AppBar. Idioma, tema, modelo de transcripción, copia
  de seguridad y bloqueo de la bóveda viven juntos en Ajustes.

- **Exportar.** Sacás cualquier item en Markdown con su procedencia, en PDF
  o en texto plano. Si vino de una página web, también como un HTML con todo
  incrustado en un solo archivo, igual que SingleFile —para leerla el día
  que la original ya no exista—. Un documento abre con la app que el sistema
  tenga asociada, sin pasar por Sinapsis. Y para llevarte varios a NotebookLM
  de una, un paquete con los archivos que mejor ingiere y un índice con las
  fuentes, armado desde el detalle o eligiendo varios en la biblioteca.

- **Transcribir y reconocer texto.** Una foto, una captura de pantalla o el
  cartel de una calle: el texto que tengan adentro queda reconocido en el
  propio dispositivo —Google ML Kit en Android, Tesseract en WebAssembly en
  la web—. Una nota de voz, un podcast o un video: transcriptos con Whisper,
  también corriendo enteramente en el dispositivo en las dos plataformas,
  sin mandar el audio a ningún lado. El modelo pesa unos 375 MB y no viene
  con la app —se descarga aparte, una sola vez, con tu permiso explícito y
  mostrando el progreso—. Nada de esto bloquea la interfaz mientras trabaja.

- **Windows.** La misma app corre en escritorio, con reconocimiento de
  texto en imágenes sobre el Tesseract instalado en el sistema —Google ML
  Kit no tiene versión de escritorio—. La bóveda de la compu y la del
  celular son independientes a propósito: no hay sincronización automática,
  se pasa una a la otra a mano cuando hace falta, con el botón de copia de
  seguridad de la biblioteca.

**Por construir**

Las ocho fases planeadas están completas: Android y la web —las dos
plataformas reales de quien construye esta app, sin ningún dispositivo iOS
de por medio— funcionan a fondo, cada una probada de punta a punta. Windows
se sumó después como tercera plataforma real. No queda ninguna fase nueva
planeada. El detalle de cada decisión está en
[`docs/arquitectura.md`](docs/arquitectura.md).

## Correr el proyecto

Requiere [Flutter](https://docs.flutter.dev/get-started/install) 3.47.2 o
posterior.

```bash
flutter pub get

# El código generado no se versiona: hay que producirlo antes de la
# primera compilación, o `flutter analyze` falla al no poder resolver los
# `part 'x.freezed.dart'`.
dart run build_runner build --delete-conflicting-outputs
flutter gen-l10n

flutter run --flavor dev -t lib/main_dev.dart
```

En Android, los tres flavors conviven instalados a la vez con nombres e
íconos propios (`app.sinapsis.dev`, `.staging`, y `app.sinapsis` para
producción). En iOS la configuración está preparada pero falta un paso manual
en Xcode: ver [`ios/Flutter/flavors/README.md`](ios/Flutter/flavors/README.md).

### Lo que corre el pipeline

Antes de subir un cambio conviene pasar lo mismo que va a pasar el CI:

```bash
dart format --output=none --set-exit-if-changed .
flutter analyze
flutter test --coverage
```

Cero advertencias toleradas — `analysis_options.yaml` usa
`very_good_analysis` con `strict-casts`, `strict-inference` y
`strict-raw-types`.

## Estructura

```
lib/
├── app/          Arranque, router y manejo global de errores
├── core/         Compartido: diseño, red, errores, registro, telemetría, i18n
└── features/     Un módulo por funcionalidad, en tres capas
    ├── vault/        Bóveda local: crear y desbloquear
    ├── capture/      Reconocer y guardar lo que entra
    └── library/      Listar, buscar, filtrar y ver el detalle
```

La regla de dependencia dentro de cada feature apunta hacia adentro:
`presentation → domain ← data`. El dominio no importa nada de las otras dos.
`core` no importa nada de `features`. Las convenciones completas están en
[`lib/features/README.md`](lib/features/README.md).

## Privacidad

Lo que entra a Sinapsis no sale del dispositivo. No hay servidor propio al que
mandarlo, y la app no pide cuenta.

Las únicas conexiones salientes son las que pedís vos: descargar la página que
querés archivar, los subtítulos del video que guardaste. El procesamiento
—transcribir, reconocer texto, extraer— ocurre localmente.

El reporte de errores es opcional, viene apagado, y solo se enciende con un
DSN configurado en tiempo de compilación. Nunca incluye contenido de la
bóveda: únicamente el error, su traza y un identificador interno.
