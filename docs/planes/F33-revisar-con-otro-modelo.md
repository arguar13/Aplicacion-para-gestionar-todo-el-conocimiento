# F33 — «Revisar con otro modelo»: que un modelo más capaz revise lo que hizo la IA anterior

> **Estado: aprobado** (2026-10-16), en el chat, **con las cinco recomendadas**: revisa todo lo de la
> IA que sigue siendo suyo; corrige y saca, sin agregar; sale de la cuota de la persona, avisando
> antes cuánto cuesta; el aviso al cambiar a un modelo más capaz, una vez por modelo; se construye
> apenas cierre F32.
>
> Pedido: *"agrega también un botón elegante o botones para que si lo aprieto revise lo que otro
> modelo hizo, por ejemplo si cambio a un modelo más inteligente … que al apretar revise si la IA
> anterior hizo todo bien, y que en caso de haber correcciones o mejoras me las muestre y yo las
> acepte una a una o acepte todas en bloque elegantemente, así tenga todo lo anterior acorde
> correctamente"*.

## Lo que hay hoy (relevado en el código)

| Qué | Cómo está |
|---|---|
| **Quién hizo cada cosa** | Cada pasada de la IA guarda **qué modelo la hizo** (`ai_runs.model`, desde F32: «gemini-3.8-flash», «Gemma 4 E4B»…). Todo lo que la IA crea —vínculos, tarjetas, propiedades, el tema, los datos de la referencia, las notas mapa— queda marcado con su pasada. |
| **Qué sigue siendo de la IA** | Lo que editaste o borraste deja de contar como de la IA: ya es tuyo. Eso no se revisa nunca. |
| **Revisar y aceptar** | «Para revisar» ya tiene **Aceptar / Descartar** de a uno y **Aceptar todo / Descartar todo** con unos segundos para **Deshacer**. |
| **Deshacer** | Cada pasada se deshace entera, y «No era» evita que la IA vuelva a proponer lo mismo. |

O sea: la app ya sabe **qué hizo cada modelo** y **qué sigue siendo suyo**, que es justo lo que hace
falta para revisarlo.

## Qué se construye

1. **El botón «Revisar con *el modelo de ahora*».** Elegante, con el ✨ y el nombre del modelo
   (p. ej. **«Revisar con Gemini 3.8 Flash»**), en tres lugares:
   - **«Lo que hizo la IA»**: arriba, una tarjeta que dice cuánto hizo cada modelo anterior
     (*«312 cosas de Gemma 4 E4B en 85 elementos»*) con el botón para revisarlas todas, o solo las
     de un modelo.
   - **En cada elemento**, en la línea «La IA organizó esto»: revisar solo ese.
   - **Al cambiar a un modelo más capaz**, un aviso una sola vez: *«Cambiaste a Gemini. ¿Querés que
     revise lo que hizo Gemma?»*.
2. **Antes de empezar, cuánto va a costar**: cuántos elementos y cuántos pedidos al modelo, y si
   tus cuentas tienen cuota para eso hoy. La revisión corre de fondo, con barra de avance, **pausa
   y cancelar**, y si se acaba la cuota **espera sin perder nada** (lo mismo que hace F32).
3. **Qué revisa el modelo nuevo**, de lo que sigue siendo de la IA:
   - **Tarjetas**: que la pregunta sea clara, que la respuesta sea correcta según la cita, que la
     cita esté en el texto. Propone **corregirla** (con el antes y el después) o **sacarla**.
   - **Vínculos**: que el tipo (Relacionado, Continúa, Contradice, Cita, Resume) y la frase de por
     qué sean correctos; o que no correspondía.
   - **Etiquetas y propiedades, el tema y los datos de la referencia**: el valor correcto, o que
     sobra.
   - **La introducción de las notas mapa**.
4. **«Revisión»: lo que propone, para que decidas.** Una sección nueva en «Lo que hizo la IA», junto a
   «Para revisar», agrupada por elemento. Cada propuesta muestra **el antes y el después** resaltado,
   **por qué** (una línea del modelo) y quién lo propone. Botones **Aceptar** y **Descartar** en cada
   una; arriba **Aceptar todo** y **Descartar todo** (de todo, o de un elemento), con **Deshacer**.
   - **Nada cambia hasta que aceptás.**
   - Lo que aceptás queda como **una pasada del modelo nuevo**: se ve en la actividad y **se deshace**
     como cualquier otra (vuelve a como estaba).
   - Lo que descartás no se vuelve a proponer.
   - Un elemento ya revisado por un modelo no se vuelve a revisar con el mismo, salvo que lo pidas.

