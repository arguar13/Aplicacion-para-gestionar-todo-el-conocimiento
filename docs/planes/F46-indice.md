# F46 — El Índice: lo procesado, con sus capítulos, como el índice automático de Word

> **Estado: APROBADO** (2026-10-30, «Aprobado» en el chat), con las decisiones A a F como están. Pedido del dueño, el 30/10: *"agregar en la pestaña de Estudiar,
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
  326 de `processed/domain/services` y `processed/data`.

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
