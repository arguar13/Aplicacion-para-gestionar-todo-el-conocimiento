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