## Decisiones que necesito que confirmes

- **A. Qué revisa.**
  - *(Recomendado)* **Todo lo de la IA que sigue siendo suyo**: tarjetas, vínculos, etiquetas y
    propiedades, el tema, la referencia y las notas mapa.
  - Alternativa: **solo las tarjetas** al principio (lo que más se nota si está mal), lo demás después.
- **B. «Mejoras»: ¿solo corregir lo que hay, o también agregar lo que falta?**
  - *(Recomendado)* **Corregir y sacar lo que está mal o sobra**, sin agregar cosas nuevas. Agregar
    (más tarjetas, vínculos que faltan) ya lo hace «Organizar con la IA» con el modelo nuevo; mezclarlo
    acá haría la revisión mucho más larga y cara.
  - Alternativa: **también agregar** lo que el modelo nuevo vea que falta, como propuestas más.
- **C. De qué cuota sale.**
  - *(Recomendado)* **De la tuya, como algo que pediste** (no del tope diario de la IA de fondo), pero
    **avisando antes cuánto cuesta** y con pausa. Una biblioteca grande pueden ser cientos de pedidos.
  - Alternativa: **del tope de la IA de fondo**: más lento (unos días para una biblioteca grande) pero
    nunca te deja sin cuota para el chat.
- **D. El aviso al cambiar de modelo.**
  - *(Recomendado)* **Sí, una vez por modelo**, solo si el nuevo es más capaz (un modelo en la nube
    después de Gemma, o uno más grande del mismo proveedor), y con «No, gracias».
  - Alternativa: **sin aviso**: solo el botón.
- **E. Cuándo se construye.**
  - *(Recomendado)* **Apenas cierre F32** (falta: las partes por la ventana del modelo, OpenAI y
    Claude). F33 se apoya en el modelo elegido de F32, así que va justo después.
  - Alternativa: **antes de OpenAI y Claude** (que hoy no usás porque son de pago).

## Lo que cambia por dentro

- **Un paso nuevo de la IA, el revisor**: por cada elemento, junta lo que sigue siendo de la IA con
  el texto de donde salió y se lo da al modelo elegido. El modelo contesta en un formato fijo (qué
  corregir, cómo y por qué) que la app lee con cuidado: lo que no entiende lo descarta, nunca lo
  aplica. Vale para cualquier modelo de F32, sin repartir tareas.
- **Las propuestas se guardan como sugerencias** (la misma maquinaria de «Para revisar»: aceptar,
  descartar, en bloque, deshacer), con un tipo nuevo, «corrección», que guarda el antes y el después.
  Hay que revisar si entra sin cambiar el esquema de la base; si no, una migración chica.
- **Aceptar aplica el cambio dentro de una pasada nueva del modelo revisor**: así «Deshacer» devuelve
  todo a como estaba, y la actividad muestra qué modelo corrigió qué.
- **La cola de la revisión** es la de la IA de fondo de F32, con lo que ya sabe: esperar la cuota,
  retomar donde quedó, ceder el modelo cuando lo usás vos.

## Orden de trabajo

1. El revisor de tarjetas, con su formato y su lectura, y las propuestas como sugerencias.
2. La sección «Revisión» con el antes y el después, aceptar y descartar de a uno y en bloque.
3. El botón en «Lo que hizo la IA» y en cada elemento, la cuenta del costo, la barra de avance.
4. Los vínculos, las etiquetas y propiedades, el tema, la referencia y las notas mapa.
5. El aviso al cambiar de modelo.
6. Pruebas con respuestas grabadas (nunca llamadas reales), comprobadas por mutación; la guía de
   uso; su decisión en `docs/arquitectura.md`.

## Avance

### Paso 1 (hecho): el revisor de tarjetas y las correcciones como sugerencias

- **Sin migración.** `correction` es un valor nuevo de `SuggestionKind` y `review` uno de
  `AiRunScope`, los dos en columnas de texto. Qué se corrige (`CorrectionSubject`), el antes, el
  después, el porqué, el modelo y la pasada de revisión van en el `payload_json`.
- **`Suggestion.correction`** (`CorrectionSuggestion`): `subject`, `subjectId`, `before`, `after`
  (`null` = sacarlo), `reason`, `aiRunId` (la pasada de revisión), `model`.
