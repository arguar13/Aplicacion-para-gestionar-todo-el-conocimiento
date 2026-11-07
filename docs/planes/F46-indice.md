# F46 — El Índice: lo procesado, con sus capítulos, como el índice automático de Word

> **Estado: CONSTRUIDO** el 2026-11-06: los cinco pasos, con la decisión 92 y la suite entera en el
> cierre conjunto con F44, F45 y F47 (15.430 pruebas pasan, 0 fallas). La medición en el emulador y
> la APK quedan para la sesión principal.
>
> **Aprobado** el 2026-10-30 («Aprobado» en el chat), con las decisiones A a F como están. Pedido del dueño, el 30/10: *"agregar en la pestaña de Estudiar,
> debajo de la sección de Procesado, una nueva sección llamada Índice … algo parecido a cuando yo
> hago en Word … un índice dinámico"*. Ajustes del mismo día:
>
> - solo los **documentos** (una página web o un libro, en cualquier formato), sacados de
>   **Procesado**;
> - si un documento es solo texto o imágenes, el **texto completo** o el **título de las
>   imágenes**;
> - **nunca** un resumen, una síntesis ni palabras clave;
> - que respete **la jerarquía, los nombres, los títulos y los temas**, y que sea dinámico,
>   elegante e interactivo, con cientos o miles de documentos.
>
> Se construye **después de F44 y F45**. Usa dos cosas de F45: los títulos que la IA marca al triar
> un PDF (decisión B) y el lector único del texto (mejora 12), que es donde se abre cada entrada.

## La idea

En Word, un texto con «Título 1», «Título 2» y «Título 3» genera un índice con sus páginas exactas,
que se actualiza con un toque. **El Índice hace eso con toda la biblioteca procesada, y sin el
toque**:

- cada documento procesado, con sus capítulos y subcapítulos en su orden y su nivel;
- agrupado por los temas, en su árbol;
- cada entrada lleva a su lugar exacto;
- se arma y se corrige solo cuando algo llega a Procesado, se renombra, se edita, se vuelve a
  triar o se borra.

## De dónde sale cada entrada

Solo de la sección **Texto** de cada documento procesado y de sus **Imágenes**. Del resumen, la
síntesis, las palabras clave, las notas y los fragmentos no sale nada.

| Lo que es | De dónde salen sus capítulos | Qué número lleva |
|---|---|---|
| **Word, EPUB, página web, Markdown o texto con títulos** | los títulos del texto (`#`, `##`, `###`…), que la extracción ya guarda | la página del texto procesado («pág. 3») |
| **PDF con marcadores** | sus marcadores, el índice que trae el propio PDF, con sus niveles | **la página real del PDF** («p. 47») |
| **PDF sin marcadores** | los títulos que la IA marcó al ordenar el texto al triar (F45, decisión B), comprobados palabra por palabra | la página del PDF donde cae |
| **Un texto sin títulos** (una transcripción, una nota larga, un artículo plano) | una sola entrada, **«Texto completo»**, que abre el texto desde el principio | — |
| **Solo imágenes** | una entrada por imagen, con **su título** | su lugar en la galería |

- **Los niveles se respetan tal cual**, solo corridos para que el primero sea el 1: un documento que
  empieza en `###` no queda colgando.
- **Lo que no es un título no entra**: un `#` dentro de un bloque de código, un título vacío o los
  encabezados repetidos de cada página (que la decisión B de F45 ya saca).
- **El título de una imagen** es el que traía la fuente: el texto alternativo o el epígrafe de la
  página web o del libro. Si no traía ninguno, el nombre de su archivo, limpio («Mapa del Imperio
  romano», no `mapa_imperio-romano_02.jpg`). Se puede renombrar con un toque largo, y el Índice se
  actualiza.

## Cómo se ve

En **Estudiar**, debajo de **Procesado**, un destino nuevo, **Índice**, con su ícono de lista
numerada.

**Arriba:**

- el buscador, **«Buscá un capítulo»**: filtra mientras se escribe, sin acentos ni mayúsculas, y
  **conserva la jerarquía**: un capítulo que coincide se ve con su documento y su tema arriba, y lo
  buscado resaltado;
- **«Por tema · Por documento»**:
  - **por tema** (lo primero): el árbol de los temas, como en el Atlas, con sus documentos y los
    capítulos de cada uno. Un documento con dos temas está en los dos y dice «también en
    Roma». Los que no tienen tema van al final, en **«Sin tema»**;
  - **por documento**: todos de la A a la Z, o los más recientes primero;
- **«Niveles: 1 · 2 · 3 · Todo»**, como en Word: hasta qué profundidad se despliega todo de una
  vez. Además, cada fila se abre y se cierra sola.

**Cada fila, con tipografía de índice de libro:**

- un **tema**: su nombre, en versalitas y con su color, y cuántos documentos tiene;
- un **documento**: su ícono de tipo (PDF, libro, web), el título en serif y, a la derecha,
  cuántos capítulos tiene;
- un **capítulo**:
  - su sangría por nivel, con una línea guía fina que une a los hermanos;
  - la numeración opcional («1», «1.2», «1.2.3»), que se prende y se apaga;
  - **la línea de puntos hasta la página**, como en Word: «El Concilio de Nicea ……… p. 47»;
- **«Nuevo»**: un punto discreto durante siete días en lo que llegó a Procesado.

**Mientras se desplaza:** el tema y el documento quedan fijos arriba mientras se recorren sus
capítulos, así nunca se pierde de qué libro es lo que se ve.

**En una pantalla ancha (la computadora, una tableta apaisada):** dos paneles, el Índice a la
izquierda y el documento a la derecha. Tocar un capítulo lo abre al lado, sin dejar el Índice.

**Cuando algo cambia:**

- lo que llega aparece en su lugar, con un brillo suave;
- lo borrado se va;
- lo renombrado cambia;
- todo sin perder lo que se tenía desplegado ni la posición.

Con «sin animaciones», sin brillo.

## Qué se hace con una entrada

- **Tocar**: abre el texto del documento en el lector único (F45, mejora 12) **justo en ese
  título**, que se resalta un momento. En el teléfono, «atrás» vuelve al Índice donde estaba.
- **Mantener apretado**:
  - «Abrir en el original»: el PDF en esa página, o la página web en ese título;
  - «Preguntar al chat»: una conversación sobre ese capítulo, con su texto;
  - «Copiar el título»;
  - en una imagen, «Renombrar».
- **«Descargar el índice»** (⋮ de arriba): el índice que se está mirando, con los filtros y los
  niveles elegidos, en **PDF** (con los puntos y las páginas, listo para imprimir) o en
  **Markdown**.

## Escalable: miles de documentos sin esperar

- **Una tabla propia, `processed_headings`**, derivada: documento, nivel, título, título sin
  acentos para buscar, su lugar (la parte, la página y la posición) y su orden. Un libro de 300
  capítulos son 300 filas; mil libros, 300.000 filas, poco para SQLite.
- **Se escribe en la misma operación que el texto**: cuando se guarda, se edita, se vuelve a triar
  o se borra la sección Texto de un documento, se rehacen sus filas en la misma transacción, **y
  solo las de ese documento**. Así el Índice nunca queda atrasado ni a medias. Al borrar el
  documento, se van con él.
- **Lo que no se guarda dos veces:** el nombre de un documento y sus temas se leen de donde ya
  están. Renombrar o cambiar de tema se ve al instante, sin tocar `processed_headings`.
- **Lo que ya está procesado** se indexa una vez, al actualizar la app, **por tandas y en segundo
  plano**, con un punto de retome (si se cierra la app, sigue desde ahí). Mientras tanto, el Índice
  muestra lo que ya tiene y una línea con cómo va.
- **La pantalla nunca trae todo:**
  - el árbol se arma de a lo que se ve: los temas con sus cuentas en una sola lectura, y los
    capítulos de un documento solo al desplegarlo;
  - la búsqueda va por un índice de texto (FTS5) y devuelve las coincidencias con sus padres;
  - la lista se dibuja de a lo que entra en la pantalla.
- **Nada se le pide a la IA ni a internet** para armarlo: sale todo de lo que ya está guardado. La
  IA solo interviene antes, al triar un PDF sin marcadores (F45, decisión B).

## Decisiones (se pueden cambiar mientras no se llegue a su paso)

- **A. Un destino propio, «Índice», en Estudiar, justo debajo de Procesado.** *Alternativa:* una
  pestaña dentro de Procesado. No la recomiendo: el Índice recorre todo, y adentro de Procesado
  quedaría escondido detrás de la lista.
- **B. Un PDF usa primero sus marcadores** (los puso el autor y traen la página real), y si no
  tiene, los títulos que marcó la IA al triar.
- **C. Cada capítulo lleva su número de página**: la real en un PDF y la del texto procesado en
  los demás (la misma «Página 3 de 6» del lector). En Word también es la página del texto que se
  está mirando.
- **D. Un documento con varios temas aparece bajo cada uno**, marcado «también en…».
  *Alternativa:* solo bajo el primero. No la recomiendo: el que lo busca por el otro tema no lo
  encontraría.
- **E. Las imágenes guardan su título** (una columna nueva en `processed_images`), sacado de la
  fuente al triar y editable. Las que ya están toman el nombre de su archivo, limpio.
- **F. El Índice es derivado**: se puede borrar y rehacer entero desde Procesado sin perder nada,
  y de la Biblioteca no se toca nada (la regla de siempre).

## Pasos (cada uno, su commit y su push)

**Ola 1, tres agentes en paralelo:**

1. **Los títulos** (decisiones B y E):
   - el lector puro de títulos de un texto, con sus niveles corridos y lo que no es un título
     afuera;
   - los marcadores de un PDF (`loadOutline` de `pdfrx_engine`, que ya está), ubicados en el
     texto;
   - el título de cada imagen al triar.
2. **Los datos** (decisión F):
   - `processed_headings` y la columna de las imágenes, con su migración;
   - la escritura en la misma transacción que el texto;
   - el relleno por tandas de lo que ya está, con su punto de retome;
   - las consultas del árbol, de un documento y de la búsqueda, con pruebas de escala (2.000
     documentos y 300.000 títulos) y `EXPLAIN QUERY PLAN`.
3. **La pantalla**, sobre un falso de los datos: el destino, el árbol por tema y por documento,
   los niveles, el buscador, las filas con los puntos y la página, lo fijo arriba, los dos paneles,
   «Nuevo» y lo que cambia en vivo.

**Ola 2:**

4. **Ir al lugar exacto** (decisión C): abrir en el lector único en ese título, abrir en el
   original en esa página, el toque largo («Preguntar al chat», «Copiar», «Renombrar») y
   «Descargar el índice» en PDF y Markdown.
5. **El cierre**: la decisión 92 en arquitectura, la GUÍA, la suite entera, la medición en el
   emulador con una bóveda grande y la APK al teléfono si la pedís.

## Lo que no entra (para que quede dicho)

- El resumen, la síntesis, las palabras clave, las notas y los fragmentos: el Índice es de los
  documentos.
- Lo que está solo en la Biblioteca, sin procesar: el Índice sale de Procesado.
- Los audios y los videos sin texto: entran por su transcripción, como «Texto completo».
- Inventar capítulos: si un documento no tiene títulos ni marcadores, es una sola entrada.

## Avance

### Paso 1 (hecho): los títulos

Once commits, de `8fd767da` a `c5e66535`, y el de este avance (decisiones B y E). Son piezas
puras y probadas, listas para que el paso 2 las guarde: no hay esquema nuevo ni nada que se vea.

- **El título de un documento procesado** (`ProcessedHeading`): su orden, su nivel corrido, el
  título como se lee, de dónde sale (`ProcessedHeadingOrigin`: un marcador, un título del texto,
  uno de la IA o «Texto completo»), su tramo en el texto procesado, la página del texto y la del
  PDF.
- **El lector de títulos de un Markdown** (`markdownHeadings`), el texto que guardan una página
  web, un Word, un EPUB, un `.md` o una nota:
  - los `#` (con hasta tres espacios adelante y sin los `#` que cierran) y los subrayados con
    `===` y `---`;
  - afuera: el código entre cercas o con cuatro espacios, las citas, las listas y lo que tiene su
    sangría, las tablas, el HTML hasta el renglón en blanco, el encabezado de datos de un `.md`,
    la negrita suelta, `#etiqueta`, siete `#` y los títulos vacíos o de solo signos;
  - el título se lee sin las marcas: los enlaces por su texto, las imágenes por su texto
    alternativo, sin énfasis, código, etiquetas ni llamadas a notas, con lo escapado y las
    entidades como lo que escriben (`plainHeadingText`).
- **Los títulos que deja la IA en un PDF sin marcadores** (`isolatedTitles`). La IA no los marca
  con `#`: la instrucción de ordenar (F45, decisión B) le pide no escribir Markdown, para que el
  texto se compruebe palabra por palabra. Los deja solos en su renglón, entre dos en blanco, y
  esa forma es la que se reconoce:
  - un solo renglón corto (hasta 15 palabras y 120 caracteres), que empieza con mayúscula, un
    número, `¿`, `¡` o comillas y no termina como una oración (punto, coma, punto y coma, dos
    puntos, puntos suspensivos o guion de corte);
  - lo de antes cerró: el comienzo del texto, otro título o un párrafo que termina una oración;
  - lo de después existe y no empieza en minúscula, como seguiría una oración partida;
  - no es un número de página, una viñeta, una marca de tiempo ni la raya de página, y no es un
    encabezado o un pie que se repite en el borde de las páginas (`TidyMargins`);
  - el nivel sale de la numeración («1.2.3 El origen» es 3); sin numeración, todos van en 1;
  - si más de la mitad de los bloques serían títulos (y son más de ocho), ninguno: es un poema
    o un PDF con un renglón en blanco entre renglón y renglón, y queda «Texto completo».
- **Los marcadores de un PDF** (`PdfiumOutlineReader`, con `loadOutline` de `pdfrx_engine`):
  cuántas páginas tiene y su árbol aplanado en el orden en que se lee (`flattenPdfOutline`), con
  la profundidad, el título limpio (`cleanBookmarkTitle`) y la página de cada uno. Abre el
  archivo como el que saca el texto: `openPdfDocument`, que salió de `PdfParser` para no
  repetir la carga directa de 64 MB.
- **Los marcadores ubicados en el texto** (`locateBookmarks`):
  - el título escrito como renglones enteros —uno, o hasta tres seguidos— y comparado sin
    mayúsculas, acentos ni puntuación (`headingKey`). Una mención en medio de un párrafo o un
    renglón del índice del libro con su página al lado no cuentan;
  - si el texto todavía tiene una raya por página (`pdfPageSlicesBySeparator`), en su página y
    solo ahí. Si no está, queda con su página y sin lugar, y no se busca en otra, que sería el
    índice del libro o una mención;
  - sin esas rayas, o un marcador sin página, entre sus vecinos ya ubicados, de atrás para
    adelante: cada uno en el último lugar antes del que sigue, así el índice del libro, que va
    antes del cuerpo, no se lleva ninguno.
- **Lo que junta todo** (`readProcessedHeadings`), según la clase de texto (`processedTextKindOf`):
  - Markdown, sus títulos; un PDF, sus marcadores, y si no trae (o no dicen nada), los de la IA;
  - un texto tal cual (una transcripción, una foto, un `.txt`), o cualquiera sin títulos, una
    sola entrada, «Texto completo», que abre el texto desde el principio;
  - sin texto, ninguna: el Índice sale de la sección «Texto».
- **El título de cada imagen** (`processedImageTitle`, `sourceImageTitles`):
  - el pie de foto, el texto alternativo o el título bajo el que está en la página, y si
    ninguno dice nada, el nombre del archivo, limpio (`imageTitleFromFileName`);
  - no dice nada lo vacío, lo que es solo signos, una dirección o una palabra de relleno
    («imagen», «foto», «image»). Un texto alternativo que es un nombre de archivo se limpia como
    tal;
  - el nombre, limpio: sin carpeta, extensión, guiones ni guiones bajos, sin lo que pone la
    cámara o el teléfono adelante (`IMG_`, `DSC`, `PXL_`, «Captura de pantalla … a las …»,
    «WhatsApp Image … at …», la fecha, la hora, un hash) y sin lo que agrega la página o la copia
    atrás (`-1024x768`, `@2x`, `-scaled`, «(1)», «copia»). Un año se queda («Colón 1492»), y una
    palabra común que dice algo también («Foto de mi abuela»);
  - una imagen ahora sabe de qué dirección se bajó (`SourceImage.originUrl`, de
    `renditions.origin_url`): con eso se la encuentra en el texto de la página
    (`headingsAboveImages`), por su dirección o, si no, por el nombre de su archivo cuando hay
    uno solo con ese nombre.

**Decisiones, con su porqué:**

- **La página del texto es la de sus páginas guardadas** (`processed_parts`, de
  `kProcessedTextPageChars`): la misma «Página 3 de 6» del lector y el mismo «Texto · 6
  páginas» del documento, porque son las mismas páginas. Se cuenta sobre las páginas como
  están, no volviendo a partir el texto: una página editada o quitada sigue contando como es.
- **El lugar es un tramo del texto procesado**: las páginas de «Texto» una detrás de la otra,
  sin nada entre ellas (`joinProcessedParts`), que es el texto propio que lee el lector único.
  En un `#` es el texto sin las marcas; en un subrayado, su párrafo; en un marcador, sus
  renglones. Con eso el paso 4 abre justo ahí y lo resalta.
- **Los niveles se corren por el árbol, no por el ranking** (`runningLevels`): cada título
  cuelga del último anterior con un nivel menor y queda uno más abajo. Un `#` seguido de un
  `###` da 1 y 2 aunque en otro lado haya `##`, y nunca queda un nieto sin padre. Contar los
  niveles usados (`#`, `##`, `####` → 1, 2, 3) dejaba saltos cuando un capítulo no usa uno.
- **Un título partido en renglones del mismo nivel es uno solo**: la extracción de un Word o de
  una página escribe así un título con un salto adentro (F22), y separa los títulos distintos
  con un renglón en blanco.
- **Dos números de página**: `textPage` siempre que está en el texto, y `pdfPage` en un PDF. La
  pantalla muestra «p. 47» con la del PDF y «pág. 3» sin ella. Un título de la IA lleva la del
  PDF solo si el texto todavía tiene una raya por página: si la IA o una edición las sacaron,
  no se adivina.
- **«Texto completo» no tiene título guardado** (`title` vacío): su nombre lo pone la pantalla en
  su idioma.
- **Sin texto no hay entradas, aunque el PDF traiga marcadores**: el plan dice que el Índice sale
  de la sección «Texto».
- **El título de las imágenes que ya están**: la decisión E dice «el nombre de su archivo», pero
  muchas ya guardan su texto alternativo (`renditions.title`, lo que se bajó con la página). Ese
  es de la fuente, así que va primero, y el nombre del archivo después.

**La interfaz para el paso 2:**

- `lib/features/processed/domain/entities/processed_heading.dart`:
  - `ProcessedHeading {int order; int level; String title; ProcessedHeadingOrigin origin;
    int? start; int? end; int? textPage; int? pdfPage; bool get located}` →
    `processed_headings`: `order` es el orden en el documento, `start` y `end` van juntos y
    `textPage` está si y solo si `start` está. Un marcador no ubicado tiene los tres en `null`;
  - `enum ProcessedHeadingOrigin { bookmark, textHeading, aiTitle, wholeText }`, que se guarda
    por su nombre;
  - `PdfBookmark {String title; int depth; int? page}` y `PdfOutline {int pageCount;
    List<PdfBookmark> bookmarks}`.
- `lib/features/processed/domain/services/headings/processed_headings.dart`:
  - `List<ProcessedHeading> readProcessedHeadings(ProcessedHeadingsSource source)`, pura y
    lineal, que puede ir a otro hilo con `runProcessedWork` (sus datos viajan tal cual);
  - `ProcessedHeadingsSource({required List<String> pages, required ProcessedTextKind kind,
    PdfOutline? pdf})`: `pages` son las páginas de «Texto» en orden de `position`;
  - `ProcessedTextKind processedTextKindOf({required bool markdown, String? originalFileName})`:
    `markdown` es `processedTextIsMarkdown(db, id)` y el nombre es el del archivo de la fuente o
    de la copia del original;
  - `String cleanBookmarkTitle(String)`.
- `lib/features/processed/domain/services/headings/pdf_outline_reader.dart`:
  `PdfOutlineReader.read(DocumentSource) → Future<PdfOutline>`, que lanza
  `UnreadableDocumentException`. En la app es `PdfiumOutlineReader`
  (`lib/features/processed/data/services/`), por `pdfOutlineReaderProvider`
  (`lib/features/processed/presentation/providers/pdf_outline_providers.dart`).
- **Cómo se usa al escribir**: el PDF se lee **antes** de la transacción, porque es un archivo y
  PDFium. Si no se puede, se pasa `pdf: null` y valen los títulos de la IA. Después, adentro de
  la transacción, `readProcessedHeadings` con las páginas que se guardan. Cuando se edita una
  página, los marcadores son los mismos: no hace falta volver a leer el archivo si se los tiene,
  pero sí rehacer las filas, porque los lugares se corren.
- **Buscar**: `headingKey` es la forma sin acentos ni puntuación con que se comparan los títulos.
  Para la columna de búsqueda conviene la misma, o el plegado del FTS5 (`remove_diacritics 2`),
  que da lo mismo en letras.
- **El título de las imágenes al triar**
  (`lib/features/processed/domain/services/processed_image_title.dart`):
  - se engancha en `applyProcessedImagesPlan` (`processed_images_store.dart`), en el
    `case NewImage(:final source)`, que hoy guarda `title: source.title` en la forma de la copia;
  - antes del bucle, `final titles = sourceImageTitles(plan.fresh, sourceTitle: <título de la
    fuente>, sourceMarkdown: <su texto, si es Markdown>)`, y cada imagen nueva va con
    `titles[source.path]` a la columna nueva;
  - el texto de la fuente se lee en el repositorio, como ya lee `_textOf`;
  - no se enganchó ahora porque el único lugar donde guardarlo es la forma de la copia, que ya
    muestra la galería: habría cambiado lo que se ve antes de que exista la columna editable.
- **El relleno de las imágenes que ya están**: `processedImageTitle(ImageTitleClues(alt:
  rendition.title, fileName: row.sourceFilePath))`. `null` quiere decir que nada dice nada, y la
  pantalla la nombra por su lugar («Imagen 3»).

**Archivos:**

- Nuevos: `processed_heading.dart` (entidad); `domain/services/headings/`: `heading_text.dart`,
  `markdown_headings.dart`, `isolated_titles.dart`, `bookmark_locator.dart`,
  `processed_headings.dart` y `pdf_outline_reader.dart`; `processed_image_title.dart`;
  `data/services/pdfium_outline_reader.dart`; y `pdf_outline_providers.dart`.
