# F44 — El Mapa: dos pestañas, un solo lienzo inteligente

> **Estado: APROBADO** (2026-10-29, «Aprobado» en el chat), con las decisiones A a G como están.
> Se construye apenas se integren las mejoras M10 a M18 de F43: el Resumen usa las piezas de
> gráficos de M17.
>
> Pedido del dueño, el 29/10, con cuatro capturas del Mapa (Grafo, Esquema, Vínculos y Tablero):
> *"las tres pestañas de mapa «Vínculos», «Esquema» y «Grafo» dicen más o menos lo mismo? Se podría
> ser más eficiente y hacer todo eso en una o dos interfaces en vez de tres?"* — y, sobre la
> propuesta de dos pestañas: *"me gustó mucho tu idea de dos pestañas en vez de 4, y a la pestaña
> de Mapa hazla súper elegantemente, muy interactivamente y profesionalmente, que sea inteligente
> y lo mejor posible"*. *"Y el tablero, si hay algo por mejorar, hazlo."*

## Lo que hay hoy (y no se pierde)

El Mapa (F14, F18 y F28; decisiones 47, 51 y 61) tiene cuatro pestañas sobre lo procesado, con el
selector «Agrupar por» (Temas, Etiquetas u otra categoría), la franja «Organizar con IA» y los
filtros de arriba:

| Pestaña | Qué dibuja | A qué altura |
|---|---|---|
| **Tablero** | siete tarjetas con números | — |
| **Grafo** | comunidades → temas → elementos, según el zoom, con migas y «Grado» | las tres |
| **Esquema** | un tema (o una nota mapa) que se despliega nodo a nodo, en radial o en árbol, con cada vínculo rotulado con su tipo | un tema |
| **Vínculos** | los elementos y sus vínculos, tengan o no tema, con «Más fuertes · Menos fuertes · Todos» | los elementos |

Las tres últimas dibujan lo mismo —nodos y uniones— a tres alturas, en tres pantallas que no se
hablan: hay que saber de antemano en cuál buscar y ninguna lleva a la otra. El Grafo **ya tiene** el
zoom por niveles (comunidades, temas, elementos) que pide la idea; lo que falta es que el Esquema y
los Vínculos dejen de ser pantallas aparte y pasen a ser **formas de mirar** y **capas** del mismo
lienzo.

**Lo que se conserva, uno por uno** (nada de esto se pierde, cambia de lugar):

- los tres niveles del Grafo, sus topes (60, 300 y 200 nodos), las migas y el «Grado»;
- el despliegue nodo a nodo del Esquema, sus modos radial y árbol, las notas mapa como raíz y los
  vínculos rotulados con su tipo y su flecha;
- de Vínculos: los elementos sin tema, el filtro de fuerza, el conteo de los sueltos, el foco de
  «Ver en el Mapa» y el elegir hasta 200 (lo recién vinculado primero);
- agregar un vínculo a mano y «✨ Sugerir vínculos con IA»;
- exportar a PNG y SVG, los filtros, «Agrupar por» y «Organizar con IA»;
- el motor en otro isolate, el caché de rasterizado durante el gesto (F18) y el layout en caliente.

## Qué se construye

### 1. Dos pestañas: Resumen y Mapa

```
┌──────────────────────────────────────────┐
│ Mapa                          ⚲   ⏷   ⇪  │  ← buscar, filtros, exportar
│ ╭────────────────┬─────────────────────╮ │
│ │    Resumen     │        Mapa         │ │  ← dos pestañas (antes, cuatro)
│ ╰────────────────┴─────────────────────╯ │
│ 🏷 Etiquetas ▾       1 sin etiquetas · ✨ │  ← «Agrupar por» y la franja, en UNA línea
└──────────────────────────────────────────┘
```

- **Resumen** es el Tablero rehecho (ver 4). Abre por defecto la primera vez; después, la última
  que se miró.
- **Mapa** es el lienzo único (ver 2 y 3).
- «Agrupar por» y la franja «Organizar con IA» comparten una línea compacta: hoy ocupan dos filas
  enteras y la franja se repetía en cada pestaña.
- **⚲ Buscar en el mapa**, arriba: escribís y aparecen los temas y los documentos que coinciden;
  tocás uno y el lienzo **vuela hasta él** (cambia de nivel si hace falta, lo encuadra y lo marca
  con un pulso).

### 2. El Mapa: un lienzo que se recorre con el zoom

```
  Todo › Cristianismo › Tomás de Aquino              ← migas: tocás una y volvés
┌──────────────────────────────────────────┐
│                                          │
│        ◯ Cristianismo (4)                │  lejos: las comunidades
│              ╲                           │
│               ◯ Lazarillo (2)    ◌ 7     │
│                                          │
│                                ┌──────┐  │
│                                │ ▪ ▫  │  │  ← minimapa: dónde estás
│ [Red · Radial · Árbol]  [Capas]│  ▫   │  │
│                    ⊕ ⊖ ⛶       └──────┘  │  ← acercar, alejar, encuadrar
└──────────────────────────────────────────┘
```

