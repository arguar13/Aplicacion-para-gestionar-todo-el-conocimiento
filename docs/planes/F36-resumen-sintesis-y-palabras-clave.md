# F36 — Resumen, síntesis y palabras clave resaltados en el documento

> **Estado: en construcción** (2026-10-22).
>
> **Aprobado** (2026-10-22), en el chat: *"aprobado"* —con las decisiones A–D tal como están—.
>
> **Ampliado** (2026-10-22), a pedido: *"todo eso del resaltado, del resumen, del subrayado y la
> síntesis y las palabras claves, que se aplique a todo tipo de documentos de texto (sea en el
> formato que sea, incluso epub) y hasta en las páginas web (en el formato descargado que sería el
> archivo original)"*. Suma la página web archivada: ver la decisión E y el paso 5b.
>
> Pedido: *"cuando se trate de un documento de texto (en el formato que sea) que tenga una opción
> elegante resumir y otra de síntesis (usando el modelo de IA que habíamos elegido en las
> configuraciones) … cuando apriete resumir o hacer síntesis me resalte en el documento original
> el resumen o al elegir síntesis me lo resalte a la síntesis (que no se superpongan) y que además
> me deje elegir las palabras claves (máximo 4 palabras por oración) de cada oración, que se
> resalte el texto con colores como un Word … Aparte de eso, quiero que haya una opción de
> «Extraer resumen» o «Extraer síntesis» o «Extraer palabras claves» y que siga la opción «Extraer
> texto» … y que se despliegue o minimice el texto extraído o lo que se haya extraído"*.

## Lo que hay hoy (relevado en el código)

| Qué | Cómo está |
|---|---|
| **Documentos** | `SourceKind.document`: PDF, Word, EPUB, texto y Markdown. El detalle muestra el original arriba (`EmbeddedFileViewer`), el panel de la fuente con cuatro mosaicos —Leer, Resumir, Copiar, Más— (F26) y, más abajo, «Texto extraído» plegado (`_CollapsedExtractedText`). |
| **El original** | Un PDF se ve con `pdfrx`, página por página, sobre el PDF real. Word, EPUB y texto se ven en el lector paginado (`DocumentReaderView`), que muestra el texto ya extraído; «Leer como libro» (F35) lo abre a pantalla completa. |
| **«Resumir» de hoy** | `SummarizeOnDemand` le pide al modelo dos o tres párrafos **escritos por él** y los muestra en un diálogo. No se puede resaltar en el original: no son frases del documento. |
| **El modelo** | `LanguageModelTasks`: cada tarea —instrucción, pedido, tope de largo, cómo se lee la respuesta— vive una vez, y quien escribe es el motor elegido en Ajustes: Gemma en el teléfono, o Gemini, OpenAI o Claude (F32). Sin modelo listo, `ensureLanguageModelReady` avisa y ofrece descargarlo; no baja nada solo. |
| **Resaltar** | `RenderedMarkdown.buildSpans` ya pinta tramos sobre el texto (los subrayados del usuario y lo que se lee en voz alta, en amarillo). `pdfrx` da la posición de cada letra de una página (`PdfPageText.charRects`) y deja pintar encima de cada página (`pagePaintCallbacks`). |
| **Texto de un PDF** | Es el texto de cada página, tal cual, con las páginas separadas por `---`: una posición del texto se puede llevar a su página y a sus letras exactas. |

## Qué se construye

### 1. Qué es cada cosa

- **Resumen**: la IA elige las oraciones del documento que llevan las ideas principales, cerca de
  una de cada cuatro. Se resaltan **las oraciones del autor, tal cual**: por eso se pueden marcar en
  el original, como haría alguien con un resaltador.
- **Síntesis**: lo esencial, el hilo del documento en pocas oraciones, cerca de una de cada diez.
  Leyendo solo lo resaltado, se entiende de qué se trata.
- **Palabras clave**: en cada oración resaltada, **hasta 4 palabras** que la sostienen. Las propone
  la IA y **las elegís vos**: tocás una palabra para agregarla o sacarla. Si una oración ya tiene 4,
  te avisa con suavidad.

La IA nunca escribe texto propio acá. Devuelve **números de oración** y **palabras que están en la
oración**, y la app descarta cualquier cosa que no exista en el documento. No hay forma de que
aparezca algo que el documento no dice.

### 2. Cómo se ve (como en Word)

- **Colores de resaltador**, suaves y legibles en modo claro y oscuro:
  - **Resumen**: verde.
  - **Síntesis**: celeste.
  - **Palabras clave**: rosa, más intenso y en negrita, encima del color de la oración.