- Cambian: `pdf_parser.dart` (`openPdfDocument`), `processed_image.dart` (`originUrl`) y
  `source_images_reader.dart` (lee `origin_url`).
- Pruebas: cinco archivos nuevos en `test/features/processed/domain/services/headings/`, más
  `processed_image_title_test.dart` y `data/services/pdfium_outline_reader_test.dart`, y una
  prueba más en `source_images_reader_test.dart`.

**Verificado:**

- analyze en 19;
- 126 pruebas nuevas, con los casos borde de a uno: títulos repetidos, vacíos, con numeración,
  en mayúsculas, subrayados, dentro de código, con saltos de nivel y textos sin títulos. Las del
  PDF abren un libro de verdad hecho con el paquete `pdf` en PDFium: sus marcadores con tildes,
  sin marcadores, un archivo que no es un PDF, y los marcadores ubicados en el texto que saca
  `PdfParser`, después del índice del libro;
- escala, medida por crecimiento y no por tiempo: con ocho veces más títulos (de 1.500 a 12.000)
  tarda menos de veinte veces más, lejos de las 64 de lo cuadrático. Se mide en los cuatro
  caminos: los títulos de un Markdown, los marcadores en su página, los marcadores sin rayas de
  página y los títulos de la IA;
- murieron las 37 mutaciones, todas por pruebas que fallan. Dos sobrevivieron la primera vez
  y murieron con su prueba nueva: la tabla subrayada con una raya y el marcador buscado en la
  página que sigue a la suya. Una tercera mostró código que no decidía nada (dónde termina el
  tramo de una página del PDF), que salió, y la que la reemplaza también murió. Entre las
  demás: un hermano del mismo nivel que se anida, dos títulos de distinto nivel que se unen,
  cuatro espacios que no son código, una cerca más corta que cierra el código, lo de una
  lista o de un HTML que se lee, la mitad justa de títulos que ya es sospechosa, un marcador
  que no está en su página buscado en otra, el primer lugar entre vecinos en vez del último,
  un título al comienzo de una página contado en la anterior, el texto alternativo antes que
  el pie, un año que se va del nombre y los hijos de un marcador a su misma profundidad;
- las 886 pruebas de `test/features/processed` y de los lectores de documentos
  (`test/features/transform/data/documents`), con PDFium, y después de los últimos cambios las
  326 de `processed/domain/services` y `processed/data`;
- commit a commit (`verify_commit`, el 6/11): los once commits de código dan 19.

**Queda abierto:**

- **Lo que la IA no deja con su forma.** Un título que la IA dejó pegado a su párrafo, o uno en
  un texto que no se ordenó y viene cortado en renglones, no se reconoce. La regla prefiere
  perder un título a inventar uno. Que la IA los marcara con su nivel pediría cambiar la
  instrucción de ordenar y la comprobación de F45, y mostrar ese Markdown en un PDF, que hoy se
  lee tal cual: es otra decisión, no de este paso.
- **Un PDF cuyas rayas de página ya no están**: sus marcadores se ubican entre vecinos y la
  página del PDF de un título de la IA queda sin decir. Si un encabezado que se repite quedó
  igual a un título, puede tomar su lugar dentro de su capítulo.
- **El título cercano de una imagen** se busca por su dirección o por el nombre de su archivo.
  Si la página la mostraba con otra dirección y otro nombre (una versión más chica de
  `srcset`), no se encuentra y vale el nombre del archivo.
- **Un HTML de bloque en medio de un párrafo** (`<div>` sin un renglón en blanco antes) se lee
  como parte del párrafo: CommonMark lo cortaría. La extracción de la app no lo escribe así.
- No se miró en el emulador ni en el teléfono: no hay nada que se vea.

### Paso 2 (hecho): los datos

Seis commits, de `a96061f5` a `6efc9f43`, y el de este avance (decisión F, y la E en la
base). El Índice tiene sus datos: el esquema v51, la escritura
con el texto, el relleno de lo que ya estaba y las consultas que va a leer la pantalla. No hay
nada que se vea: la pantalla es del paso 3.

- **El esquema v51** (`processed_headings`, `processed_images.title`):
  - `processed_headings`, una fila por entrada: `row_key` (la clave del índice de texto),
    `document_id` (se va con el documento), `origin` (`IndexEntryOrigin`: `bookmark`,
    `textHeading`, `aiTitle`, `wholeText` —los cuatro de `ProcessedHeadingOrigin`, con el mismo
    nombre— e `image`), `level`, `position` (el `order` del paso 1; en una imagen, su lugar en
    la galería), `title`, `text_start`, `text_end` y `text_page` (los tres juntos o ninguno),
    `pdf_page` e `image_id` (se va con la imagen);
  - sus reglas, en la base: el tramo y su página juntos; páginas desde 1; una imagen sin nada
    del texto y con nivel 1; un capítulo siempre con título; «Texto completo» sin título y en
    el nivel 1;
  - `idx_processed_headings_document` (documento, lugar, origen, nivel): las entradas de un
    documento en su orden, sus cuentas, su estado y los padres de lo que se busca salen del
    índice, sin volver a la tabla;
  - `processed_heading_search`, un FTS5 de contenido externo sobre el título, sin mayúsculas ni
    acentos (`remove_diacritics 2`), como `processed_part_search`: no hace falta guardar el
    título dos veces, plegado;
  - `processed_images.title`: el título de la imagen. `null` es «todavía sin titular» y vacío es
    «la fuente no dice nada» (la pantalla dice «Imagen 3»); nunca con espacios en los bordes. Lo
    encuentra el índice parcial `idx_processed_images_untitled`, vacío pasado el relleno;
  - la migración 50→51 solo agrega, con los conteos de todo lo demás como compuerta: la tabla
    nace vacía y las imágenes, sin titular. Leer títulos y limpiar nombres es Dart, y no tiene
    por qué demorar la apertura: lo hace el relleno.
- **Lo que la base hace sola** (`processed_heading_triggers.dart`):
  - cualquier escritura que cambie lo que produce los títulos de un documento —una página de
    «Texto» (su texto, su orden, su lugar o su ancla) o la copia de su original— **suelta sus
    entradas de texto en la misma sentencia**. Así «sin indexar» es exactamente «tiene texto y
    ninguna entrada de texto», y nunca se ven capítulos de un texto que ya no es ese, venga la
    escritura de donde venga: el repositorio, la unión de bóvedas, la papelera del contenido o
    la reubicación de las anclas;
  - cada imagen ya titulada tiene su entrada, que sigue su título y su lugar y se va con ella.
- **La escritura con el texto** (`ProcessedHeadingsIndexer`):
  - el repositorio de Procesado la llama en la misma transacción que guarda o rehace el texto:
    al triar, deshacer, corregir, quitar o devolver una página. Rehace solo las de ese
    documento, y solo si quedó sin indexar;
  - **el PDF se lee antes de la transacción** (`prepare`): el de la copia del original —también
    la que está por entrar al triar, o la que vuelve al deshacer— o, si no tiene, el de su
    fuente, que solo se lee. Lo leído se recuerda por archivo (los originales no se reescriben:
    otro archivo es otra ruta), así que corregir una página de un libro no lo vuelve a abrir;
  - un PDF que no se puede leer vale sin marcadores (los títulos de la IA). Una falla que no es
    del archivo, o PDFium que no responde en 20 s, no se recuerda: el documento queda para el
    relleno;
  - si el lector falla, el texto se guarda igual y el documento queda sin indexar. Un documento
    con texto siempre termina con al menos una entrada: un texto en blanco tiene su «Texto
    completo» aunque el lector no devuelva nada;
  - lo que devuelve el lector pasa por `settleHeadings`: los `assert` de `ProcessedHeading` no
    corren en la app, y la base nunca recibe algo que rompa sus reglas.
- **El título de las imágenes al triar**: `applyProcessedImagesPlan` guarda el de
  `sourceImageTitles` —el título de la fuente como pie de foto de su propio archivo, el texto
  alternativo y, si su texto es Markdown, el título bajo el que está—. La galería muestra el
  suyo; la papelera del contenido lo guarda (`imageTitle`) y lo devuelve, también renombrado.
- **El relleno** (`ProcessedHeadingsBackfill` y `ProcessedHeadingsBackfillKeeper`):
  - titula las imágenes sin titular (`processedImageTitle` con su texto alternativo y su
    archivo) y después indexa los documentos sin indexar, los vivos y los más recientes primero,
    uno por transacción y devolviéndole el turno a la interfaz entre uno y otro;
  - **el punto de retome es la base misma**: lo que falta es lo que la base dice que falta, sin
    un cursor aparte que pueda mentir —una copia restaurada, una unión—. Es idempotente;
  - lo que falla se saltea en ese relleno, sin vueltas sin fin, y se reintenta al abrir la app;
  - `rebuildAll` borra el Índice entero y lo deja para rehacer: las entradas de las imágenes
    vuelven en el acto, y los documentos, en la pasada siguiente. De la Biblioteca no toca nada;
  - lo hace correr `ProcessedHeadingsBackfillKeeper`, que se lee al abrirse la bóveda
    (`App`, en `lib/app/app.dart`) y mira la base: corre cuando algo queda sin indexar sin que
    nadie lo rehaga
    —lo que trae la unión, lo que devuelve la papelera del contenido—.
- **Las consultas** (`IndexRepository`, `index_query_sql.dart`), todas streams en vivo y sin lo
  de la papelera:
  - `watchTopics`: los temas con cuántos documentos del Índice tienen —con texto o con
    imágenes— y «Sin tema» al final, en una lectura;
  - `watchDocumentsOf(tema)` y `watchDocuments(orden)`: cada fila con su título, tipo, fecha
    («Nuevo»), cuántos capítulos e imágenes, si ya está indexado y todos sus temas
    (`IndexDocument.alsoIn`, decisión D);
  - `watchEntries(documento)`: sus capítulos —o «Texto completo»— y después sus imágenes;
  - `watchSearch(texto)`: por el índice de texto, las mejores coincidencias en el orden del
    Índice, cada una con su documento, sus temas y los capítulos que la contienen (una cadena
    recursiva que va hacia atrás por el índice);
  - `watchProgress`: cuántos documentos hay, cuántos están indexados y cuántas imágenes falta
    titular;
  - `renameImage`: cambia el título de una imagen y su entrada, y toca el documento;
  - de la A a la Z sin mayúsculas ni acentos, con la ñ después de la n (`indexSortKey`).

**Decisiones, con su porqué:**

- **Una tabla para todas las entradas, también las imágenes.** El árbol, las cuentas y la
  búsqueda van por un solo lugar. El título de la imagen vive en `processed_images` y su
  entrada lo copia por un trigger: no hay dos que escribir.
- **Los triggers que sueltan y el indexador que rehace.** Escribir los títulos es Dart y no se
  puede hacer desde un trigger; soltarlos, sí. Con los dos, lo que escribe el repositorio queda
  al día en su transacción, y lo que escribe cualquier otro camino queda «sin indexar» —nunca
  viejo— hasta que el relleno lo rehace, enseguida.
- **La unión no copia las entradas**: son derivadas, y las de la copia valen para su texto y su
  PDF. Lo que entra queda sin indexar y se rehace acá. El título de las imágenes sí viaja, con
  ellas (de una que las dos tienen queda el de acá, como su lugar).
- **`null` y vacío en el título de una imagen**: «sin titular» es lo único que el relleno tiene
  que hacer; «no dice nada» es un resultado, que no se vuelve a calcular.
- **El indexador va en Procesado** (`features/processed/data/services/`), junto al lector del
  paso 1; el Índice (`features/index/`) tiene las consultas y lo que lee la pantalla. Así no hay
  un ciclo entre las dos.

**Los puertos para el paso 1, conectados:**

- `HeadingsExtractor.headingsOf(ProcessedHeadingsSource) → Future<List<ProcessedHeading>>`
  (`processed/domain/services/headings/headings_extractor.dart`): no lee la base ni archivos;
  en la app es `ReadingHeadingsExtractor`, que corre `readProcessedHeadings` con
  `runProcessedWork`. Las pruebas usan `FakeHeadingsExtractor`.
- `PdfOutlineReader` (`pdfOutlineReaderProvider`): lo llama `prepare`, antes de la transacción.
  Las pruebas, y `LibraryHarness`, usan `FakePdfOutlineReader`: el PDFium de la app espera un
  plugin que en una prueba no existe, y colgaba las de pantalla que tocan un PDF.
- Las imágenes usan las funciones puras del paso 1 directamente: `sourceImageTitles` al triar
  y `processedImageTitle` en el relleno.

**Los censos:**

- `VaultCounts.processedHeadingTables`, y un censo nuevo (`vault_counts_census_test.dart`): toda
  tabla del esquema está en un grupo de `VaultCounts` o dice por qué no.
- La unión: `kProcessedImageColumns` con `title` (su censo de columnas), y en las guardas
  (`MergeGates._referencing`) `processed_headings`. Un censo nuevo
  (`merge_references_census_test.dart`) exige que toda tabla con claves foráneas esté ahí o
  diga por qué no: mostró que la unión escribía `item_spaces`, `flashcard_options` y
  `content_trash` sin que las guardas las miraran, y ahora las miran.
- `MergeGates._neverShrink` no la tiene, a propósito: es derivada y se rehace.
- La copia de seguridad copia la base entera; la bóveda sintética aparta y devuelve sus
  triggers (`synthetic_vault_test`); el borrado en cascada se la lleva con el documento o con
  la imagen, con su índice de texto.
- `repoint_item_references_v18` no aplica: la tabla nace en v51 y no cuelga de `item`.
- `IndexEntryOrigin` y `ProcessedHeadingOrigin` tienen los mismos nombres
  (`index_entry_origin_test.dart`).

**Archivos:**

- Nuevos: `tables/processed_headings.dart`, `processed_heading_triggers.dart` e
  `index_entry_origin.dart` (en `core`); `headings_extractor.dart` y `settle_headings.dart` (en
  `processed/domain/services/headings/`); `processed_headings_indexer.dart`,
  `processed_headings_backfill.dart` y `processed_headings_backfill_keeper.dart` (en
  `processed/data/services/`); `processed_headings_providers.dart`; y en `features/index/`:
  `index_tree.dart`, `index_repository.dart`, `index_order.dart`, `index_query_sql.dart`,
  `index_repository_impl.dart` e `index_providers.dart`. El esquema `drift_schema_v51.json` y
  `schema_v51.dart`.
- Cambian: `app_database.dart` (v51), `search_index.dart`, `vault_counts.dart`,
  `processed_images.dart`, `processed_images_store.dart`, `processed_repository_impl.dart`,
  `processed_providers.dart`, `set_union_merge.dart`, `merge_gates.dart` y `app.dart`.

**Verificado:**

- analyze en 19 en cada uno de los seis commits, cada uno armado y analizado por su cuenta;
- 87 pruebas nuevas: la migración 50→51 (que llega al esquema de v51, que no cambia ningún
  conteo y que deja todo sin indexar y sin titular), los triggers uno por uno, el indexador
  (con el texto, el PDF leído antes y recordado, uno ilegible, una falla pasajera, la copia que
  entra al triar, el de la fuente), el relleno (idempotente, se retoma, saltea lo que falla,
  los vivos y recientes primero, borrar y rehacer, la Biblioteca intacta, lo que llega tarde),
  el título de las imágenes al triar, en la galería y en la papelera, la unión, las consultas y
  los censos;
- **la misma transacción**, probada desde otra conexión a la misma base en un archivo: mientras
  el lector trabaja, afuera todavía se ven el texto viejo y sus tres entradas; al terminar, el
  texto nuevo y sus entradas, juntos;
- **la escala, en la PC** (`index_scale_test.dart`): 2.000 documentos con 150 capítulos cada
  uno —300.990 entradas con las imágenes—, 1.000 imágenes y una Biblioteca de 6.000 fuentes con
  sus temas, armada en 3,4 s. Los temas con sus cuentas, 6 ms; los documentos de un tema, 7 ms;
  los 1.990 documentos vivos con sus cuentas, 65 ms; las entradas de uno, 3 ms; una búsqueda
  rara, 1 ms; una común, con las 200 mejores y sus padres, 38 ms; cómo va el relleno, 4 ms. El
  `EXPLAIN QUERY PLAN` de cada consulta —también las del relleno— no tiene ningún `SCAN` de
  `processed_headings`, `processed_parts`, `item`, `item_spaces` ni `processed_images`: solo
  `processed_documents` (`SCAN d`, miles de filas), el índice de texto, la cadena de padres y
  el índice parcial de las imágenes sin titular;
- la suite entera por carpetas, con `--concurrency=2`: 15.151 pruebas. Una de
  `in_app_model_file_transfer_test` (una descarga que se pausa) falló una vez bajo carga y pasa
  sola; las de PDFium se saltean sin `PDFIUM_PATH`;
- murieron las 38 mutaciones, todas por pruebas que fallan: la omisión de cada censo
  (`VaultCounts`, la columna en la unión, las guardas, la papelera del contenido), la
  migración sin la columna o sin sus índices, cada trigger que suelta o que lleva la imagen,
  el indexador (rehacer lo indexado, indexar un PDF no leído, no leer la copia que entra,
  recordar una falla pasajera, olvidar un PDF ilegible, «Texto completo»), el repositorio (no
  leer el PDF antes, no rehacer al quitar una página, las imágenes sin titular), el relleno,
  las consultas (la papelera, los padres, «Sin tema», lo de solo notas) y el saneo. Dos
  sobrevivieron la primera vez y mostraron lo que faltaba: el relleno leía las imágenes sin
  titular afuera de la transacción que las titulaba —ahora es una sola, y una renombrada en el
  medio no se pisa—, y nada probaba lo que llega justo cuando una pasada termina, que ahora
  tiene su prueba. Tres estaban mal armadas (la sangría, después de formatear) y murieron al
  corregirlas.

**Queda abierto:**

- **La pantalla** (paso 3) se arma sobre un falso de los datos: al integrar, se conecta a
  `IndexRepository` (`indexRepositoryProvider`), con sus entidades (`index_tree.dart`).
- **«Por documento» con todo** cuesta 65 ms en la PC con 300.000 entradas, y el teléfono es
  varias veces más lento: si la pantalla lo nota, pedirlo de a tramos o mostrar las cuentas
  después. Lo demás está en milisegundos.
- **Una versión nueva del lector del paso 1 no reindexa sola** lo que ya está: hace falta
  `rebuildAll` o una migración que suelte las entradas de texto, y el relleno hace el resto.
- **El título de una imagen que las dos bóvedas tienen**: en la unión queda el de acá, como su
  lugar en la galería. Un renombre hecho en el otro dispositivo no llega.
- **La búsqueda es de capítulos e imágenes**: los títulos de los documentos los filtra la
  pantalla sobre la lista que ya tiene.
- **Una migración futura que rehaga** `processed_parts`, `processed_originals` o
  `processed_images` tiene que volver a crear sus triggers (`_createProcessedHeadingIndex`),
  como v50 hizo con los de `text_notes`.
- **Un documento sin copia del original** toma los marcadores del PDF de su fuente, que solo
  se lee; si la fuente se borra de verdad, valen los títulos de la IA.
- No se midió en el emulador ni en el teléfono: no hay nada que se vea. La cola del relleno
  se mide con la pantalla, en el cierre (paso 5).

### Paso 3 (hecho): la pantalla

Siete commits, de `af1cfbbe` a `e34b02ef`, y el de este avance (decisión A). El Índice se ve: un
destino propio en Estudiar, sobre los datos del paso 2 (`IndexRepository`), sin ningún falso en
la app.

- **El destino «Índice»** (decisión A): en Estudiar, justo debajo de Procesado, con la lista
  numerada (`Icons.format_list_numbered`, que no usa ningún otro destino). Es una rama propia del
  shell (`ShellBranch.processedIndex`, al final para no correr ninguna; no `index`, que es el
  lugar de cada valor de un enum), en `/index`. Lo que abre —el lector único, una imagen— ya está
  en la raíz, como desde Procesado.
- **Arriba**: el buscador «Buscá un capítulo» (fijo), la línea de avance del relleno (fija, y se
  va cuando termina) y, ya dentro de la lista —se va al desplazarse, para dejarle el lugar al
  índice en un teléfono con la letra grande—, «Por tema · Por documento» y «Niveles: 1 · 2 · 3 ·
  Todo», como fichas que se acomodan solas en dos renglones si no entran. En ⋮, «Numerar los
  capítulos»; y «Por documento» suma, en la barra, el orden: de la A a la Z o los más recientes.
- **El árbol, con tipografía de índice de libro**:
  - un **tema**: su nombre en versalitas (mayúsculas con aire), su color —el de su clave,
    ajustado al tema de la app para que contraste: el mismo `DocumentColors` de la línea de
    tiempo— en una rayita y en una franja apenas teñida, y cuántos documentos tiene;
  - un **documento**: el ícono de su tipo, el título en Lora, y debajo, en chico, «● Nuevo»
    (siete días), «Indexando…» (si el relleno todavía no llegó) y «también en Roma» (decisión D)
    o, en «Por documento», «en Roma, Egipto»; a la derecha, cuántos capítulos —o imágenes— tiene,
    en una cápsula tenue que no se confunde con una página;
  - un **capítulo**: su sangría por nivel, una línea guía fina por cada nivel que lo contiene
    —una tras otra arman la línea que une a los hermanos—, ⌄ si tiene algo adentro, la
    numeración si está prendida y **la línea de puntos hasta la página**, en cifras tabulares:
    «p. 47» con la del PDF y «pág. 3» con la del texto (decisión C); «Texto completo», sin puntos;
    una imagen, con su título o «Imagen 3», y «img. 3».
- **El buscador**: filtra mientras se escribe (con una pausa de 220 ms entre letra y letra), por
  `watchSearch`, y **conserva la jerarquía**: cada documento con coincidencias es un grupo con su
  fila fija arriba —con sus temas— y, antes de cada coincidencia, los capítulos que la contienen
  que todavía no se mostraron, más tenues (`groupIndexSearch`); lo buscado, resaltado en el
  comienzo de cada palabra (`indexMatchRanges`, con la misma regla que la base: sin mayúsculas
  ni acentos, la ñ como n y el comienzo alcanza). Arriba, «Documentos»: los títulos que
  coinciden, filtrados sobre la lista de todos (lo que el paso 2 dejó para la pantalla). Sin
  nada, «Ningún capítulo dice «…»», con dónde se busca; al llegar a las 200, lo dice.
- **Lo fijo arriba**: cada tema es un grupo (`SliverMainAxisGroup`) con su encabezado fijo
  (`PinnedHeaderSliver`), y cada documento desplegado, otro grupo adentro, con su fila fija
  debajo de la del tema. Cuando el grupo se termina, el que sigue empuja al de arriba, como en
  una agenda.