- **Tres alturas, un gesto**: de lejos, las comunidades; al tocar una o acercarte, sus temas
  **salen de la burbuja** con una animación corta (los nodos nacen donde estaba la comunidad y se
  acomodan); otro toque o más zoom en un tema despliega sus documentos alrededor. Alejarte los
  recoge de vuelta. Con «sin animaciones», el cambio es directo.
- **Las migas** de arriba dicen dónde estás («Todo › Cristianismo › Tomás de Aquino») y llevan a
  cualquier altura anterior.
- **Disposición: Red · Radial · Árbol.** Es lo que hoy es el Esquema, pero sobre lo que estás
  mirando:
  - **Red** es la de fuerzas de siempre;
  - **Radial** pone en el centro el tema o el documento en foco y sus ramas alrededor;
  - **Árbol** lo despliega de izquierda a derecha, de lo general a lo particular.

  Radial y Árbol mantienen el despliegue nodo a nodo del Esquema («›» abre una rama, «‹» la
  cierra) y los vínculos rotulados con su tipo.
- **El minimapa** aparece cuando te acercás: un rectángulo muestra qué parte ves, y tocarlo o
  arrastrarlo te lleva ahí. Se esconde solo con el lienzo entero a la vista.
- **⊕ ⊖ ⛶**: acercar, alejar y encuadrar todo. Vuelven del grafo viejo, porque en la computadora y
  con el lector de pantalla pellizcar no alcanza.
- **El color dice la comunidad**, como hoy; los documentos, su rol (fuente o nota). Un tema que
  **une dos comunidades** —un puente— lleva un anillo doble (ver 3).

### 3. Tocar es entender: la ficha, el foco y las capas

**La ficha.** Tocar cualquier nodo abre abajo una ficha corta, sin tapar el mapa:

```
╭──────────────────────────────────────────╮
│ ◯ Cristianismo                           │
│ 7 documentos · 3 temas · 2 vínculos      │
│ Une con: Imperio romano, Literatura      │  ← sus vecinos más fuertes, tocables
│ Lo más reciente: Regla de san Benito     │
│                                          │
│ [Entrar]  [Centrar aquí]  [Abrir]        │
│ [✨ Preguntar al chat]  [🎓 Estudiar]     │
╰──────────────────────────────────────────╯
```

- **Entrar** baja una altura (lo mismo que tocar dos veces o acercarse).
- **Centrar aquí** es el **modo foco**: el nodo al centro, su vecindario alrededor según el
  «Grado» (0, 1, 2, Todos) y el resto apagado. Es la vista «Esquema» de hoy, a un toque de
  cualquier nodo y no solo del tema más grande. «Salir del foco» o la miga lo devuelven.
- **Abrir** abre el tema en el Explorador o el documento en Procesado, como hoy.
- **✨ Preguntar al chat** abre el chat con la pregunta hecha y visible —«¿Qué dicen mis documentos
  sobre Cristianismo y cómo se relaciona con Imperio romano y Literatura?»—, en una conversación
  nueva sobre lo procesado. Se manda solo al tocar el botón (como «Explicar», decisión L de F43).
- **🎓 Estudiar** abre Repasar con el selector ya puesto en ese tema o documento: el Mapa y Estudiar
  quedan conectados en los dos sentidos.
- En un documento, además: **Vincular** (el flujo de siempre) y **Ver sus vínculos** (prende la capa
  de vínculos con él en foco).

**Las capas** (botón «Capas»; se pueden prender varias a la vez):

| Capa | Qué agrega | De dónde sale |
|---|---|---|
| **Vínculos** | las uniones entre documentos, con «Más fuertes · Menos fuertes · Todos» y el aviso «Se muestran 3 de 6» | lo de la pestaña Vínculos de hoy |
| **Sin tema** | una burbuja gris con los documentos que no tienen tema ni etiqueta, para que también estén en el mapa | hoy solo se ven en Vínculos |
| **Contradicciones** | las uniones en tensión, en rojo con su rayo, y un atajo a Tensión | hoy mezcladas en el grafo |
| **Parecidos (IA en el teléfono)** | líneas punteadas entre documentos que **hablan de lo mismo** pero no están vinculados; tocar una ofrece «Vincular» con un toque | los vectores que ya guarda la app (F30), sin red |
| **Estudio** | tiñe cada documento según su estudio: sin tarjetas, con tarjetas para hoy, al día | las tarjetas de Repasar |

- **Parecidos** solo aparece si el modelo de vínculos está descargado; si no, la capa explica qué
  hace y lleva a descargarlo. No se manda nada a ningún servicio: los vectores ya están en el
  teléfono. Nunca vincula sola: propone y la persona confirma.