- **`lib/core/database/correction_suggestions.dart`**, compartido por los repositorios de
  sugerencias y de pasadas, como `atlas_suggestions.dart`:
  - **Aplicar al aceptar.** Solo si la tarjeta sigue siendo de la IA y está igual que cuando la
    vio el modelo; si no, falla y no toca nada.
  - **Corregir.** Cambia el texto y la tarjeta sigue siendo de la IA, de la pasada que la hizo.
    Si cambió la pregunta, recuerda la de antes como «no era».
  - **Sacar.** Guarda la tarjeta entera, con sus opciones y sus repasos, recuerda su pregunta
    como «no era» y la borra.
  - **Deshacer la pasada de revisión** (`undoAiCorrections`, desde `AiRunRepositoryImpl._undo`).
    La tarjeta corregida vuelve a su texto si sigue como la dejó la corrección. La sacada vuelve
    entera, salvo que la pasada que la hizo se haya deshecho. Olvida solo el «no era» que recordó
    ella, y la corrección queda descartada, para que no se vuelva a proponer.
  - **Contar** (`aiCorrectionCounts`). `AiRunTally.corrections` lleva lo aceptado (la historia) y
    lo que sigue en pie.
- **El revisor.**
  - La interfaz es `FlashcardReviewer`, implementada en `LanguageModelTasks.reviewFlashcards` con
    su instrucción y su tope (`flashcardReviewReplyTokens`).
  - El formato es `TARJETA <n>: bien | corregir | sacar`, más `P:`, `R:` y `POR QUÉ:`.
  - El lector, `parseFlashcardReview`, descarta lo que no entiende: un veredicto sin porqué, una
    corrección incompleta o que no cambia nada, un número fuera de la lista. Si una tarjeta
    aparece dos veces, vale la primera.
  - `passageForReview` arma el pasaje de cada tarjeta alrededor de su cita.
- **El paso** `ReviewFlashcardsStep.review(item, runId:, model:)`:
  - Revisa solo las tarjetas de pregunta y respuesta que siguen siendo de la IA.
  - Pide de a tantas como lee el modelo, con el pasaje repartido entre ellas, entre 400 y 2400
    caracteres por tarjeta.
  - No vuelve a revisar una tarjeta con una corrección pendiente, ni propone otra vez lo que la
    persona descartó.
- **Lo que no se ve todavía.** Las correcciones no entran en «Para revisar» ni en el diálogo de la
  Bandeja: tienen su sección propia, que es el paso 2. Todavía no hay botón ni cola: eso es el
  paso 3.
- **Pruebas.** Lector y pasaje (16), aplicar, deshacer y contar contra SQLite en memoria (17), el
  paso (7) y `reviewFlashcards` con un Gemma de mentira (2), todas con respuestas grabadas.
- **Mutación: 33 de 34 muertas.** La que sobrevive, «cuenta como vigente una corrección
  deshecha», es equivalente: una corrección aplicada solo queda descartada al deshacerse, y para
  entonces la tarjeta ya volvió a como estaba (o volvió entera), así que no cuenta igual.

### Paso 2 (hecho): la sección «Revisión»

- **`SuggestionRepository.watchPendingCorrections()`** trae las correcciones pendientes por
  elemento (`CorrectionReviewItem`), el de la más nueva primero.
  - Solo ofrece las que todavía valen (`stillApplicableCorrections`): una sobre una tarjeta que la
    persona editó, borró o cambió se va sola, también mientras se mira.
  - Las de un elemento en la papelera no se ofrecen.
- **En «Lo que hizo la IA»**, después de «Para revisar» y con el mismo estilo
  (`ai_correction_cards.dart`):
  - Arriba, «Aceptar todo» y «Descartar todo» con «Deshacer». El lote se aplica cuando se cierra
    el aviso, igual que en «Para revisar».
  - Una tarjeta por elemento, con «Aceptar las N» cuando hay más de una.
  - En cada corrección: qué propone (corregir o sacar la tarjeta) y quién lo propone, con el ✨ y
    el nombre lindo del modelo (`modelLabel`: «Gemini 3.8 Flash», «Claude Opus 5.5»,
    «GPT-5.2 mini»).
  - La pregunta y la respuesta muestran el antes, con lo que se va tachado, y el después, con lo
    que llega resaltado, palabra por palabra (`wordDiff`, la subsecuencia común más larga, sin
    distinguir mayúsculas). Lo que no cambió se muestra una sola vez.
  - Debajo va el porqué, y después Descartar y Aceptar.
