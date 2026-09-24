# F16 — Cuadernos, consulta enfocada y vistas (NotebookLM y Notion)

> **Estado: aprobado** (2026-09-24), en el chat, tal como está escrito. Planificado con el
> masterprompt completo del encargo F12–F17 que el usuario pegó en el chat ese mismo día. Lo que
> salga distinto de lo planeado se dice en su decisión de `../arquitectura.md`.

Quinta fase del encargo F12–F17. No cambia el texto de ninguna fuente ni un chunk; si algo de lo
nuevo generara texto, es SIEMPRE un `item` de nota nuevo, nunca una edición de lo existente —ver la
precisión de la sección 1 del masterprompt, repetida en las decisiones de abajo—. Al cierre,
`verifyChunkInvariant` en verde sobre la bóveda entera.

**Al final de F16 se puede:** acotar el chat a un subconjunto de fuentes y notas («un cuaderno»),
que sigue funcionando como buscador acotado sin modelo descargado; generar una guía de estudio, una
lista de preguntas, un esquema o una cronología a partir de un cuaderno o de un elemento, siempre
como una nota nueva, marcada y citada; guardar una combinación de filtro + vista + orden con nombre
y fijarla en la navegación; crear una nota desde una plantilla con su estructura y sus propiedades
ya puestas; y ver los elementos en un calendario por su fecha.

## Lo que ya existe (F16 no parte de cero, pero tampoco hereda casi nada)

Investigué el código antes de escribir esto (no adivino), y el resultado es que casi todo lo que
pide F16 es nuevo:

- **El chat** (`lib/features/chat/`) tiene exactamente dos modos, `ChatConversationMode.vault` y
  `.free` —confirmado, nada más—. `LibraryVaultRetriever` busca con el mismo FTS5 de la Biblioteca
  (`LibraryRepository.list`), partiendo la pregunta en palabras sueltas; no usa embeddings ni
  similitud semántica (esa pieza, `embedding_similarity.dart`, es del motor de sugerencia de
  relaciones de F5, ajena al chat). **No existe ningún parámetro para acotar el chat a un
  subconjunto**: ni `spaceId` ni una lista de ids. Sí existe el mecanismo para construirlo:
  `LibraryQuery` ya tiene `ids` y `spaceId`, y dos pantallas ya lo usan así (`PickItemDialog.
  scopeIds`, el diálogo de sugerir relaciones con IA) — extenderlo al chat es del mismo tipo de
  cambio, no uno nuevo.
- **`ChatSource`** (lo que el chat cita) es `{itemId, itemTitle, excerpt}`: el `excerpt` son los
  primeros 400 caracteres del texto buscable del elemento, **no un chunk real** (sin `chunkId` ni
  offsets). El límite de contexto real del modelo es de 2048 tokens en total (`maxTokens: 2048`),
  recortado en caracteres, no en tokens.
- **«Cuaderno» no existe como concepto interno.** Lo único que se llama así es el cuaderno de
  NotebookLM, el producto externo de Google: el exportador de ese nombre (`export_notebooklm_
  package_usecase.dart`) arma una carpeta de Markdown para que el usuario la arrastre a UN cuaderno
  que crea él mismo en la web de Google. No aporta estructura de datos reusable.
- **Ninguna nota lleva marca de generada por IA.** Grepeé `generatedBy|isGenerated|generationModel`
  en todo `lib/`: cero resultados. `KnowledgeNotes` (la tabla de una nota) dice de sí misma, en su
  propio comentario: «sin procedencia propia». El precedente más cercano a «crear una nota nueva con
  cita al origen» es `HighlightableText._extractSelection`: captura la selección como un `item`
  nuevo (`captureItemUseCaseProvider`) y la vincula con `RelationKind.extractedFrom` +
  `sourceCharStart`/`sourceCharEnd` hacia la fuente. Es el molde a seguir para 16.2, adaptado a
  dispararse desde una respuesta del chat en vez de una selección manual de texto.
