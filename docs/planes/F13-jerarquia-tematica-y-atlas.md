# F13 — Jerarquía temática y Atlas

> **Estado: propuesto, pendiente de aprobación** (2026-09-21). Se aprueba contestando «aprobado» en el chat —con mis recomendaciones—, o diciendo qué decisiones cambiar.

Segunda fase del encargo F12–F17. Depende de F12 cerrada. Cambia el esquema (v20 → v21).
Restricción inalienable intacta: ningún paso toca el texto de una fuente ni un chunk; al
cierre, `verifyChunkInvariant` en verde sobre la bóveda entera.

## Dónde el encargo choca con el código real (a confirmar al aprobar)

1. **La unicidad del vocabulario es por categoría, no por padre.** `property_values` tiene
   `UNIQUE (definition_id, value COLLATE NOCASE)`, y los alias, `resolvePropertyValue`, la
   fusión de valores y la fusión de bóvedas buscan por esa etiqueta. Con jerarquía, «Economía»
   bajo «Roma» y «Economía» bajo «Grecia» no pueden convivir: hay que llamarlas «Economía
   romana» y «Economía griega». Cambiar la unicidad a (categoría, padre, valor) toca cinco
   caminos de código y la fusión de copias. **Propongo mantenerla** y decirlo.
2. **Tres consumidores del vocabulario que la jerarquía toca**, no solo la pantalla:
   `LibraryQuerySql` (el filtro por `propertyValueIds`/`tagIds`, un único lugar: la
   transitividad va ahí y la heredan Biblioteca, Explorador, Línea de tiempo y Salud),
   las operaciones de F8 con deshacer (`mergeValues`, `deleteUnusedValues`, alias) y la
   **fusión de bóvedas** de F11 (`vocabulary_merge.dart` inserta `property_values` con una
   lista de columnas explícita y un `valueMap` entrante→local: un `parent_id` que llega de
   otra copia hay que reapuntarlo, y dos dispositivos pueden haber puesto A bajo B y B bajo A).
3. **Ocho destinos no caben en una barra de celular.** Hoy son siete (Biblioteca, Bandeja,
   Explorador, Grafo, Chat, Repaso, Ajustes). Ver decisión D1.
4. **«Nota viva», «atómica», «mapa» y «madurez» sí existen** (`note.note_kind`,
   `note.maturity`), pero no hay un vínculo tema↔nota aparte de las propiedades: «notas mapa de
   una rama» = notas mapa que tienen un valor de esa rama o de sus descendientes. Y el eje
   temporal sale de «Fecha del hecho» (`date_from_*`/`date_to_*`) de los elementos de la rama.
5. **El censo de lecturas** (`read_census_test`) obliga a que todo archivo que lea `item` use
   los ayudantes de `active_entries` (lo de la papelera no cuenta). Los agregados del Atlas los
   usan; no hace falta excepción.
6. **La jerarquía solo tiene sentido en categorías de texto** (y «Tema»): «Fecha del hecho» y
   las de número ya tienen su propio orden. Se restringe a nivel de escritura.

## Decisiones que necesito que confirmes (mi recomendación va primero)

- **D1 Navegación.** Atlas = destino de primer nivel nuevo. En el celular la barra muestra
  cinco (Biblioteca, Bandeja, Atlas, Grafo, Repaso) y un «Más» que abre una hoja con
  Explorador, Chat y Ajustes; en escritorio el riel muestra los ocho. *Alternativa:* Atlas
  como pestaña dentro de Explorador (no es «de primer nivel»).
- **D2 Qué categoría muestra el Atlas.** Una a la vez, con selector; por defecto «Tema» (la de
  sistema, la de las etiquetas).
- **D3 Consulta transitiva.** Implemento y mido las DOS (CTE recursiva y cierre materializado)
  con la bóveda de 10.000 elementos y 2.000 valores, y me quedo con la que cumpla el umbral de
  la búsqueda (300 ms en dispositivo). Mi apuesta previa: la CTE (la recursión es sobre los
  ~2.000 valores, no sobre los 10.000 elementos; un cierre materializado es una tabla más que
  mantener en cada asignación, fusión y migración).
- **D4 «Sin ciclos a nivel de escritura».** Triggers de SQLite (`BEFORE INSERT` y `BEFORE UPDATE
  OF parent_id`) que abortan un ciclo, un padre de otra categoría, una categoría que no es de
  texto y una profundidad mayor que 5, **además** de la validación amable del repositorio:
  solo así queda cubierta también la fusión de bóvedas, que escribe con SQL crudo.