- **El número de Ajustes › IA** (`pendingDecisionsCountProvider`) suma «Para revisar» y «Revisión».
- **Pruebas.** Diff (7), nombre del modelo (4), lo que lista «Revisión» (3) y la pantalla (9).
- **Mutación: 17 de 17 muertas.**
- **Lo que sigue: el paso 3.**
  - El botón «Revisar con <modelo>» en «Lo que hizo la IA» y en cada elemento.
  - Antes de empezar, cuánto va a costar.
  - La revisión corre en la cola de fondo, con barra de avance, pausa y cancelar.
  - Usa el turno de la cola, que cede el modelo cuando lo usás vos, pero gasta de tu cuota y no del tope de la IA de fondo.
  - Al cambiar de modelo a mitad, espera y retoma.

### Paso 3a (hecho): la cola de la revisión, por dentro

- **`AiReviewQueue`** revisa de a un elemento por vez y en segundo plano, cada uno en su pasada de
  revisión (`AiRunScope.review`) con el modelo elegido:
  - **Sale de la cuota de la persona** (decisión C). El chequeo del modelo es el de la persona,
    sin el tope de la IA de fondo, y el revisor usa
    `LanguageModelTasks.requestedInBackground`: tiene el turno de la cola (le cede el modelo a la
    persona cuando lo pide y repite lo cortado), pero gasta con el motor de la persona.
  - **Si el modelo no puede contestar por ahora** (sin cuota, sin conexión, saturado), espera sin
    perder nada: el elemento cortado se retoma primero y en la misma pasada, a la hora de la
    renovación o al cambiar el modelo o las cuentas.
  - **Pausa, seguir, cancelar y cerrar.** Cancelar cierra la pasada del que esperaba con lo que
    alcanzó. Un pedido nuevo se suma al que corre, sin repetir elementos.
  - **Revisar la biblioteca deja afuera lo que hizo el mismo modelo**; pedido en un elemento, no.
  - Publica cómo va (`AiReviewBatch`: cuántos, cuántas propuestas, qué lee, por qué espera) y
    mantiene viva la app con su propio dueño del servicio en primer plano
    (`LongWorkOwner.aiReview`, «Revisando lo que hizo la IA» en Android), antes que la IA de fondo.
- **Qué hay para revisar** (`AiRunRepository`):
  - `aiWorkByModel()`: cuántas tarjetas de la IA siguen en pie por modelo y en cuántos elementos.
  - `reviewCandidates(reviewer:, madeBy:, itemId:)`: los elementos por revisar. Sin `itemId`,
    sin lo del mismo modelo ni lo que ese modelo ya revisó (una pasada de revisión suya,
    terminada y en pie). Con `itemId`, todo lo de ese elemento.
  - Cuentan solo las tarjetas de pregunta y respuesta, de pasadas en pie y elementos fuera de la
    papelera; lo de pasadas viejas sin modelo anotado también.
- **Pruebas.** La cola (15), qué hay para revisar (5), el motor pedido de fondo (4), el servicio en
  primer plano (2).
- **Mutación: 31 de 32 muertas.** La que sobrevive, «cuenta lo de una pasada deshecha», es
  equivalente: deshacer una pasada borra las tarjetas que siguen siendo suyas, así que no queda
  ninguna que apunte a una pasada deshecha.

### Paso 3b (hecho): el botón, la cuenta del costo y la barra de avance

- **La oferta**, arriba de «Lo que hizo la IA» mirando toda la biblioteca (`AiReviewOfferCard`):
  - El título es «Que otro modelo lo revise». Debajo, cuánto hizo cada modelo que el elegido
    todavía no revisó, por ejemplo «12 tarjetas de Gemma 4 E4B en 5 elementos».
  - El botón **«Revisar con Gemini 3.8 Flash»**, con el nombre del modelo elegido, revisa todo.
    Si hay trabajo de más de un modelo, «Solo lo de …» revisa lo de uno.
  - No se ve si no hay nada para revisar, ni mientras corre una revisión.
  - Lo cuenta `aiWorkByModel(reviewer:)`, con los mismos filtros que `reviewCandidates`: sin lo
    que hizo el mismo modelo ni los elementos que ya revisó. Se vuelve a contar al cambiar de
    modelo y a medida que avanza la revisión.
- **En cada elemento**, en la línea «La IA organizó esto», «Revisar con …» si dejó tarjetas.
  Revisa todo lo del elemento, aunque lo haya hecho o revisado el mismo modelo, y avisa
  «Revisando con …», con «Ver».
