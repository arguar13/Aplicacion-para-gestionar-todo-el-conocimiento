# F19 — Modo lote transaccional (deuda de arquitectura)

> **Estado: aprobado** (2026-09-25), en el chat, tal como está escrito, con las decisiones A/B/C/D
> como se recomendaron. Planificado con el masterprompt F18–F20. Segunda fase del encargo, antes
> que F20 porque el modo lote beneficia también a la generación de un quiz largo.

F15 encontró que importar 5.000 entradas de BibTeX tarda ~20 s en escritorio, y el diagnóstico ya
dado entonces es el que este plan confirma con el código real: la causa no son las transacciones,
sino que cada entrada paga el costo completo de un guardado normal —índice de texto, versionado por
campo, sugerencias— fila por fila. Esto pega en cualquier operación masiva, no solo en BibTeX.

## Dónde el encargo choca con el código real (confirmar al aprobar)

1. **`LibraryRepository.runInTransaction` ya existe (F15) y confirma el diagnóstico del encargo,
   pero no hace lo que un lector rápido del punto podría asumir.** Es un envoltorio de una línea
   sobre la transacción SQL de Drift (`_db.transaction(body)`), nada más: no difiere ni agrupa
   ninguno de los costos por fila. `ImportReferencesFileUseCase` ya lo usa hoy, y cada entrada
   adentro sigue pagando el costo entero de un guardado normal —índice de texto, `field_version`,
   sincronía de etiquetas y chunking—, solo que dentro de una única transacción en vez de una por
   entrada.
2. **Suspender y rearmar el índice de texto (`item_search`/`chunk_search`) ya es un patrón usado
   en el proyecto, pero solo dentro de pasos de migración.** `app_database.dart` ya sabe borrar los
   triggers reales, reconstruir la tabla FTS5 y repoblarla de una vez (`populateItemSearch`, y el
   comando `rebuild` propio de FTS5 para chunks) — pero siempre como parte de un `onUpgrade`, nunca
   en tiempo de ejecución normal de la app. Técnicamente no hace falta una migración para hacerlo en
   caliente (son sentencias DDL comunes, no versionado de esquema de Drift) — de hecho la fusión de
   bóvedas ya crea y borra triggers TEMPORALES en cada corrida (`merge_gates.dart`) — pero sería la
   primera vez que se hace con los triggers REALES fuera de una migración.
3. **Hallazgo importante: `mergeBackup` ya tiene su propio camino de escritura en lote, que NO pasa
   por `KnowledgeEntryWriter`.** `EntryMergeApplier` escribe por conjuntos —una sentencia SQL por
   tabla y grupo de elementos, no una llamada Dart por fila— y copia `field_version` tal cual en
   bloque, no por el mismo camino que un guardado normal. Su costo real (los 68 s medidos al traer
   10.000 elementos a una bóveda vacía) no está repartido entre transacciones ni entre escrituras:
   está casi todo en `DerivedRebuild.apply()`, que rehace los chunks de cada elemento tocado con EL
   MISMO camino de fragmentación que un guardado común —el que sí dispara los triggers del índice de
   texto fila por fila—. Esto significa que un `runBulk` atado únicamente a `KnowledgeEntryWriter`
   **no ayudaría a `mergeBackup` de forma automática**: la fusión necesita suspender el índice de
   texto por su cuenta, alrededor de `DerivedRebuild`, con el mismo mecanismo pero sin pasar por el
   escritor único (que la fusión no usa).
4. **Las cuatro generadoras de sugerencias y los embeddings no son parte del costo síncrono de
   guardar.** `ProcessItemUseCase` las dispara con `unawaited(...)` después de cada guardado — ya
   son asíncronas y no bloquean nada hoy. «Suspender y rearmar» acá no puede significar diferir un
   costo DENTRO de la transacción (como con el índice de texto o el versionado): significa evitar
   que un lote de N filas dispare N×4 llamadas sin esperar, cada una con sus propias lecturas de
   base y, en el caso de relaciones, cálculo de embeddings, TODAS A LA VEZ mientras el lote todavía
   escribe — y en cambio dispararlas una vez por elemento tocado, en orden, recién cuando el lote
   cierra. Ninguna de las cuatro generadoras expone hoy una entrada por lotes (una consulta para N
   elementos en vez de N consultas): leo «encolados y disparados una sola vez al terminar» como
   «diferidos y disparados uno por elemento al final», no como «recalculados con una sola consulta
   más barata para todo el lote» —lo segundo es un rediseño de las cuatro generadoras, mucho más
   trabajo que lo que este punto parece pedir—.

## Decisiones que necesito que confirmes al aprobar (mi recomendación va primero)