- **Vínculos** prendida al nivel de los documentos es exactamente la vista Vínculos de hoy, con los
  mismos topes y el mismo orden. «Ver en el Mapa» (el aviso de «Vinculado») abre el Mapa a esa
  altura, con la capa prendida y el documento en foco, como hoy.

**Con el lector de pantalla**, un dibujo no se recorre bien. El lienzo ofrece **«Ver como lista»**:
el mismo contenido como una lista que se despliega (comunidades › temas › documentos, con sus
vínculos), con las mismas acciones de la ficha.

### 4. Resumen: el Tablero, más claro, más útil y conectado con el Mapa

```
┌──────────────────────────────────────────┐
│ ╭────────╮╭────────╮╭────────╮╭────────╮ │
│ │   14   ││   13   ││   2    ││   1    │ │  ← cifras grandes, tocables
│ │ docum. ││etiquet.││comunid.││vínculo │ │
│ ╰────────╯╰────────╯╰────────╯╰────────╯ │
│ Lo nuevo · esta semana                   │
│ Para estudiar                            │
│ Temas con más material   (barras + %)    │
│ Puentes entre temas                      │
│ Los más conectados entre sí              │
│ Sueltos y aislados                       │
│ Contradicciones abiertas                 │
│ Cómo creció (barras por mes, con ejes)   │
│ Cuánto lo trabajaste                     │
└──────────────────────────────────────────┘
```

- **Cifras grandes** en lugar de las fichas grises: documentos, temas (o etiquetas), comunidades y
  vínculos, cada una con su cambio de los últimos 30 días («+3»). Tocar una abre el Mapa a esa
  altura.
- **Lo nuevo · esta semana** (nueva): lo procesado y lo vinculado en los últimos 7 días, con un
  toque para verlo en el Mapa.
- **Para estudiar** (nueva): los temas con más material **sin tarjetas** y los que tienen **tarjetas
  para hoy**, con «🎓 Estudiar» al lado de cada uno. Une el Mapa con Estudiar (F43).
- **Temas con más material**: las barras de hoy, con el número y el porcentaje del total, y cada
  fila **lleva al Mapa** con ese tema en foco (hoy abre el Explorador; el Explorador sigue en la
  ficha, con «Abrir»).
- **Puentes entre temas** (nueva): los temas que unen comunidades distintas —los que, si se
  sacaran, dejarían dos partes sueltas—. Son los que mejor ordenan lo que sabés.
- **Los más conectados entre sí**, **Contradicciones abiertas** y **Cuánto lo trabajaste**, como
  hoy, con las filas tocables y el mismo diseño de tarjeta que el resto.
- **Sueltos y aislados** junta los temas aislados de hoy con los documentos sin ningún vínculo, y
  ofrece «✨ Sugerir vínculos» y «Organizar con IA».
- **Cómo creció**: la línea sin ejes de hoy pasa a barras por mes con sus ejes y sus meses, del mismo
  estilo que las estadísticas nuevas de Repasar (M17), para que la app hable un solo idioma visual.
- Todo cabe en 360 dp con la letra al doble, en claro y en oscuro, con el lector de pantalla.

### 5. Inteligente, sin mandar nada a ningún lado

Lo «inteligente» se arma con lo que la app ya sabe, en el teléfono:

- **Puentes**: los temas que más unen comunidades distintas (un cálculo de grafos en el motor, en
  el mismo isolate que las comunidades, con un tope para que no crezca con el cuadrado).
- **Parecidos**: los vectores de cada documento que ya guarda la app para el chat y los cuadernos
  (F30). Se comparan solo los que están a la vista y como mucho unos cientos.
- **El nombre de cada comunidad** deja de ser solo su tema más grande: dice sus dos temas
  principales («Cristianismo · Tomás de Aquino») y, en la ficha, todos.
- **Buscar en el mapa** sabe en qué comunidad está cada tema y cada documento, y vuela hasta él.
- **Preguntar al chat** y **Estudiar** son las dos salidas: entender lo que ves y estudiarlo.

## Decisiones (se pueden cambiar mientras no se llegue a su paso)

- **A. Dos pestañas, Resumen y Mapa** (recomendada). Las vistas Grafo, Esquema y Vínculos dejan de
  ser pestañas y pasan a ser alturas, disposiciones y capas del Mapa. *Alternativa:* dejar el
  Esquema como tercera pestaña. No la recomiendo: «Centrar aquí» con Radial o Árbol hace lo mismo
  desde cualquier nodo.
- **B. Las capas arrancan apagadas salvo Vínculos al nivel de los documentos.** Un mapa limpio
  primero, y lo demás a pedido; la elección se recuerda.
- **C. «Parecidos» propone y la persona confirma**, nunca vincula sola, y solo con los vectores que
  ya están en el teléfono: sin red ni claves.
- **D. Tocar una fila del Resumen lleva al Mapa**, no al Explorador. El Explorador sigue a un toque,
  con «Abrir» en la ficha.
