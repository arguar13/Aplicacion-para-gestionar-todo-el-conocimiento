# F36 — Resumen, síntesis y palabras clave resaltados en el documento

> **Estado: en construcción** (2026-10-22).
>
> **Aprobado** (2026-10-22), en el chat: *"aprobado"* —con las decisiones A–D tal como están—.
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

- En una página web, un video, un audio o una nota, «Resumir» sigue siendo el párrafo en el diálogo.
- En un documento, el mosaico «Resumir» del panel lleva a la tarjeta nueva y prende el resumen.
- No se pierde ninguna función: «Texto extraído» sigue con todo lo de hoy —leer en voz alta,
  subrayar, seleccionar—, solo que ahora vive dentro de «Extraer».

## Decisiones para que confirmes al aprobar

- **A.** Resumen y síntesis son **oraciones del documento**: es lo que permite resaltarlos en el
  original. Si querés, además, una síntesis **redactada** con otras palabras, va aparte.
- **B.** **Uno a la vez**, resumen o síntesis, y las palabras clave encima del que esté activo.
- **C.** Colores: resumen verde, síntesis celeste, palabras clave rosa. El amarillo queda para lo
  que se lee en voz alta.
- **D.** Las palabras clave **las propone la IA y las ajustás vos**, hasta 4 por oración.

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
6. **La tarjeta «Estudiar el documento»**:
   - los tres botones y la leyenda;
   - la franja de avance;
   - «Extraer», con sus cuatro filas;
   - el mosaico «Resumir» de un documento;
   - la barra del lector a pantalla completa.
   - Textos en español e inglés. Pruebas de widget y mutación.
7. **Documentación y cierre**:
   - GUIA_DE_USO.md;
   - la decisión 78 en `docs/arquitectura.md`;
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