- **Dos paneles** desde 840 dp de ancho (la clase «expandida» de Material): el Índice a la
  izquierda (42 %, entre 340 y 480 dp) y, a la derecha, el **lector único entero**
  (`ProcessedReaderScreen`) con el documento elegido, o «Elegí un capítulo» si no hay ninguno.
  El mismo Índice en uno o en dos paneles (`GlobalKey`): agrandar la ventana no pierde lo
  escrito ni el lugar.
- **El lector al costado** (`ProcessedReaderScreen.onClose`, `ReadingFrame.leading`): ✕ en
  lugar de ←, porque no hay adónde volver; otra parte del documento —el resumen, la síntesis— se
  abre encima en lugar de reemplazar la lectura, y «atrás» vuelve a los dos paneles; mandarlo a
  la papelera cierra el panel.
- **«Nuevo»**: un punto y la palabra, en lo que llegó a Procesado en los últimos siete días
  (`createdAt` contra el reloj de la app, que las pruebas fijan).
- **Lo que cambia en vivo**: todo son streams del paso 2. Lo que llega se ilumina un momento
  (`IndexArrivals` + `IndexGlow`, 1,4 s, nada con «sin animaciones»), lo borrado se va y lo
  renombrado cambia, sin perder lo desplegado —es del estado de la vista, no de los widgets— ni
  la posición —las claves estables y `findChildIndexCallback`—. Mientras corre el relleno, la
  línea «Armando el Índice: 27 de 40 documentos» con su barra, o «Titulando 12 imágenes».
- **Los estados**: la ruedita mientras se leen los temas; «El Índice todavía está vacío» con «Ir
  a Procesado»; un documento sin indexar lo dice al desplegarlo («Sus capítulos todavía se están
  leyendo. Aparecen acá solos.»); uno sin entradas, también; un error, con el mensaje de
  siempre.
- **Accesibilidad**: claro y oscuro; 360 dp con la letra al doble, sin desbordes; cada fila es
  un solo nodo para el lector de pantalla, con lo que es, su nivel, su título —con su número si
  se numera— y su página («Capítulo de nivel 2: Las guerras púnicas, página 3 del texto»), si
  está desplegada (`expanded`) y si está elegida (`selected`); los temas y los documentos son
  encabezados (`headingLevel` 2 y 3), y plegar un capítulo es una acción propia. Con teclado:
  el foco arranca en el Índice, Ctrl+F (⌘F) va al buscador y Esc lo borra, Tab recorre las
  filas, → despliega, ← pliega y Enter abre.

**Decisiones, con su porqué:**

- **«Niveles» es la profundidad de los capítulos de un documento abierto, no de todo el árbol.**
  Es lo que hace Word, y desplegar «todo de una vez» los miles de documentos sería leer las
  entradas de todos, que es justo lo que el plan prohíbe («los capítulos de un documento solo al
  desplegarlo»). Los temas empiezan desplegados y los documentos plegados; elegir un nivel
  rehace lo abierto o cerrado a mano adentro de los documentos, como Word, y no toca los temas ni
  los documentos.
- **Tocar un documento lo despliega; tocar un capítulo lo abre.** El documento es una rama del
  árbol, no una entrada: se abre por sus capítulos, o por «Texto completo». En la búsqueda, un
  documento cuyo título coincide sí se abre al tocarlo, desde el comienzo: ahí se busca para ir.
- **Los documentos de un tema se leen recién cuando el tema llega cerca de la pantalla**
  (`IndexWhenNear`). Un `SliverList` dibuja siempre su primera fila aunque esté a mil pantallas,
  y la primera fila de un tema es leer sus documentos: con cien temas serían cien lecturas, que
  la base repite con cada escritura —el relleno escribe un documento por vez—. Hasta llegar,
  ocupa lo que ocuparían sus filas (a la letra de ahora), así nada salta; ya armado, se queda.
- **Ninguna lectura avisa si trae lo mismo** (`distinct` en cada provider): drift vuelve a leer
  cada consulta con cada escritura en sus tablas, y sin esto cada documento indexado volvería a
  dibujar cada tema y cada documento abierto. Con esto, un cambio dibuja solo lo suyo.
- **Cada parte mira solo lo suyo** (`select`): desplegar un documento vuelve a armar solo su
  lista; abrir un capítulo, solo su documento (los capítulos abiertos a mano están en un mapa
  por documento); la fila marcada, solo esa fila.
- **La fila de un documento tiene una clave global por lista** (`IndexRowKeys`): al desplegarse
  pasa de la lista perezosa a ser el encabezado fijo de su grupo, y con la misma clave es la
  misma fila —el foco del teclado sigue en ella—. Sin eso, → desplegaba y el foco se perdía.
- **La línea de puntos es un solo objeto que pinta título, puntos y página**
  (`IndexLeaderLine`): un `Row` no sabe dónde termina el último renglón de un título partido, y
  en Word los puntos salen de ahí. Siempre guarda lugar para los puntos, la página va a la
  altura del último renglón, y cada punto cae en una grilla contada desde el borde derecho, así
  quedan en columna con los de las otras filas, como una tabulación.
- **Las cuentas son una cifra en una cápsula, y la frase entera va en su ayuda y en lo que lee
  el lector de pantalla**: «2 documentos» a la derecha de un tema desbordaba con la letra al
  doble, y una cifra suelta a la derecha se confundía con una página.
- **Lo que llega se reconoce por lo que es, no por su clave**: volver a indexar un documento
  rehace todas sus filas con claves nuevas, y no «llegó» nada; un capítulo nuevo sí. La primera
  lectura de cada lista es lo que había: desplegar un tema no lo ilumina entero.
- **El lector, al costado, es el de siempre**, con un enganche chico (`onClose`) y no una copia:
  todo lo que el lector hace —la IA, Aa, el audio, las notas— está también al costado.
- **Lo que se recuerda entre una vez y otra** es cómo se arma (por tema o por documento, el
  orden, los niveles y la numeración, en `SharedPreferences`); lo desplegado y lo buscado son de
  esta vez, y viven mientras vive la app, así que cambiar de destino y volver lo encuentra igual.
- **Sin avisos**: nada de lo de este paso falla de un modo que haya que contar con un aviso —las
  lecturas en vivo muestran su error en su lugar—. Los avisos llegan con el paso 4 (renombrar,
  descargar).

**El enganche para el paso 4:**

- **Ir al lugar exacto** (decisión C): `openIndexEntry` (`index_opening.dart`) recibe un
  `IndexOpening` con la entrada entera —`textStart`, `textEnd`, `textPage`, `pdfPage`—. Hoy abre
  el texto en el lector único desde el comienzo: en un teléfono con
  `RoutePaths.extractReading(fullText, [id])`, y al costado con
  `indexReaderBuilderProvider` (`index_panels.dart`), que arma `ProcessedReaderScreen`. El paso 4
  le pasa al lector el tramo —por la dirección y por ese builder— para que lo muestre y lo
  resalte un momento. El lector al costado lleva la clave del documento, así que abrir otra
  entrada del mismo documento no lo rearma: el paso 4 lo lleva al lugar nuevo.
- **El toque largo**: `IndexEntryRow` y `IndexDocumentRow` ya tienen su `Semantics` y su
  `InkWell`; falta el `onLongPress` con «Abrir en el original», «Preguntar al chat», «Copiar el
  título» y, en una imagen, «Renombrar», que ya existe en el repositorio
  (`IndexRepository.renameImage`).
- **«Descargar el índice»**: va en ⋮ (`_MoreButton`, `index_screen.dart`), junto a la
  numeración. Lo que se está mirando —la forma, el orden, los niveles, lo plegado y la
  numeración— está entero en `IndexView` (`indexViewProvider`), y `indexOutline` ya da las
  filas con su número.

**Archivos:**

- Nuevos, en `features/index/`: `domain/services/index_outline.dart` (las filas de un documento
  con sus niveles, lo plegado y la numeración, y lo encontrado con sus padres) e
  `index_match.dart` (lo que coincide y lo que se resalta); `presentation/index_opening.dart`;
  `providers/index_view.dart` e `index_arrivals.dart`; `screens/index_screen.dart`; y en
  `widgets/`: `index_leader_line.dart`, `index_rows.dart`, `index_tree_slivers.dart`,
  `index_search_view.dart` e `index_panels.dart`.
- Cambian: `index_providers.dart` (las lecturas de la pantalla), `reading_frame.dart`
  (`leading`), `processed_reader_screen.dart` (`onClose`), `nav_destinations.dart`,
  `app_router.dart`, `route_paths.dart`, `app_es.arb` y `app_en.arb` (56 textos `f46P3…`),
  `GUIA_DE_USO.md` («El Índice») y `NOVEDADES.md` (F46).
- Pruebas: `fake_index_repository.dart` (un repositorio de prueba que arma cada lectura como el
  de verdad, cuenta quién mira qué y puede retener una lectura); en `test/features/index/`:
  `domain/index_outline_test.dart`, `index_match_test.dart`,
  `presentation/providers/index_view_test.dart`, `widgets/index_leader_line_test.dart`,
  `index_rows_test.dart`, `screens/index_screen_test.dart` (con `index_screen_harness.dart`),
  `index_screen_scale_test.dart` e `index_screen_vault_test.dart`; y las de la navegación
  (`nav_destinations_test`, `adaptive_scaffold_test`, `app_router_branches_test`).

**Verificado:**

- `flutter analyze`: 19, la línea base, con todo y commit a commit: cada uno de los siete,
  sacado solo en el árbol de trabajo, con sus textos generados, da 19.
- **106 pruebas nuevas** —17 de las filas de un documento y de lo encontrado, 12 de lo que
  coincide y se resalta, 14 de la vista y de lo que llega, 9 de la línea de puntos, 13 de las
  filas, 30 de la pantalla, 3 de escala, 5 sobre la base de verdad y 3 de la navegación— y las
  de la navegación que cambiaron (el destino en «Estudiar», el riel con once, la rama).
- Por carpetas, con `--concurrency=2`: `test/features/index` (127, con las del paso 2),
  `test/app` y `test/features/help` (305 en total con las del Índice);
  `test/features/processed/presentation` y `test/features/reading` (318), por el lector al
  costado; y `test/core/i18n`, `test/features/viewer` y `test/features/creations` (2.333), por el
  marco de lectura.
- **Sobre la base de verdad** (`index_screen_vault_test`, con `LibraryHarness` y el router de
  la app): lo que se procesa aparece con sus capítulos, leídos al guardarse el texto; tocar uno
  abre el lector entero encima en un teléfono, con ←, y al costado en una pantalla ancha, con ✕;
  al costado, el resumen se abre encima y «atrás» vuelve a los dos paneles; y mandarlo a la
  papelera cierra el panel y lo saca del Índice en vivo.
- **La escala, por crecimiento** (`index_screen_scale_test`, con `timeGrowth`): abrir el Índice
  con ocho veces más documentos (8 temas de 50 contra 8 de 400) tarda **×1,27**; desplegar un
  libro de ocho veces más capítulos (1.000 contra 8.000), **×1,05**; un cambio en vivo en un
  documento con ocho veces más documentos alrededor, **×1,26** —lo lineal daría ×8—. Y se cuenta
  quién lee qué: con 60 temas de 10 documentos, al abrir se leen menos de 6; los demás, al bajar
  hasta ellos. Un capítulo que cambia vuelve a dibujar su documento y ninguna fila del otro
  desplegado (el mismo widget, `same`). `indexOutline` con 32.000 capítulos contra 4.000 crece
  mucho menos que lo cuadrático.
- **Para todos**: a 360 dp con la letra al doble, en claro y en oscuro, el árbol, un documento
  desplegado y la búsqueda, sin un desborde; lo que oye el lector de pantalla en un tema y en un
  capítulo, con su estado; el teclado (Ctrl+F, Tab, → ←, Enter al costado). Y capturas con las
  letras de verdad (Inter y Lora) en claro, en oscuro, en una pantalla ancha, de una búsqueda y a
  360 dp con la letra al doble, que se miraron y se borraron: de ahí salieron la franja teñida de
  cada tema y la cápsula de las cuentas.
- **Murieron las 42 mutaciones**, todas por pruebas que fallan. Cuatro sobrevivieron la primera
  vez y mostraron pruebas flojas, que ahora las matan: «también en…» se comprobaba con que el
  texto estuviera en alguna fila —y con la mutación lo decía otro documento—, ahora fila por
  fila; elegir cómo se arma se guardaba pero la prueba encadenaba otras elecciones que también
  guardaban, ahora cada una sola; y la línea de puntos se probaba con títulos que no
  distinguían el último renglón del ancho del título ni el lugar mínimo de los puntos, ahora
  con un último renglón corto y los 18 puntos enteros. Las demás: los niveles (el último
  también desplegado, lo plegado que no esconde o que esconde a los hermanos), la numeración
  (sin volver al padre, prendida siempre, las imágenes numeradas), un hermano como hijo, lo
  encontrado (padres repetidos, el padre que coincide), lo que coincide (cualquiera de las
  palabras, en el medio de una palabra, el resaltado más corto, lo que está fuera del plano
  básico de Unicode), la vista (los niveles que no rehacen, los espacios, el capítulo abierto a
  mano), lo que llega (la primera lectura, el brillo que no se apaga, la imagen por su título),
  las lecturas iguales que vuelven a dibujar, los temas lejanos que se leen, el tema que no queda
  fijo, la fila que pierde el foco al desplegarse, el documento sin indexar, la página del texto
  antes que la del PDF, «Nuevo» en lo viejo, el brillo sin animaciones, → al revés, el tema sin
  su estado para el lector de pantalla, dos paneles en un teléfono, Ctrl+F, abrir encima al
  costado, la imagen en la primera, el lector al costado con ←, otra parte que reemplaza la
  lectura, la papelera que no cierra el panel, el marco que ignora lo de la izquierda y el
  Índice fuera de «Estudiar».

**Queda abierto:**

- **Ir al lugar exacto, el toque largo y «Descargar el índice»**: el paso 4, con su enganche
  arriba. Hoy tocar un capítulo abre el texto desde el comienzo, y la guía lo dice.
- **El brillo de lo que cambia**: un documento o una imagen renombrados cambian sin brillo (son
  los mismos); un capítulo cuyo título cambió al editar el texto se reconoce por lo que dice, así
  que brilla como uno que llegó.
- **Los temas se arman todos**: cada tema es un grupo, aunque sus documentos se lean recién al
  acercarse. Con cientos de temas es liviano (un encabezado cada uno); con miles convendría
  hacer perezosos también los grupos.
- **«Por documento» con todo** sigue costando lo que midió el paso 2 (65 ms con 300.000 entradas
  en la PC), una vez por cambio mientras se lo mira: si en el teléfono se nota, pedirlo de a
  tramos.
- **La búsqueda no numera**: lo encontrado lleva su nivel y su página, pero no su número, que
  pediría leer todas las entradas del documento.
- **Las líneas guía** se dibujan por fila y se cortan en el encabezado fijo de un documento: con
  el documento fijo arriba, la línea de los capítulos de más arriba no sigue por detrás.
- No se miró en el emulador ni en el teléfono: las capturas de esta revisión se hicieron en la
  PC, con las letras de verdad (Inter y Lora), en claro, en oscuro, en una pantalla ancha y a 360
  dp con la letra al doble. La medición en el emulador con una bóveda grande es del paso 5.

### Paso 4 (hecho): ir al lugar exacto

Siete commits, de `d88623e5` a `181b49f5`, y el de este avance (decisión C). Cada entrada
lleva a su lugar: el título en el lector único, la página del PDF o el título de la página web
en el original; mantenerla apretada ofrece lo que se hace con ella, y ⋮ descarga lo que se está
mirando.

- **El lector único se abre en un lugar** (`ExtractPlace`: el documento y el tramo del texto
  propio): por el mismo camino que una nota de «Notas (N)» (`_revealRange`, que antes era
  `_revealNote`) va justo ahí —de un salto, también con «sin animaciones»— y lo resalta dos
  segundos con el color de ese resalte. Espera a que el documento termine de leerse y va a
  cada lugar una sola vez, aunque la lista se vuelva a armar porque se marcó algo o se editó
  una página.
- **Tocar un capítulo** (`openIndexEntry`): en el teléfono, la dirección del lector lleva el
  lugar (`/read/full_text?docs=…&at=doc:inicio-fin`) y «atrás» vuelve al Índice como estaba
  —lo desplegado es del estado de la vista y la posición, del Índice que sigue debajo—. Al
  costado, el mismo lector (la clave es la del documento) va al lugar nuevo, y cada toque es un
  pedido distinto (`IndexOpening.visit`): volver a tocar el mismo capítulo después de leer más
  abajo vuelve a llevar a su título. «Texto completo», una imagen y un marcador sin lugar en el
  texto no tienen lugar: abren desde el comienzo o en su galería.
- **«Seguir escuchando»** vuelve a la lectura, no al capítulo: el lector le da a lo que se
  escucha su dirección sin el lugar (`ReadableDocument.location`).
- **Mantener apretada una entrada** —o el clic derecho, la tecla de menú, Mayús+F10, o la acción
  «Más opciones» del lector de pantalla— abre la hoja común de la app (`showReadingMore`, la de
  ⋮ del marco), con el título arriba —con su número si se numera— y lo que es: «Capítulo de
  nivel 2 · pág. 3 · Historia de Roma».
  - **«Abrir en el original»**: un PDF en la página del capítulo (`PdfViewerView.initialPage`,
    el `initialPageNumber` de `pdfrx`, que la acota); una página web en su título, que se
    resalta dos segundos; lo demás, desde el comienzo. Sin copia del original, apagada y
    diciendo por qué. La dirección lleva el lugar (`/processed/:id/original?page=47` o
    `?heading=…&nth=1`).
  - **«Preguntar al chat»**: por el camino de siempre (`askInChat`, el de «Preguntar a la IA» del
    lector), una conversación nueva con el capítulo, su documento y su texto —desde su título
    hasta el siguiente de su nivel o de uno más alto, con sus secciones adentro
    (`indexChapterSpan`), en una línea y con 2.000 caracteres como mucho
    (`indexChapterPassage`)— a medio escribir, para que se pregunte lo que se quiera.
  - **«Copiar el título»**, con su número; y en una imagen, **«Renombrar»**
    (`IndexRepository.renameImage`), que el Índice muestra en vivo.
  - En un documento: «Abrir el texto», «Abrir en el original», «Preguntar al chat» con el
    borrador del lector («Sobre «…»: ») y «Copiar el título».
- **«Descargar el índice»** en ⋮: la hoja común dice qué se baja —«Por tema · hasta el nivel 3
  · numerado», o «Lo que coincide con «…»»— y ofrece **PDF** y **Markdown**. Se guarda con el
  selector de siempre (`fileSaverProvider`, como lo creado y la bibliografía), como «Índice
  2026-11-06.pdf», con los avisos de la app (`AppSnackBar`).
  - Los renglones salen de lo mismo que dibuja la pantalla (`indexPrintTree`, sobre
    `indexOutline`; `indexPrintSearch`, sobre `groupIndexSearch`), así lo descargado y lo que
    se ve dicen lo mismo;
  - el **PDF** (`IndexPdfExporter`): A4 con Lora e Inter de la app —tildes, ñ, «»—, los temas en
    versalitas con un filete, los documentos en serif con lo que dicen debajo, cada capítulo con
    su sangría, su número y la línea de puntos hasta su página, «Página 3 de 12» al pie. Se arma
    con `compute`;
  - el **Markdown** (`indexMarkdown`): los temas como `##`, los documentos como `###` (o `##` sin
    temas), las entradas como una lista con sangría, número y página, y lo que Markdown leería
    como marca, escapado;
  - las entradas de todos los documentos se leen de una vez (`IndexRepository.readEntries`, de a
    tandas de 500), sin quedarse mirando la base.

**Decisiones, con su porqué:**

- **El lugar va por el camino de «Notas (N)»**, no por uno nuevo: es el mismo problema —llevar
  la vista a un tramo del texto propio y marcarlo un momento— y el lector ya lo resolvía con
  filas que todavía no se armaron.
- **Un pedido por toque** (`visit`), y no la entrada a secas: al costado, el lector no se
  rearma, y tocar el mismo capítulo dos veces tiene que volver a llevar; en la dirección del
  teléfono el pedido no viaja, porque esa pantalla se abre una vez por toque.
- **La página web se abre por el título, no por la posición**: el original es la página de la
  fuente y el texto procesado pudo perder pedazos al triarlo o editarse después; el título es
  lo que los dos comparten. Se compara como el Índice compara los títulos (`headingKey`),
  sin lo que la página agrega entre corchetes (el «[editar]» de una enciclopedia), y entre
  iguales vale su orden en el documento (`indexHeadingOccurrence`). Se marca en la copia que
  se muestra —en Dart, en el hilo aparte donde ya se arma—, y un programa chico de la app la
  lleva ahí al terminar de cargarse; la página va sin sus propios programas, como con lo
  estudiado.
- **Las acciones no atan las filas a Procesado**: lo que necesitan de un documento —su título,
  su copia del original, su texto— va por un puerto chico (`IndexDocumentAccess`, en la app
  sobre `ProcessedRepository`) y se lee recién al mantener apretado, no mientras se recorre.
- **«Preguntar al chat» deja el texto a medio escribir y no lo manda**: como «Preguntar a la
  IA» del lector, la pregunta la escribe la persona; el tramo es del capítulo con sus
  secciones, cortado a 2.000 caracteres para no llenarle la ventana al modelo.
- **Lo que dice cuánto se descarga son los niveles**, como en Word: plegar un tema o un
  documento es para recorrer la pantalla, y lo descargado los lleva igual; lo abierto o
  cerrado a mano adentro de un documento sí cuenta, porque cambia lo que dicen los niveles.
- **Los puntos guía del PDF son una grilla desde el borde derecho**, debajo del título y de la
  página, que los tapan con su fondo: quedan en columna de un renglón al otro, como en la
  pantalla, y la página va en una columna fija.

**Una causa de raíz en las pruebas:** el repositorio de prueba del Índice
(`FakeIndexRepository`) devolvía, al soltar una lectura, el futuro de soltar una suscripción de
difusión, que se completa en la zona raíz: con el reloj de mentira de las pruebas, `first` —que
espera a soltar antes de dar su valor— no terminaba nunca. Ya no lo devuelve.

**Archivos:**

- Nuevos: `creations/extract/domain/extract_place.dart`;
  `viewer/domain/services/archived_page_heading.dart`; en `features/index/`:
  `domain/repositories/index_document_access.dart`,
  `data/repositories/processed_index_document_access.dart`,
  `domain/services/index_chapter.dart` e `index_print.dart`, `presentation/index_actions.dart`,
  `index_download.dart` y `export/index_pdf_exporter.dart`.
