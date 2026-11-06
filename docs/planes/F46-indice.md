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