- **D5 Fusión de bóvedas.** Un valor que ya existe conserva SU padre local; uno sin padre local
  adopta el del otro lado si no forma un ciclo; nada se versiona por campo (el vocabulario se
  une por conjuntos, como en F11) y lo que se ignora se cuenta en el resultado.
- **D6 Estado de cobertura de una rama** = el nivel más avanzado presente en la rama y sus
  descendientes (sin material < solo fuentes < atómicas sin viva < viva seed/developing < viva
  mature), con los conteos a la vista para que un estado alto no esconda un hueco.
- **D7 Umbrales de «vacíos»**, en una clase de constantes como `HealthThresholds`: tema con ≥ 5
  fuentes y ninguna nota viva; rama con un solo elemento; rama sin tocar hace 6 meses.
- **D8 Profundidad máxima 5.**

## Secuencia de commits (cada uno compila y analiza solo; `tool/verify_commit.ps1` tras cada uno)

1. `feat(db)`: esquema v21 — `parent_id`, `depth`, índice, los triggers de D4; migración con
   respaldo previo, conteos como compuerta y todo en la raíz (`depth = 0`); instantánea
   `drift_schema_v21.json`. Tests: v20→v21 sin perder nada; ciclo directo e indirecto, padre de
   otra categoría, categoría de fecha, profundidad 6 y reparentar dentro de una transacción.
2. `feat(vocabulary)`: repositorio de jerarquía — `setParent`, `moveBranch` (reapunta y recalcula
   `depth` del subárbol en una transacción), `watchTree`, `descendantsOf`; integrado con las
   operaciones de F8: fusionar pasa los hijos al valor que queda, «borrar sin uso» no borra un
   padre con hijos, todo con deshacer.
3. `feat(library)`: consulta transitiva en `LibraryQuerySql`, según D3. Tests: filtrar por Roma
   trae lo de Roma republicana; asignar el hijo NO asigna el padre; plan sin recorridos
   completos (`query_plans_test`); la papelera sigue afuera.
4. `feat(vault)`: la fusión y la copia llevan `parent_id`: reapuntado por `valueMap`, sin
   ciclos, `depth` recalculado al terminar, compuertas de conteo.
5. `feat(vocabulary)`: vista de árbol en Vocabulario, arrastrar para reparentar (con
   confirmación y deshacer) y teclado.
6. `feat(vocabulary)`: sugerencia de jerarquía por palabras enteras («Roma republicana» bajo
   «Roma»), siempre propuesta a confirmar. Es la misma heurística que hoy ofrece FUSIONAR
   «Roma» con «Roma antigua»: la tarjeta gana una segunda acción, «Poner bajo…».
7. `feat(atlas)`: el repositorio de agregados — conteos en cascada de fuentes y notas, cobertura
   por rama, rango de fechas, notas mapa, vacíos —, caché en memoria invalidada por escritura.
8. `feat(atlas)`: la pantalla — árbol con conteos y estado, eje temporal que abre la línea de
   tiempo ya filtrada, notas mapa destacadas, vacíos tocables hacia su acción, búsqueda dentro,
   teclado, actualización reactiva —, la ruta y la navegación (D1).
9. `feat(atlas)`: exportar el índice como Markdown, con la jerarquía y los conteos.
10. `test(bench)`: la bóveda sintética con jerarquía (generador v5, 2.000 valores, hasta 5
    niveles) y las mediciones —consulta transitiva, agregados, abrir el Atlas, migrar 909 MB de
    v20 a v21— en el emulador y en escritorio; cifras versionadas.
11. `docs(arquitectura)`: Decisión 46.

## Medición (Android = el emulador, rotulado; real, cuando haya teléfono)

Abrir el Atlas con 10.000 elementos y 2.000 valores en menos de 500 ms (los agregados corren en
SQL dentro del isolate de la base, el árbol se arma en Dart); filtrar por un tema raíz con miles de
descendientes; migrar la bóveda de 909 MB; memoria. Con la PC enchufada.

## Criterios de cierre (13.3)

Jerarquía sin ciclos con test · filtrar por el padre trae al hijo · el Atlas muestra árbol,
conteos, cobertura y vacíos y se genera solo · abre en < 500 ms con 10.000 elementos, medido en el
dispositivo disponible · invariante de chunking verde sobre la bóveda entera.

## Lo que no hará (dicho de antemano)

No versiona el padre por campo ni resuelve conflictos de jerarquía entre copias (gana el local).
No permite el mismo nombre bajo dos padres de una categoría (punto 1). Solo el Atlas de una
categoría a la vez. Sin cifras de un teléfono real mientras no haya uno.
