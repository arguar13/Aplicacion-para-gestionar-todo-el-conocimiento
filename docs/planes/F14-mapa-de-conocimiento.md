# F14 — Mapa de conocimiento (esquema, grafo de conocimiento y tablero)

> **Estado: aprobado y construido** (2026-09-21). Aprobado en el chat, junto con el de F13. Lo construido, lo que se midió y lo que no hace, en la Decisión 47 de `../arquitectura.md`. Lo que salió distinto de lo planeado: el paso 8 salió en tres commits —agregar vínculo y sugerir con IA, el filtro por tema que el grafo viejo tenía y el retiro del grafo completo—; la medición del paso 9 pidió un commit de arreglos (`perf(map)`): un tope de uniones en el nivel de temas y un arrastre que subía de nivel; el benchmark mide con temas estructurados además de los de la bóveda sintética, que se asignan al azar y dan una sola comunidad; y **el criterio de interacción fluida NO se cumple en el emulador** salvo en el nivel de elementos: el armado sí, el raster no.

Tercera fase del encargo F12–F17. Depende de F13 (la jerarquía de temas es lo que da el
«esquema»). **No cambia el esquema de la base**: todo lo nuevo es derivado, se reconstruye
y no es fuente de verdad. Restricción inalienable intacta: no toca texto de fuentes ni chunks;
al cierre, `verifyChunkInvariant` en verde sobre la bóveda entera.

## Dónde el encargo choca con el código real (a confirmar al aprobar)

1. **El «grafo completo» de hoy no escala y es lo primero que se reemplaza.** `GraphScreen`
   hace `libraryItemsProvider(const LibraryQuery())` —TODOS los elementos— más
   `allRelationEdgesProvider` —TODAS las relaciones—, y `computeGraphLayout` es
   Fruchterman–Reingold cuadrático en Dart (300 iteraciones). Con 10.000 elementos no es una
   vista, es una espera. F14 lo sustituye por vistas sobre TEMAS con niveles de detalle; el
   grafo de elementos queda como el nivel de más zoom, con el mismo tope que el grafo local
   (200 nodos).
2. **«Incremental» no puede significar «el motor sabe qué cambió»**: drift avisa por TABLA, no
   por fila, así que ninguna escritura dice qué asignación o vínculo cambió. Lo que sí se puede
   cumplir de verdad, y es lo que propongo: recalcular **por lotes** (debounce), con **arranque
   en caliente** (las comunidades nuevas parten de las anteriores y convergen en una o dos
   pasadas), con **identidades de comunidad estables** (los colores no saltan) y con
   **invalidación acotada** (solo si cambiaron `item_property_values`, `relation`, `item` o
   `property_values`). El agregado de coocurrencia se vuelve a pedir a SQL en cada lote; si en
   el emulador con 10.000/2.000 no cabe en el presupuesto, pasa a una tabla derivada mantenida.
3. **Ya hay una pieza de estructura de dominio: las notas mapa** (`NoteKind.map`, sección de
   enlaces en el detalle). Se usan como punto de entrada del esquema; no se crea un concepto
   nuevo.
4. **El tablero pide lo que ya existe en pedazos**: las contradicciones abiertas son las
   `relation` `contradicts` sin `reviewed_at` (hoy solo un contador en Salud); la madurez sale de
   `note.maturity`; el tamaño en el tiempo, de `item.created_at`. Se reutilizan y se les agrega
   la lista.
5. **La navegación no crece**: la pestaña «Grafo» pasa a llamarse «Mapa» y contiene las tres
   vistas con un selector. El grafo local del detalle no cambia.

## Decisiones que necesito que confirmes (mi recomendación va primero)

- **D1 Comunidades: propagación de etiquetas ponderada** (determinista, con semilla fija y
  desempate por id), no Louvain. Es O(aristas) por pasada, el arranque en caliente es natural y
  la calidad alcanza para colorear temas; Louvain se deja para si se ve que agrupa mal.
- **D2 Pesos** (constantes en `TopicGraphWeights`, ajustables): coocurrencia en elementos × 1,
  relaciones tipadas entre elementos de dos temas × 2, y `contradicts` × 3 —con la arista
  marcada como tensión, que es información y no ruido—.
- **D3 Qué son los nodos**: los valores de UNA categoría a la vez (por defecto «Tema») con su
  jerarquía de F13; opcionalmente, todas las de texto juntas. Coocurrir Región × Época es
  interesante pero multiplica las aristas; queda detrás de un interruptor.