- No uso el amarillo, porque ya marca lo que se está leyendo en voz alta.
- **No se superponen.** Se ve el resumen **o** la síntesis, nunca uno encima del otro: los dos
  botones funcionan como un interruptor de dos posiciones. Las palabras clave se ven sobre el que
  esté activo.
- Tus subrayados de siempre siguen ahí. Lo que se lee en voz alta va por encima de todo, como hoy.
- **Dónde se resalta:**
  - **PDF**: sobre las letras del PDF real, en la vista del detalle y en «Leer como libro».
  - **Word, EPUB y texto**: en el lector, embebido y a pantalla completa.
  - **«Texto extraído»**, cuando lo desplegás.
  - **Página web**: sobre la página tal como quedó archivada al guardarla —su HTML original, con
    su diseño y sus fotos—, y también en su texto extraído y en «Leer como libro».
  - **Excepción**: en una página escaneada (una foto de la página, reconocida con OCR) el PDF no
    tiene letras donde pintar. Ahí el resaltado se ve en el texto extraído, y la página lo dice.

### 3. La tarjeta «Estudiar el documento»

Va en el detalle, entre el original y lo demás, solo en documentos. Tiene tres partes:

- **Arriba, tres botones**, lindos y con su color:
  - **Resumir** (verde) y **Sintetizar** (celeste): el interruptor. Tocar uno lo resalta; tocarlo
    de nuevo lo apaga.
  - **Palabras clave** (rosa): las muestra u oculta, y tiene un lápiz para **elegirlas**. Mientras
    elegís, tocar una palabra de una oración resaltada la agrega o la saca.
  - Una leyenda chica con los tres colores.
- **Mientras analiza**, una franja: *«Analizando el documento… parte 3 de 12»*, con su barra y un
  «Parar». Lo resaltado va apareciendo a medida que se analiza cada parte.
- **Abajo, «Extraer»**, cuatro filas que se despliegan y se pliegan con una animación:
  - **Extraer texto**: el «Texto extraído» de siempre, que se muda acá.
  - **Extraer resumen**: las oraciones del resumen, en orden y como texto corrido.
  - **Extraer síntesis**: lo mismo con la síntesis.
  - **Extraer palabras clave**: las palabras como etiquetas, en el orden en que aparecen.
  - Cada fila dice cuánto tiene (por ejemplo, «12 oraciones · 340 palabras») y trae **Copiar**.
    Antes de analizar, las tres nuevas dicen *«Tocá Resumir o Sintetizar para empezar»*.
- **A pantalla completa** («Leer como libro»), el lector lleva los mismos tres botones en su barra.
  Ese lector hoy tiene «Resumir con IA» por página; en un documento, ese botón pasa a ser el
  interruptor nuevo.

### 4. El modelo y los documentos largos

- **Usa el modelo elegido en Ajustes.** Si es Gemma y no está descargada, aparece el aviso de
  siempre con «Descargar»: no baja nada sin que lo pidas.
- **Una sola pasada da las tres cosas.** El primer toque en Resumir o Sintetizar analiza, y de esa
  pasada salen el resumen, la síntesis y las palabras. Cambiar de uno a otro es instantáneo y no
  gasta otra vez.
- **Por partes, en orden y retomable.** Un libro no entra entero en la ventana de un modelo. Se
  analiza de a partes del tamaño que admite el modelo elegido:
  - en la nube, partes grandes y pocos pedidos;
  - con Gemma en el teléfono, partes chicas, así que es más lento.
  - Cada parte se guarda al terminar: si cerrás la app o lo parás, sigue desde ahí la próxima vez.
- **Se guarda.** Lo analizado y las palabras que elegiste quedan en la bóveda:
  - en tablas propias, atadas a la forma de texto;
  - si volvés a extraer el texto, se reubican igual que tus subrayados;
  - entran en la unión de bóvedas, el respaldo y la copia.
- **«Volver a analizar»**, en el menú de la tarjeta, rehace todo. Antes pregunta, porque reemplaza
  también las palabras que elegiste a mano.

### 5. Lo que no cambia

- En un video, un audio o una nota, «Resumir» sigue siendo el párrafo en el diálogo.
- En un documento o una página web, el mosaico «Resumir» del panel lleva a la tarjeta nueva y
  prende el resumen.
- No se pierde ninguna función: «Texto extraído» sigue con todo lo de hoy —leer en voz alta,
  subrayar, seleccionar—, solo que ahora vive dentro de «Extraer».