- **Antes de empezar** (`startAiReview`, `AiReviewCostDialog`) dice cuántas tarjetas hay en
  cuántos elementos y unos cuántos pedidos al modelo (`aiReviewRequests`, de a tantas tarjetas
  por pedido como lee el modelo). Si no queda nada, lo dice y no pregunta.
  - **En la nube** sale de tu cuota, no del tope de la IA de fondo. Muestra los pedidos de hoy
    con las cuentas del proveedor y, si todas están sin cuota, a qué hora empieza sola. Si no,
    aclara que los proveedores no dicen cuánto queda.
  - **Con Gemma** corre en el teléfono, sin cuota, y puede tardar.
- **El avance** (`AiReviewProgressCard`) muestra cuántos elementos van de cuántos, cuántas
  propuestas dejó y qué lee, con la barra, «Pausar», «Seguir», «Cancelar» y, al terminar,
  «Cerrar».
  - Si espera al modelo dice por qué, con los mismos textos que la cola de la IA de fondo.
  - Si hace falta que la persona haga algo (falta el modelo o una clave, sin cuota, claves
    rechazadas) ofrece «Ir al modelo». Sin conexión o con el proveedor saturado, no: vuelve sola.
- **Guía de uso.** Nueva sección «Revisar con otro modelo», y «Revisión» en «Lo que hizo la IA».
- **Pruebas.** La pantalla (12), la línea del elemento (4), la consulta con revisor y la cuenta de
  pedidos (2).
- **Mutación: 22 de 22 muertas.**

### Paso 4: cómo se arma (diseño, relevado en el código)

Lo que no son tarjetas se revisa junto: **un pedido por elemento** (o los que hagan falta para que
entre en la ventana del modelo) con todo lo que sigue siendo de la IA en ese elemento, numerado.
Cada cosa con su contexto: el vínculo con el título y un fragmento del otro elemento, la propiedad
con su categoría, el tema con los temas que hay, el dato de la referencia con su nombre. El
formato es el mismo de las tarjetas: `DATO <n>: bien | corregir | sacar`, el valor nuevo y
`POR QUÉ:`. El lector descarta lo que no entiende o no cumple las reglas de cada cosa.

| Qué | Corregir | Sacar | Lo que se recuerda como «no era» |
|---|---|---|---|
| **Vínculo** | El tipo (uno de los cinco) y su frase | Sí | El vínculo con su tipo de antes |
| **Etiqueta o propiedad** | Por otro valor **que ya esté** en esa categoría: inventar vocabulario se mira en «Para revisar», como hoy | Sí | La asignación |
| **Tema** | Por otro tema que ya exista | Sí | — (no hay memoria de temas) |
| **Dato de la referencia** | Los de texto: revista o libro que lo contiene, editorial, lugar, edición, volumen, número, páginas, ISBN, ISSN, DOI | Sí (lo vacía) | — |
| **Introducción de una nota mapa** | El texto | No: es el índice de un tema | — |

El tipo de obra, las personas y la fecha de la referencia no se revisan en F33. Son datos con su
propio editor (rol y orden, exactitud de la fecha), y corregirlos a ciegas rompe más de lo que
arregla.

Las mismas reglas que las tarjetas:
- Solo se toca lo que sigue siendo de la IA y está como lo vio el modelo.
- Lo corregido **sigue siendo de la IA, de la pasada que lo hizo**. En el tema y la referencia se
  actualiza también lo que esa pasada recuerda haber puesto (`ai_field_changes.after_value`), para
  que deshacerla devuelva lo de antes de la IA.
- Deshacer la revisión devuelve lo que cambió, si sigue como lo dejó.

Partes, un commit cada una:
- **4a.** El núcleo de las correcciones, para más de una cosa, y los vínculos: aplicar, deshacer,
  contar, ofrecer solo lo vigente, y cómo se ven en «Revisión».
- **4b.** Las etiquetas y propiedades, y el tema.
- **4c.** Los datos de la referencia y la introducción de las notas mapa.
- **4d.** El revisor de «lo demás»: instrucción, formato, lector y paso, sumado a la cola. La
  oferta y el costo cuentan todo («312 cosas de Gemma 4 E4B en 85 elementos»). La guía.

### Paso 4a (hecho): el núcleo para más de una cosa, y los vínculos