- Cambian: `extract_viewer.dart`, `processed_reader_screen.dart`, `route_paths.dart`,
  `app_router.dart`, `index_opening.dart`, `index_panels.dart`, `index_rows.dart`,
  `index_screen.dart`, `index_providers.dart`, `index_repository.dart`,
  `index_repository_impl.dart`, `index_query_sql.dart`, `archived_page_study.dart`,
  `web_page_viewer_view.dart`, `pdf_viewer_view.dart`, `original_view.dart`,
  `processed_original_screen.dart`, `app_es.arb` y `app_en.arb` (43 textos `f46P4…`),
  `GUIA_DE_USO.md` y `NOVEDADES.md`.
- Pruebas nuevas: `extract_place_test`, `archived_page_heading_test`, `index_chapter_test`,
  `index_print_test`, `index_actions_test`, `index_download_test` e
  `index_pdf_exporter_test`; y suman casos `index_screen_vault_test`, `index_screen_test`,
  `index_scale_test`, `processed_original_screen_test` y `original_view_pdf_test`.

**Verificado:**

- `flutter analyze`: 19, la línea base, con todo y commit a commit: cada uno de los seis de
  código, sacado solo en el árbol de trabajo con sus textos generados (`verify_commit`), da 19.
- **72 pruebas nuevas**: 5 del lugar en la dirección, 11 de la página web en su título (qué se
  marca, la copia sin los programas de la página, «sin animaciones», lo estudiado igual y la
  dirección del original), 11 del tramo de un capítulo, su orden entre iguales y su pasaje, 7
  de los renglones y del Markdown, 18 del toque largo, 10 de la descarga, 4 del PDF leído con
  PDFium, y 6 sumadas a las de siempre: el lector justo en un capítulo lejano en el teléfono y
  al costado sobre la base de verdad, el original en su página y en su título por la
  dirección, y las entradas de muchos documentos en la escala. Cambiaron las que esperaban la
  dirección del lector sin el lugar.
- Por carpetas, con `--concurrency=2`: `test/features/index`, `test/features/text_notes`,
  `test/features/creations/extract` y `test/app` (412); `test/features/processed/presentation`,
  `test/features/reading`, `test/features/viewer` y `test/features/creations` (2.689); y las
  que se sumaron después (51).
- **Sobre la base de verdad** (`index_screen_vault_test`): un libro de 40 capítulos; tocar el
  36 en un teléfono abre el lector con ese título resaltado y su primer renglón en la pantalla,
  el resalte se apaga solo, «Seguir escuchando» no lleva el lugar y «atrás» vuelve al Índice
  con lo desplegado y en el mismo lugar de la lista. Al costado, otro capítulo del mismo
  documento mueve el mismo lector —el mismo `State`—, y el mismo capítulo, tocado otra vez
  después de bajar hasta el final, vuelve a su título.
- **El PDF, leído con PDFium**: el texto con las tildes, las comillas, los números y las
  páginas; los puntos guía, contados en la franja del medio de un renglón —donde no llegan ni
  el título ni la página— y ninguno sin página; un índice de 400 capítulos en las páginas que
  hagan falta, cada una con «Página N de M». Y armado de verdad en otro hilo con las letras de
  la app.
- **La escala, por crecimiento** (`index_scale_test`, con 2.000 documentos y 300.990
  entradas): las entradas de 800 documentos contra 100 cuestan ×7,6 (×6,9 y ×11,4 en otras dos
  corridas) —lo que leen, ocho veces más; lo cuadrático daría ×64—, y su `EXPLAIN QUERY PLAN` va
  por `idx_processed_headings_document`, sin recorrer `processed_headings`.
- **Para todos**: la hoja a 360 dp con la letra al doble, en claro y en oscuro, sin
  desbordes; lo que oye el lector de pantalla («Más opciones» en cada fila, y su acción); el
  clic derecho, Mayús+F10 y la tecla de menú.
- **Murieron las 54 mutaciones**, todas por pruebas que fallan. Tres sobrevivieron la primera
  vez y mostraron pruebas flojas, que ahora las matan: cancelar el selector se probaba con un
  aviso que nunca existe —ahora con el nombre del archivo—; los puntos guía se contaban en la
  página entera, donde el borde suavizado de los números de página alcanzaba solo —y la franja
  medida, además, empezaba debajo del único renglón: ahora es la del medio del renglón, de
  arriba abajo—; y las entradas repetidas no se leían dos veces porque `IN` ya las junta en una
  tanda —ahora un documento se repite en dos tandas, que es lo que el `toSet` cuida—. Las
  demás: el lugar repetido en cada armado o sin esperar al documento, «Seguir escuchando» con
  el lugar, el pedido sin su número, «Texto completo» con lugar, el teléfono y el costado sin
  el lugar, un tramo vacío, la dirección sin `at=`; entre iguales siempre el primero, lo de
  entre corchetes, la página con sus programas, la copia sin JavaScript, «sin animaciones»
  que se desliza, el PDF en la primera, la vista, la pantalla y el router sin la página o el
  título, la dirección sin `page` o sin `nth`; copiar sin el número, el original sin página o
  siempre en el primer título, apretable sin copia, el chat sin texto, renombrar con el mismo
  título o vacío; el tramo que corta en un subcapítulo o en uno sin lugar, las imágenes entre
  los iguales, el pasaje justo en el límite; sin toque largo, sin la acción del lector de
  pantalla, sin clic derecho o sin Mayús+F10 en un capítulo o un documento; y en la descarga,
  «también en» con todos los temas, lo abierto a mano, los padres como encontrados, los `##`,
  la sangría, el `#` sin escapar, siempre por tema, sin niveles, la búsqueda como árbol, lo
  vacío guardado, la hoja sin «numerado», sin pie de página y una sola tanda.

**Queda para después:**

- **Un Word o un EPUB** se abren en el original desde el comienzo: el lector los muestra por su
  texto, y llevarlo al título pediría ubicar el capítulo en el texto de la fuente.
- **La página web en su título no se probó en un WebView**: en las pruebas no hay uno. Lo que
  se marca y el programa que lleva ahí se prueban en Dart, sobre la copia que se muestra; que
  la página se desplace de verdad se mira en el emulador, en el cierre (paso 5).
- **Un título que la página web escribe distinto** —otra puntuación que no es la del extraído,
  un pedazo que la extracción le sacó— no se encuentra, y la página se abre desde arriba.
- **El PDF de un índice enorme** («Todo» con cientos de miles de capítulos) se arma en otro
  hilo, pero con todas sus entradas en memoria: si en el teléfono pesa, armarlo de a tandas.
- **«Preguntar al chat» en una imagen**: no está; una imagen no tiene texto que llevar.
- No se miró en el emulador ni en el teléfono: es del paso 5.

### Paso 5 (hecho): el cierre

El cierre de F46 y el cierre conjunto de F44, F45 y F47, en nueve commits, de `687f2faf` al de
este avance. Sin el emulador, el teléfono ni la APK, que son de la sesión principal.

- **La decisión 92 en `docs/arquitectura.md`** (`e01512c5`), entre la 91 y la 93, con F46 en
  «Construido» (esquema v51): el pedido con sus ajustes del 30/10; de dónde sale cada entrada y por
  qué solo del texto y de las imágenes; la tabla derivada con su FTS5, sus reglas y el título de cada
  imagen; los triggers que sueltan y el indexador que rehace en la misma transacción, con el PDF leído
  antes; el relleno que se retoma por la base misma; las consultas que no recorren nada; la pantalla
  que nunca trae todo; ir al lugar exacto, el toque largo y la descarga; los censos; las invariantes;
  las trampas para lo que venga —las migraciones que rehagan `processed_parts`,
  `processed_originals` o `processed_images` tienen que volver a crear los triggers, un lector de
  títulos nuevo necesita `rebuildAll`, el renombre de una imagen no viaja en la unión de bóvedas— y
  las que costaron; lo descartado y lo no probado. Cada clase y cada archivo citados se buscaron en el
  código.
- **Los tres arreglos que dejó anotados el cierre de F44 y F45, y uno más:**
  - `mapExportUnavailable` (`687f2faf`), la ayuda del botón de exportar, apagado en el Resumen,
    decía «Se puede exportar desde el esquema y desde el grafo»: esas pestañas no existen desde F44.
    Ahora dice «Se exporta desde la pestaña Mapa» («You can export from the Map tab»), que es lo que
    hace `map_screen.dart`: el menú se prende solo con `MapTab.map`. La prueba del botón apagado
    pide, además del texto, que nombre la pestaña Mapa y que no nombre el esquema ni el grafo;
  - `mapEmptyMessage` (el mismo commit), el Mapa sin temas, decía «Lo que vinculaste ya está en
    «Vínculos»», como si fuera una pestaña: ahora «Lo que vinculaste ya se ve con la capa
    «Vínculos»», que es lo que prende su botón «Ver los vínculos» (`_setLinks`, con
    `MapLayer.links`). La prueba del lienzo vacío apaga la capa antes, mira el mensaje y comprueba
    que el botón la prende. Las descripciones de los dos textos en los `.arb` también decían lo
    viejo, y se corrigieron;
  - el comentario de `ProcessedDocumentScreen` (`8ef2c0ec`) decía que el botón redondo lee «desde
    la página que se editó por última vez». No es así: `processedTextPageProvider` es `autoDispose`
    y solo lo mira la edición del texto (`ProcessedTextPages`), que tapa el documento y le retira el
    botón mientras está abierta (`ReadableRegion` se aparta cuando su pantalla queda tapada), así
    que desde el documento vale siempre 0 y la lectura empieza por la primera página. El comentario
    de la clase y el de `_startAt` lo dicen así; el comportamiento no cambió.
  - Y uno que encontró este cierre: el Avance del paso 2 y el comentario de
    `processedHeadingsBackfillKeeperProvider` decían que el guardián del relleno se lee en
    `SinapsisApp`, una clase que no existe: es `App` (`lib/app/app.dart`), al abrirse la bóveda
    (`f4b4f638`).
- **La GUÍA, «El Índice» repasada entera** (`d75440ca`) contra el código de los pasos 3 y 4:
  - una sección nueva, «De dónde salen los capítulos»: los títulos del texto con la página del texto,
    los marcadores de un PDF con la del PDF, los que dejó la IA al ordenar un PDF sin marcadores,
    «Texto completo» y el título de cada imagen, con el nombre del archivo limpio y «Imagen 3» solo
    cuando nada dice nada (antes decía que sin título de la fuente era «Imagen 3»);
  - «Por tema» decía «el árbol de tus temas»: los temas no tienen padre y van de la A a la Z, como en
    el Atlas;
  - mantener apretado describía las mismas opciones para todo: ahora dice qué ofrece un capítulo,
    «Texto completo», una imagen (solo «Renombrar» y «Copiar el título»: no tiene texto que llevar al
    chat) y un documento, y que un marcador sin lugar en el texto avisa que no tiene texto;
  - tocar lo encontrado lo abre en su título, «Titulando N imágenes» en la línea del relleno, el
    relleno que sigue donde iba si se cierra la app, y lo editado o vuelto a extraer que se vuelve a
    leer solo.

  Los enlaces internos de la guía son 196 y todos apuntan a títulos que existen (comprobado con un
  script que arma cada ancla como GitHub).
- **`NOVEDADES.md`** (`a0620859`): F46 deja de estar «en curso», con los capítulos de verdad y
  nunca inventados, lo ya procesado que se suma solo, y el teclado y el lector de pantalla.
- **`CONTEXTO_DEL_PROYECTO.md`** (`70c9ae83`): F46 en la historia, en el estado y en los módulos
  (`index`), la decisión 92 en su lugar y las cifras de la suite de este cierre.
- **La suite entera** (`flutter test --concurrency=2 --timeout 150s`, con `PDFIUM_PATH` apuntando a
  `.pdfium/win-x64/bin/pdfium.dll`, así que corren también las de PDFium real), en siete tandas de
  carpetas, una detrás de la otra y sin nada pesado al lado, sobre el árbol con los arreglos de este
  paso:

  | Tanda | Carpetas | Pasan | Fallan | Omitidas | Tiempo |
  |---|---|---:|---:|---:|---:|
  | 1 | `test/core`, `test/app`, `test/benchmark`, `test/support` y `widget_test.dart` | 1.519 | 0 | 47 | 5 min 25 s |
  | 2 | `test/features/creations` | 2.008 | 0 | 0 | 16 min 48 s |
  | 3 | `narration` y `vault` | 1.363 | 0 | 0 | 7 min 45 s |
  | 4 | `processed`, `flashcards` y `transform` | 2.343 | 0 | 0 | 13 min 33 s |
  | 5 | `map`, `ai_organize`, `chat` y `ai_models` | 2.138 | 0 | 0 | 11 min 9 s |
  | 6 | `export`, `timeline`, `library`, `viewer` y `reference` | 2.461 | 0 | 0 | 11 min 15 s |
  | 7 | las otras 32 carpetas de `test/features` (`index`, `study`, `inbox`, `help`…) | 3.598 | 0 | 0 | 20 min 26 s |
  | **Total** | las 47 carpetas de `test/features` y las de afuera | **15.430** | **0** | **47** | **86 min** |

  Las 47 omitidas son todas pruebas de rendimiento de `test/benchmark`, que corren solo
  con `--dart-define=BENCH=true` (`Skip: se corre con --dart-define=BENCH=true`): ninguna de PDFium
  quedó afuera.

  **Ninguna falla, tampoco suelta**: las siete tandas terminaron con `All tests passed!` y salida 0,
  y no hubo nada que repetir ni que anotar como intermitente. Tampoco se cayeron la descarga que se
  pausa de `in_app_model_file_transfer_test`, que falló una vez bajo carga en el paso 2, ni las de
  memoria de la copia y la compactación.
- **Los cierres de F44, F45 y F47** (`9c2911f1`): cada uno tiene ahora su línea con este resultado,
  los arreglos que había dejado anotados, ya hechos, y en su estado lo que queda para la sesión
  principal (la medición en el emulador, la APK y la prueba con tus voces).
- **`flutter analyze`**: 19, la línea base, en el árbol con todo. Se corrió dos veces: con los
  arreglos de los `.arb`, sus pruebas y el comentario de `ProcessedDocumentScreen` (el árbol de
  `8ef2c0ec`; el de `687f2faf` es el mismo salvo ese comentario), y al final, con el de
  `processedHeadingsBackfillKeeperProvider` (`f4b4f638`). Los otros seis commits son de documentos.
  Las pruebas que miran los textos corregidos —`map_screen_test.dart` y
  `map_canvas_view_test.dart`, 148— pasaron solas antes de la suite. No se cambió lógica, así que no
  hubo mutaciones que correr.
- **Sobre `main`**: los nueve commits se rebasaron sobre `main` local, que mientras tanto sumó
  `296a1857` (los subtítulos de una página web como títulos, sin su «[editar]»). Ese commit no
  estaba en el árbol de la suite: después del rebase se corrieron sus dos carpetas,
  `test/features/organize` y `test/features/transform`, con PDFium real: 1.146 pasan, 0 fallas.

**Queda para la sesión principal** (no se hace sin el emulador ni el teléfono):

- la medición en el emulador con una bóveda grande: abrir el Índice, desplegar un libro, buscar y la
  cola del relleno; y la de F44, los gestos del lienzo con las capas prendidas contra la de F18;
- la página web del original que se desplaza de verdad hasta su título en la `WebView`;
- la APK al teléfono, si el dueño la pide, con lo que cada plan dejó para mirar ahí (F44, F45 y F47).

**Sigue abierto** (de los Avances de cada paso y de la decisión 92): lo que la IA no deja con su
forma; un PDF sin sus rayas de página; un Word o un EPUB en el original desde el comienzo; un título
que la página web escribe distinto; los grupos de los temas, que con miles convendría hacer
perezosos; el PDF de un índice enorme en memoria; la búsqueda que no numera; y el renombre de una
imagen, que no viaja en la unión de bóvedas.

### Paso 5b (hecho): lo que se vio en el emulador

Con la biblioteca de ejemplo (Ajustes › Desarrollo) y once artículos de Wikipedia pasados de la
Bandeja a Procesado con «Pasar todo», el Índice y el «Contenido» del lector mostraban muchos
menos capítulos que los de la página, y en «Leer» de Fotosíntesis se veía crudo `[bacterias` en
un bloque y `purpúreas](https://…)` en el siguiente. Tres causas, cada una arreglada donde nace.

**Las cifras** (entradas del Índice; «la página» son los títulos del artículo —sus
`div.mw-heading`—; medido en la PC con la cadena entera: `ReaderModeArticleExtractor` →
`htmlToMarkdown` → `processedTextPages` → `readProcessedHeadings`, sobre el HTML bajado con el
User-Agent de la app):

| Página               | La página | Emulador | Antes de este paso | Ahora |
|----------------------|----------:|---------:|-------------------:|------:|
| Fotosíntesis         |        30 |        0 |                 30 |    30 |
| Benito de Nursia     |        15 |        0 |                 15 |    15 |
| Primer Concilio de Nicea |    10 |        1 |                 10 |    10 |
| Imperio romano       |        57 |        7 |                 57 |    57 |
| Agujero negro        |        23 |        8 |                 23 |    23 |
| Agustín de Hipona    |        31 |        8 |                 31 |    31 |
| Edad Media           |        61 |       28 |                 53 |    61 |
| Sócrates             |        22 |        — |                 22 |    22 |
| Tomás de Aquino      |        37 |        — |                 37 |    37 |
| Platón               |        55 |        — |                 55 |    55 |
| Revolución francesa  |        38 |        — |                 38 |    38 |

Ahora coinciden todas, título por título (no solo en la cuenta). La página archivada en el
emulador (la de Fotosíntesis, sacada con `run-as`) da los mismos 30.

1. **Dónde se perdían los títulos: en la extracción, y el emulador tenía texto de antes de
   `296a1857`.** Se siguió el camino entero sobre la base del emulador (copiada con `run-as`):
   el texto de la Biblioteca de Fotosíntesis (la forma `markdown` principal, 90.531 caracteres)
   ya no tenía ni un `#`, y sus 12 páginas de Procesado son ese texto tal cual. «Pasar todo» y
   las páginas no sacan nada; el Índice lee bien lo que recibe. El texto se guardó a las 11:59,
   con la APK instalada a las 11:53, antes de `296a1857` (12:34). Corrida en la PC con el código
   de entonces, la extracción da **exactamente** las cifras del emulador (0, 0, 1, 7, 8, 8, 28).
   La causa (documentada ahora en `reader_mode_article_extractor.dart`): con el control de
   edición adentro, el `<div class="mw-heading">` que envuelve cada título tiene dos enlaces
   —«[editar código · editar]»— y casi tanto texto de enlace como de título; la limpieza
   condicional de Readability (`_cleanConditionally`, densidad de enlaces > 0,2) lo tiraba con
   el título adentro. Solo sobrevivían los títulos largos, que diluían el enlace, con su
   «[editar]» debajo —que es lo que `296a1857` vio—. Sacar el control antes de leer, que hizo
   `296a1857`, arregla también esto; acá quedan las pruebas que lo atan, sobre un recorte de
   la página real (`test/fixtures/web/wikipedia_fotosintesis_recorte.html`), que fallan sin él.
2. **Readability tiraba los títulos cuyo `id` dice «media», «social»…** Readability juzga un
   elemento por los pedazos de su `class` y de su `id` (`_cleanHeaders`, en los `h1`/`h2`, y
   `unlikelyCandidates`, en cualquiera); MediaWiki le pone a cada título de `id` su propio
   texto («Alta_Edad_Media_(siglos_V_al_X)»). En Edad Media se iban los cinco `h2` que dicen
   «Media» y dos `h4` que dicen «social» (8 de 61). La regla nueva (`unweightTitleAnchors`):
   el `id` que es el ancla del propio texto del título —en minúscula, sin separadores ni
   acentos, también en la forma vieja `.C3.B3`, en la de dirección `%C3%B3` y con el número de
   un título repetido— no dice nada de la estructura y se saca antes de leer; un `id` que no
   es el texto (`<h2 id="comments">3 comentarios</h2>`) y la `class` siguen pesando. Un título
   que es justo una de esas palabras («Comments», «Related», «Tags») conserva su `id`: el ancla
   y el nombre de estructura se escriben igual y no hay cómo distinguirlos.
3. **Un corte partía un enlace.** No eran las páginas de Procesado (en Fotosíntesis cortan
   todas en un fin de párrafo) sino los bloques del lector: «Leer» parte el texto en bloques de
   1.200 caracteres y el lector de libros en páginas de 2.400 (`readerPageRanges`), y un
   párrafo más largo se cortaba en el último espacio (`_hardSplit`), aunque cayera adentro de
   `[bacterias purpúreas](…)`. Ahora un solo lugar dice qué es una construcción en línea
   (`markdownInlinePattern`, en `lib/core/util/markdown_inline.dart`): el mismo patrón con que
   el lector da formato (`RenderedMarkdown`, que antes tenía el suyo) y con que se corta. Ninguna
   alternativa cruza un renglón, así que sobre el texto entero encuentra lo mismo que el lector
   renglón por renglón (probado al azar). `markdownSafeCut`: si el corte cae adentro de una,
   justo antes de ella; si empieza donde empieza el tramo —un enlace más largo que una
   página—, justo después, y ese tramo sale más largo. Lo mismo en las páginas de «Texto» de
   Procesado, que se muestran, se editan y se ordenan de a una (`processedTextPages`, con
   `splitIntoParts(markdown: true)`: oración o espacio, el último que no cae adentro de nada).
   Lo de siempre de `splitIntoParts` —los tramos para un modelo de lenguaje, con su ventana
   fija— no cambia: ahí un tramo no puede pasarse del largo pedido.

**Los datos ya guardados.** Lo que se capturó antes —todo artículo de Wikipedia guardado hasta
hoy— tiene el texto de la Biblioteca sin esos títulos, y sus páginas de Procesado también. De la
Biblioteca nada se borra, y su texto solo se reemplaza en su lugar con «Volver a extraer el
texto» (F22), que reubica los subrayados; pero ese camino hoy no existe para una página web, a
propósito (`canReextractText`: volver a bajarla no es volver a leer el mismo original), y la
página archivada no sirve tal cual: sus fotos están incrustadas, y releerla da un texto de
1,6 MB con las imágenes en `data:` y sin sus direcciones. Queda para decidir (y toca
`reextraction.dart`, que este paso no podía tocar):

- **(a) Volver a leer la página archivada**, que es el mismo original, sin red: hace falta que
  el archivador guarde la dirección de cada foto (un atributo propio al lado del `data:`) para
  las páginas nuevas; para las viejas, devolverles las direcciones del texto anterior, que trae
  las mismas fotos en el mismo orden.