## Decisiones para que confirmes al aprobar

- **A.** Resumen y síntesis son **oraciones del documento**: es lo que permite resaltarlos en el
  original. Si querés, además, una síntesis **redactada** con otras palabras, va aparte.
- **B.** **Uno a la vez**, resumen o síntesis, y las palabras clave encima del que esté activo.
- **C.** Colores: resumen verde, síntesis celeste, palabras clave rosa. El amarillo queda para lo
  que se lee en voz alta.
- **D.** Las palabras clave **las propone la IA y las ajustás vos**, hasta 4 por oración.
- **E.** (ampliación) **Página web**: se estudia su texto extraído, igual que un documento, y las
  marcas se dibujan sobre la página archivada. Para eso la app inserta las marcas en una copia del
  HTML guardado antes de mostrarlo; el archivo guardado no se toca. Hoy esa página se muestra con
  JavaScript apagado, así que sus programas ya no corren. La copia que se muestra los quita, y
  enciende solo un programa chico de la app, que avisa qué palabra tocaste para elegir palabras
  clave. La página se ve igual que hoy.
- Los formatos de texto que la app reconoce hoy son PDF, Word (.docx), EPUB, texto (.txt) y
  Markdown: todos entran. Un .odt, un .rtf o un .pptx hoy no se reconocen ni se les saca texto;
  sumarlos sería otro pedido.

## Pasos (cada uno, su commit y su push)

1. **El análisis**, sin interfaz:
   - partir en oraciones (abreviaturas, decimales, viñetas, títulos, español e inglés);
   - partir el documento en partes según la ventana del modelo;
   - leer la respuesta del modelo y validar las palabras contra la oración, sin acentos ni
     mayúsculas.
   - Pruebas y mutación.
2. **Dónde se guarda**:
   - tablas `study_marks` y `study_analysis_parts`, con la migración a v40 y su repositorio;
   - la reubicación al volver a extraer;
   - la unión de bóvedas, los conteos y el respaldo.
   - Pruebas y mutación.
3. **La tarea del modelo y quien la corre**:
   - la instrucción en `LanguageModelTasks`;
   - el análisis por partes, retomable, con su avance y «Parar»;
   - sus providers.
   - Pruebas con modelos falsos grabados, nunca llamadas reales.
4. **Resaltar en Word, EPUB, texto y «Texto extraído»**: los colores en `buildSpans` y elegir
   palabras tocándolas. Pruebas de widget y mutación.
5. **Resaltar en el PDF**: pintar sobre las letras de cada página, y elegir palabras tocándolas en
   la página. Pruebas y mutación.
5b. **Resaltar en la página web** (ampliación): estudiar también una página web; ubicar cada marca
   en el HTML archivado y envolverla con su color en la copia que se muestra; tocar una palabra
   para elegirla. Pruebas y mutación.
6. **La tarjeta «Estudiar el documento»**:
   - los tres botones y la leyenda;
   - la franja de avance;
   - «Extraer», con sus cuatro filas;
   - el mosaico «Resumir» de un documento;
   - la barra del lector a pantalla completa.
   - Textos en español e inglés. Pruebas de widget y mutación.
7. **Documentación y cierre**:
   - GUIA_DE_USO.md;
   - la decisión 79 en `docs/arquitectura.md`;
   - CONTEXTO y el «Avance» de este plan;
   - suite entera y `verify_commit`.
   - APK al teléfono solo si la pedís.

## Avance

### Paso 1 (hecho)

- `lib/features/study/domain/services/`:
  - `study_sentences.dart`: `splitStudySentences` parte en bloques —renglón en blanco, separador de
    páginas, título, ítem, viñeta— y cada bloque en oraciones. Un salto de línea solo no corta, y
    tampoco cortan una abreviatura, una inicial ni lo que sigue en minúscula. Una oración de más de
    600 caracteres se parte en sus renglones.
  - `study_words.dart`: las palabras con su lugar, `pickKeywords` (solo palabras de la oración, sin
    las vacías, hasta 4) y `studyWordAt`.
  - `study_reply.dart`: `studyPartEnd` (las partes, hasta 120 oraciones), `buildStudyPrompt` (las
    oraciones numeradas y sin marcado), `parseStudyReply` (tolerante a acentos, viñetas, negritas,
    rangos y «ninguna»; `null` si no contestó en el formato) y `studyReplyTokens`.