- **La citación a un chunk ya existe entera y es reusable tal cual como PRESENTACIÓN**:
  `CitedSourcesSection`, `citeFragment`, `FragmentLocatorResolver` (F15) leen relaciones
  `extractedFrom`/`cites` con offsets y arman la cita con página o minuto. Lo que falta no es esa
  capa: es que el chat produzca offsets reales para que esa capa tenga algo válido que resolver.
- **«Vistas» no existe como sistema.** `LibraryViewMode` (lista/tabla/tablero) y `MapView`
  (tablero/esquema/grafo) son enums fijos de PRESENTACIÓN, estado local de cada pantalla —el propio
  comentario de `LibraryViewMode` dice que es «una preferencia de la sesión, no un dato que otra
  pantalla necesite conocer»—, no vistas configurables ni guardadas. No hay ninguna entidad
  `SavedView` ni nada parecido.
- **Plantillas de nota no existen.** Una nota se arma con los mismos bloques de siempre
  (`content_block.dart`); no hay estructura predefinida ni propiedades que se precarguen.

## Dónde el encargo choca con el código real (a confirmar al aprobar)

1. **El chat no ancla a un chunk real hoy.** El `excerpt` de 400 caracteres no es lo que la
   restricción inalienable exige para un derivado («cita las fuentes... con su chunk exacto»). Hace
   falta que el chat resuelva, para cada fuente citada, el chunk real que cubre ese fragmento —no
   rediseñar el buscador entero, solo agregar la resolución del offset real antes de armar el
   `ChatSource` (ver D2).
2. **«Cuaderno» no tiene dónde apoyarse.** `Space` ya es «una carpeta que agrupa, un ítem
   pertenece a lo sumo a una» —pero el encargo pide explícitamente que «un elemento puede estar en
   varios» cuadernos a la vez. `Space` no sirve tal cual: hace falta una entidad nueva (D1).
3. **Ningún dato de la bóveda dice «esto lo escribió un modelo».** Hace falta esquema nuevo (D3),
   igual que F15 subió a v22: acá sube a v23.
4. **Vistas guardadas y plantillas son sistemas nuevos de punta a punta**, sin nada que heredar más
   allá de `LibraryQuery` (el dato que una vista guarda) y los bloques que una nota ya admite (lo que
   una plantilla predefine). Es trabajo nuevo, no una extensión.
5. **El tope de contexto del chat (2048 tokens) no cambia con un cuaderno.** Un cuaderno acota QUÉ se
   busca —menos ruido, resultados más pertinentes dentro del subconjunto—, no agranda cuánto entra en
   una respuesta. No prometer lo segundo.

## Decisiones que necesito que confirmes (mi recomendación va primero)

- **D1 Un cuaderno es una entidad propia**, `Notebook` (id, nombre, creado, actualizado) + una tabla
  de unión `notebook_items` (notebookId, itemId) para la pertenencia manual —liviana, referencias y
  no copias, el mismo criterio que `item_property_values`—, MÁS un modo «por consulta»: un cuaderno
  puede guardar una `LibraryQuery` con nombre en vez de una lista manual, resuelta en el momento
  (mismo mecanismo que una vista guardada de 16.3 — de hecho un cuaderno «por consulta» y una vista
  guardada son el mismo dato, `LibraryQuery` con nombre, aplicado a dos pantallas distintas: una
  filtra la Biblioteca, la otra acota el chat). *Alternativa que descarto:* apoyarse en `Space`, que
  no admite que un elemento esté en varios a la vez.
- **D2 El chat resuelve el chunk real de cada fuente que cita**, sin rediseñar el buscador: se queda
  el `excerpt` de 400 caracteres para mostrar, y se le suma el offset real dentro del texto
  (`FragmentLocatorResolver.locate`) para que `CitedSourcesSection`/`citeFragment` tengan algo válido
  que resolver cuando un derivado cite esa fuente. *Alternativa que descarto:* que el retriever
  devuelva chunks en vez de un recorte de texto —cambia más de lo que hace falta para este encargo—.