- **E. No cambia el esquema de la base** (sigue en v48): todo lo nuevo es derivado y se calcula en el
  motor o en la vista.
- **F. Los topes no suben** (60, 300 y 200): el lienzo único tiene que andar igual de fluido en el
  teléfono que hoy cada pestaña. Las cifras se miden por estructura (nodos, consultas), no en
  milisegundos crudos.
- **G. Exportar sigue**: PNG y SVG de lo que se ve, con las capas prendidas.

## Pasos (cada uno, su commit y su push)

Se construye en dos olas de agentes en paralelo, cada uno en su rama, con su GUÍA, sus pruebas y
sus mutaciones. Cada paso se integra en `main` con su suite, su push y su verificación.

**Ola 1:**

1. **El motor sabe más**: los puentes, el nombre de dos temas por comunidad, la búsqueda (índice de
   temas y documentos con su comunidad y su tema), los «sin tema» como burbuja y lo nuevo de los
   últimos 7 y 30 días. En el dominio y el motor, con pruebas de estructura.
2. **El lienzo único**: las dos pestañas, la línea compacta de arriba, las tres alturas con la
   animación de salir de la burbuja, las migas, Red · Radial · Árbol (con el despliegue del
   Esquema), el minimapa, ⊕ ⊖ ⛶, la exportación y «Ver como lista». Sale el código de las
   pestañas viejas que ya no se usa.
3. **Resumen**: las cifras grandes, las nueve tarjetas, «Cómo creció» con ejes (con las piezas de
   gráficos de M17) y cada fila llevando al Mapa.

**Ola 2 (sobre la 1):**

4. **La ficha y el foco**: la ficha de cada nodo con sus acciones, «Centrar aquí» con el «Grado»,
   «Preguntar al chat» (con `askInChat`) y «Estudiar» (Repasar con el selector puesto). «Ver en el
   Mapa» apunta al lienzo nuevo.
5. **Las capas y la búsqueda**: Vínculos con su filtro de fuerza, Sin tema, Contradicciones,
   Parecidos (con su aviso si falta el modelo), Estudio, y ⚲ Buscar con el vuelo hasta el nodo.
6. **El cierre**: la suite entera, la medición en el emulador de los gestos del lienzo con las capas
   prendidas (contra la de F18), la decisión 90 en arquitectura, la GUÍA de «El Mapa» reescrita y
   la APK si el dueño la pide.

## Lo que no entra (para que quede dicho)

- **Arrastrar los nodos a mano** y guardar posiciones: el layout es del motor (decisión 47).
- **Nombrar las comunidades con la IA de la nube**: mandaría los títulos afuera; el nombre de dos
  temas alcanza.
- **El Atlas** no cambia: sigue en Organizar.
- **El grafo local** de cada documento (en Procesado) no cambia; su «Ver en el Mapa» lleva al nuevo.

## Avance

### Paso 1 (hecho): el motor sabe más

Diez commits, solo en `lib/features/map/domain` y `lib/features/map/data`, sin nada visible
todavía. Todo llega con cada mapa en `KnowledgeMapSnapshot.insights` (`MapInsights`), calculado en
el mismo isolate que las comunidades y sin datos nuevos en la base (decisión E).

- **Los puentes** (`BridgeAnalysis`): los temas que unen comunidades distintas, pesados por la
  parte que llevan de lo que une a cada par. El único camino entre dos comunidades vale todo su
  peso; uno entre cien parecidos, casi nada. Marca la «única unión» contando uniones, no sumando
  decimales. El costo es lineal en las uniones, con un tope de 12 puentes y de 6 comunidades por
  puente; la prueba cuenta lo recorrido exacto.
- **El nombre de cada comunidad**, con sus dos temas más unidos con los demás de ella («Cristianismo
  · Tomás de Aquino»), sin repetir un nombre por acentos o mayúsculas. Trae su ficha: sus temas en
  orden, sus documentos y vínculos, con quién se une y lo más reciente.
- **El índice de búsqueda** de temas y documentos, con tema o sin él, en memoria, sin acentos ni
  mayúsculas, ordenado por cuán bien coincide; cada entrada dice por qué tema se llega a ella.
- **La burbuja «Sin tema»**: los documentos sin ningún valor de lo que se mira, los más nuevos
  primero hasta 200, con sus vínculos y las comunidades con las que se vinculan.
- **Lo nuevo** de los últimos 7 y 30 días —lo procesado y lo vinculado, cada documento con su
  lugar en el mapa— y **las cuatro cifras con lo que valían hace un mes**. El grafo de hace un mes
  sale de la misma pasada que el de hoy, y se vuelve a agrupar solo si algo cambió en el mes.
- **«Para estudiar» no está en el motor, a propósito**: necesitaría las tarjetas, y repasar una
  tarjeta recalcularía el mapa (decisión 47). Lo calcula el Resumen (paso 3), aparte.
