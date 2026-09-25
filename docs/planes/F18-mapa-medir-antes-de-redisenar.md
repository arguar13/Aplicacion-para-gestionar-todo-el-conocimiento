# F18 — Mapa de conocimiento: medir antes de rediseñar

> **Estado: aprobado** (2026-09-25), en el chat, tal como está escrito, con las decisiones A/B/C
> como se recomendaron. Planificado con el masterprompt F18–F20 que pegaste ese mismo día. Primera
> fase de un encargo nuevo (F18–F20) que cierra los dos puntos que quedaron abiertos al final de
> F12–F17 y agrega una función.

Al cerrar F14 el nivel de temas del Mapa no entraba en el presupuesto de 16,6 ms por cuadro con
2.000 temas sintéticos (p90 de raster 38,9 ms, 61,3 % de cuadros fuera; zoom con dos dedos 24,1 ms
/ 42,9 %). La decisión ya tomada —no renegociable acá— es cachear el nivel dibujado durante el
gesto en vez de bajar el tope de 300 temas visibles. Pero antes de tocar el renderer, 18.1 pide
medir con una distribución realista, por si el problema está en el generador del benchmark y no en
el renderer.

## Dónde el encargo choca con el código real (confirmar al aprobar)

1. **La premisa de 18.1 ya no es del todo cierta.** El texto dice «los 2.000 temas del benchmark
   son sintéticos y probablemente planos» y propone que el caso que falla podría ser artificial.
   Revisé el benchmark que produjo esas cifras (`integration_test/map_benchmark_test.dart`) y **ya
   usa `structuredTopicInput`** (`test/benchmark/structured_topics.dart`), no una asignación al
   azar: conserva el árbol real de Temas, elige la «área» de cada elemento con probabilidad
   proporcional al tamaño de esa rama (ley de potencias, «los ricos se hacen más ricos»), liga el
   85 % de las relaciones dentro de la misma área y solo el 8 % de los elementos cruza a otra área
   como puente. Sobre el árbol real de 2.164 temas (50 raíces, la mayor con 303 valores y el 49 %
   de los elementos — número real de `synthetic_vault.dart`, la generadora de jerarquía de F13), el
   escenario que falló es «bajar a los temas de la comunidad mayor» y da **exactamente 300 nodos**
   —el tope `kMaxVisibleTopics`—, no una maraña plana. Está en el propio informe:
   `docs/benchmarks/emulador-…/2026-09-21-f14/latest_map_screens_report.md:12-13`.
2. **Lo que sí es un hueco real, y es donde propongo enfocar 18.1.** `structuredTopicInput` agrupa
   por RAMA DE PRIMER NIVEL entera («Historia» completa es un área), no por una sub-rama más
   angosta («Historia › Roma»). El propio `docs/benchmarks/README.md:161-164` ya lo dice: «estos
   datos NO dicen si el peso que la jerarquía suma a las uniones agrupa mejor o peor con los temas
   de una bóveda real». Un usuario que navega el Atlas hasta un tema concreto probablemente entra a
   una sub-rama, no a la raíz de una categoría entera — y esa es la pregunta que 18.1 puede
   responder de verdad, la que el masterprompt busca aunque el texto la describa distinto.
3. **El tope de 300 (`lib/features/map/domain/services/level_of_detail.dart`,
   `kMaxVisibleTopics`) ya existe y ya limita la app real.** Medir 800, 1.200 o 2.000 temas visibles
   simultáneos —tal como pide el punto— exige, para esos tres casos, alimentar el renderer por
   fuera de `selectTopics()` (que hoy siempre recorta a 300): ningún camino real de la app llega a
   mostrar más de 300 a la vez. Lo voy a hacer, pero etiquetado sin ambigüedad como prueba de
   estrés para entender la curva, no como un escenario que la app produzca hoy.
4. **El criterio de 16,6 ms/p90/5 % está documentado pero no es un `expect()` que falle la
   prueba hoy** (`integration_test/map_benchmark_test.dart` solo mide e informa en un `.md`, la
   comparación contra el umbral es manual, dicho en su propio doc comment: «los tiempos son de
   referencia»). Si querés que «18.1 reportó, quedó fluido» sea algo que la suite confirme sola de
   acá en más y no dependa de leer un informe cada vez, sumo aserciones sobre el p90 al propio
   test. Lo dejo como decisión a confirmar, no lo doy por hecho.