- **`correction_suggestions.dart`** queda con una pieza por cosa que se corrige (`_Target`), y
  todo lo demás compartido: aplicar, deshacer, contar y ofrecer solo lo vigente. Cada pieza sabe
  leerse, decir si sigue siendo de la IA y como la vio el modelo, cambiarse o sacarse, y volver.
- **Vínculos** (`CorrectionSubject.relation`, `RelationCorrectionField`: el tipo y la frase).
  Solo los que son una opinión sobre dos elementos; una extracción o un índice no se tocan.
  - **Corregir** cambia el tipo y la frase. El vínculo sigue siendo de la IA, de su pasada, y el
    tipo de antes queda como «no era». No se acepta un tipo de estructura, uno que no existe, ni
    uno que ya hay entre los dos elementos.
  - **Sacar** lo borra, recuerda que «no era» y lo guarda entero.
  - **Deshacer la revisión:**
    - Al vínculo corregido le devuelve el tipo y la frase, salvo que la persona ya haya hecho
      ese vínculo.
    - El que se sacó vuelve solo si su pasada sigue en pie, no hay otro igual y sus dos
      elementos existen (en la papelera también cuentan).
    - En los dos casos olvida el «no era» que recordó.
  - «Revisión» deja de ofrecerlo apenas la persona edita el vínculo: la consulta también mira la
    tabla de vínculos.
- **`label`** en la corrección: qué es, cuando no lo dicen los datos. En un vínculo, el título
  del otro elemento («Corregir el vínculo con «Cartago»»).
- **Arreglo de raíz en las tarjetas:** el «después» se guardaba sin recortar los espacios, y una
  corrección aceptada con espacios de más no contaba como en pie.
- **Pruebas.** Vínculos contra SQLite en memoria (14), y la vista en «Revisión» (1).
- **Mutación: 17 de 17 muertas.** Una sobrevivía, «no mira el tipo», y faltaba la prueba de dos
  correcciones sobre el mismo vínculo.

### Paso 4b (hecho): las etiquetas y propiedades, y el tema

- **El núcleo**, un poco más general:
  - **Lo corregido puede cambiar de identidad.** Una etiqueta corregida es otra fila, porque la
    asignación es el par elemento y valor. La corrección anota cuál quedó (`appliedSubjectId`), y
    contar y deshacer miran esa.
  - **«Sacado» lo decide cada cosa** (`isRemoved`). Casi siempre es que ya no está; el tema, en
    cambio, sigue teniendo su registro, y sacado es el elemento sin tema.
  - **Deshacer recibe la hora**, porque cambiar el tema queda versionado como cualquier edición.
- **Etiquetas y propiedades** (`CorrectionSubject.property`, `PropertyCorrectionField`: la
  categoría y el valor; el id es `elemento/valor`).
  - **Corregir** la cambia por un valor **que ya esté** en esa categoría, como está escrito ahí o
    por un alias. No inventa vocabulario, no la cambia por lo mismo ni pone una que el elemento ya
    tiene. Sigue siendo de la IA y de su pasada, y la de antes queda como «no era».
  - **Solo se corrigen las de texto.** Un número, una fecha o una persona se sacan o se editan a
    mano.
  - **Sacar** la quita del elemento (el valor sigue en el vocabulario) y recuerda que «no era».
  - **La que puso una nota mapa** es parte de la nota y no se ofrece.
  - **Deshacer la revisión** vuelve al valor de antes, salvo que la persona haya sacado la
    corregida o puesto a mano el de antes. La sacada vuelve si su pasada sigue en pie y nadie la
    volvió a poner. En los dos casos olvida el «no era».
- **Tema** (`CorrectionSubject.space`, `SpaceCorrectionField`: el id y el nombre; el id de la
  corrección es el registro de la pasada en `ai_field_changes`).
  - **Corregir** lo cambia por otro tema que exista. También cambia lo que la pasada recuerda
    haber puesto (`after_value`), así sigue siendo de la IA: deshacer esa pasada deja el elemento
    sin tema, como estaba antes de ella.
  - **Sacar** lo deja sin tema.
  - **No toca** el tema que eligió la persona, aunque coincida con lo que vio el modelo, ni el de
    una pasada deshecha.
  - **Deshacer la revisión** devuelve el de antes o vuelve a ponerlo, salvo que la persona ya le
    haya elegido otro o la pasada que lo puso se haya deshecho.
- **«Revisión»** muestra la categoría y el valor de antes y de después («Corregir «Tema»»), y el
  tema («Sacar el tema»). La consulta en vivo también mira las asignaciones y el vocabulario:
  renombrar un valor vuelve vieja la corrección.