- **A. La suspensión del índice de texto se construye como una utilidad de bajo nivel reusable, NO
  atada a `KnowledgeEntryWriter`**, para que tanto el modo lote del escritor único como
  `VaultMerger`/`DerivedRebuild` puedan usarla cada uno alrededor de su propio bucle de escritura.
  *Alternativa que descarto:* atarla solo a `KnowledgeEntryWriter.runBulk` — más simple, pero no
  ayuda a `mergeBackup`, que el propio encargo nombra como uno de los casos a migrar.
- **B. `KnowledgeEntryWriter` gana un modo interno diferido**: mientras está activo, no escribe cada
  `field_version` de inmediato — guarda en memoria el último valor por (elemento, campo) y lo vuelca
  en una sola escritura por campo al cerrar el lote, tal como pide el punto. *Alternativa:* no tocar
  `_touch`, dejar que cada guardado siga versionando fila por fila y limitar el modo lote al índice
  de texto y las sugerencias — bastante menos beneficio (el versionado por campo también paga un
  `SELECT` más un `INSERT` por campo hoy), pero mucho menos riesgo sobre el escritor único.
- **C. Las sugerencias y los embeddings se difieren y se disparan una vez por elemento tocado, en
  orden, al cerrar el lote — sin construir una entrada por lotes nueva en las cuatro generadoras.**
  *Alternativa:* construir de verdad una entrada por lotes en cada una — mucho más trabajo, y
  probablemente fuera de lo que este punto del encargo pide en realidad (ver hallazgo 4).
- **D. Para `mergeBackup`**: `VaultMerger` envuelve su llamada a `DerivedRebuild.apply()` con la
  misma utilidad de la decisión A, en vez de pasar por `KnowledgeEntryWriter.runBulk` —que no
  aplica, porque la fusión no usa el escritor único—. Las sugerencias y los embeddings siguen sin
  dispararse para elementos fusionados, como ya es hoy («los rehace el proceso de siempre», F16).

## Secuencia de commits (cada uno compila y pasa el analizador por sí solo; probablemente se parta
más de lo que esta lista muestra, mismo criterio que toda fase anterior cuando el trabajo real
resulta más grande que un commit)

1. `feat(database)`: utilidad de bajo nivel para suspender y rearmar `item_search`/`chunk_search`
   en tiempo de ejecución —baja los triggers reales, repuebla de una vez al cerrar—, con un test que
   fuerza un fallo a mitad de un lote y confirma que el rearmado corre igual antes de propagar el
   error, para que el índice nunca quede a medias.
2. `feat(database)`: `KnowledgeEntryWriter.runBulk` —modo diferido de `field_version` (decisión B) +
   usa la utilidad del commit 1 alrededor de su propio bucle—. Las guardas de integridad de texto de
   fuente y las claves foráneas NUNCA se suspenden, con test dedicado.
3. `feat(transform)`: diferir y disparar una sola vez, al cerrar el lote, las cuatro generadoras de
   sugerencias y los embeddings (decisión C).
4. `feat(reference)`: migrar `ImportReferencesFileUseCase` a `runBulk`, medido antes y después en el
   emulador (objetivo: bien por debajo de los 90 s acordados como techo provisorio en F15, apuntando
   a menos de 30 s).
5. `feat(vault)`: `VaultMerger` usa la utilidad del commit 1 alrededor de `DerivedRebuild.apply()`
   (decisión D), medido antes y después de `mergeBackup` con 10.000 elementos a una bóveda vacía.
6. `feat(suggestions)`/`feat(duplicates)`: migrar a `runBulk` la aceptación de sugerencias en lote y
   la reconstrucción de chunks tras fusionar duplicados, si medirlas primero muestra que también les
   duele —a confirmar según lo que salga de medir, no doy por sentado que hace falta—.
7. `docs(arquitectura)`: Decisión 52, cierre de F19.

## Cómo se verifica

Mismo ritmo de siempre: `dart format` de lo propio → `flutter analyze` (línea base 31) → tests del
área → suite completa en la copia aislada → `git add` explícito → commit → `tool/verify_commit.ps1`
(PowerShell, nunca Bash) → push → actualizar la memoria del encargo. Antes de cerrar cada operación
migrada: conteos antes y después, `PRAGMA foreign_key_check` vacío y `verifyChunkInvariant` sobre lo
tocado.

## Criterios de cierre (19.3, del encargo)

- [ ] Existe un modo lote genérico, usable por cualquier operación masiva.
- [ ] Un lote fallido no deja índices ni datos a medias, verificado forzando un fallo.
- [ ] Importación de BibTeX medida antes y después, con mejora sustancial.
- [ ] `mergeBackup` medido antes y después.
- [ ] Las guardas de texto de fuente nunca se suspenden, verificado por test.
- [ ] Invariante de chunking verde.