- **(b) Volver a bajarla**, con aviso de que la página pudo cambiar, por el mismo camino de F22
  (reemplazo en su lugar y subrayados reubicados), y después «Actualizar» el texto en Procesado,
  que conserva las páginas editadas y rearma el Índice en la misma transacción.

Mientras tanto, la guía dice cómo tenerlos: volver a guardar el enlace con «Guardar aparte».

**Pruebas** (todas con HTML o Markdown armados o recortados de las páginas reales, sin red):

- `reader_mode_article_extractor_test.dart`: los seis títulos de Fotosíntesis en su nivel y su
  lugar y sin «editar»; los nueve de Edad Media, con los de «Media» y «social»; lo que la página
  nombra como comentarios o para compartir se sigue yendo; y la regla sola (las formas del
  ancla, lo de adentro del título, el `id` que no es el texto, la palabra de estructura sola,
  la clase intacta).
- `markdown_inline_test.dart`: cada construcción, sus bordes, el texto sin Markdown, el texto
  entero contra renglón por renglón (300 al azar), buscar desde un corte anterior, y el corte
  antes, después y con un enlace de 5.000 caracteres.
- `reader_pagination_test.dart`: el párrafo real de Fotosíntesis (fixture) en bloques de 1.200,
  2.400, 300 y 80; antes del enlace que tapa el límite; un enlace más largo que una página; 200
  párrafos al azar, con cada tramo leído solo igual que en el texto entero.
