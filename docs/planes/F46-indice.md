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
    (`SinapsisApp`) y mira la base: corre cuando algo queda sin indexar sin que nadie lo rehaga
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