- Pruebas con la bóveda grande (2.000 temas, 10.000 documentos, 25.000 vínculos y 500 sin tema),
  de estructura, y `EXPLAIN QUERY PLAN` con un solo recorrido de `item` y de `relations`, como
  antes. Diez mutaciones, todas muertas: dos sobrevivían y se reforzaron sus pruebas.
- Las carpetas del mapa, las creaciones, las tarjetas y Organizar: 3.168 pruebas pasan.
- Queda medirlo en el emulador contra la medición de F18, en el cierre (paso 6).

### Paso 2 (hecho): el lienzo único

Siete commits, de `7628016f` a `b3678ce2`. Sale lo visible de antes: las pestañas Tablero,
Vínculos, Esquema y Grafo (`MapGraphView`, `MapSchemaView`, `MapLinksView`, `schema_tree_builder`
y `SchemaEntry`, con sus pruebas y siete claves sin uso).

- **Dos pestañas, Resumen · Mapa** (`map_tab_provider.dart`): la primera vez abre en el Resumen;
  después, en la última que se miró, también entre reinicios.
- **Una sola línea arriba**: «Agrupar por», los filtros puestos y «N sin … · ✨ Organizar con
  IA». En angosto baja de renglón.
- **El lienzo** (`presentation/widgets/canvas/`), sobre dos piezas puras del dominio:
  - el árbol de lo que se mira (`canvas_tree_builder.dart`): todo, una comunidad, un tema o lo
    vinculado, desplegable nodo a nodo como el Esquema;
  - las cuentas (`canvas_viewport.dart` y `canvas_motion.dart`): qué parte se ve, ⊕ ⊖ alrededor
    del centro, el minimapa y el movimiento entre alturas.
- **Lo que hace el lienzo:**
  - tres alturas: los temas salen de la burbuja de su comunidad y lo de abajo se recoge al
    subir; con «sin animaciones», el cambio es directo;
  - las migas «Todo › comunidad › tema» llevan a cualquier altura;
  - Red · Radial · Árbol sobre lo que se mira. Lo tocado queda quieto al desplegar, una nota mapa
    puede ser la raíz, y los vínculos llevan su tipo y su flecha;
  - el minimapa, ⊖ ⊕ ⛶, «Ver como lista» y exportar en PNG o SVG con la disposición en el nombre
    (`mapa-radial-etiquetas.svg`).
- **Cada comunidad se llama por sus dos temas** (`insights.communities.of(id).name`) en la
  burbuja, las migas, Radial, Árbol, la lista y lo que oye el lector. Sin `insights`, queda el
  tema más unido.
- **Se conserva lo de F18**: los topes 60/300/200, el layout en otro isolate y en caliente, y el
  caché de rasterizado durante el gesto. `integration_test/map_benchmark_test.dart` usa las
  claves nuevas.
- **Decisiones del paso:**
  - los vínculos quedan, hasta la capa «Vínculos» de la ola 2, en un botón de cadena junto a Red
    · Radial · Árbol, con todo lo de antes: los sueltos, el filtro de fuerza, el foco de «Ver en
    el Mapa», agregar uno y «✨ Sugerir vínculos con IA»;
  - tocar un tema baja a sus documentos; su material se abre con el botón de carpeta;
  - ⊕ ⊖ solo acercan y alejan, sin cambiar de altura;
  - un solo canal de pedidos, `mapCanvasRequestProvider` (`MapShowLinks`, `MapShowAltitude` y
    `MapShowTopic`), en lugar de `mapLinksFocusRequestProvider`: lo usan las filas del Resumen y
    lo va a usar la búsqueda.
- **Verificado:** analyze en 19; `test/features/map` y la navegación, 519 pruebas; las creaciones
  y las tarjetas, 2.365. Murieron las 13 mutaciones; entre otras, los temas que nacen en su
  lugar, ignorar «sin animaciones», volver a pedir lo ya traído, exportar visto como lista, abrir
  la primera vez en el Mapa y el nombre de una comunidad.
- **Queda para después:** `map_canvas_view.dart` tiene unas 1.950 líneas y se parte cuando entren
  la ficha y las capas (ola 2). El desborde del Resumen a 360 dp con la letra al doble es del paso
  3, que lo arregla.

### Paso 3 (hecho): el Resumen

Once commits, de `ab8d1b2b` a `6518618c`.

- **Las cuatro cifras grandes**: documentos, temas (o etiquetas), comunidades y vínculos, en dos
  columnas del mismo alto.
  - Cada una lleva su cambio de 30 días, que sale del motor (`insights.recent.figures`). Puede
    bajar: «−1 en 30 días» si un vínculo juntó dos comunidades. Si el motor no midió la hora, no
    se muestra ningún cambio.
  - Tocarla abre el Mapa a esa altura; la de vínculos, con los vínculos.