- **D3 La marca de generado por IA** vive en `KnowledgeNotes` (esquema v23): `generated_by_model`
  (texto, nulo si no es generada), `generated_at` (fecha), y `derived_edited` (booleano, en falso al
  nacer, en verdadero la primera vez que el usuario edita el contenido después de generarse —así
  «pasa a ser suya» sin necesitar un historial de versiones nuevo, ya que `field_versions` ya anota
  cuándo se tocó un campo—).
- **D4 Vistas guardadas y plantillas son dos tablas nuevas**, en el mismo v23: `saved_views` (id,
  nombre, `query_json`, modo de vista, orden, fijada, creada) y `note_templates` (id, nombre,
  `blocks_json`, `properties_json`, creada). Sin motor de bloques nuevo: una plantilla predefine
  bloques y propiedades con los tipos que una nota ya admite hoy.
- **D5 Los cuatro derivados —guía de estudio, preguntas abiertas, esquema, cronología— son un
  generador único**, `DerivedNoteGenerator`, parametrizado por un enum de cuatro valores con su
  propia plantilla de instrucción cada uno —mismo patrón que `FlashcardGenerator`, que ya tiene la
  regla «mejor ninguno que uno equivocado» para lo que no se puede anclar—.
- **D6 Cada afirmación de un derivado se ancla con el mismo mecanismo que ya existe**: una relación
  `RelationKind.extractedFrom` con `sourceCharStart`/`sourceCharEnd` hacia la fuente citada —
  `CitedSourcesSection` ya sabe leer esto, cero cambios ahí—. Lo que no se pueda anclar a un offset
  real, no se escribe en el derivado.
- **D7 La vista de calendario** es elegible entre Fecha del hecho y fecha de captura, con Fecha del
  hecho por defecto —es lo que el encargo nombra primero, y es la que responde «qué pasó cuándo» en
  vez de «qué guardé cuándo»—.
- **D8 Orden interno de F16: vistas y plantillas primero (16.3), cuadernos después (16.1), derivados
  al final (16.2)** — al revés del orden en que el encargo los nombra. Motivo: 16.3 es la pieza más
  autocontenida y de menor riesgo, y 16.1 reusa directamente su mecanismo de «consulta guardada»; el
  16.2 es lo más nuevo (cambios al chat, esquema de notas, generación con IA que hay que anclar bien)
  y conviene dejarlo para cuando 16.1 y 16.3 ya estén probados. El encargo solo exige que F15 y F16
  sean independientes entre sí, no fija un orden interno.

## Secuencia de commits (cada uno compila y analiza solo)

Bloque A — vistas y plantillas (16.3)

1. `feat(views)`: esquema v23 —`saved_views`, `note_templates`, aditivo—, migración con respaldo
   previo y compuerta de conteo.
2. `feat(views)`: dominio y repositorio de vistas guardadas; guardar la vista actual de la
   Biblioteca con nombre (consulta + modo + orden), fijarla en la navegación, aplicarla.
3. `feat(notes)`: plantillas de nota —dominio, repositorio, elegir plantilla al crear una nota, la
   estructura y las propiedades quedan precargadas—.
4. `feat(views)`: vista de calendario sobre Fecha del hecho o fecha de captura (D7), reusando
   `LibraryQuery`.

Bloque B — cuadernos (16.1)

5. `feat(notebooks)`: dominio y repositorio de `Notebook` —manual y «por consulta» (D1)—, CRUD.
6. `feat(notebooks)`: pantalla de cuadernos —crear, nombrar, elegir el modo, panel de fuentes con
   excluir sin sacar el elemento de la bóveda—.