- **Pruebas.** Etiquetas (14) y tema (11) contra SQLite en memoria, y las dos filas en «Revisión»
  (2).
- **Mutación: 23 de 23 muertas, y un chequeo que nunca corría, sacado.**
  - «corrige un número» sobrevivía porque la prueba fallaba por otra razón: el valor no estaba en
    el vocabulario.
  - «el tema de la persona» sobrevivía porque faltaba la prueba del tema que la persona eligió
    igual al que vio el modelo.
  - «no mira el origen» sobrevivía porque se pedía también la pasada, que solo va con origen
    `ai`. Queda solo el origen: una asignación de la IA cuya pasada se borró sigue siendo de la
    IA.
  - «vuelve la sacada sobre una puesta» probaba un chequeo que nunca se alcanzaba (lo mira antes
    quien llama). Se sacó, y quedó la prueba del caso.

### Paso 4c (hecho): los datos de la referencia y la introducción de las notas mapa

- **Datos de la referencia** (`CorrectionSubject.reference`, `ReferenceCorrectionField`: cuál,
  de qué clase de obra y su valor; el id es el registro de la pasada en `ai_field_changes`).
  - Solo los de texto: revista o libro que lo contiene, editorial, lugar, edición, volumen,
    número, páginas, ISBN, ISSN y DOI (`AiChangedField.isReferenceText`).
  - **Corregir** guarda el valor como lo dejaría el formulario (recortado, con los
    identificadores normalizados), y lo mira **antes** de escribir: un ISBN que no es válido no
    deja nada a medias. Como el tema, actualiza lo que la pasada recuerda haber puesto, así
    deshacer esa pasada vacía el dato como antes de la IA.
  - **Vaciar** lo deja vacío.
  - **Deshacer la revisión** devuelve el de antes o lo vuelve a poner, salvo que la persona ya
    haya escrito otro o la pasada que lo completó se haya deshecho.
  - En «Revisión» se llama como en el formulario según la clase de obra: el contenedor de un
    artículo es la «Revista».
- **Introducción de una nota mapa** (`CorrectionSubject.mapIntro`, el id es la nota).
  - Es el párrafo que va antes del primer título; una nota sin introducción no se ofrece.
  - Solo se corrige mientras la nota sigue siendo de la IA: viva, generada, sin editar y sin que
    la persona haya deshecho la pasada que la organizó. Es lo mismo que mira el Atlas para
    mantenerla.
  - **Corregir** deja un párrafo, sin enlaces (los arma la app). No se saca: es parte del
    índice. No marca la nota como editada por la persona, así el Atlas la sigue actualizando.
  - **Deshacer la revisión** vuelve a la de antes, salvo que la introducción haya cambiado
    después.
- **Cómo se escribe:**
  - `KnowledgeEntryWriter.setRenditionContent` cambia el texto de una forma sin pasar por el
    elemento entero, versionado como cualquier edición.
  - Lo que compara y vacía los datos de la referencia (`aiFieldValue`, `referenceWithout`,
    `referenceWithText`) pasó del registro de la pasada a core (`ai_field_values.dart`): el que
    deshace la pasada y el que corrige leen igual.
  - `organizeRunSql` también pasó a core.
- **Arreglo de raíz en el Atlas.** Para saber si la persona le sacó una nota mapa a la IA, el
  Atlas miraba la última pasada sobre la nota, fuera la que fuera. Deshacer una revisión de esa
  nota hacía que la IA la soltara y dejara de mantenerla. Ahora mira solo las pasadas que
  organizan (`organizeRunSql`), en las dos consultas.
- **«Revisión» en vivo.** No hacía falta sumar tablas: la referencia, el texto de la nota y la
  marca de editada los escribe el escritor del elemento, que sube su versión con cada cambio. Las
  tres mutaciones que lo muestran se dejaron documentadas en el comentario de la consulta.
- **Pruebas:**
  - referencia (10) e introducción (11), con los repositorios de verdad;
  - el escritor (2);
  - las dos filas en «Revisión» (2).
- **Mutación: 26 de 26 muertas, y las 3 equivalentes de las tablas del watch, sacadas.**
  - «la revisión suelta (por nota)» sobrevivía por dos cosas de la prueba. El reloj fijo
    empataba las dos pasadas, y una segunda revisión abierta antes de mirar tapaba el caso.
  - «la introducción sin su texto»: la prueba de pantalla no miraba el texto.