- `text_parts_test.dart` y `processed_text_test.dart`: ni en «Dr. » ni en un espacio adentro de
  un enlace (y sin la regla, sí); el enlace más largo que el tramo, entero; 200 al azar, donde
  solo se pasa del tope lo que mide una construcción que no entraba; un texto sin Markdown,
  idéntico a lo de siempre; y la página de Procesado que se cortaba en «[bacterias ».

**Commits:** `d7820996` (las pruebas que atan la extracción de los títulos), `26776252` (el `id`
que es el ancla del título), `e1d4c750` (los cortes que no parten una construcción) y el de este
avance, con la guía y las Novedades.

**Mutaciones (`tool/mutar.py`): 22 de 22 muertas.** Sin sacar el control de edición; sin la
regla de las anclas; la palabra de estructura sin su excepción, o sin plural; solo el título y no
lo de adentro; cualquier `id` como ancla; sin la forma vieja, sin la de dirección, sin el número
de un repetido, sin quitar acentos o con los separadores en la clave; el lector sin el corte
seguro; el corte siempre después, o partiendo la construcción más larga que el tramo; el borde
como adentro; la imagen en HTML que cruza renglones; las páginas de Procesado sin `markdown`;
`splitIntoParts` que lo ignora; la oración o el espacio elegidos adentro de una construcción; la
búsqueda binaria que no mira dónde empieza (se cuelga); y el tope sin corte seguro.

**Queda:**

- **Los textos ya guardados** (ver arriba): la decisión entre (a) y (b), y su paso.
- **Los pedazos para la IA** (`tidyPieces`, `splitIntoParts` sin `markdown`) pueden partir un
  enlace al ordenar una página: el tope ahí es la ventana del modelo, y un tramo no puede pasarse.
  Con `markdown: true` y el tope duro solo para una construcción más larga que el tramo se
  arreglaría, si se ve que la IA los estropea.
- **El «Contenido» del lector** muestra hasta el nivel 3 a propósito (`readerHeadings`, F47); el
  Índice, todos.
- No se volvió a mirar en el emulador: hace falta una APK nueva y volver a cargar los artículos
  (los de la biblioteca de ejemplo ya cargados conservan su texto viejo).

### Paso 5c (hecho): el original desde el Índice, la página web que trababa y los avisos

Tres cosas que se vieron en el emulador con la biblioteca de ejemplo, en seis commits, de
`f86c8efd` al de este avance. Sin el emulador ni el teléfono: las pruebas son con fakes y las
mediciones, en la PC.

- **«Abrir en el original» del Índice, apagado sin necesidad** (`f86c8efd`). Con un documento
  procesado al «Pasar todo» —que pasa solo el texto—, Procesado no guarda su copia del original y
  la entrada quedaba apagada con «Este documento no guardó una copia de su original», aunque el
  documento conoce su fuente en la Biblioteca y las otras pantallas ya ofrecen «Ver el original en
  la Biblioteca». **La causa**: el puerto chico del Índice (`IndexDocumentAccess`) solo sabía de la
  copia de Procesado. Ahora `IndexDocumentFacts` lleva además la fuente (`IndexLibrarySource`: el
  elemento, qué original tiene y si está en la papelera), que `ProcessedIndexDocumentAccess` lee
  recién al abrir la hoja: el elemento por `LibraryRepository.watchById` y qué original tiene con el
  mismo `FileViewerResolver` que elige el visor de su ficha —así ofrece abrir en un lugar exactamente
  lo que ese visor sabe abrir en un lugar—. La copia de Procesado sigue ganando; sin ella:
  - un PDF se abre **en la página del marcador**, una página web **en el título del capítulo** (el
    que corresponde de los iguales) y un Word, un EPUB o un texto con su texto para estudiar, desde
    el comienzo, en la ruta nueva **`/library/:id/original`** (`RoutePaths.libraryOriginal`, con el
    mismo `?page=`, `?heading=` y `nth` que `processedOriginal`; las dos leen el lugar con
    `_originalPageOf` y `_originalHeadingOf`). La pantalla, `LibraryOriginalScreen`, es **la misma**
    que abre «Ver la página» o «Leer como libro» desde la ficha: `openDocumentViewer` la arma ahora
    con `libraryOriginalScreenOf`, que además pasa la página y el título a `OriginalView`. Si el
    elemento ya no está, lo dice;
  - una fuente cuyo original no se lee en un visor —un audio, un video, un YouTube, una foto— abre
    **su ficha**, que lo muestra;
  - apagada, diciendo por qué, solo sin copia y sin fuente, o con la fuente en la papelera
    («restaurala para abrir el original»). De la Biblioteca nada se borra ni se toca: solo se abre.

  Textos nuevos en los dos `.arb`, a la par y con sus descripciones: `f46P5cSourcePdfPage`,
  `f46P5cSourceHeading`, `f46P5cSourceStart`, `f46P5cSourceItem` y `f46P5cSourceInTrash`;
  `f46P4NoOriginal` dice ahora la verdad completa («No guardó una copia del original y su fuente ya
  no está en la Biblioteca») y las descripciones de `f46P4OpenOriginal` y `f46P4NoOriginal`, los dos
  caminos. **Pruebas**: siete en `index_actions_test` (PDF, página web con el segundo de los iguales,
  Word, audio a su ficha, papelera, la copia que gana y la hoja del documento) con la Biblioteca en
  el router de prueba; `processed_index_document_access_test` (diez: qué original de la fuente
  según su visor, la papelera sin mirar el visor, el elemento que ya no está) y
  `library_original_screen_test` (la dirección con el título llega al `WebPageViewerView`, la de la
  página, y el elemento que no está o sin original). **Mutaciones**: 13 de 13 muertas.

- **La página web de Fotosíntesis que trababa la app** (`10e48bf9`). Abrir en la Biblioteca el
  elemento «Fotosíntesis» —la página de Wikipedia archivada, 2,2 MB, embebida en su ficha con «Ver
  la página» encima— dio «Sinapsis Dev isn't responding». **Lo que se encontró**: el trabajo pesado
  de Dart ya corría en otro hilo (`showArchivedPage` dentro de `Isolate.run`); lo que quedaba en el
  hilo de la pantalla era leer y decodificar el archivo entero y mandarlo al otro hilo. Y, sobre
  todo, **la ficha le daba al `WebView` la página entera** —2.273.665 caracteres, 28 fotos adentro
  del archivo, 3.173 elementos— solo para mostrar su comienzo debajo de «Ver la página». El `WebView`
  recibe esa página (`loadHtmlString`), la navega, la dibuja y arma su árbol de accesibilidad **en
  el hilo principal de Android**, que es el único que puede dar un «no responde»: un hilo de Dart
  ocupado no lo da. En el emulador se recorrió además la pantalla con `uiautomator dump`, que pide
  ese árbol entero. No se pudo comprobar en el emulador cuál de esas tareas del `WebView` se pasó
  de los cinco segundos (este paso no lo usa); lo que se arregló de raíz es que la ficha ya no le
  da la página entera:
  - **la vista previa es el comienzo de la página** (`cutArchivedPagePreview`, con
    `showArchivedPage(previewLetters:)`): lo de antes del artículo —el encabezado, los menús— y las
    primeras 2.000 letras del artículo (`main`, `article` o `#mw-content-text`; si no hay, el
    `<body>`), donde **cada foto vale 800 letras** —lo que ocupa, unos diez renglones, y no lo que
    pesa—. Lo que sigue se saca; los estilos que estaban más abajo se mudan al `<head>`. Se corta
    **después de contar el texto** de la página entera: lo que queda está en el mismo lugar del
    texto corrido, así que lo estudiado, los resaltados y las notas se pintan igual en lo que se ve,
    y el programa de la app se agrega al final de lo que quedó. La vista previa no va a ningún
    título. La piden la ficha de la Biblioteca (`EmbeddedFileViewer`) y la tarjeta del original de
    un documento procesado (`ProcessedOriginalSection`) con `WebPageViewerView(preview: true)`; a
    pantalla completa, la página entera, como siempre;
  - **el archivo se lee en el otro hilo**: el visor manda un `ArchivedPageJob` (la ruta, no el
    texto; `archivedPageJobOf`) y `buildArchivedPage` lo lee y lo arma allá, desde una función de
    primer nivel para que al otro hilo viaje solo el pedido y nunca el visor.

  **Mediciones (PC, `flutter test`, el HTML real sacado del emulador y su Markdown, cuatro rondas)**:
  antes, el hilo de la pantalla leía y decodificaba el archivo en 12–22 ms y el `WebView` de la
  ficha recibía 2.273.665 caracteres, 28 fotos y 3.173 elementos, armados en 388–681 ms en el otro
  hilo; después, el hilo de la pantalla no lee nada y el `WebView` recibe **643.877 caracteres (el
  28 %), 6 fotos y 1.050 elementos (el 33 %)**, armados en 398–440 ms en el otro hilo (el texto se
  sigue contando entero, para que lo estudiado caiga en su lugar). **Pruebas**: seis en
  `archived_page_study_test` (lo que queda y lo que se va con sus fotos, el estilo mudado, que lo
  que queda sea el comienzo del texto de la página entera y el alineamiento el mismo, la foto que
  vale diez renglones, sin título, la página corta entera y sin artículo marcado),
  `web_page_job_test` (el pedido a pantalla completa y en la ficha) y la vista previa pedida en la
  ficha y en la tarjeta de Procesado, y no a pantalla completa. **Mutaciones**: 11 de 11 muertas.

- **El aviso con hueco** (`ae057a7f`). En el lector, la tarjeta «Todavía no tiene palabras clave»
  —la de lo que falta en cada resultado de Extraer, `_MissingCard`, la misma para el resumen, la
  síntesis y las palabras clave— ponía «Marcar con IA» y «Abrir el documento» en un `Wrap`: cuando
  no entraban, cada uno con su ancho, pegados a la izquierda y con un hueco grande a la derecha.
  Ahora van en un **`AdaptiveButtonBar`** (`lib/core/design/widgets/adaptive_button_bar.dart`), un
  `RenderBox` propio: si la suma de sus anchos naturales y el espacio entra, en un renglón, con 8
  entre ellos y centrados en alto (de derecha a izquierda, el primero a la derecha); si no,
  apilados, con 8 entre ellos y **todos del ancho entero**. **Pruebas**: el widget a 360 y 412 dp
  con la letra a 1,0, 1,3 y 2,0, justo al límite, de derecha a izquierda, alturas distintas y el
  toque; y la tarjeta de verdad en el lector, en los mismos seis casos, midiendo posiciones.

- **Los huecos en el texto** (`09e10ac8`). Entre «véase Fotosíntesis (película).» y
  «Representación esquemática…» no había cajas reservadas ni fotos que no cargaban: el texto
  procesado trae cada foto de la página como un renglón propio —`[![](https://thumb.wikimedia…)](…)`,
  sin texto alternativo— y `RenderedMarkdown` la leía como nada **pero dejaba sus fines de línea**:
  entre dos párrafos, tres renglones vacíos. El 429 de Wikimedia no tiene que ver: el lector no
  baja esas fotos. **De raíz, en el renderizador** (`_collapseVanished`): cada tramo seguido de
  renglones vacíos y de renglones que no muestran nada, con al menos uno de estos, se ve como sin
  ellos —un solo corte de párrafo si había un renglón vacío, ninguno si la foto estaba sola entre
  dos renglones, nada al comienzo del texto—. Lo que se quita sigue en el crudo con su lugar: cada
  tramo que se ve es el mismo pedazo del crudo y los resaltados caen donde caían. Los renglones
  vacíos que no tocan una foto quedan como estaban; una foto con texto alternativo se sigue
  leyendo. **Pruebas**: siete en `markdown_display_test` (Fotosíntesis, la foto sola entre dos
  renglones, varias seguidas y al comienzo, los espacios de su renglón, la que tiene texto
  alternativo, los renglones vacíos sin foto y un resaltado guardado). **Medición (PC)**: el texto
  de Fotosíntesis tiene 17 renglones de foto sin texto alternativo; con el renderizador de antes, lo
  que se veía tenía 17 huecos de tres renglones vacíos o más, y ahora ninguno.

  **Mutaciones** de los dos: 8 de 8 muertas en la barra y la tarjeta, y 6 de 6 en el
  renderizador; una de estas —que el renglón de la foto se quede con los espacios que la rodean—
  sobrevivió en la primera vuelta, y la mató la prueba de los espacios, que se agregó por eso.

- **La GUÍA** (`ad4df27f`) dice lo nuevo de «Abrir en el original» del Índice, que la ficha
  muestra el comienzo de una página web y la entera se abre con «Ver la página», cómo van los
  botones de lo que falta y que una foto sin descripción no deja un espacio en blanco en el texto.

**Sobre `main`**: los commits se rebasaron sobre `32e3d23c` (el paso 5b, que movió la regla de lo
en línea de `RenderedMarkdown` a `markdownInlinePattern`), sin conflictos: el arreglo de los huecos
está en el armado de los renglones, no en esa regla.

**Analizador**: 19 avisos, la línea base (todos `comment_references` previos). **Pruebas**, con
fakes y `--concurrency=2`: antes del rebase, `test/features/index`, `viewer`, `processed`,
`creations`, `organize`, `library` y `reading`, `test/app` y `test/core`: 5.836 pasan, 0 fallas;
después, las mismas salvo `creations` fuera de `extract`: 3.884 pasan, 0 fallas.

**Queda para la sesión principal**: mirar en el emulador que la ficha de «Fotosíntesis» abre sin
trabarse —también con `uiautomator dump`— y que «Ver la página» abre la entera; que «Abrir en el
original» de un documento pasado con «Pasar todo» abre el PDF en su página y la página web en su
título; y la tarjeta de lo que falta y el texto de Fotosíntesis sin huecos, en el teléfono.

### Paso 5d (hecho): el aviso sin hueco

**Qué se vio** (emulador, 427 dp de ancho a 3x): el aviso de la Biblioteca de ejemplo, «Biblioteca
de ejemplo: cargados 76 · con error 4» con **«Ver qué falló»**, mostraba un renglón de texto, un
hueco grande y recién abajo a la derecha el botón, con más aire abajo que arriba. `uiautomator`
medía el aviso en 345 px (115 dp con los márgenes de afuera del `SnackBar`: la tarjeta, 100), la ✕
en [1079,2214][1223,2358] y el botón debajo de ella, en [895,2358][1223,2502].

**Causa**: el texto entraba en un renglón al lado de la ✕, pero no al lado del botón y la ✕, y el
aviso se armaba «como tarjeta» con la ✕ arriba a la derecha —centrada con el primer renglón, con
su caja de 48 para el dedo, de 0 a 48— y los botones en un renglón propio en
`max(fin del texto + 4, fin de la ✕)`: con un renglón de texto (de 14 a 34), la ✕ ganaba y los
botones bajaban a 48, con 4 más abajo de ellos. El hueco era la caja de la ✕.

**Qué se hizo** (`cba0717e`): con botones, si no entra todo en un renglón, el texto toma el ancho
entero arriba (menos 16 de cada lado) y, justo debajo, van los botones y la ✕ en un renglón pegado
a la derecha —en un idioma que se escribe al revés, a la izquierda—, centrados entre sí, como el
`SnackBar` de Material 3 con un botón largo pero sin su aire de más: el renglón empieza donde
termina el texto y el aviso donde termina el renglón, porque los botones y la ✕ ya traen su aire
adentro, el mismo arriba y abajo de su letra. Con un renglón y un botón, el aviso mide
14 + el renglón + 48: 82 en el teléfono (antes 100), 76 con la letra de las pruebas.

- **Si los botones no entran juntos al lado de la ✕** (dos botones con la letra grande), se apilan
  a la derecha en el orden en que se leen y la ✕ queda **al lado del último**, el principal,
  centrada con él. Se eligió así porque deja al principal pegado a la ✕ como en cualquier renglón
  —«Ver», «Deshacer», ✕—, y la ✕ queda abajo a la derecha, en el mismo lugar en todo aviso con
  botones; arriba de ella no hay nada, porque los botones apilados terminan donde empieza la ✕.
- **Sin botones**, no cambia: el texto al lado de la ✕, que queda arriba a la derecha, centrada
  con el primer renglón. **En un renglón**, tampoco: todo centrado, 48 de alto.
- Los botones dejan de ir en un `OverflowBar` y pasan a ser dos lugares del acomodo
  (`secondaryAction` y `action`): para centrar la ✕ con el último botón apilado hay que saber
  dónde queda cada uno. Las cajas de 48 nunca se enciman: los botones van a la izquierda de la ✕ y
  debajo del texto.
- **Intrínsecas, medida en seco y línea base**: con botones, lo más angosto es la palabra más larga
  con el ancho entero o el botón más angosto apilado al lado de la ✕; lo más ancho, todo en un
  renglón; el alto sale de la misma cuenta que el acomodo. El acomodo no tenía **línea base en
  seco** (`computeDryBaseline`) y ahora la tiene: la del texto, medida con el ancho que le toca. El
  toque y el dibujo recorren las partes donde quedaron; la huella que publica (`SnackBarFootprint`)
  la mide `TopEdgeProbe` sobre el borde de arriba del aviso, así que lo que flota se corre lo justo,
  más bajo que antes.

**Archivos**: `lib/core/design/widgets/app_snack_bar.dart` (el comentario de la clase dice el
acomodo nuevo y el porqué), `test/core/design/widgets/app_snack_bar_test.dart`, la GUÍA y la
decisión del aviso único en `docs/arquitectura.md` (`8a337aeb`).

**Pruebas** (todas con fakes): cambian cinco que fijaban la ✕ arriba en la tarjeta con botones —el
texto «hasta la ✕», la ✕ «a la altura del primer renglón», los botones «4 arriba del borde» y
«debajo de la ✕»—, que ahora dicen que la ✕ va en el renglón del último botón, pegada a él, y que
no hay aire de más arriba ni abajo del renglón. Se suman 113: a 360, 412 y 427 de ancho, con la
letra a 1, 1,3 y 2, con un botón corto, uno largo o dos, texto de uno y de tres renglones, de
izquierda a derecha y al revés (108), que nada se encime, que las cajas de 48 estén enteras y
adentro, que la ✕ esté al final y en la fila del último botón, que los botones vayan juntos con 4
entre ellos o apilados, y que la medida en seco, las intrínsecas y la línea base digan lo que se
ve; y el alto justo con un renglón y un botón (76), el caso en un renglón que no cambia (48), el
aviso sin botones, los toques en el borde entre la ✕ y el botón, y el aviso de la Biblioteca de
ejemplo a 427. El archivo pasa de 17 a 130 pruebas.

**Mutaciones** (`tool/mutar.py`): 19 de 20 muertas —aire entre el texto y el renglón o debajo de
él; el texto sin el ancho entero; la ✕ arriba en la tarjeta; siempre apilados o nunca; la ✕ con el
primer botón apilado; aire debajo de los apilados; los apilados contra el borde o sin bajar; sin
espacio entre botones; el último despegado de la ✕; el renglón sin centrar; los botones al revés;
las tres del mínimo de ancho; el espacio fuera del ancho del renglón; y la línea base en seco sin
el corrimiento del texto—. Sobrevivió una, equivalente: la línea base en seco medida con el ancho
del aviso en vez del del texto da lo mismo para un texto, cuyo primer renglón no depende del ancho;
se deja el ancho del texto porque es el que de verdad le toca.

**Sobre `main`**: rebasado sobre `28aa3caa` (el paso 5c) sin conflictos.

**Analizador**: 19 avisos, la línea base. **Pruebas**, con `--concurrency=2`, sobre la rama
rebasada: `test/core/design` (con el censo de los avisos y la huella) y los archivos de pruebas que
muestran un aviso —Biblioteca de ejemplo, Bandeja, Repasar, el lector en voz alta, la IA y los
demás—: 986 pasan, 0 fallas.

**Queda para la sesión principal**: mirarlo en el emulador con una APK nueva —el aviso de la
Biblioteca de ejemplo a 427 dp debería medir 82 dp de tarjeta, con «Ver qué falló» y la ✕ juntos
justo debajo del texto—.

### Paso 5e (hecho): lo que viaja al chat, como se lee

**El defecto** (visto en el emulador). En el Índice, «Preguntar al chat» sobre el capítulo «Siglo XX»
de «Fotosíntesis» —una página de Wikipedia— dejaba en el campo del chat *«Sobre el capítulo «Siglo
XX» de «Fotosíntesis»: «Siglo XX En 1905, [Frederick Frost Blackman](https://es.wikipedia.org/wiki/…)
… la síntesis de [glucosa](https://es.wikipedia.org/wiki/Glucosa) procedía de la…»»*. Tres cosas:
el Markdown viajaba crudo —enlaces con su dirección, fotos `![…](…)` con direcciones larguísimas,
`**`, `#` y las notas al pie `[[1]](…)`—, que veía la persona y recibía el modelo, y las
direcciones se comían el tope de 2.000; el tramo empezaba en el propio título y lo pegaba al
párrafo («Siglo XX En 1905»); y «Explicar» de las tarjetas tenía el mismo defecto.

**La causa**: `indexChapterPassage` y `explainPassage` cortaban del texto crudo y solo juntaban los
espacios. El texto propio de una página web es el Markdown que escribe `htmlToMarkdown`, y lo que
se ve en el lector es otra cosa: `RenderedMarkdown` lo interpreta. Ninguno de los dos caminos al
chat pasaba por esa interpretación, y había cuatro maneras sueltas de pasar Markdown a texto llano,
cada una con su regla (`studyPlainText`, el `_plain` del extracto, `_stripMarkdown` de la voz y
`plainHeadingText`).

**Lo que se hizo, de raíz** (doce commits, de `4b6b6e19` al de este avance, rebasados sobre el
paso 5d sin conflictos):

- **Qué se lee de cada construcción, en un solo lugar** (`markdownInlineText`, en
  `lib/core/util/markdown_inline.dart`). Junto al patrón del paso 5b: para una coincidencia de
  `markdownInlinePattern`, cuál es (`MarkdownInline`: código, imagen, enlace, `[[Título]]`, enlace e
  imagen de HTML, superíndice, subíndice, negrita, cursiva, y si lo de adentro se vuelve a leer) y
  el tramo que se lee. `RenderedMarkdown._parseInline` lo usa ahora: le da el formato y quita lo de
  alrededor, sin decidir él qué se ve. El comportamiento del lector no cambió: sus pruebas de antes pasan sin
  tocarlas.
- **Lo que se lee de un texto en Markdown** (`markdownPlainText` y `markdownPlainBlocks`, en
  `lib/core/util/markdown_plain_text.dart`). Lo en línea con `markdownInlineText`, como el lector;
  y los bloques: un párrafo —sus renglones hasta uno en blanco— es un bloque; un título, un
  elemento de lista y una fila de tabla, uno cada uno, sin `#` ni viñeta (el número de una lista
  numerada queda: es parte de lo que se lee) y con las celdas separadas por coma, como las lee la
  voz; la cita sin `>`; el separador y la fila separadora de una tabla, nada; un bloque de código
  entre cercas, tal cual. Lee de a un renglón y recién cuando se pide el bloque siguiente: el
  comienzo de un capítulo largo no recorre el libro.
- **Las notas al pie se van** (`markdownFootnoteCall`: `[1]`, `[a]`, `[n. 1]`, `[nota 3]`,
  `[cita requerida]`, en enlace o sueltas). Sin la nota, que no viaja, no dicen nada; en un párrafo
  de Wikipedia hay una cada pocas oraciones, y son letras de menos en el tope. Adentro del código no
  se tocan. El lector las sigue mostrando: en la pantalla llevan a la nota.
- **El pasaje que viaja al chat** (`readablePassage`, en el mismo archivo). Con Markdown, cada
  bloque es una oración —uno que no termina en un signo recibe un punto: «Siglo XX. En 1905…»—,
  todo en un renglón, y **recién después** el tope y el corte en una palabra entera con «…»: el
  tope cuenta letras que se leen. Sin Markdown —un PDF, una transcripción—, tal cual y en un
  renglón: ahí un renglón sin punto es casi siempre una oración que sigue abajo, y un `*` no es una
  marca.
- **«Preguntar al chat» del Índice** (`indexChapterPassage`). El puerto del Índice
  (`IndexDocumentAccess.textOf`) devuelve ahora el texto **y si es Markdown**
  (`IndexDocumentText`), como lo sabe `ProcessedStudyText.markdown`; `_askAboutEntry` le pasa además
  el título del capítulo, y el renglón con que empieza el tramo queda afuera si es ese título
  —comparado con `headingKey`, sobre el renglón como se lee, y también con su número delante
  («3. Siglo XX», «1.2 Desarrollo»)—. Si el tramo no empieza con él —el título de la IA de un PDF,
  que no es un renglón—, no se saca nada. Un capítulo que es solo su título no tiene texto: se avisa
  como siempre.
- **«Explicar»** (`explainPassage`, `explain_in_chat_button.dart`). El mismo pasaje legible, con
  `markdown: extractedTextIsMarkdown(item.source)`, la regla con que la app ya decide si el texto de
  un elemento es Markdown, y su tope de 600.
- **Estudiar y el extracto delegan** (`studyPlainText`, el `_plain` de `extract_markdown.dart`). Las
  oraciones del resumen y de la síntesis y las palabras clave que van al modelo, que se copian y que
  se descargan salen ahora de `markdownPlainText`: antes dejaban la cursiva con sus `*`, una foto
  enlazada a medias y la nota `[[1]](…)` entera.

**Lo que no se cambió, y por qué:**

- `chatAnswerPlainText` (lo que se copia de una respuesta): ya usa el lector para lo en línea, y
  sus bloques los conserva a propósito —viñetas, números, «———», `|`— porque es para pegar.
- `_stripMarkdown` de la lectura en voz alta: corta por oraciones con sus posiciones en el crudo,
  no dice el texto alternativo de una foto (no se pronuncia) y lee `[[a|b]]` y escapes; son otras
  reglas, y cambiarlas mueve los ±10 s y el resaltado de lo que suena.
- `plainHeadingText`: de él sale `headingKey`, la clave de los títulos ya indexados; lee escapes,
  entidades, `~~` y `[^1]`. Cambiarlo cambiaría los títulos del Índice sin reindexar.
- Los otros caminos al chat no llevan texto de un documento: `askAiAbout` (`reading_frame.dart`) y
  el del documento del Índice, solo el título; el del Mapa (`map_screen.dart`), la pregunta armada
  con los nombres de los temas; el del mapa mental (`mind_map_actions.dart`), las etiquetas de las
  ideas, que escribió el modelo.

**Cifras** (PC, el recorte real de Fotosíntesis pasado a Markdown como lo guarda la app):

| Capítulo | Crudo | Antes: viajaba | Antes: legible | Ahora |
|---|---|---|---|---|
| «Siglo XX» | 1.249 | 1.245 (con «### Siglo XX» y una dirección) | 1.183 | 1.174, entero, empieza en «En 1905» |
| «Historia del estudio» | 6.017 | 1.993, cortado (15 direcciones) | 1.217 | 1.996 legibles, cortado |

En el capítulo largo, antes el 39 % del tope eran direcciones; ahora entran 1.996 letras que se
leen, un 64 % más de texto. (El recorte es más corto que la página real: en el emulador, «Siglo
XX» traía además fotos y notas, que ahora no ocupan nada; lo prueba un caso armado con una foto de
Wikipedia y sesenta notas.)

**Pruebas**, todas con fakes: `markdown_plain_text_test` (cada construcción, combinadas, los
renglones, la foto sin texto alternativo entre palabras, las notas en enlace, sueltas y adentro del
código, «2 * 3 * 4» y «var_uno_dos», cada bloque, el tramo pedido con fines de renglón de Windows,
el pasaje y su tope) y **la que ata las dos reglas**: renglón por renglón, sobre los recortes de
Fotosíntesis y Edad Media, el párrafo real con sus notas y un renglón de cada construcción,
`markdownPlainText` da lo mismo que `RenderedMarkdown.displayText` sin las notas
(`test/support/wikipedia_fixtures.dart` arma el Markdown de un recorte como lo hacía la prueba del
extractor del 5b). `index_chapter_test`: «Siglo XX» empieza con «En 1905», sin «](», «http», «![»,
«#», `**` ni renglones; «Historia del estudio» lleva más del 90 % del tope en letras legibles; la
foto y las notas; el subtítulo de adentro como oración; el título con número; el renglón que no es
el título; el capítulo de solo su título. `explain_in_chat_question_test` (la página web y el recorte
real), `processed_index_document_access_test` (el texto con si es Markdown, y sin texto),
`index_actions_test` (el borrador del capítulo de una página sin su título ni la dirección del
enlace, y el de un PDF tal cual) y `study_extracts_test`.

**Mutaciones** (`tool/mutar.py`): 69 armadas sobre `markdown_plain_text.dart`, `markdown_inline.dart`,
el lector, `index_chapter.dart`, `index_actions.dart`, `processed_index_document_access.dart`,
`explainPassage` y `studyPlainText`. En la primera vuelta murieron 56 y sobrevivieron 13: diez por
pruebas que faltaban —el título que corta un párrafo sin renglón en blanco, el código con fines
de renglón de Windows, el corte con el último espacio lejos del tope, la imagen con un texto
alternativo de espacios, el `<img>` con el suyo escapado y el subíndice (las dos últimas no las
podía ver la prueba que compara con el lector, porque las dos reglas son la misma), el formato del
subíndice y del código en el lector, el renglón que termina en el título sin ser su número y el
título que es un enlace—, que se agregaron y las mataron en la segunda vuelta; y tres eran guardas
que no cambiaban nada (el capítulo de solo su título, el título sin letras y el tramo al revés de
«Explicar», que `readablePassage` ya deja vacíos), que se sacaron. **66 de 66 muertas.**

**Analizador**: 19 avisos, la línea base. **Pruebas**, con fakes y `--concurrency=2`, antes del
rebase: `test/features/study`, `organize`, `flashcards`, `habit`, `chat`, `processed` y
`creations`, 4.679 pasan y 0 fallas; `test/features/index`, `test/core/util` y las de «Explicar» y
Estudiar después de los últimos cambios, 344 pasan y 0 fallas; y `test/core` entero, en la primera
tanda, sin fallas. En esa primera tanda falló una de Estudiar —«una oración que queda vacía sin
marcado no cuenta», con `**__**`—: la regla común muestra `__` como el lector, y `studyPlainText`
ahora deja vacío lo que no tiene ni una letra ni un número (`490d8dd4`).

**Queda abierto**: el material de las creaciones (`CreationMaterialBuilder`) y los pasajes del chat
que salen de la búsqueda en la bóveda (`chat_passages.dart`) le siguen llegando al modelo en
Markdown crudo. No es el mismo defecto que se ve —no lo lee la persona en el campo— pero las
direcciones también le comen ventana; los dos guardan posiciones en el crudo (la cita del chat
salta a su pasaje, y «Ver en el documento» busca el de la creación), así que pasarlos a lo que se
lee pide traducir esas posiciones y queda para otro paso. Para la sesión principal: mirar en el
emulador el borrador de «Siglo XX» y el de «Explicar» de una tarjeta de una página web.

### Paso 5g (hecho): el lugar del reproductor de «leer en voz alta»

**Qué se vio** (emulador, 1280x2856 px, unos 2,86 px por dp):

- **H.** En Ajustes › «Clonación de voz», el mini reproductor quedaba a la altura de cuando hay
  barra de pestañas (y=2448 px): tapaba el botón «Empezar» y abajo dejaba un hueco vacío, donde no
  había barra.
- **K.** Con el reproductor achicado, en **Ajustes** el último renglón, «Bloquear bóveda», quedaba
  debajo de él y no había forma de subirlo; en **Estudiar › Cuadernos**, vacío, el botón flotante
  «Nuevo cuaderno» quedaba casi entero debajo y solo asomaba un borde; en la **bienvenida del
  chat**, el reproductor —parado sobre el campo— tapaba a medias «Cargar una clave» de la tarjeta
  de Gemini; y en **Organizar › Bandeja**, la tarjeta de triar quedaba centrada en todo el cuerpo,
  sin contar el reproductor, con mucho aire arriba y poco abajo.

**Las causas**, una sola raíz: la geometría del reproductor anclado, que va por encima de todo
(`ReadAloudOverlay`, en el `builder` de la app):

- **H**: `_shellOnTop()` decidía si había barra mirando la configuración de `go_router`
  (`matches.last is ShellRouteMatch`), y `go_router` no se entera de una pantalla abierta con
  `Navigator.of(context, rootNavigator: true).push(...)`: para él seguía arriba la pestaña.
- **K**: casi ninguna pantalla sabía que el reproductor existía. Solo el marco de lectura
  (`ReadingPlayerSlot`) y el podcast leían su alto (`readAloudPlayerExtentProvider`) y le
  reservaban lugar a mano; el resto —listas con su propio margen, botones flotantes, lo centrado—
  quedaba debajo.

**Los arreglos**:

- **H (`dd3d3680`): si la barra de navegación se ve lo dice la barra misma.** `NavigationBarScope`
  (`lib/app/navigation/navigation_bar_scope.dart`) envuelve el `Scaffold` de las pestañas
  (`AdaptiveScaffold`, en el celular) y avisa en `navigationBarShownProvider` mientras su ruta es
  la de arriba (`ModalRoute.isCurrent`) o lo de arriba es un diálogo, un panel o un menú —que se
  llevan el foco: `popupRouteHasFocus`, el mismo criterio con que el lector ya se hacía a un lado—;
  y no se ve si su ruta quedó fuera de escena (`TickerMode`), aunque arriba haya un diálogo. Se
  descartó mirar la animación de la ruta de abajo (`secondaryAnimation`): no se mueve con una
  pantalla a pantalla completa (`fullscreenDialog`), que es justo «Clonación de voz». Se entera en
  el momento en que se abre otra pantalla encima —la abra el router o un `Navigator.push`— y vuelve
  apenas se empieza a cerrar. Una pantalla abierta dentro de una pestaña, en el navegador de la
  rama, no la tapa; en una pantalla ancha, con el riel, no hay barra abajo, y el lector ya no mira
  el ancho por su cuenta. El alto de la barra sale de un solo lugar (`navigationBarHeightOf`).
  Las pantallas de la lista, caso por caso: las que usan `rootNavigator: true` —«Clonación de voz»
  (y su `pushReplacement` a sí misma, que sigue en el navegador de la raíz), «Crear una voz», la
  presentación a pantalla completa— tapan la barra, y antes el lector no se enteraba (el panel de
  conversaciones del chat también va a la raíz, pero es una ruta emergente: deja ver la barra y
  el lector se hace a un lado); las demás usan `Navigator.of(context)` y van al navegador de quien las
  abre: desde una pestaña, al de la rama, con la barra a la vista —«Lo que puede hacer la IA» y
  «Las imágenes en el teléfono» desde Ajustes, el valor de un vocabulario—, y desde una pantalla que
  ya tapa las pestañas —el detalle de un elemento, Capturar, un procesado abierto encima—, sobre
  ella, sin barra. Antes las dos maneras daban «hay barra» si debajo había una pestaña; ahora lo
  resuelve la barra en todos los casos, sin una lista que mantener.
- **K (`a301815c`): las pantallas le dejan su lugar al reproductor como al teclado.**
  `ReadAloudRoom` (`read_aloud_room.dart`) le pasa a las pantallas el alto del reproductor como
  algo que tapa el pie de la ventana, por `MediaQueryData.viewInsets`, lo mismo que el teclado:
  cada `Scaffold` achica su cuerpo hasta el borde de arriba del reproductor. Con eso el final de
  una lista se sube por encima de él aunque la lista tenga su propio margen —Ajustes—, el botón
  flotante y los avisos quedan arriba, y lo centrado se centra en lo que queda a la vista, sin que
  ninguna pantalla haga nada. Se evaluó la idea de pasarlo por `padding`/`viewPadding`: alcanza a
  `SafeArea`, a las listas sin margen y al botón flotante, pero no a una lista con su propio margen
  como la de Ajustes ni a lo centrado, que habría que tocar pantalla por pantalla.
  - **Al pie** (una pantalla sin barra): `ReadAloudOverlay` le da al `Navigator`
    `mediaWithRoomAtBottom`, el alto del reproductor más el borde seguro de abajo, que el
    reproductor lleva debajo; el borde entra de a poco con los primeros píxeles, así lo que lo
    respeta no salta al aparecer o irse el reproductor.
  - **Encima de la barra**: `NavigationBarScope` le da al `Scaffold` de las pestañas
    `mediaWithRoomAboveBar` —la barra, su borde y el reproductor—; el cuerpo se achica hasta arriba
    del reproductor y la barra queda donde está, debajo. Lo toma de `ReadAloudRoom`, no del
    `MediaQuery` de arriba: así no cambia mientras se abre o se cierra otra pantalla encima de las
    pestañas, ni con un panel abierto. `AdaptiveScaffold` mira el teclado de verdad
    (`ReadAloudRoom.outerOf`) para irse con él, no el lugar del reproductor.
  - **Con el teclado** manda el más alto de los dos, no la suma: el reproductor se hace a un lado y
    el teclado lo tapa; al cerrarse, el contenido baja hasta donde vuelve el reproductor, sin saltar.
  - **Los diálogos y paneles no lo ven**: abiertos encima, el reproductor se hace a un lado y el
    `MediaQuery` de arriba del `Navigator` —que también ven ellos— suelta su lugar en el acto; un
    panel empieza desde el pie. Las pestañas lo conservan: ahí no lo ve nadie más.
  - **Con la Lectura enfocada, el lugar sigue a la forma elegida** (`resting`), no a la de cada
    momento (`current`): el reproductor se achica mientras se desplaza, pero lo que se arrastra no
    cambia de alto a mitad del arrastre, y los avisos se quedan donde estaban, encima de él. El
    lugar cambia, con el mismo andar que el reproductor (220 ms), al abrirlo, cerrarlo, achicarlo
    o agrandarlo.
  - **El reproductor va siempre en el mismo lugar**: encima de la barra o al pie. Lo que se le pide
    esquivar (`ReadAloudClearance`: el campo del chat, el mini reproductor del audio, los controles
    de página, el aviso de un enlace roto) lo sigue esquivando el botón redondo; el reproductor ya
    no se para encima, porque la pantalla le deja su lugar debajo y eso queda arriba de él. En el
    chat, el campo va arriba del reproductor y la bienvenida no queda tapada.
  - **Sin reproductor, nada cambia**: `MediaQuery` es el mismo de siempre.
  - **Lo que reservaba a mano, ya no**: el marco de lectura (`ReadingPlayerSlot`, sonando, ya no
    ocupa nada: quedaría doble) y el podcast. Se borraron `readAloudPlayerExtentProvider` y
    `SnackBarFloor`, que subía los avisos sobre el reproductor: ahora los pone encima el `Scaffold`.
    El reproductor mide solo su forma, sin el borde seguro, que depende de dónde se pare.
  - **Las dos barras con botón al pie de una pantalla** (`Scaffold.bottomNavigationBar`: «Elegir
    temas» de lo que no tiene tema y «Guardar» de las preguntas de un cuestionario) usan
    `BottomActionBar`, que se para encima de lo que tape el pie: un `Scaffold` deja su barra de abajo
    debajo del teclado, y también la dejaría debajo del reproductor.

**Archivos**: `lib/app/navigation/navigation_bar_scope.dart` (nuevo), `adaptive_scaffold.dart`,
`lib/features/narration/presentation/read_aloud/read_aloud_room.dart` (nuevo, con `HeightProbe`,
que viene de `read_aloud_player_extent.dart`, borrado), `read_aloud_overlay.dart`,
`read_aloud_anchored_player.dart`, `read_aloud_clearance.dart`,
`lib/core/design/widgets/bottom_action_bar.dart` (nuevo), `snack_bar_footprint.dart`,
`reading_player_slot.dart`, `podcast_viewer.dart`, `quiz_review_screen.dart`,
`unsorted_items_screen.dart` y `app.dart`; la GUÍA y `docs/arquitectura.md`.

**Pruebas** (todas con fakes; `--concurrency=1`, de a una tanda por vez):

- **H**, siete nuevas: en `read_aloud_overlay_test.dart`, una pantalla abierta encima con
  `Navigator.push` a pantalla completa tapa la barra en el momento —antes de terminar de abrirse,
  el reproductor ya va al pie— y vuelve apenas se empieza a cerrar; una abierta dentro de la
  pestaña no la tapa; un diálogo tampoco —el reproductor se hace a un lado y vuelve arriba de la
  barra—; sin barra no hay nada que avisar. En `adaptive_scaffold_test.dart`, con el router de
  verdad: la barra se ve, la tapa un `Navigator.push` a pantalla completa como «Clonación de voz»
  y vuelve al cerrarlo; la lista de un paso no la tapa; en una pantalla ancha no hay barra. Y una
  más con el K: un diálogo sobre una pantalla que tapa a las pestañas no las destapa.
- **K**, diecisiete nuevas: en una pestaña y en una pantalla abierta con `Navigator.push`, el
  final de una lista larga con su propio margen se sube por encima del reproductor; sin
  reproductor la lista llega hasta la barra y `MediaQuery` es el de siempre; el botón flotante
  queda entero arriba en una pestaña —con la barra debajo del reproductor— y en una pantalla
  abierta encima, y vuelve a su lugar al cerrarlo; con el borde seguro, al pie y encima de la
  barra; con el teclado manda el teclado, al pie y en una pestaña; un panel no ve el lugar ni en
  sus primeros cuadros y empieza desde el pie; en una pantalla ancha la lista termina arriba del
  reproductor; achicado, el lugar es el del achicado. Con la app de verdad
  (`adaptive_scaffold_test.dart`, el lector encima como en `App`): en Ajustes, «Bloquear bóveda»
  se sube por encima del reproductor; en Cuadernos vacío, «Nuevo cuaderno» queda entero arriba;
  y en una pantalla ancha, con el riel —que también se achica—, lo último de Ajustes también. Y
  `bottom_action_bar_test.dart`: el botón va encima del borde seguro y encima de lo que tapa el
  pie, sin sumar el borde que quedó debajo.
- **Cambian** seis que fijaban la geometría vieja: el reproductor ya no se para sobre lo que
  esquiva el botón (ahora, eso queda arriba de él); en vez del alto publicado, el cuerpo de la
  pestaña termina donde empieza el reproductor; con la Lectura enfocada la lista que se arrastra
  no cambia de alto y el aviso se queda donde estaba, encima del reproductor achicado; y en el
  marco, lo que se lee termina donde empieza el reproductor, abierto o achicado, sin lugar
  reservado aparte. **Se borran** las cuatro de `SnackBarFloor`.
- La tanda relacionada —`test/features/narration`, `test/app`, `test/core/design`,
  `test/features/reading`, el podcast, el extracto, las pantallas de tarjetas, lo que no tiene
  tema y el chat que lee en voz alta— pasa entera: 1.486 pruebas, y después de las pruebas de las
  mutaciones, las 506 de las carpetas tocadas (el lector, la navegación, el marco y los widgets del diseño).

**Mutaciones** (`tool/mutar.py`): 24 de 24 muertas. **H** (5): un panel encima tapa la barra; la
barra se ve con otra pantalla encima; sin mirar si su ruta está en escena; el lector no lee lo que
dice la barra; el andamio no avisa. **K** (19): sin el borde seguro debajo del reproductor; el
teclado y el lugar se suman, al pie y encima de la barra; el borde seguro sigue contando debajo de
lo tapado; encima de la barra sin su borde; la barra sin lugar o con el del `MediaQuery` de arriba;
el teclado de la barra con el lugar del reproductor (la barra se iba); los paneles ven el lugar, o
se les va despacio; el lugar sigue al abierto estando achicado, queda sin lector, sigue a lo de
cada momento con la Lectura enfocada o salta en vez de acompañar; el reproductor se para sobre lo
que esquiva el botón; el alto medido con el borde seguro; el marco reserva su lugar aparte; y la
barra con botón no sube o pierde el borde seguro. Equivalentes, no se mutaron: la salida temprana
sin lugar de `mediaWithRoomAtBottom` y `mediaWithRoomAboveBar` (con 0 dan el mismo `MediaQuery`,
o uno que el `Scaffold` acomoda igual: es para no armar uno nuevo), y que `NavigationBarScope`
se retire al desmontarse (antes de irse ya avisa que no se ve, porque su ruta deja de ser la de
arriba; el retiro es por si algún día no fuera así).

**Sobre `main`**: rebasado sobre `8aa95914` (el paso 5e); el único choque fue este Avance, al final del
plan, que va después del 5e.

**Analizador**: 19 avisos, la línea base.

**Queda para mirar en el emulador** (con una APK nueva): «Clonación de voz» con algo sonando —el
reproductor al pie apenas se abre, sin tapar «Empezar», y de vuelta arriba de la barra al
cerrarla—; Ajustes con el reproductor achicado y abierto, hasta «Bloquear bóveda»; Cuadernos vacío,
con «Nuevo cuaderno» entero arriba; la bienvenida del chat, con el campo arriba del reproductor;
la Bandeja, con la tarjeta centrada en lo que queda; el teclado en el chat con algo sonando; un
panel (la velocidad, la cola) abierto desde el reproductor en una pantalla sin barra; y la
Lectura enfocada desplazando una lista larga, que no debería cambiar de alto.

### Paso 5f (hecho): la negrita del PDF, el Mapa vacío, «Escuchar» desde lo que se ve y el nombre de la voz

**Qué se vio** (emulador), cinco cosas:

- **B.** En el PDF de «Descargar el índice», todo salía en negrita a partir del título.
- **C.** En el Mapa sin etiquetas, debajo de «Todavía no hay etiquetas», la ayuda «Tocá una comunidad
  para ver su ficha…», sin nada que tocar.
- **D.** «Escuchar» en el texto completo que abre el Índice empezaba por el principio, aunque la
  vista estuviera en la mitad del capítulo.
- **F.** Sin voz elegida, con la que el lector tomó sola (`es-us-x-…-local`), la misma voz tenía tres
  nombres: «Español (Estados Unidos)» en el reproductor, «Lee ahora: Voz 1» en la biblioteca y la
  marca en «Voz del sistema».
- **G.** «Voces descargadas» vacía decía «Las bajás desde la biblioteca de voces» sin un botón para
  llegar; «Voces por idioma» sí lo tenía.

**Causas**:

- **B.** Las letras de la app son variables y la negrita se dibuja trazando el contorno (modo
  `2 Tr`). El paquete `pdf` (3.12.0, `graphics.dart`) escribe el modo solo cuando no es el de
  relleno y nunca lo vuelve a `0 Tr` —eso llega únicamente al comienzo de cada página—. El título
  del Índice iba directo en la página, con el trazo puesto en su estilo y sin nada que guardara y
  repusiera el estado del dibujo: el modo 2 quedaba para todo lo que seguía, con el trazo negro de
  1 punto (el tema, en su color de acento, se trazaba en negro). En el informe ya había un `_Ink`
  y un `_StrokedWord` que aislaban, pero cada título tenía que acordarse de envolverse, y el número
  de una nota en un título en negrita salía con trazo: su `renderingMode: fill` no se escribe nunca.
- **C.** La ayuda salía con `!_links && communities && !_isTree` sin mirar si había temas; lo mismo
  las demás filas y notas que acompañan al dibujo («0 contradicciones a la vista», «Ver como lista»,
  cuántos documentos quedaron sin vínculos, la raíz del árbol de la lista).
- **D.** `ExtractViewer` ofrecía su `ReadableDocument` sin `startAt`; sin `fromSegment`,
  `ReadAloudController.open` usa `startIndexOf`, que sin lugar empieza por el primer pedazo.
- **F.** `voiceName` caía en `readAloudVoiceNumber(number!)` y `voiceProfileOf` ponía `number = 1`
  de antemano: un «Voz 1» que no era de ninguna lista (en la biblioteca, esa voz es la segunda de
  su acento). La cara usaba el mismo número: el reproductor dibujaba «1» y su tarjeta «2». El audio
  descargado tenía su propio `speechVoiceDisplayName`, con el mismo «Voz 1».
- **G.** El vacío de la hoja era un texto solo.

**Qué se hizo**:

- **B** (`576a4523`). La negrita sale a `lib/core/pdf/pdf_bold.dart` y es la única forma de ponerla:
  `PdfBold` (y `PdfBold.text`) aísla un texto entero —guarda el estado, pone el trazo del color de
  la letra y de un grosor proporcional a su tamaño (3 %), dibuja y repone— y le da el trazo a lo de
  adentro por el tema, así **ningún estilo lleva `renderingMode`** (`grep fillAndStroke lib` da solo
  ese archivo); `pdfBoldWords` dibuja cada palabra en negrita sola dentro de un párrafo que no lo
  es. El Índice y el informe la usan; en el informe, un texto en negrita con la llamada de una nota
  va palabra por palabra y la llamada, al lado, solo rellena. Línea nueva en `docs/arquitectura.md`
  (Exportación).
- **C** (`ac5ff594`). Una sola condición, `_hasContent` —«hay algo a la vista que tocar»: los
  temas o, con los vínculos prendidos, lo vinculado que ya llegó—, decide todo lo que acompaña al
  dibujo: las filas de contexto (la ayuda, el grado, la raíz, el resumen y la fuerza de los
  vínculos), las notas de abajo (lo que no entró y lo de las capas), «Ver como lista» y sus capas.
- **D** (`a2264b53`). El visor dice por dónde va su vista, como el libro, el PDF, la página web y
  el documento procesado: `_placeInView` recorre las filas armadas y, en la primera que llega más
  abajo del borde de arriba, da el título del documento si se lee (con varios) o la posición del
  texto propio de la línea que está ahí, aunque esté cortada (`textOffsetAt`, nuevo en
  `_Revealable`: el párrafo dibujado y `getPositionForOffset`, llevado al texto propio con
  `_toRaw`). Los avisos se siguen de largo. **La regla «el mismo documento sigue donde iba» se
  revisó y queda**: `close()` olvida el documento, así que con el reproductor cerrado «Escuchar»
  siempre arranca desde lo que se ve, aunque la persona se haya ido lejos de lo que sonaba; con el
  reproductor abierto o en pausa no hay «Escuchar» —el botón aparece solo sin nada leyéndose— y lo
  que vuelve a ofrecer lo mismo (el menú del audio, la cola) sigue donde iba.
- **F** (`5eeba7c7`). Una sola forma de nombrar en una frase la voz que suena, la del reproductor
  (`readAloudVoiceName`), la usan «Lee ahora» de la biblioteca y de Ajustes
  (`now_reading_text.dart`) y el audio descargado. `voiceProfileOf` ya no tiene número por defecto:
  el número lo pone solo `deviceVoiceProfiles`, por el lugar entre las de su acento, y `voiceName`
  sin número nombra por el acento. **La cara es de la voz**: `VoiceProfile.label` ya no usa el
  número, así es la misma en la tarjeta, el reproductor y la tarjeta de lo que suena, y no cambia
  si el teléfono suma otra voz del acento (en la lista, las iniciales de una voz con código pasan
  de «2» a la del acento). «Lee ahora», sin una elegida para lo que se lee —lo mismo que marca «Voz
  del sistema», ahora una sola condición, `noVoiceChosenProvider`—, lo dice: «Lee ahora: Español
  (Estados Unidos), porque no elegiste ninguna» (`f46P5fNowReadingUnchosen`, en los dos .arb).
  «Voces por idioma», que es una lista, nombra cada voz con su tarjeta de la biblioteca
  (`libraryVoiceProfileOf`): «Voz 2», como donde se la eligió.
- **G** (`a2d23cb4`). El botón «Biblioteca de voces» sale de «Voces por idioma» a
  `VoiceLibraryButton` y la hoja vacía lo lleva debajo de lo que dice. Se revisaron las demás: la
  pestaña Mías está dentro de la biblioteca; Clonar y Crear una voz ya llevan su botón cuando falta
  algo (abrir la nube, bajar Kokoro); lo de ElevenLabs (cambiar de plan) no tiene adónde llevar en
  la app.

**Pruebas** (todas con fakes):

- **B.** `test/support/pdf_text_modes.dart` lee el flujo de dibujo sin PDFium: descomprime cada
  página, sigue `q`/`Q`, `Tr`, `rg`, `RG` y `w`, decodifica cada palabra con su `ToUnicode` y falla
  si una página deja algo guardado sin reponer. En el Índice, en negrita van exactamente el título,
  el tema, el documento y los capítulos de primer nivel —también en todas las páginas de uno de
  120—, cada uno aislado, con el trazo del color de su letra y su grosor; el subtítulo, lo que dice
  un documento, un capítulo de segundo nivel, el texto completo, una imagen, las páginas y el pie,
  solo relleno. En el informe, lo mismo con el título, las secciones, el subtítulo, las preguntas,
  las negritas, las palabras clave y las respuestas, y la llamada de una nota en un título y en un
  subtítulo, sin negrita. Con PDFium pasan también las de siempre.
- **C.** Sin temas no están la ayuda, «Ver como lista» ni la nota de una capa, y vuelven al
  prender los vínculos; sin nada vinculado, el vacío va solo; vaciado mientras se mira como lista,
  se van sus capas y su raíz; con temas, la ayuda sigue.
- **D.** Con un texto completo largo: desplazado hasta la mitad, lee desde el párrafo de arriba; en
  un párrafo larguísimo cortado arriba, desde la oración de la línea de arriba; con dos documentos
  y pasado el título del segundo, desde su texto y no desde su título; en el resumen, que muestra
  solo lo marcado, desde la oración marcada de arriba; arriba de todo, desde el comienzo; en pausa y
  desplazado, ofrecerlo otra vez sigue donde iba, y cerrado, «Escuchar» lee desde lo que se ve.
- **F.** El reproductor, «Lee ahora» y la marca dicen lo mismo, y la cara del reproductor es la de
  su tarjeta «Voz 2»; la tarjeta de lo que suena la nombra igual y lleva esa cara; «Lee ahora» nunca
  dice «Voz 1»; el audio descargado y su falla la nombran como el reproductor; la numeración sale
  solo de la lista; «Voces por idioma» dice «Voz 2».
- **G.** En Ajustes, con ninguna bajada, la hoja dice que está vacía, trae el botón y el botón abre
  la biblioteca; en «Voces por idioma», el mismo botón la abre.

**Mutaciones** (`tool/mutar.py`): B, 19 de 19; C, 7 de 7; D, 7 de 7; F, 13 de 13; G, 4 de 4. Todas
muertas. Dos de D sobrevivieron la primera vuelta —saltear las filas que quedaron arriba y usar la
posición de lo dibujado como la del texto propio— porque todas las pruebas eran de un solo
documento con un solo bloque; se sumaron las de dos documentos y del resumen, y murieron. Una de B
(«aislado sin reponer») también sobrevivió primero: el trazo quedaba puesto sin que nada lo notara,
y la lectura del PDF ahora falla si una página no repone lo que guarda.

**Sobre `main`**: rebasado sobre `7c161061` (el final del paso 5g, que ya trae el 5e). Los únicos archivos en común eran la
GUÍA, `docs/arquitectura.md` y este plan, y quedan los dos lados. La rama se rearmó para que cada
commit de código dé por sí solo los 19 avisos del analizador: lo que arreglaba los avisos que había
sumado el paso fue a parar al commit que los había metido, y el ajuste de una prueba de D, a D.

**Analizador**: 19 avisos, la línea base, en cada commit de código. La GUÍA, en `18756d62`.

**Pruebas**, con `--concurrency=2`, antes de rebasar: `test/features/index`, `creations`, `map`,
`narration`, `reading/presentation/frame` y `settings`, 3.609 pasan (una prueba nueva de D contaba
«la oración de arriba» distinto que `startIndexOf` cuando la línea de arriba era la vacía entre dos
párrafos: se la corrigió y las mutaciones de D se volvieron a correr). Con PDFium (`.pdfium` del
repositorio), las del Índice y el informe pasan. Después de rebasar, `test/features/index`, `map`, `narration`,
`reading/presentation/frame`, `settings` y `creations/extract`, `report` y `podcast`: 1.923 pasan,
0 fallas (9 saltadas: las de PDFium).

**Queda para mirar en el emulador**, con una APK nueva:

- el PDF del Índice, con negrita solo en el título, los temas, los documentos y los capítulos de
  primer nivel, y el tema con el trazo de su color;
- el Mapa sin etiquetas, con el vacío solo;
- «Escuchar» en el texto completo abierto desde el Índice, desplazado a la mitad: tiene que empezar
  por la línea de arriba;
- sin voz elegida, el reproductor, «Lee ahora» de la biblioteca y de Ajustes y la tarjeta de lo
  que suena, con el mismo nombre y la misma cara que la tarjeta de la lista;
- «Voces descargadas» vacía, con su botón.

### Paso 5h (hecho): lo de la pantalla que se colaba, «atrás», el separador y la cuenta del vacío

**Qué se vio** (emulador):

- **J.** En *Platón*, el recuadro de la ficha decía «Ἀριστοκλῆς Ver y modificar los datos en
  Wikidata», y así cada dato de la ficha; debajo, el cuadro «Escucha este artículo».
- **L.** Desde Estudiar › Línea de tiempo, y desde Estudiar › Índice, cada una la entrada de su
  rama, «atrás» minimizaba la app.
- **M.** El separador «Lo creado» de Repasar estaba corrido: la línea de la izquierda iba de x=34 a
  x=200 y la de la derecha de 393 a 558, cuando tenía que llegar al borde.
- **N.** Con el recorte «Todo lo procesado · 14 documentos · 0 tarjetas», la franja decía «58
  elementos todavía no tienen tarjetas».

**Las causas, confirmadas:**

- **J**: el extractor (`reader_mode_article_extractor.dart`) solo sacaba el `[editar]`
  (`.mw-editsection`). Readability deja lo que está dentro del artículo, y la ficha lo está. El lápiz
  es una imagen con ese texto alternativo dentro de un `.noprint`, la clase de MediaWiki para lo que
  no se imprime. Medido sobre las once páginas guardadas (Platón, Sócrates, Tomás de Aquino, Agustín
  de Hipona, Benito de Nursia, Agujero negro, Fotosíntesis, Edad Media, Imperio romano, Revolución
  francesa, Primer Concilio de Nicea): también se colaban el «[editar datos en Wikidata]» al pie de
  la ficha (en diez), el cuadro «Escucha este artículo» (Platón, Sócrates, Revolución francesa), el
  aviso «necesita más referencias» (Sócrates), un «Para otros usos…» (Fotosíntesis) y viñetas
  vacías de `.mw-empty-elt` (Sócrates). Los «Artículo principal: …», «Control de autoridades» y
  «Obtenido de» ya los sacaba Readability, pero solo porque el artículo es largo: por debajo de 500
  caracteres no limpia nada.
- **L**: en la entrada de una rama, ni la rama ni el navegador principal tenían nada que cerrar, y
  go_router le pasaba el gesto al sistema (`popRoute` da `false`, y Flutter llama a
  `SystemNavigator.pop`). Lo que se le avisaba a Android (`setFrameworkHandlesBack(false)`) era
  coherente con eso, así que el gesto ni llegaba a la app.
- **M**: `_CreatedHeader` armaba `Row[Expanded(línea), Flexible(flex: 3, suelto)(texto),
  Expanded(línea)]`. El `Flexible` suelto se queda con lo que mide el texto, pero lo que le sobra de
  sus tres quintos no vuelve a las líneas: queda vacío al final de la fila.
- **N**: `ReviewEmptyState` contaba con `itemsWithoutCardsCountProvider`, toda la Biblioteca —notas
  y fuentes incluidas—, y su botón «Crear tarjetas con IA» abría la hoja sobre `repasarScopeProvider`.
  Además, la sesión vacía (`ReviewScreen`) contaba la Biblioteca y abría la hoja sobre lo elegido en
  Repasar, aunque la sesión fuera de otro recorte.

**Los arreglos:**

- **J (`511cf5d0`): lo que la página marca como de la pantalla no entra al texto.** Antes de leer se
  sacan, por su marca y no por su texto, las clases que MediaWiki reserva para lo que no es el
  artículo: `.noprint`, `.navbox`, `.metadata`, `.mbox-small`, `.sistersitebox`, `.mw-jump-link`,
  `.printfooter` y `.mw-empty-elt`, además de `.mw-editsection`. Lo de una cita se queda (`cite`,
  `.citation`, `.references`): la plantilla «cite arxiv» marca como `.noprint` el número del trabajo
  («arXiv:1403.2371 [math-ph]», nota 23 de Agujero negro), y sin él la cita no lleva a ningún lado.
  Las llamadas a notas (`.reference`) no se tocan: el lector las vuelve «[n. 1]». Antes y después
  sobre las once páginas, renglón por renglón: solo se va lo de la pantalla, Edad Media queda igual
  y ningún renglón del artículo se pierde. El recorte de la prueba
  (`test/fixtures/web/wikipedia_platon_recorte.html`) sale de la página real con el parser de la
  app: el aviso de arriba, la ficha entera, el cuadro del audio, la introducción, el capítulo
  «Obra», la caja «Control de autoridades» y el «Obtenido de», sin los atributos internos de
  MediaWiki.
- **L (`51fe82e3`): «atrás» en la entrada de una pestaña que no es la Biblioteca lleva a la
  Biblioteca.** `BackToLibrary` (`lib/app/router/back_navigation.dart`) envuelve el shell
  (`AdaptiveScaffold`, en el celular y en el riel) en un `PopScope` de la ruta del shell: fuera de
  la rama `ShellBranch.library` la ruta no deja que la saquen y, cuando lo intentan, va a la
  Biblioteca con lo que tenía abierto (`goBranch`, sin volver a su entrada). **La regla es por rama,
  no por botón de la barra**: cada destino de un paso con varios —la Bandeja y el Atlas;
  Procesado, el Índice, Cuadernos, la Línea de tiempo, el Mapa y Repasar— es la entrada de su rama.
  Lo de arriba se cierra antes, como siempre: go_router le da «atrás» primero a la pila de la rama
  —una pantalla, una hoja de abajo abierta en la pestaña— y el navegador principal saca lo que
  tiene encima del shell —un diálogo, una pantalla sin barra— antes de preguntarle a su ruta. Lo
  que se le avisa a Android sale del mismo `PopScope`: con la ruta que no deja sacarla, el
  navegador principal avisa «lo maneja la app» aunque la rama acabe de avisar que no
  (`_getNavigatorCanHandlePop` de Flutter mira `RoutePopDisposition.doNotPop`), y `reportBackHandling`
  —el aviso con todos los navegadores de HyperOS / Android 16— lo deja pasar sin cambios. En la
  Biblioteca sin nada abierto el aviso es «no», así el sistema hace su gesto atrás predictivo de
  salir.
- **M (`a36ad9a1`): un separador común con el nombre en el medio.** `LabeledDivider`
  (`lib/core/design/widgets/labeled_divider.dart`): dos líneas `Expanded` iguales y el nombre entre
  ellas con lo que mide, a 12 de cada una; como mucho el 60 % del ancho (`LayoutBuilder`), en
  renglones centrados. Lo usan «Lo creado» de Repasar y el «o» de Capturar, los dos únicos
  separadores con texto de la app (buscado con `grep` por `Divider` dentro de una fila).
- **N (`984829cb`): el vacío cuenta los documentos del recorte que se estudia.** Los mismos a los que
  «Crear tarjetas con IA» —la hoja de «Tarjetas didácticas» sobre ese recorte, «Para cada
  documento»— se las pediría, con la misma regla (`FlashcardCoverageReader`):
  `CreationScopeResolver.watchWithoutCards` resuelve el recorte y lo cuenta al día con
  `withoutCardsCountOf`, una sola consulta aunque sean diez mil (los ids viajan como un JSON). Una
  tarjeta de la fuente no saca al documento de la cuenta —las tarjetas salen de lo procesado, F41—,
  y un recorte que ya no existe no tiene ninguno. `ReviewEmptyState` recibe el recorte que se
  estudia: la franja «Para hoy» le da el de Repasar, la sesión vacía el suyo, y el botón abre la
  hoja sobre ese mismo. Un recorte de estudio de antes —un espacio, un valor, un cuaderno o un
  elemento, que solo llega por una dirección vieja— no es uno de lo creado
  (`CreationScope.ofStudyScope` da `null`): no cuenta nada ni ofrece crear. El texto dice
  «documentos» y la ayuda «desde cada documento» (`f46P5hWithoutCards`, `f46P5hWithoutCardsHint`,
  agregados al final de los `.arb`). Se borran `itemsWithoutCardsCountProvider` y
  `watchWithoutCardsCount`, que no usaba nadie más. Revisado: la forma `compact` y la grande
  cuentan lo mismo; de `_reasons`, la espera del cargador sigue diciendo cuántos esperan en la cola
  de la IA, que es de toda la bóveda y no de un recorte, y el resto no cuenta nada.

**Decisiones:**

- **J**: se sacan las clases de la familia que no aparecen en ninguna de las once páginas
  (`.metadata`, `.mbox-small`, `.sistersitebox`) porque son las que MediaWiki usa para los avisos y
  las cajas de proyectos hermanos, y también las que Readability ya sacaba en un artículo largo
  (`.navbox`, `.printfooter`), para que no dependa de su limpieza: en uno corto no limpia nada.
  `.reference` no entra: es del artículo.
- **L**: la regla vive en `back_navigation.dart`, al lado del aviso a Android, y la aplica el shell;
  no hizo falta tocar `reportBackHandling` ni `app_router.dart`.
- **N**: la cuenta es del recorte y no de la sesión de estudio, porque es la que tiene un botón que
  la resuelve. Los textos viejos (`reviewEmptyWithoutCards` y su ayuda) quedan sin usar en los
  `.arb`: solo se agregan textos al final.

**Pruebas** (todas con fakes; `--concurrency=2`, solo las carpetas tocadas):

- **J**, 15 nuevas en `reader_mode_article_extractor_test.dart`: con el recorte de Platón, el lápiz
  se va de cada dato y el dato queda solo; no quedan el audio, los avisos que llevan a otra
  página ni las cajas del pie; la ficha, el texto, «## Obra» y la llamada «[n. 1]» quedan. En un
  artículo corto, cada clase se va por su marca (siete), lo vacío no deja una viñeta vacía, y lo
  marcado como de la pantalla dentro de una cita queda: en la lista de notas, en una cita fuera de
  ella, en un `<cite>` y en una nota sin cita. La tanda de `test/features/transform` y de quien usa
  los recortes de Wikipedia (el índice, el texto llano, «Explicar»): 867 pruebas, todas pasan.
- **L**, 9 nuevas. En `back_navigation_test.dart`, con un shell envuelto como en la app: desde la
  entrada de la Bandeja y de la Línea de tiempo, «atrás» va a la Biblioteca sin salir, y Android
  sabe que es de la app; desde la Biblioteca sin nada encima, sale; dentro de la pila de una
  pestaña vuelve a la pantalla de antes —con el aviso en «sí» aunque la pila avisó que no— y
  después a la Biblioteca; con un diálogo o una hoja de abajo abiertos, primero los cierra; la
  Biblioteca vuelve con lo que tenía abierto y desde ahí lo cierra antes de salir. En
  `adaptive_scaffold_test.dart`, con el router de verdad, en el celular y en el riel: desde la
  entrada de cada una de las diez ramas que no son la Biblioteca —también el Índice y la Línea de
  tiempo—, «atrás» lleva a la Biblioteca. La tanda de `test/app/router` y `test/app/navigation`:
  97 pruebas.
- **M**, 11 nuevas: en `labeled_divider_test.dart`, las dos líneas miden lo mismo y llegan a los
  bordes con un nombre corto, uno largo, la letra al doble y las dos cosas; el largo ocupa como
  mucho el 60 % y va en renglones centrados; el corto queda a 12 de cada línea; la letra y el color
  de siempre, o los elegidos. En Repasar, «Lo creado» centrado, con la letra normal y al doble; en
  Capturar, el «o» del video centrado.
- **N**, 13 nuevas y 5 que cambian. En `flashcard_coverage_reader_impl_test.dart`, la cuenta de
  unos documentos es la de `withoutCards`, solo de esos, sin repetir, con cero si no hay, con diez
  mil en una consulta, y una tarjeta nueva lo saca; la del procesado sin texto pasa a contarse
  cuando llega su parte. En `creation_scope_resolver_impl_test.dart`, con diez en la Biblioteca y un
  cuaderno de dos, el cuaderno dice 2, «Todo» 3 y un documento 1; al día con una tarjeta propia, no
  con una de la fuente; un recorte que no existe o sin documentos, 0. En
  `review_entry_screen_test.dart`, **con un recorte de dos sin tarjetas y una Biblioteca de diez,
  dice dos**; «Todo lo procesado» cuenta sus documentos; el botón abre la hoja con esas dos fuentes;
  una tarjeta fuera del recorte no cambia nada; la sesión vacía de un recorte cuenta ese recorte, y
  la de uno de antes no cuenta ni ofrece crear. Cambian las de `review_ai_flashcards_test.dart`
  (siembran documentos procesados en vez de notas) y la del vacío de la franja; los dobles de la
  cobertura de los cuadernos y el armado del resolvedor suman lo nuevo. La tanda de
  `test/features/flashcards`, `test/features/creations/data`, el selector de recortes y
  `test/features/notebooks/presentation`: 988 pruebas.

**Mutaciones** (`tool/mutar.py`): 46 de 46 muertas. **J** (15): sin cada una de las nueve clases; la
excepción de las citas sin `cite`, sin `.citation`, sin `.references` o sin ella; y `_isInside`
siempre sí o siempre no. **L** (7): la ruta del shell se puede sacar siempre o nunca; no va a la
Biblioteca; va con el gesto al revés; va a la entrada de la rama en la que está; va a la entrada de
la Biblioteca, perdiendo lo abierto; y el shell sin la regla. **M** (8): el texto en el `Flexible`
suelto de antes; sin tope de ancho; sin centrar los renglones; sin el aire; otra letra, otro color
de letra, sin la letra elegida y otro color de línea. **N** (16): la cuenta de los que ya tienen,
de toda la Biblioteca, de lo elegible con o sin tarjetas o sin mirar si puede tenerlas; uno sin
ninguno; el recorte sin sus documentos; «Todo» que no es «Todo lo procesado», el de lo procesado que
no se reconoce y el de antes que cuenta todo; crear sobre todo; la sesión o la franja que cuentan
todo; y los textos viejos, en la franja y en la sesión. Equivalentes, no se mutaron: la salida
temprana de `withoutCardsCountOf` sin ids (con `[]`, `json_each` no da filas y la consulta da 0: es
para no consultar), y la lista explícita de clases de `StudyScopeKind` que dan `null` (con `_`
daría lo mismo; va escrita para que una clase nueva obligue a decidir).

**Sobre `main`**: el trabajo salió de `7c161061` (el 5g) y se rebasó sobre `1c663822` (el 5f) antes
del segundo commit; sin choques.

**Analizador**: 19 avisos en cada commit, la línea base.

**Para el dueño (consulta, con la de los textos de antes de `296a1857`):** los textos de Wikipedia
ya guardados no cambian —siguen con el lápiz de Wikidata y el resto— porque volver a extraerlos
pasa por `reextraction.dart`, que no se toca. Queda para la misma decisión (a) o (b) que esos
textos.

**Queda para mirar en el emulador** (con una APK nueva): guardar de nuevo *Platón* (con «Guardar
aparte») y ver la ficha sin «Ver y modificar los datos en Wikidata», sin «Escucha este artículo»,
con las llamadas a notas; «atrás» desde la entrada de cada destino de Organizar y Estudiar —sobre
todo el Índice y la Línea de tiempo—, del Chat y de Ajustes, que va a la Biblioteca, y desde la
Biblioteca, que sale con el gesto predictivo; «atrás» con una hoja de abajo o un diálogo abiertos
en una pestaña; «Lo creado» centrado con la letra normal y al doble; el «o» de Capturar › Video; y
Repasar vacío con «Todo lo procesado» y con un cuaderno, que dice los documentos de cada uno.

### Paso 5i (hecho): la búsqueda que lee, el botón que se lee, el teclado que no vuelve y el panel sin franja

**Qué se vio** (emulador, con la APK de `1c663822`), cuatro cosas:

- **O.** Buscando «Fotosintesis» en la Biblioteca, Fotosíntesis (Wikipedia) mostraba
  «…[](https://thumb.wikimedia.org/…/**Fotosintesis**_ox_ano…» y Evolución biológica «…debido a la
  [**fotosíntesis**](https:/…».
- **P.** El botón grande del visor embebido («Ver la página», «Leer como libro», «Ampliar») se leía
  mal encima de la página blanca y de la foto amarilla.
- **Q.** Buscando en la Biblioteca, cerrado el teclado con «atrás», tocado un resultado y vuelto, el
  teclado aparecía solo y tapaba la mitad de los resultados.
- **R.** En Ajustes, con el reproductor achicado sonando, la hoja «Aspecto de lectura» escondía el
  reproductor pero terminaba unos 190 px reales arriba de la barra, con una franja del color de la
  página y sin el sombreado del panel (una regresión del 5g).

**Causas** (confirmadas):

- **O.** Dos: `buildSnippet` armaba el fragmento sobre el texto crudo del chunk, y `chunk_search`
  indexaba `chunks.content` tal cual (`chunkSearchText` y la vista `chunk_search_text`): las palabras
  de las direcciones de fotos y enlaces eran aciertos y pesaban en `rank`. En la bóveda sintética
  con sus páginas como las de Wikipedia, «wikipedia» estaba en 48.348 de 49.488 chunks.
- **P.** `_CenterButton` usaba `Colors.black.withValues(alpha: 0.4)` con letra blanca: sobre blanco el
  fondo queda en ≈#999 y el contraste en 2,9 a 1; `_ExpandButton`, lo mismo con 0,45.
- **Q.** Cerrar el teclado no le saca el foco al campo, y la ruta de abajo, cuando vuelve a ser la de
  arriba, le devuelve el foco a lo último que lo tuvo (`_ModalScopeState._routeSetState` →
  `setFirstFocus`), y el campo abre el teclado al recibirlo. Ningún buscador soltaba el foco al
  tocar fuera: en Android, el `onTapOutside` de fábrica de un campo no hace nada.
- **R.** `ReadAloudOverlay` tenía dos lugares: el del pie (`mediaWithRoomAtBottom`), que se soltaba en
  el acto al abrirse un diálogo o un panel, y el de las pestañas (`ReadAloudRoom.height`, que
  `NavigationBarScope` le da al `Scaffold`), que a propósito se quedaba —«ahí no lo ve nadie más»—.
  Pero los paneles de una pestaña se abren en el navegador de la rama, adentro del cuerpo que ese
  lugar achica: la hoja terminaba a la altura del reproductor que ya no estaba (64 de los de Flutter
  en la prueba: el reproductor achicado) y la barrera, que cubre solo la ruta, no llegaba hasta la
  barra. Se reprodujo con una prueba en el shell de verdad antes de arreglarlo.

**Qué se hizo**:

- **O** (`105fa9c3`). Cada chunk en Markdown guarda **lo que se lee** en `chunks.search_text` (esquema
  **v52**), el índice indexa eso y el fragmento sale de ahí.
  - Qué se lee: `chunkSearchSource` (`search_index.dart`), con `markdownPlainText` —la regla del 5e,
    la del lector—, sin otra nueva; `markdownPlainBlocks` suma `keepLineBreaks`, que deja los
    renglones de cada párrafo en el suyo para que `chunkSearchText` siga uniendo los guiones de corte
    (F22). Qué es Markdown: `extractedTextIsMarkdownFor`, la regla de `extractedTextIsMarkdown`
    sobre el tipo y el archivo, que es lo que el que fragmenta lee de `source`. `null` en un PDF o
    una transcripción, que se leen tal cual —su dirección escrita se sigue encontrando—, y en lo que
    leído cambia solo espacios.
  - Qué se indexa: `COALESCE(search_text, content)` (`chunkSearchColumn`), en los triggers y en la
    vista de `rebuild`, así los dos indexan lo mismo; el trigger de cambio mira también
    `search_text`. El fragmento de un resultado (`_citationsFor` y `_citationsByRanking`) lee la
    misma columna: la palabra queda marcada en el texto legible, donde la encontró el índice.
  - **La decisión: una columna calculada en Dart al escribir el chunk.** Se descartó una función
    SQL registrada: el FTS5 de contenido externo da de baja una fila con el texto que indexó, y con
    una función ese texto se recalcula en cada baja —el día que cambie la regla de lectura, que es de
    la interfaz, cada baja le diría al índice otra cosa y lo corrompería sin aviso—; además habría
    que registrarla en cada conexión (el worker de la web es el de drift, la unión abre otra) y sin
    ella toda escritura de un chunk fallaría. Y SQL puro no lee Markdown. Guardado, lo que se borra
    es siempre lo que se indexó. El costo es lugar, solo donde leer cambia algo: 16,7 MB de `search_text` sobre 81,1 MB de texto de los chunks (el 21 %); el índice, que recién rehecho sobre el texto crudo ocupaba 24,5 MB, queda en 27,5 MB después del relleno, que lo reindexa fila por fila y deja que FTS5 junte sus segmentos de a poco.
  - **La migración no lee Markdown.** La primera versión llenaba la columna en la migración: medido
    en la PC, 13,6 s con 3.000 elementos —unos 45 s con 10.000, varias veces más en un teléfono—
    con la bóveda cerrada. Ahora la migración 51→52 agrega `search_text` y `search_text_rule`
    vacías —el índice no cambia: `COALESCE` da el texto de siempre— y rehace solo los triggers y la
    vista; si una base no tuviera el índice, lo recibe entero. Las llena `ChunkSearchTextBackfill`,
    desde `App` al abrir la bóveda, por tandas de 200 y en segundo plano, con el retome en la base
    misma: falta lo que no tiene la versión de hoy (`kChunkSearchTextRule`). Lo que no es Markdown
    solo recibe la versión, sin tocar el índice. Si la regla cambia, se sube el número y el relleno
    rehace lo viejo, sin otra migración. El paso v32, que rehace el índice con la definición de hoy,
    agrega antes las dos columnas, y el v16 las crea con la tabla. La Biblioteca no se toca.
  - `chunkAndPersistSource`, el único que escribe chunks, los guarda ya con lo que se lee y la
    versión; la bóveda sintética, igual.
- **P** (`233a8d41`). `OverlayControlColors` (`core/design`): `inverseSurface` y `onInverseSurface` del
  tema —el par de Material para lo que va encima del contenido— con la menor opacidad, de a un 1 % y
  desde la mitad, que deja al menos 4,5 a 1 sobre blanco y sobre negro. Lo que se ve de un fondo con
  transparencia queda entre cómo se ve sobre negro y sobre blanco, así que con las dos puntas alcanza
  para cualquier cosa de abajo. Si el par de un tema no contrastara ni opaco, la letra pasa a blanco
  o negro. Los dos botones lo usan; siguen dejando ver el original.
- **Q** (`fc29d203`). `SearchField` (`core/design/widgets`): un solo buscador de lista que suelta el foco al
  buscar, al tocar fuera y cuando algo se abre encima. Para lo último no alcanza con `unfocus` —ya
  no tiene el foco y le sacaría el suyo a lo que se abrió—: si el foco se va a otra ruta y la suya
  todavía lo recuerda, el campo deja de poder tomarlo (`canRequestFocus`) hasta que su ruta vuelve a
  tenerlo; la ruta que vuelve descarta a quien no puede tomarlo y se queda con el foco ella. Vale
  también sin un toque (el lector de pantalla, una hoja, código) y con el resultado en la raíz,
  encima de las pestañas. Lo usan la Biblioteca, el Índice, el Atlas, el Mapa, la línea de tiempo,
  Mis tarjetas, la Ayuda, las conversaciones del chat y las dos listas para elegir. Un censo exige
  que todo campo con la tecla de buscar sea uno, salvo dos que no son buscadores de una lista: la
  barra de «Buscar en la guía», donde la tecla va a la coincidencia siguiente y el foco tiene que
  quedar, y el tema de un cuaderno con IA, un formulario.
- **R** (`bc297cba`). Un solo lugar, que sigue al reproductor que se ve: con un diálogo, un panel o un
  menú abierto se va en el acto en los dos niveles —al pie y encima de la barra— y vuelve con el
  reproductor, con su mismo andar, al cerrarlo. Las 84 hojas siguen en el navegador de su rama: no se
  tocaron.
  - **Con lo que decidió el dueño** —que las hojas pasen a la raíz, tapando la barra, en el paso 5j—
    esto no cambia: el lugar sigue a la visibilidad del reproductor, no a dónde se abre lo de
    encima. Una hoja en la raíz tapa también la barra y su sombreado la pantalla entera; debajo, la
    pestaña deja de guardarle lugar a un reproductor escondido, sin que se vea. Lo que quede en el
    navegador de una rama —menús, diálogos, lo que se siga abriendo ahí— ya llega hasta la barra.
    La prueba del shell ya mira las dos: el 5j puede pasar las hojas sin tocar el lugar.

**Pruebas** (todas con fakes, contra SQLite real en memoria donde hay base):

- **O.** Una palabra que solo está en la dirección de una foto no encuentra el chunk ni el
  documento; el fragmento de una página web no tiene `](`, `![`, `http` ni `**`, marca
  «fotosíntesis» y dice «debido a la fotosíntesis de las algas.», por los dos caminos de las citas;
  los guiones de corte se siguen encontrando en un Markdown; un PDF con una dirección la encuentra; un
  Word es Markdown; un Markdown sin marcas no se guarda dos veces; rehacer los chunks, cambiar lo que
  se lee y `rebuild` dejan el índice exacto (`integrity-check`). La migración 51→52: solo agrega,
  la búsqueda anda como antes, los conteos son los mismos y el texto de la Biblioteca no cambia; el
  relleno pone al día lo de Markdown, le da la versión al PDF, rehace lo de una regla vieja, corta
  entre tandas y sigue después, y no rehace lo hecho. `keepLineBreaks` y
  `extractedTextIsMarkdownFor`, con las suyas.
- **P.** El texto y el ícono de los dos botones, con al menos 4,5 a 1 sobre una página blanca y una
  foto negra, en el tema claro, el oscuro, Sepia y Noche; los colores, en todos los temas, también
  sobre 52 grises y cuatro colores saturados; la opacidad es la menor que alcanza; un tema sin
  contraste cae en blanco o negro.
- **Q.** Tocar un resultado le saca el foco y al volver no hay teclado, en una pantalla y desde una
  pestaña con el resultado en la raíz; abierto sin tocar, al volver tampoco, y tocarlo lo enfoca;
  una hoja encima, igual; la tecla de buscar y tocar fuera lo sueltan; la ✕ de adentro no; con un
  foco de afuera, y si ese foco cambia, la regla lo sigue. El censo.
- **R.** En el shell de verdad (`AdaptiveScaffold` con `StatefulShellRoute` y el lector encima, como
  en `App`): con el reproductor sonando la pestaña le deja su lugar; una hoja abierta en la pestaña
  llega hasta la barra y su sombreado cubre todo el cuerpo; al cerrarla el reproductor y su lugar
  vuelven; una hoja en la raíz tapa la barra con su sombreado y al cerrarla vuelve el lugar; un
  diálogo y un menú de la pestaña también lo sueltan y lo devuelven.

**Rendimiento** (PC, bóveda sintética de 3.000 elementos, 95.051 chunks, con sus 49.488 chunks de
páginas web convertidos en páginas como las de Wikipedia: una foto con su dirección, tres enlaces y
una llamada a nota por párrafo):

- **Leer un chunk** (`chunkSearchSource`): 0,23 ms con la PC libre, 0,46 ms con la PC ocupada por otra tarea pesada, como en la última medición. Guardar una página de 42 chunks suma 10 ms (20).
- **La migración**: llenar la columna adentro de ella costaba 13,6 s más 2,0 s de `rebuild` con la bóveda cerrada; ahora agrega dos columnas y rehace tres triggers y una vista: nada que dependa del tamaño.
- **El relleno** (PC ocupada): 45 s para los 95.051 chunks, en tandas de 200 de unos 95 ms cada una —una sola, medida aparte, 66 ms—, con la lectura del Markdown en otro isolate: el hilo de la interfaz solo manda y escribe.
- **Buscar** (mediana de nueve, la página de 50 con sus citas, como la pantalla; antes del relleno contra después): una palabra rara, 43 → 34 ms; una mediana, 49 → 42; una que está en casi todo, 62 → 59; dos palabras, 48 → 40; «wikipedia», que estaba en 48.348 chunks, 43 → 11 ms y en ninguno. Nada se hace más lento: el índice tiene menos palabras por chunk, y el fragmento sale de un texto más corto.
- Una corrida de la medición, con un artefacto de la bóveda de prueba —un enlace partido por el renglón en blanco del final del párrafo—, dejó 1.020 chunks con una dirección colgando: se corrigió la conversión de prueba, no la regla, y en la de arriba no queda ninguno.

**Mutaciones** (`tool/mutar.py`): O, 25 de 25 —una sobrevivió la primera vuelta, «el que fragmenta no pone la versión»: nada miraba la versión de lo recién guardado; se sumó la prueba de que todo chunk guardado la lleva y el relleno no tiene nada que rehacer, y murió—; P, 12 de 13; Q, 6 de 6; R, 2 de 2. **Equivalentes, justificadas**: P7, el piso de opacidad en 0 en vez de 0,5: con cualquier par de colores, para tener 4,5 a 1 sobre blanco y sobre negro a la vez hace falta más de la mitad de opaco, así que el piso nunca decide; queda como lo que dice —menos que eso ya no se ve como un botón—. Y no se corrió la de quitar el punto de retome dentro de una pasada (`after`): lo hecho ya no cumple la condición de lo que falta, así que solo se vuelve a recorrer lo terminado; es de rendimiento. Una de P salió mal armada la primera vez (el formateador había juntado un renglón) y se corrió de nuevo: murió.

**Sobre `main`**: rebasado sobre `f0136493` (el final del paso 5h), sin conflictos: en común solo la
GUÍA, `docs/arquitectura.md` y este plan, y quedan los dos lados. Después de rebasar se volvieron a
generar los textos (el 5h cambió los `.arb`) y se volvieron a correr el analizador y las pruebas de
`test/app` —el 5h tocó `AdaptiveScaffold`, que usa la prueba del lugar del reproductor—,
`test/core/design`, las pantallas de Repasar y Mis tarjetas, la Biblioteca y las del índice: 975 pasan, 6 saltadas, y el analizador sigue en 19.
La GUÍA, en `d6c2715c`.

**Analizador**: 19 avisos, la línea base, en cada commit de código, comprobado commit por commit en
una exportación de cada uno.

**Pruebas**, con `--concurrency=2`: `test/core/database`, `test/core/util`, `test/features/library`, `test/benchmark/synthetic_vault_test.dart` y las de `test/features/vault` que abren una bóveda vieja: 1.497 pasan y la única falla era una prueba nueva que había que correr con el relleno, corregida y pasada (antes, en la primera vuelta, el paso v32 rompía 141 pruebas de migración y de unión: rehacía el índice con la definición nueva sobre una tabla sin la columna; ahora le agrega las columnas antes). `incoming_vault_file_test` falló una vez al correr en paralelo —un archivo de la carpeta temporal que otro proceso tenía tomado— y pasa solo: no toca nada de este paso. `test/core/design`, `test/features/viewer`, `test/app`, `test/features/narration`, `atlas`, `chat`, `flashcards`, `index`, `help`, `timeline`, `map` y `test/features/library/presentation`: 4.846 pasan, 19 saltadas (PDFium) y una falla, una prueba de Mis tarjetas que leía el buscador como `TextField`, corregida y pasada.

**Queda para mirar en el emulador**, con una APK nueva:

- buscar «Fotosintesis» en la Biblioteca con Fotosíntesis y Evolución biológica guardadas: los
  fragmentos sin `[](…)` ni `**`, con la palabra marcada, y sin el documento que solo la tenía en
  una dirección —después de que el relleno pase: con una bóveda grande, unos segundos después de
  abrirla—;
- «Ver la página» sobre la página blanca y la foto amarilla de Fotosíntesis, en el tema claro, el
  oscuro y Sepia;
- buscar, cerrar el teclado con «atrás», tocar un resultado y volver: sin teclado; lo mismo en el
  Índice;
- en Ajustes, con el reproductor achicado sonando, «Aspecto de lectura»: la hoja hasta la barra, con
  el sombreado entero, y al cerrarla el reproductor en su lugar.
- Lo que queda abierto: la búsqueda de Procesado (`processed_part_search`) indexa todavía el texto
  crudo de cada parte, con el mismo problema en una página web copiada; no tiene fragmento, pero sí
  coincidencias en las direcciones. Se escriben desde muchos lugares (editar, ordenar, cortar): es
  un paso propio. Y los pasajes que el chat toma de los chunks (`chunk_passage_retriever`) se
  encuentran ahora por lo que se lee, pero viajan todavía con su texto guardado.