- El plegado de acentos y las palabras vacías salen de `quote_anchor.dart` a
  `lib/core/util/word_folding.dart`, compartido: no quedan dos copias.
- Pruebas: 46. Mutación 25/25. Una condición que sobraba (el rango al revés, que el ciclo ya no
  recorre) se sacó.

### Paso 2 (hecho)

- Esquema v40 (`study_marks.dart`):
  - `study_marks`: id, forma, clase (resumen, síntesis o palabra), origen (IA o persona), rango y
    fragmento copiado. Se borra en cascada con la forma.
  - `study_analyses`: hasta dónde se analizó cada texto y si terminó.
  - `content_trash.study_marks`: el JSON de lo estudiado de un texto soltado.
  - Migración aditiva, con los conteos de lo anterior como compuerta (`migration_v40_test.dart`).
- `StudyRepositoryImpl`:
  - `savePart` reemplaza, en una sola transacción, lo de la IA en el tramo de la parte. Las
    palabras que eligió la persona se quedan y no se duplican. Retomar una parte cortada no
    duplica nada.
  - También `addKeyword`, `removeKeyword` (nunca una oración), `clear` y `watch`.
- Al volver a extraer el texto (`TextAnchorRelocatorImpl`):
  - las marcas se reubican por su fragmento, y la que no aparece se va;
  - hasta dónde se analizó va al final de lo mismo en el texto nuevo, o vuelve a 0;
  - «terminado» se conserva solo si el texto nuevo no agrega nada al final.
- La papelera del contenido guarda lo estudiado con el texto y lo devuelve al recuperarlo.
- La unión de bóvedas trata cada análisis como uno solo:
  - si acá ya se analizó ese texto, queda el de acá, y de la copia entran solo las palabras
    elegidas a mano;
  - si no, entra el de la copia entero;
  - la misma marca con otro id no entra dos veces.
  - Las tablas nuevas se suman al censo de columnas, a «nunca se achica» y a las referencias.
- Pruebas: 11 del repositorio, 6 de la reubicación, 2 de la papelera, 4 de la unión, 4 de la
  migración y el censo de columnas. 1.799 pasan en `test/core`, papelera, transformación y estudio,
  y 634 en la bóveda. Mutación 20/20.
- Una trampa: `drift_dev schema generate` reescribe todos los `schema_vN.dart`; se restauraron
  con git y quedaron solo `schema_v40.dart` y el índice.


### Paso 3 (hecho)

- `AnalyzeForStudy` (`lib/features/study/domain/usecases/`):
  - analiza por partes, en orden, desde donde quedó (`analyzedUntil`), y guarda cada parte al
    terminarla: lo marcado aparece a medida que avanza y un corte no pierde nada;
  - avisa cuántas partes van y cuántas son desde antes de la primera;
  - si el modelo no contesta en el formato, reintenta una vez; si tampoco, la parte queda
    analizada sin marcas y se cuenta como «no se pudo leer»;
  - entre parte y parte mira si hay que parar.
- `StudyMarker` lo implementa `LanguageModelTasks`, así que usa el modelo elegido en la
  configuración —Gemma o el de la nube—:
  - el tamaño de parte sale de la ventana del modelo (`studyPartCharBudget`): de 800 a 15.000
    caracteres;
  - si el pedido no entra en la ventana, achica la parte a 3/4 hasta que entra, y avisa cuántas
    oraciones analizó.
- `StudyAnalysisNotifier` (por texto, no se descarta al salir de la pantalla) corre el análisis,
  lo para y mantiene viva la app con el servicio en primer plano («Analizando para estudiar»,
  en español e inglés).
- Pruebas: 8 del caso de uso, 4 del modelo, 4 del notificador. Mutación 18/18 (una mal armada por
  la sangría, rehecha y muerta).

### Paso 4 (hecho)

- `RenderedMarkdown.buildSpans` pinta **capas** (`PaintedRange`): las oraciones del resumen o de la
  síntesis debajo de los subrayados de la persona, las palabras clave encima y en negrita, y lo que
  se lee en voz alta por encima de todo. Es un barrido por los bordes de las capas, así que dos
  subrayados que se pisan ya no pierden el segundo. `rawToRender` pasa a búsqueda binaria: un
  documento largo tiene miles de oraciones marcadas.
- `readerPageRanges`: cada página del lector es un tramo tal cual del texto, y lo marcado cae en su
  página sin traducir nada. Un separador `---` pegado al principio o al final (una página vacía de
  un PDF) ya no deja una página con los guiones.
