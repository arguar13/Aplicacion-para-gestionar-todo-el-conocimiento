# F20 — Quizzes generados y anclados

> **Estado: aprobado** (2026-09-25), en el chat, tal como está escrito, con las decisiones A/B/C/D
> como se recomendaron. Planificado con el masterprompt F18–F20. Tercera y última fase, después de
> F19 porque el modo lote también beneficia a la generación de un quiz largo.

Quinto tipo de derivado sobre `DerivedNoteGenerator` (F16), con dos decisiones ya tomadas que este
plan no vuelve a abrir: el quiz se integra a la programación SM-2 (no es un derivado de una sola
vez), y las opciones incorrectas salen de material real de la bóveda, nunca inventadas por el
modelo, cada una anclada a su propio chunk.

## Dónde el encargo choca con el código real (confirmar al aprobar)

1. **`RelationKind.extractedFrom` no sirve para anclar las opciones de una pregunta tal cual está.**
   Tiene `UNIQUE(from_item_id, to_item_id, kind)`: si dos opciones de la MISMA pregunta —la correcta
   y un distractor, o dos distractores— citan el mismo elemento fuente, solo una relación cabría en
   la tabla. Con cuatro opciones sacadas de temas cercanos o de una contradicción, dos citando la
   misma fuente no es un caso raro, es esperable. Propongo que las opciones de un quiz **no se
   anclen por `relations` en absoluto**: cada opción guarda su propia procedencia (elemento fuente +
   rango de caracteres) en columnas propias, el mismo patrón que `Flashcard.sourceChunkId/
   sourceCharStart/sourceCharEnd` ya usa para una tarjeta común, sin depender de la restricción de
   unicidad de `relations`, pensada para relaciones ENTRE elementos, no para procedencias dentro de
   una misma pregunta. La afirmación central de la pregunta (si hace falta una, más allá de las
   opciones) sí puede seguir usando `extractedFrom` con el mismo criterio que los otros cuatro
   derivados de F16.
2. **`Flashcard`/`flashcards` no tiene hoy ningún campo para distinguir su forma.** Es estrictamente
   `front`/`back`, sin tipo. Hace falta esquema nuevo: una columna `kind` en `flashcards`
   (`freeRecall` por defecto para todo lo que ya existe, `multipleChoice`, `trueFalse`) y una tabla
   nueva, `flashcard_options`, con una fila por opción —texto, si es la correcta, y su propia
   procedencia— solo para las de opción múltiple. Verdadero/falso no necesita la tabla nueva: el
   `front` es la afirmación y el `back` la explicación de por qué es verdadera o falsa, con la
   procedencia que `Flashcard` ya tiene. El programador SM-2 y `review_log` ya son indiferentes a la
   forma de la tarjeta (confirmado: ninguno de los dos lee `front`/`back`), así que no necesitan
   ningún cambio.
3. **De las cuatro fuentes de distractores, «misma comunidad del Mapa» es la única sin datos
   disponibles fuera de una sesión del Mapa abierta.** Las comunidades se calculan en un isolate
   aparte, agrupan TEMAS (no elementos) y no quedan guardadas en ningún lado fuera del estado de la
   pantalla del Mapa mientras está abierta. Usarla de verdad —posiblemente sin haber abierto nunca
   el Mapa— exigiría forzar un cálculo completo de comunidades de toda la bóveda solo para conseguir
   un puñado de distractores: un costo fuera de proporción con lo que pide la función. Propongo
   implementar primero las otras tres —hermanos en la jerarquía del Atlas, el otro lado de una
   `contradicts`, cercanía por embedding (que ya tiene una función lista,
   `RelationCandidateSelector.selectCandidates`)— y dejar «misma comunidad» como una cuarta fuente
   que solo se usa si el Mapa YA fue calculado en esta sesión de la app, sin forzar el cálculo. Si
   las primeras tres ya alcanzan el mínimo de distractores por pregunta, ni hace falta.

## Decisiones que necesito que confirmes al aprobar (mi recomendación va primero)

- **A. Las opciones de un quiz guardan su propia procedencia en columnas propias, no por
  `relations`/`extractedFrom`** (hallazgo 1). *Alternativa:* sumar valores nuevos a `RelationKind`
  para las opciones — no resuelve la colisión por sí sola, porque la restricción es por
  `(elemento origen, elemento destino, tipo)`, no por posición dentro de la pregunta; necesitaría
  además una tabla intermedia con la posición de cada opción, una complejidad parecida a la que
  propongo pero sin reusar el patrón ya probado de `Flashcard`.
- **B. Esquema: `flashcards.kind` + tabla `flashcard_options`** (hallazgo 2), reusando el
  programador SM-2 y `review_log` tal cual. *Alternativa:* una tabla `quiz_cards` aparte, con sus
  propias columnas de programación duplicadas de `flashcards` — la descarto porque perdería sin
  necesidad la reutilización del programador y del historial que ya son agnósticos a la forma de la
  tarjeta.
