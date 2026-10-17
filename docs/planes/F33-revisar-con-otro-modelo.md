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
- **Lo que sigue: el paso 2**, la sección «Revisión» en «Lo que hizo la IA».
  - El antes y el después, resaltados palabra por palabra.
  - Aceptar y descartar de a uno, y en bloque con «Deshacer» (el lote se aplica al cerrarse el
    aviso, como en «Para revisar»).
  - Agrupado por elemento y con quién lo propone.
  - Se ocultan las correcciones de una tarjeta que ya cambió o que ya no es de la IA.
  - Su número se suma al de Ajustes › IA.