- `study_highlighting.dart`: `StudyView` (resumen **o** síntesis, palabras clave, elegir),
  compartida entre el detalle, «Leer como libro» y «Texto extraído»; los colores de resaltador
  (verde, celeste y rosa, con letra oscura en los dos modos); `studyPaints` y `paintsWithin`.
- Elegir palabras clave: tocar una palabra de una oración resaltada la agrega o la saca
  (`keywordToggleAt`). Con cuatro, avisa. Un artículo o una preposición no se elige, igual que con
  la IA.
- Se pinta en el lector de Word, EPUB y texto (embebido y a pantalla completa) y en «Texto
  extraído» de un documento.
- Pruebas: 6+2 del toque, 13 de la vista y el lector, 7 de las capas, 1 de `HighlightableText`, 4
  de la paginación. Mutación 23/24: el que sobrevive (`<` por `<=` en la búsqueda binaria) es
  equivalente, porque el texto renderizado no tiene huecos entre segmentos. Dos sobrevivientes
  llevaron a sacar una condición de más y a una prueba de tramos vacíos.
- Falta dónde prenderlo: los botones van en la tarjeta del paso 6.

### Paso 5 (hecho)

- Cada página del PDF se ubica en su texto extraído (`pdf_study_pages.dart`):
  - con un separador menos que páginas, el tramo N es la página N, y el texto de la página lo
    confirma al leerla;
  - si no da la cuenta, o una página con letras propias no coincide con su tramo, se recorren en
    orden (`PdfPageWalker`), que es exacto aunque una página traiga un `---` adentro. Del
    recorrido se guarda solo dónde cae cada una, no un libro entero de letras en memoria.
- `cleanPdfPageText` y el separador salen del parser a `transform/domain/documents/pdf_page_text.dart`,
  con `pdfCleanToRawIndices`: un `\r\n` de PDFium es un solo salto en el texto, y cada letra del
  texto vuelve a la suya en la página.
- `PdfStudyOverlay` pinta con `pagePaintCallbacks`: lee el texto de una página recién cuando hay
  que pintarla, arma un rectángulo por renglón y por color (la palabra clave encima de su oración,
  sin estirarse por un salto de renglón ni saltar de columna) y lo **multiplica** con el papel, así
  que la letra queda negra, como un resaltador. Los colores son los claros también en modo
  oscuro, porque la página es blanca.
- Una página escaneada no tiene esas letras: si algo resaltado cae en ella, lleva el aviso «Página
  escaneada: lo resaltado se ve en el texto extraído».
- Eligiendo palabras clave, tocar una letra del PDF agrega o saca su palabra; cualquier otro toque
  sigue con la selección de siempre.
- El PDF lleva su texto extraído desde el resolver (`PdfResolvedViewer.text`), en el detalle y a
  pantalla completa.
- Pruebas: 4 de la correspondencia de letras, 21 de la ubicación y los rectángulos, 8 de la capa
  sobre un PDF falso, 1 del resolver. Mutación 22/22. Dos que sobrevivían al principio llevaron a
  probar la última página con un sello y un salto de renglón con lugar en la página.

### Paso 5b (hecho)

- Una página web se estudia como un documento (`study_target.dart`): su texto principal es el
  Markdown que dejó el modo lectura.
- `archived_page_study.dart` arma la copia que se muestra del HTML archivado:
  - sin los programas de la página —`<script>`, atributos `on…`, enlaces `javascript:`, el
    `meta refresh` y su CSP—; lo de `<noscript>` queda a la vista;
  - cada oración del resumen o de la síntesis se busca en el texto de la página, letra por letra
    sin acentos ni signos —saltando las marcas y las direcciones de los enlaces del Markdown—, en
    orden y, si no aparece después de la anterior, desde el principio; la que no está se saltea;
  - se envuelve en `<mark>` con su clase, partida en cada etiqueta que cruza; cada palabra lleva
    su lugar en el texto (`data-o`), así que una palabra cortada por una etiqueta es una sola;
  - no se toca lo que no es texto de leer —un desplegable, un campo, un SVG— ni los espacios entre
    bloques, que entre las filas de una tabla moverían cosas;
  - suma una hoja con los colores de resaltador y un programa propio, chico: prende el resumen o
    la síntesis y las palabras clave cambiando una clase, y eligiendo palabras manda la tocada por
    el canal `SinapsisStudy`.
- `WebPageViewerView` arma esa copia en otro hilo (`Isolate.run`) solo cuando cambian las
  oraciones; prender una capa o una palabra es un `runJavaScript`, sin volver a cargar la página.
  Se carga con la dirección de la página como base, así que lo que no se guardó se busca en
  internet.