- **Las nueve tarjetas**, con el diseño de las estadísticas de Repasar:
  - Lo nuevo · esta semana, del motor (`insights.recent.week`);
  - Para estudiar, con «🎓 Estudiar» hacia Repasar con el tema (y su espacio, en los temas de
    F37). Se actualiza sola al repasar;
  - Temas con más material;
  - Puentes entre temas, de `insights.bridges`: «Une con Cristianismo · Tomás de Aquino, Egipto»,
    con el nombre de cada comunidad, y «Única unión con …» si sin él quedarían sueltas
    (`isSole`);
  - Los más conectados entre sí;
  - Sueltos y aislados, con «✨ Sugerir vínculos» y «Organizar con IA»;
  - Contradicciones abiertas;
  - Cómo creció, en barras por mes con sus meses (`StatsBarChart`, de M17);
  - Cuánto lo trabajaste.
- **Cada fila lleva al Mapa** por el canal del lienzo (`mapCanvasRequestProvider`), con la función
  pura `canvasRequestFor`:
  - un documento, a sus vínculos;
  - un tema, a su comunidad, resaltado;
  - una cifra, a su altura.

  La pantalla pasa sola a la pestaña Mapa.
- **Lo que lee aparte del grafo** (`board_facts_source_impl.dart` y `board_facts_sql.dart`): los
  documentos con sus vínculos, con el mismo recorte y el mismo filtro que el Mapa, y las tarjetas
  de cada uno. Lo pendiente de estudiar y lo suelto se calcula en `buildBoardInsights`; lo demás
  sale del motor, y salió `board_bridges.dart`.
- **Dos arreglos de raíz**:
  - el lienzo atendía el pedido con el que se abre dentro de `initState`, donde todavía no puede
    leer los textos del idioma. Ahora lo atiende en el primer `didChangeDependencies` (`df894aea`).
    El Resumen es el primero que lo abre con un tema pendiente;
  - el repositorio del Mapa medía «lo nuevo» y los 30 días con la hora del sistema y no con
    `clockProvider`, el reloj de las tarjetas del Resumen (`11f7eff2`).
- **El desborde a 360 dp con la letra al doble**, del tablero viejo, se arregló de raíz:
  - «Estudiar» baja debajo del tema;
  - la barra de «Temas con más material» va debajo del nombre;
  - los títulos largos se cortan en dos renglones.

  Se prueba recorriendo todas las tarjetas, en claro y en oscuro.
- **Verificado**:
  - analyze en 19, sobre `main` con el paso 2 de F45 y el 7c;
  - 4.309 pruebas del Mapa, la navegación, la Biblioteca, el panel de estado, la base, las
    creaciones y las tarjetas;
  - el censo de lecturas suma `board_facts_source_impl.dart` con su motivo (`6518618c`);
  - murieron las 10 mutaciones: el signo del delta, una baja dicha como subida, «Única unión» en
    todas o en ninguna, «Une con» sin los nombres, un tema pedido como documento, los vínculos con
    un foco que nadie pidió, el lienzo que no atiende el pedido con el que se abre, el panel que no
    manda nada y el repositorio sin el reloj de la app.
- **Queda para la ola 2** (la ficha y el foco): que un documento sin vínculos vuele a su tema; hoy
  se abre en Procesado.

### Paso 4 (hecho): la ficha y el foco

Seis commits, de `a8de0df7` a `b55938de`.

- **El lienzo, partido en piezas con nombre propio** (`a8de0df7`, refactor aparte; las 509
  pruebas del Mapa pasaron sin tocarlas):
  - `map_canvas_view.dart` bajó de 1.970 a unas 1.500 líneas, y con la ficha y el foco quedó en
    1.875. Ahí queda solo lo que se mira y cómo se pasa de una cosa a otra;
  - el dibujo de la red y de Radial y Árbol, en `map_canvas_layers.dart` (`MapNetworkLayer`,
    `MapTreeLayer`);
  - las migas, los controles de abajo y las notas de lo que no se dibujó, en `canvas_chrome.dart`;
  - dónde va cada nodo, en `canvas_placement.dart`; el caché de rasterizado de F18, en
    `canvas_gesture_cache.dart`; la raíz del árbol, en `canvas_tree.dart`;
  - «Sugerir vínculos con IA», que el lienzo y el Resumen tenían copiado, en `suggest_links.dart`.
- **Tocar abre la ficha**, en la red, en la lista y en Radial y Árbol con el botón ⓘ. El lienzo se
  achica para dejarle lugar y no la tapa. Dos toques, «Entrar» o acercarse bajan una altura; un
  documento, que no tiene doble toque, abre su ficha en el acto.
  - **Dice:** qué es y cuánto tiene (en una comunidad, todos sus temas); «Une con», hasta tres
    vecinos que llevan a cada uno; lo más reciente de una comunidad y el tema de un documento.
  - **Acciones**, lo principal primero: Entrar, Centrar aquí, Abrir, Preguntar al chat y
    Estudiar. En un documento, además, Vincular (el flujo de siempre, partiendo de él) y Ver sus
    vínculos.
  - **Abrir la ficha no recalcula nada:** sale del grafo, el motor (`insights`), la escena y el
    árbol, y queda recordada (`MapNodeFactsMemo`). Las pruebas cuentan que no hay layouts nuevos
    ni lecturas de la base.