- **D4 Nada persistido en la primera versión** (derivado en memoria, reconstruible). Si la
  medición lo exige, una tabla derivada `topic_community`, nunca fuente de verdad.
- **D5 Niveles de detalle en vez de dibujar 2.000 nodos a la vez**: alejado = comunidades
  (~60 supernodos); medio = temas (≤ 300: los de más peso y los vecinos del foco); cerca =
  elementos (≤ 200 alrededor de un tema). El layout de fuerzas sigue siendo el actual y siempre
  sobre ≤ 300 nodos. *Alternativa:* Barnes–Hut en Dart para dibujar los 2.000 juntos —más
  código, más riesgo, y dibujar 2.000 nodos legibles en un celular no es el objetivo—.
- **D6 Esquema**: radial o de árbol según el tema (elige el usuario), partiendo de un tema o de
  una nota mapa; nodos = temas y notas vivas; aristas etiquetadas con el tipo de relación;
  expansión al tocar.
- **D7 Exportar**: PNG con `RenderRepaintBoundary`/`PictureRecorder` y SVG con un escritor
  propio del layout; sin dependencias nuevas.
- **D8 Los filtros**: `LibraryQuery` restringe los ELEMENTOS y el grafo de temas se calcula
  sobre ellos; no hay un segundo motor de filtros (y hereda la consulta transitiva de F13).

## Secuencia de commits (cada uno compila y analiza solo)

1. `feat(map)`: `TopicGraph` (nodos, aristas, pesos) y su constructor desde un agregado SQL —
   coocurrencia, relaciones, contradicciones— que respeta `LibraryQuery` y la papelera. Tests
   contra SQLite real y plan de consulta sin recorridos completos.
2. `feat(map)`: `CommunityDetector`: propagación de etiquetas ponderada, pura y determinista.
   Tests: comunidades conocidas, estabilidad de identidades, y que tras un cambio chico solo se
   reasignen pocos nodos (arranque en caliente).
3. `feat(map)`: `KnowledgeMapEngine`: corre en un isolate, por lotes con debounce, invalidación
   acotada, caché y **fallo aislado** (si el cálculo falla, las demás pantallas siguen); provider
   reactivo.
4. `feat(map)`: layouts puros — esquema radial y de árbol, y la agregación por nivel de detalle —
   con tests.
5. `feat(map)`: la pantalla «Mapa» con el selector de tres vistas, en tres commits: **5a Tablero**
   (temas más densos, más conectados entre sí, aislados, contradicciones abiertas, tamaño de la
   bóveda en el tiempo, madurez), **5b Esquema**, **5c Grafo de conocimiento** (comunidades
   coloreadas, del tema al elemento al acercar).
6. `feat(map)`: filtros compartidos, notas mapa como entrada, `EntityRole` para distinguir fuente y
   nota, transiciones cortas entre vistas, paleta y tipografía legibles a cualquier zoom.
7. `feat(map)`: exportar a PNG y SVG.
8. `refactor(graph)`: se retira la carga total del grafo completo; queda acotado.
9. `test(bench)`: la bóveda sintética con 2.000 temas y 10.000 elementos (usa la jerarquía de
   F13) y las mediciones en el emulador: construir el grafo, comunidades en frío y tras un cambio,
   abrir cada vista, y zoom y arrastre sostenidos con `watchPerformance`; cifras versionadas.
10. `docs(arquitectura)`: Decisión 47.

## Medición (Android = el emulador, rotulado; real, cuando haya teléfono)

Interacción fluida con 2.000 temas: percentil 90 de armado y de raster bajo los 16,6 ms y menos del
5 % de cuadros fuera del presupuesto (el presupuesto que F12 propuso para la línea de tiempo);
tiempo de comunidades en frío y tras una captura; memoria. Los cuadros por segundo de un emulador
dependen de la PC y de cómo dibuje: se miden con la PC enchufada y se dicen como lo que son.

## Criterios de cierre (14.3)

Las tres vistas comparten motor, datos y filtros · el agrupamiento es incremental y no bloquea la
UI · se actualiza solo · interacción fluida con 2.000 temas en el dispositivo disponible ·
invariante de chunking verde.

## Lo que no hará (dicho de antemano)

«Incremental» es por lotes con arranque en caliente, no por diferencias fila a fila (punto 2). No
persiste nada (D4). No dibuja los 2.000 temas a la vez (D5). Sin cifras de un teléfono real
mientras no haya uno.