### Paso 4d: cómo se arma (diseño)

- **Qué se revisa lo dice el núcleo.** Cada pieza de `correction_suggestions.dart` ya sabe si algo
  sigue siendo de la IA y como lo vería el modelo. Ahora también sabe listar lo de un elemento
  (`reviewableAiThings`): cada cosa con su antes, su nombre, la pasada que la hizo y las opciones
  que valen al corregirla (los valores de esa categoría, los temas que hay, los cinco tipos de
  vínculo). Así lo que se le muestra al modelo y lo que después se acepta salen de la misma regla.
- **El pedido.** Un pedido por elemento, o los que hagan falta para que entre en la ventana del
  modelo, con el título y un fragmento del elemento y todo lo suyo numerado. El formato es el de
  las tarjetas:
  - un encabezado `DATO <n>: bien | corregir | sacar`;
  - el valor nuevo (`VALOR:`; en un vínculo, `TIPO:` y `FRASE:`);
  - `POR QUÉ:`.
- **El lector** es estricto, como el de las tarjetas, y descarta lo que no cumple:
  - un valor que no está entre las opciones;
  - sacar una introducción;
  - una «corrección» que deja todo igual;
  - un veredicto sin su porqué.
- **El paso** (`ReviewThingsStep`) no vuelve a proponer lo que ya está para decidir ni lo que la
  persona descartó. Se suma al de las tarjetas en un revisor compuesto: la cola no cambia.
- **La oferta y el costo cuentan todo**, por modelo, en SQL: las tarjetas y las demás cosas. La
  introducción de una nota mapa se cuenta por nota (si no tiene introducción, el paso no la
  manda). Los textos dicen «cosas»: «312 cosas de Gemma 4 E4B en 85 elementos».

### Paso 4d, primera parte (hecha): el revisor de lo demás

- **Qué se revisa:** `reviewableAiThings` en `correction_suggestions.dart`. Cada pieza (menos la
  de las tarjetas) sabe:
  - qué hicieron las pasadas sobre el elemento (`madeOn`); lo que hizo una pasada sobre otro
    elemento no es de este, aunque lo vincule;
  - cómo mostrárselo a un revisor (`describe`): su antes, su nombre, la pasada y su modelo, y
    las opciones.

  Las opciones son los cinco tipos de vínculo, hasta 25 valores de la categoría (los más usados)
  o hasta 30 temas. Además dice si se puede corregir (una etiqueta que no es de texto, no) y si
  se puede sacar (una introducción, no). Lo devuelve `AiRunRepository.reviewableThings`, y queda
  en `ReviewableAiThing` (core).
- **El pedido** (`LanguageModelTasks.reviewThings`): el elemento con un fragmento, y cada cosa
  numerada con lo que tiene puesto, el contexto (el comienzo del otro elemento de un vínculo; lo
  que reúne una nota mapa), las opciones y sus reglas («no se saca», «no se corrige»). Los tipos
  de vínculo se nombran con las mismas palabras que el pedido de vínculos (`relacionado`,
  `contradice`…), ahora compartidas (`relationKindForToken`, `relationKindToken`).
- **El lector** (`parseThingsReview`), estricto:
  - el valor tiene que ser una de las opciones, y queda escrito como ella;
  - en un vínculo, lo que no dice queda como estaba;
  - la introducción se limpia como la escribe la IA;
  - no saca lo que no se saca, no corrige lo que no se corrige, y una «corrección» que deja todo
    igual no cuenta.
- **El paso** (`ReviewThingsStep`):
  - no repite lo que está para decidir ni lo que la persona descartó, y deja afuera lo del
    modelo que revisa;
  - manda de a tantas cosas por pedido como el modelo escribe (cuatro en Gemma, ocho con una
    ventana grande), con el fragmento del elemento en un cuarto de lo que lee;
  - lo que propone se acepta tal cual (la prueba acepta cada cosa de punta a punta).
- **El revisor compuesto** (`AiItemReviewers`): primero las tarjetas, después lo demás. Para la
  cola son uno solo.
- **Pruebas:** la lista (4), el lector (8), el pedido (2), el paso (5), el compuesto (2).
- **Mutación: 30 de 30 muertas.**
- **Falta, en la segunda parte:** que la oferta, el costo y los candidatos cuenten todo. Hoy la
  cola llega solo a los elementos con tarjetas de la IA, aunque en ellos ya revisa lo demás.