- **Centrar aquí**, con el «Grado»:
  - el nodo queda en el medio, y se enciende su vecindario según el «Grado», por las uniones que
    se dibujan (`focusNeighborhood`). El resto se apaga en una sola capa, también en el SVG;
  - en Radial y Árbol, el centrado es la raíz, y ahí no se muestra el «Grado»;
  - se sale con «Salir del foco», con la ✕ de «Centrado en …» o con la miga de la altura;
  - si lo centrado no estaba dibujado, el Mapa primero va hasta él.
- **Preguntar al chat y Estudiar:** «Preguntar al chat» abre una conversación nueva con
  `askInChat`, que se manda sola. «Estudiar» abre Repasar con el selector puesto
  (`openRepasarWith`).
- **«Ver en el Mapa»** y un tema del Resumen llegan por el mismo camino que la ficha, y abren la
  suya. El pedido nuevo `MapShowDocument` lleva un documento a los documentos de su tema,
  resaltado.
- **Lo que quedaba del paso 3:** un documento suelto del Resumen vuela a su tema, en vez de
  abrirse en Procesado.
- **El encuadre:** si se abre o se cierra la ficha y nadie movió el mapa, se vuelve a encuadrar.
  Si la persona lo movió o tocó ⛶, se respeta el suyo.
- **Lo de F18 se conserva:** los topes, el layout en otro isolate y el caché del gesto. La
  medición (`map_benchmark_test.dart`) baja ahora con «Entrar» desde la ficha.
- **De paso:**
  - el SVG escribe la opacidad de un texto translúcido, que antes salía opaco;
  - salieron tres claves sin uso: `mapGraphHint`, `f44S2EnterCommunity` y `mapSchemaOpen`.
- **Para el lector de pantalla:** la ficha es un contenedor con nombre, su título es un
  encabezado que se anuncia al abrirse, y cada acción es un botón.
- **Verificado:**
  - analyze en 19, sobre `main` con el paso 0 de F47;
  - 4.169 pruebas del Mapa, la app, la base, el chat, las creaciones y las tarjetas;
  - murieron las 18 mutaciones. Entre ellas:
    - tocar baja de altura en vez de abrir la ficha, y el doble toque no baja;
    - el «Grado» no cambia lo encendido, y el centrado no queda en el medio;
    - el título de la ficha no se anuncia;
    - el texto translúcido sale opaco en el SVG;
    - un suelto va a lo vinculado;
    - abrir la ficha no vuelve a encuadrar.
- **Queda para el paso 5:**
  - Vínculos, que hoy es el botón de cadena (`MapLinksToggle`), pasa a ser una capa;
  - un documento sin vínculos y sin tema cae, por ahora, en lo vinculado, donde no aparece. Su
    lugar es la burbuja «Sin tema»;
  - ⚲ Buscar puede volar con `MapShowTopic` y `MapShowDocument` tal como están.
- **A mirar en el teléfono:** con la letra al doble, la ficha se desplaza sola y las acciones de
  abajo pueden quedar fuera de la vista hasta desplazarla. La medición en el emulador es del
  cierre (paso 6).

### Paso 5 (hecho): las capas y la búsqueda

Nueve commits, de `f5c0a59d` a este Avance: los pares parecidos en las relaciones, el dominio de las
capas, cómo se ve cada una, las capas en el lienzo, ⚲ Buscar, la GUÍA, una prueba que faltaba y un
import sin uso. Cada commit compila solo: los archivos que llevan cambios de dos commits se
stagearon en su versión intermedia.

- **El botón «Capas»** (`map_layers_sheet.dart`), donde estaba la cadena: una hoja con las cinco,
  cada una con su interruptor, lo que agrega y sus atajos. Arrancan apagadas salvo «Vínculos»
  (decisión B) y la elección se recuerda (`mapLayersProvider`). Visto como lista, el botón está
  arriba.
- **Prender o apagar una no acomoda nada ni vuelve a leer lo que ya se tiene** (`layeredScene`): el
  lienzo acomoda una sola vez lo que cualquier capa puede mostrar —la burbuja, los vínculos entre
  documentos— y dibuja el recorte. Lo que se lee aparte —las tarjetas, los parecidos— lo escucha
  `CanvasLayerFeeds` solo con su capa prendida. Las pruebas cuentan los layouts y las lecturas.