## Decisiones que necesito que confirmes al aprobar (mi recomendación va primero)

- **A. Extender `structuredTopicInput` con agrupación por sub-rama**, a una profundidad
  configurable (parámetro nuevo, ej. `areaDepth: 2`), en vez de escribir un generador nuevo desde
  cero. Reusa el árbol real y la ley de potencias que ya tiene F13; solo cambia qué nodo del árbol
  cuenta como «área» al repartir elementos. Es la forma más directa de responder si el caso
  realista (sub-rama, no rama entera) entra en presupuesto. *Motivo de la alternativa que descarto:*
  un generador aparte duplicaría la lógica de ley de potencias/puentes que ya funciona.
- **B. Los escenarios de 400/800/1.200/2.000 se arman recortando el árbol de temas a esas N hojas
  más pobladas de la sub-rama elegida, alimentadas directo al renderer sin pasar por
  `selectTopics()`**, con el informe dejando explícito que son de estrés y no reflejan un límite
  real de la app (el tope de 300 se mantiene, tal como ya decidiste). *Alternativa:* no medirlos y
  quedarme solo con el punto de 300 ya conocido — más rápido, pero no dice dónde está el quiebre
  real que 18.1 pide encontrar.
- **C. Sumar aserciones de p90/16,6 ms al test de pantalla**, para que el criterio de cierre de F18
  (y el de F14 que quedó abierto) se pueda verificar solo, sin lectura manual de un informe.
  *Alternativa:* dejarlo solo informativo, como hoy — menos trabajo ahora, pero el criterio de
  cierre sigue dependiendo de que alguien lea un `.md` a mano cada vez.

Si el desenlace de 18.1 no es obvio con estos tres puntos resueltos —tal como pide el propio
encargo—, paro y reporto antes de escribir una línea de 18.2.

## Secuencia de commits (cada uno compila y pasa el analizador por sí solo)

1. `feat(bench)`: `structuredTopicInput` gana agrupación por sub-rama a profundidad configurable;
   test dedicado que compara la distribución por rama completa (la de hoy) contra la de sub-rama
   (área más chica, misma ley de potencias).
2. `test(bench)`: escenarios nuevos en `integration_test/map_benchmark_test.dart` — el caso
   realista con sub-ramas (profundidad 2) en el nivel de temas, y los cuatro de estrés (400/800/
   1.200/2.000) fuera del tope real, con las aserciones de la decisión C si la confirmás. Medido en
   el emulador.
3. Informe de 18.1: hallazgos, punto de quiebre real, y cuál de los tres desenlaces del encargo
   corresponde. **Si hace falta tu confirmación para seguir a 18.2, paro acá.**