- **C. Orden de las fuentes de distractores: hermanos del Atlas → contradicts → embedding, con
  «misma comunidad» opcional y sin forzar su cálculo** (hallazgo 3). *Alternativa:* las cuatro con
  el mismo peso, aceptando forzar un cálculo completo del Mapa cuando haga falta — más fiel a la
  letra del punto, pero cara y en tensión con «premiar destilar y consolidar, nunca…» un costo que
  el usuario no pidió.
- **D. La generación y el guardado quedan en UNA transacción —nota (si hace falta), marca de
  generado, tarjetas y opciones, todo o nada—**, en vez del bucle de guardados sueltos que usa hoy
  la revisión de flashcards comunes (que guarda cada tarjeta aceptada una por una). *Alternativa:*
  seguir el patrón actual de flashcards, tarjeta por tarjeta — más simple de escribir, pero una falla
  a mitad de guardar un quiz de varias preguntas lo dejaría a medias.

## Secuencia de commits (cada uno compila y pasa el analizador por sí solo; se va a partir más de lo
que esta lista muestra, mismo criterio que F15/F16/F17 con trabajo grande)

1. `feat(database)`: esquema —`flashcards.kind` (aditivo, `freeRecall` por defecto para lo que ya
   existe) + tabla `flashcard_options`—, migración con respaldo previo y compuerta de conteo.
2. `feat(flashcards)`: `FlashcardRepository` gana lo necesario para crear y leer una tarjeta de
   opción múltiple o verdadero/falso, con sus opciones y la procedencia de cada una (decisión A).
3. `feat(notes)`: `DerivedNoteType.quiz` + las piezas de dominio de una pregunta generada —texto,
   opción correcta, distractores, cada uno con su propia ancla— SIN guardar nada todavía, mismo
   criterio que el resto de `DerivedNoteGenerator`: solo sugiere.
4. `feat(notes)`: las fuentes de distractores en el orden de la decisión C, cada una devolviendo
   candidatos YA anclados a un chunk real; una pregunta sin suficientes distractores anclados
   degrada a verdadero/falso o se descarta —test dedicado: ninguna opción de ningún quiz existe sin
   un chunk real que la respalde, y un distractor nunca puede ser también correcto—.
5. `feat(notes)`: el caso de uso que genera y GUARDA —revisión obligatoria antes, transacción única
   (decisión D)—, sin el modelo descargado se ofrece deshabilitado con explicación.
6. `feat(flashcards)`: pantalla de revisión antes de guardar (opción múltiple/verdadero-falso, con
   la procedencia de cada opción visible, editar/confirmar/descartar por pregunta) + entrada desde
   una rama del Atlas, un cuaderno, un elemento, una vista guardada y la pantalla de Repaso.
7. `feat(flashcards)`: presentación de una sesión de quiz en Repaso —una pregunta por pantalla,
   revelación con la procedencia de cada opción (la correcta y las incorrectas), modo «sesión
   suelta» explícito que no toca la programación—.
8. `feat(habit)`: una sesión de quiz cuenta como actividad para la racha (mismo camino que repasar,
   F17 D6); al terminar, qué temas del Atlas concentraron los errores, con acceso directo a la nota
   viva correspondiente.
9. `feat(export)`: un segundo tipo de nota de Anki para las preguntas de opción múltiple —hoy
   `AnkiPackageBuilder` arma un único modelo fijo para todo el paquete—; lo que no se pueda mapear de
   forma fiel queda fuera de la exportación y documentado, nunca degradado a medias.
10. `docs(arquitectura)`: Decisión 53, cierre de F20 y del encargo F18–F20 entero.

## Cómo se verifica

Mismo ritmo de siempre. Tests nuevos: ninguna opción de ningún quiz existe sin chunk real
(propiedad, no caso suelto); una pregunta sin distractores suficientes degrada o se descarta, nunca
se completa con material inventado; las preguntas confirmadas entran en `review_log` con el mismo
esquema que un repaso común; ninguna pregunta llega al repaso sin pasar por la revisión.

## Criterios de cierre (20.6, del encargo)

- [ ] Ninguna opción de ningún quiz existe sin un chunk que la respalde, verificado por test.
- [ ] Una pregunta sin distractores suficientes degrada o se descarta, nunca se completa con
      material inventado.
- [ ] Las preguntas confirmadas entran en la programación SM-2 y en `review_log`.
- [ ] Ninguna pregunta llega al repaso sin revisión del usuario.
- [ ] Las cuatro condiciones de generación por IA se cumplen, como en F16.
- [ ] La sesión de quiz cuenta para la racha; capturar sigue sin contar.
- [ ] Invariante de chunking verde.