- **Vínculos**: las uniones entre documentos donde los haya. «Ver todo lo vinculado» es lo que era
  la vista Vínculos, con su filtro de fuerza y «Se muestran 3 de 6»; apagar la capa ahí vuelve
  adonde se estaba. «Ver en el Mapa» y «Ver sus vínculos» la prenden si estaba apagada.
- **Sin tema**: la burbuja gris de lejos, unida a las comunidades con las que se vinculan sus
  documentos. Un toque entra (no tiene ficha) y sus documentos los trae el motor, sin la base; la
  miga dice «Todo › Sin tema» y alejarse vuelve a las comunidades. En Radial, Árbol y la lista,
  entre las comunidades. **`MapShowDocument` de un documento sin tema vuela a ella** y prende la
  capa: es lo que quedaba del paso 4.
- **Contradicciones**: en rojo y con su rayo, en la pantalla y en el SVG; apagada, se dibujan como
  las demás. Abajo, cuántas hay a la vista, con «Abrir Tensión» (también en la hoja).
- **Parecidos**: con los vectores de F30 (`ItemVectorIndex.similarPairs`), fuera del hilo de la
  interfaz, entre los documentos a la vista (a lo sumo 200), con un mínimo de 0,6, dos por
  documento y 30 en total, sin lo ya vinculado en ningún sentido —también lo que «Más fuertes» no
  dibuja: la fuente lee los vínculos (`mapSimilarSource`)—. Una línea punteada con su «≈»; tocarlo
  ofrece «Vincular» (un «relacionado»), «Elegir el tipo» o «Ahora no»: nunca vincula sola
  (decisión C), y lo vinculado deja de proponerse en el acto. Sin el modelo, la capa lo dice y
  lleva a descargarlo.
- **Estudio**: tiñe cada documento con la lectura de las tarjetas del Resumen
  (`boardCardsProvider`), con una insignia que se lee sin el color —anillo vacío, la cuenta de hoy
  o ✓— y su leyenda; en la Red, en Radial y Árbol y en la lista.
- **⚲ Buscar** (`map_search_delegate.dart`), arriba: el índice del motor, en memoria; cada
  resultado dice dónde está. Elegir uno deja `MapShowTopic` o `MapShowDocument` tal como estaban,
  y el lienzo vuela, abre la ficha y **lo marca con un pulso** (`MapPulse`; sin animaciones, solo
  el anillo). El pulso vale para todo lo que se pide de afuera.
- **Se exporta lo que se ve** (decisión G): la burbuja, el rayo, los parecidos punteados y el
  estudio, en el SVG; el PNG ya es la captura.
- **Con el lector de pantalla**: cada capa es un interruptor con su nombre, y cada cambio se anuncia
  («Contradicciones: prendida»); un documento con Estudio dice cómo va, el «≈» nombra los dos
  documentos y cuánto se parecen, la burbuja dice cuántos tiene, y la búsqueda anuncia cuántos
  resultados hay.
- **Lo de F18 se conserva**: los topes 60/300/200, el layout en otro isolate y el caché del gesto.
  `map_canvas_view.dart` creció lo justo: las capas tienen su pieza (`canvas_layer_state.dart`,
  `canvas_layer_feeds.dart`, `canvas_layer_notes.dart`, `map_layer_marks.dart`).
- **Verificado:**
  - analyze en 19, la línea base;
  - 1.914 pruebas del Mapa, la app, la base, el chat y las relaciones, y 2.723 de las creaciones,
    las tarjetas y Organizar (13 salteadas, como siempre);
  - a 360 dp con la letra al doble, en claro y en oscuro, con la hoja de las capas y todas
    prendidas: la leyenda de Estudio desbordaba y ahora baja de renglón;
  - murieron las 23 mutaciones. Sobrevivía «Parecidos compara sin el modelo»: la prueba se quedaba
    de lejos, sin documentos; se sumó la de la capa prendida de antes, sin el modelo y con
    documentos a la vista. Entre las otras: la burbuja que se ve apagada, el rayo sin su capa,
    «Vínculos» apagada que sigue dibujando, el desborde que no suma sus vínculos con la burbuja,
    un parecido ya vinculado, sin tope por documento, la fuente que no deja afuera lo vinculado,
    la elección que no se recuerda, «Estudio» que lee apagada, el anuncio equivocado, la búsqueda
    que pide un tema como documento, el pulso que no late y alejarse de la burbuja hacia los
    temas.
- **Queda para el paso 6 (el cierre):**
  - la suite entera y la medición en el emulador de los gestos con las capas prendidas, contra la de
    F18 —la burbuja suma un nodo de lejos; Parecidos compara en otro isolate—;
  - la decisión 90 en arquitectura y la GUÍA de «El Mapa» reescrita de punta a punta;
  - mirar en el teléfono la hoja de las capas y el «≈» con la letra al doble;
  - la burbuja dibuja los 200 documentos sin tema más nuevos: buscar uno más viejo vuela a ella, pero
    no lo encuentra dibujado.