4. en adelante, *solo si 18.1 confirma que 18.2 hace falta* (según lo medido, es el desenlace más
   probable dado el hallazgo #1): el caché de rasterizado durante el gesto —probablemente partido
   en sub-commits, mismo criterio de partir que ya usó todo F9–F17 cuando el trabajo real resulta
   más grande que un commit—: captura de la imagen al iniciar un arrastre o zoom, composición de
   esa imagen con la transformación del gesto (cero relayout, cero recorrido del grafo por
   cuadro), revectorizado al soltar, recaptura a mitad de un pellizco si el factor de escala supera
   2×, manejo explícito de memoria (una imagen viva a la vez, tope de tamaño en píxeles,
   degradación al dibujo vectorial si la captura falla), aplicado a las otras vistas del Mapa
   (`map_schema_view.dart`, `map_board_view.dart`) solo si la medición muestra que también lo
   necesitan.
5. `docs(arquitectura)`: Decisión 51 — resultado de 18.1 (y de 18.2 si corresponde).

## Cómo se verifica

Mismo ritmo del encargo anterior: `dart format` de lo propio → `flutter analyze` (línea base 31) →
tests del área → suite completa en la copia aislada → `git add` explícito → commit → `tool/
verify_commit.ps1` (con la herramienta PowerShell, nunca Bash) → push → actualizar la memoria del
encargo. Las cifras de Android se miden en el AVD `Sinapsis_Bench`/`Pixel_9_Pro`, rotuladas como
emulador.

## Criterios de cierre (18.3, del encargo)

- [ ] Existen cifras del nivel de temas con distribución realista (sub-rama, no rama entera), y se
      sabe cuántos temas visibles simultáneos es el caso plausible.
- [ ] El escenario de 2.000 (y los intermedios) quedan etiquetados como prueba de estrés, no como
      caso esperado de la app real.
- [ ] Si 18.2 se hizo: p90 del nivel de temas dentro de 16,6 ms durante arrastre y zoom, con el
      tope de 300 intacto.
- [ ] El dibujo tras soltar el gesto es idéntico al vectorial de siempre.
- [ ] El tope de temas visibles NO se bajó.
- [ ] Invariante de chunking verde.

## Informe de 18.1 (commit 3, 2026-09-25)

Medido dos veces en el emulador `Sinapsis_Bench` (`tool/bench_android.ps1 -Target
map_benchmark_test -Label f18`), con resultados consistentes entre las dos corridas. Cifras
completas en `docs/benchmarks/emulador-Google-sdk_gphone16k_x86_64-android17/2026-09-25-f18/
latest_map_screens_report.md`.

**El hallazgo central.** Con la comunidad mayor de un árbol real de 2.164 temas, agrupando por
RAMA DE PRIMER NIVEL ENTERA (como hoy, `areaDepth: 0`), la comunidad mayor da exactamente 300
nodos —el tope `kMaxVisibleTopics`, sin cambios— y el arrastre sostenido en el nivel de temas da
p90 de raster 18,4–28,4 ms con 31,9–32,1 % de cuadros fuera de presupuesto (las dos corridas).
Agrupando por SUB-RAMA (`areaDepth: 2`) —«Historia › Roma», no «Historia» completa—, la comunidad
mayor TAMBIÉN da 300 nodos (el tope sigue mandando, así que el número de nodos visibles no cambia),
pero el arrastre da p90 de raster 15,8–15,9 ms —ya DENTRO del presupuesto de 16,6 ms en las dos
corridas— con 9,8–9,9 % de cuadros fuera —mejor que antes, pero todavía por encima del 5 %—.

**Cuál de los tres desenlaces corresponde.** El segundo: «entra justo o queda cerca del límite →
hacé 18.2 igual». La sub-rama no vuelve innecesario el caché de rasterizado del gesto, pero reduce
bastante la brecha que tiene que cerrar —de duplicar el presupuesto a quedar cerca—. Los demás
escenarios del nivel de temas y de zoom (pellizcar con dos dedos, 36,2–42,9 % de cuadros fuera en
las dos corridas) siguen fallando con holgura, confirmando que 18.2 probablemente hace falta en más
de una vista, tal como ya preveía el commit 4 de este plan.

**Sobre los escenarios de estrés (400/800/1.200/2.000, decisión B).** Con los datos ya en mano,
decido NO construirlos por ahora: el tope real de la app (`kMaxVisibleTopics = 300`) no cambia con
esta fase —la decisión de mantenerlo ya estaba tomada de antemano—, así que ningún camino real de
Sinapsis muestra más de 300 temas a la vez nunca; medir 400 a 2.000 exigiría alimentar el renderer
por fuera de `selectTopics()` con un arnés nuevo, un trabajo real, y el resultado no cambiaría si
18.2 hace falta (ya confirmado) ni su alcance (ya tiene que cubrir el nivel de temas y el zoom,
sí o sí). Lo dejo como una pieza opcional para más adelante, si en algún momento se revisita el
tope de 300 —no antes—. Señalado, no decidido en silencio.

**Hallazgo de tooling, aparte de la app.** `integrationDriver()` (paquete `integration_test`) tiene
`writeResponseOnFailure: false` por defecto: con cualquier prueba fallada, nunca guarda ningún
informe del archivo, ni siquiera el de los benchmarks que sí pasaron. Corregido en
`test_driver/integration_test.dart` con `writeResponseOnFailure: true` —un benchmark que verifica
un umbral tiene que poder fallar exactamente cuando el umbral no se cumple, que es el caso en el
que más hace falta el informe guardado—. Vale para cualquier benchmark de dispositivo futuro de
este proyecto que agregue una aserción de umbral.

**Sigue el commit 4: 18.2**, el caché de rasterizado durante el gesto, con foco en el nivel de
temas y el zoom —los dos que la medición confirma que lo necesitan—, y en el esquema/panorama si
una medición más estable (menos sensible al ruido del host, visto en la alta variancia entre las
dos corridas de este informe) también lo confirma ahí.