- El visor incrustado de la página web lleva el botón grande, como un libro: **«Ver la página»**.
- **Las fotos no aparecían** por dos causas:
  - una carga perezosa deja en `src` un cuadradito y la foto en `data-src`: sin JavaScript nadie
    los cambia;
  - con un `srcset`, el navegador del teléfono —de pantalla densa— elige de ahí antes que el `src`
    que se había guardado, y esa versión no estaba guardada.
- Se arreglan en las dos puntas: el archivador guarda la foto de verdad y la deja sola, sin
  alternativas (`settleImage`); el visor arregla al mostrarlas las páginas archivadas antes
  (`showArchivedImages`).
- La elección de la foto queda en un solo lugar, `transform/domain/archive/page_images.dart`, que
  usan el buscador de adjuntos (la más grande), el archivador y el visor (la que alcanza para
  leer, hasta 1600 de ancho o 2x). Ahí pasan `parseSrcset` y los atributos de carga perezosa, que
  estaban repetidos en `page_urls.dart` y en el buscador.
- Pruebas: 16 de la página estudiada, 21 de las fotos, 4 del archivador, 2 de las direcciones
  completas (no tenían ninguna), 1 del resolver, 1 del botón grande y 3 de qué se estudia; el
  buscador de adjuntos, con una foto de más de 1600 de ancho.
- Mutación 44/44, en dos tandas. Siete sobrevivían al principio: buscar desde el principio, el
  texto fuera de una oración, lo que no es de leer, el cuadradito en la carga perezosa, el tope
  del buscador y completar las direcciones perezosas. Cada uno llevó a su prueba.

### Paso 6 (hecho)

- **La tarjeta «Estudiar el documento»** (`study_document_card.dart`) va en el detalle debajo del
  original, en un documento y en una página web (ahí se llama «Estudiar la página»):
  - arriba, los tres botones con su color —Resumir y Sintetizar se excluyen, y tocar el prendido
    lo apaga— y el lápiz para elegir palabras; debajo, la leyenda;
  - prender uno analiza lo que falta, si no está todo analizado ni se está analizando; sin el
    modelo listo lo avisa, con su botón para bajarlo;
  - la franja: «Analizando… parte 3 de 12» con su barra y «Parar»; si se corta, «Reintentar»
    sigue desde ahí; las partes que no se pudieron leer se cuentan, con «Entendido». Terminado
    sin problemas, no ocupa lugar;
  - el menú «⋮» trae «Volver a analizar», que pregunta antes de borrar lo estudiado y no se
    ofrece mientras analiza;
  - «Extraer»: el texto extraído (solo en un documento: el de una página web se sigue mostrando
    entero), el resumen y la síntesis como texto corrido, con cuántas oraciones y palabras son, y
    las palabras clave como etiquetas en orden. Una fila sin nada no se abre y dice por qué:
    «Tocá Resumir o Sintetizar para empezar» o «Todavía no hay nada acá». Cada una tiene «Copiar».
- Lo que se extrae se calcula en `study_extracts.dart`, sin marcado de Markdown;
  `studyPlainText` sale de la respuesta del chat de estudio para usarse en los dos lados.
- **Una sola fuente de qué se estudia**: `studyTextOf(item)` (forma de texto, contenido y si es
  Markdown). La usan la tarjeta, el resolver y los visores. El visor de texto lleva lo estudiado
  solo si muestra esa misma forma de texto; si no, pintaría las marcas fuera de lugar.
- El mosaico «Resumir» del panel, en lo que se estudia, prende el resumen en la tarjeta y la trae
  a la vista, sin el diálogo de siempre.
- **A pantalla completa** llevan los mismos botones (`StudyBar`): el lector de libros en vez de
  «Resumir con IA» por página, el PDF y la página web arriba. Un adjunto que no se estudia
  conserva su «Resumir con IA».
- Textos en español e inglés.
- Pruebas: 19 de la tarjeta, 5 de lo que se extrae, 2 de la página a pantalla completa, 2 del
  lector, 2 del detalle, 1 del panel, 2 del visor abierto y 1 del resolver; `MemoryStudyRepository`
  y `FakeStudyAnalysis` quedan en `test/support/`.
- Mutación 29/29. Tres sobrevivían al principio: que el «Resumir» del panel analice, que una fila
  vacía no se abra y que el visor no lleve lo estudiado de otra forma de texto. Cada uno llevó a
  su prueba.