7. `feat(chat)`: el chat se acota a un cuaderno —`VaultRetriever`/`LibraryVaultRetriever` ganan un
   alcance opcional (D1); selector de cuaderno en la pantalla del chat; la conversación recuerda su
   cuaderno (columna nueva en `Conversations`, mismo v23)—.
8. `test(notebooks)`: el cuaderno funciona como buscador acotado sin modelo descargado —confirma el
   camino que el paso 7 ya deja construido, con test dedicado—.

Bloque C — derivados marcados (16.2)

9. `feat(chat)`: el chat resuelve el chunk real de cada fuente citada (D2), sin cambiar lo que ya se
   muestra.
10. `feat(notes)`: esquema —`generated_by_model`/`generated_at`/`derived_edited` en `KnowledgeNotes`
    (D3), mismo v23 si no se hizo antes—.
11. `feat(notes)`: `DerivedNoteGenerator` —los cuatro tipos (D5), con el anclaje de D6 y el descarte
    de lo que no se pueda anclar—.
12. `feat(notes)`: generar un derivado desde un cuaderno o un elemento, con su marca visible; editar
    un derivado lo pasa a `derived_edited`.
13. `test(bench)`: cifras del chat acotado a un cuaderno grande, en el emulador.
14. `docs(arquitectura)`: Decisión 49, este plan pasa a «construido».

Si una cifra del paso 13 obliga a un arreglo, va en un commit `perf(...)` antes del 14, como en F13
y F14; si pide rediseño, se reporta antes de hacerlo.

## Medición (Android = el emulador, rotulado; PC enchufada; real, cuando haya teléfono)

El encargo no fija objetivos numéricos para F16. Propongo estos, para que los apruebes o los
cambies:

| Escenario | Objetivo propuesto |
|---|---|
| Abrir un cuaderno con su panel de fuentes | < 200 ms |
| Buscar dentro de un cuaderno de 500 elementos | < 300 ms (mismo FTS5 de la Biblioteca) |
| Aplicar una vista guardada | < 200 ms |
| Anclar las afirmaciones de un derivado ya generado (post-proceso, sin contar el tiempo del modelo) | < 500 ms |

## Criterios de cierre (16.4, del encargo)

- [ ] El chat se puede acotar a un cuaderno y cita solo dentro de él.
- [ ] Los derivados cumplen las cuatro condiciones de la sección 1 del encargo, verificado por test:
      item nuevo, marcado con modelo y fecha, cada afirmación citada a su chunk, nunca sustituye al
      original.
- [ ] Ninguna pantalla muestra un derivado en lugar del texto original.
- [ ] Vistas guardadas y plantillas funcionando.
- [ ] Invariante de chunking verde sobre la bóveda entera.

## Lo que no hará (dicho de antemano)

- **No sincroniza con el NotebookLM real de Google**: comparten nombre por la función que cumplen
  (consulta acotada a un subconjunto), no el producto ni el formato.
- **Un derivado no ancla una afirmación a más de un chunk.** Una afirmación, un origen; lo que
  necesite dos fuentes para sostenerse no se afirma tal cual.
- **La generación de un derivado no funciona sin modelo descargado** —a diferencia de un cuaderno,
  que sí sirve como buscador acotado sin él—.
- **No hay comentarios ni nada multiusuario en un cuaderno**: la bóveda sigue siendo de un
  dispositivo, como el resto de la app.
- **Las plantillas de nota no son un motor de bloques nuevo**: predefinen una estructura con los
  bloques que ya existen, no agregan tipos de bloque.
- **No convierte de golpe las notas que ya existen** en «generadas»: la marca solo la llevan las que
  nazcan desde un derivado de acá en adelante.

## Opcional, pero me ayudaría mucho

Un ejemplo real de cómo usarías un cuaderno hoy —qué fuentes juntarías, qué le preguntarías, qué
derivado esperarías sacar— con tu propia bóveda o con datos parecidos. Sin eso, pruebo con la bóveda
sintética de siempre, que no tiene una pregunta real detrás.
