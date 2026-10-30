# F46 — El Índice: lo procesado, con sus capítulos, como el índice automático de Word

> **Estado: PARA APROBAR.** Pedido del dueño, el 30/10: *"agregar en la pestaña de Estudiar,
> debajo de la sección de Procesado, una nueva sección llamada Índice … algo parecido a cuando yo
> hago en Word … un índice dinámico"*. Ajustes del mismo día:
>
> - solo los **documentos** (una página web o un libro, en cualquier formato), sacados de
>   **Procesado**;
> - si un documento es solo texto o imágenes, el **texto completo** o el **título de las
>   imágenes**;
> - **nunca** un resumen, una síntesis ni palabras clave;
> - que respete **la jerarquía, los nombres, los títulos y los temas**, y que sea dinámico,
>   elegante e interactivo, con cientos o miles de documentos.
>
> Se construye **después de F44 y F45**. Usa dos cosas de F45: los títulos que la IA marca al triar
> un PDF (decisión B) y el lector único del texto (mejora 12), que es donde se abre cada entrada.

## La idea

En Word, un texto con «Título 1», «Título 2» y «Título 3» genera un índice con sus páginas exactas,
que se actualiza con un toque. **El Índice hace eso con toda la biblioteca procesada, y sin el
toque**:

- cada documento procesado, con sus capítulos y subcapítulos en su orden y su nivel;
- agrupado por los temas, en su árbol;
- cada entrada lleva a su lugar exacto;
- se arma y se corrige solo cuando algo llega a Procesado, se renombra, se edita, se vuelve a
  triar o se borra.

## De dónde sale cada entrada

Solo de la sección **Texto** de cada documento procesado y de sus **Imágenes**. Del resumen, la
síntesis, las palabras clave, las notas y los fragmentos no sale nada.

| Lo que es | De dónde salen sus capítulos | Qué número lleva |
|---|---|---|
| **Word, EPUB, página web, Markdown o texto con títulos** | los títulos del texto (`#`, `##`, `###`…), que la extracción ya guarda | la página del texto procesado («pág. 3») |
| **PDF con marcadores** | sus marcadores, el índice que trae el propio PDF, con sus niveles | **la página real del PDF** («p. 47») |
| **PDF sin marcadores** | los títulos que la IA marcó al ordenar el texto al triar (F45, decisión B), comprobados palabra por palabra | la página del PDF donde cae |
| **Un texto sin títulos** (una transcripción, una nota larga, un artículo plano) | una sola entrada, **«Texto completo»**, que abre el texto desde el principio | — |
| **Solo imágenes** | una entrada por imagen, con **su título** | su lugar en la galería |

- **Los niveles se respetan tal cual**, solo corridos para que el primero sea el 1: un documento que
  empieza en `###` no queda colgando.
- **Lo que no es un título no entra**: un `#` dentro de un bloque de código, un título vacío o los
  encabezados repetidos de cada página (que la decisión B de F45 ya saca).
- **El título de una imagen** es el que traía la fuente: el texto alternativo o el epígrafe de la
  página web o del libro. Si no traía ninguno, el nombre de su archivo, limpio («Mapa del Imperio
  romano», no `mapa_imperio-romano_02.jpg`). Se puede renombrar con un toque largo, y el Índice se
  actualiza.

## Cómo se ve

En **Estudiar**, debajo de **Procesado**, un destino nuevo, **Índice**, con su ícono de lista
numerada.

**Arriba:**

- el buscador, **«Buscá un capítulo»**: filtra mientras se escribe, sin acentos ni mayúsculas, y
  **conserva la jerarquía**: un capítulo que coincide se ve con su documento y su tema arriba, y lo
  buscado resaltado;
- **«Por tema · Por documento»**:
  - **por tema** (lo primero): el árbol de los temas, como en el Atlas, con sus documentos y los
    capítulos de cada uno. Un documento con dos temas está en los dos y dice «también en
    Roma». Los que no tienen tema van al final, en **«Sin tema»**;
  - **por documento**: todos de la A a la Z, o los más recientes primero;
- **«Niveles: 1 · 2 · 3 · Todo»**, como en Word: hasta qué profundidad se despliega todo de una
  vez. Además, cada fila se abre y se cierra sola.

**Cada fila, con tipografía de índice de libro:**

- un **tema**: su nombre, en versalitas y con su color, y cuántos documentos tiene;
- un **documento**: su ícono de tipo (PDF, libro, web), el título en serif y, a la derecha,
  cuántos capítulos tiene;
- un **capítulo**:
  - su sangría por nivel, con una línea guía fina que une a los hermanos;
  - la numeración opcional («1», «1.2», «1.2.3»), que se prende y se apaga;
  - **la línea de puntos hasta la página**, como en Word: «El Concilio de Nicea ……… p. 47»;
- **«Nuevo»**: un punto discreto durante siete días en lo que llegó a Procesado.

**Mientras se desplaza:** el tema y el documento quedan fijos arriba mientras se recorren sus
capítulos, así nunca se pierde de qué libro es lo que se ve.

**En una pantalla ancha (la computadora, una tableta apaisada):** dos paneles, el Índice a la
izquierda y el documento a la derecha. Tocar un capítulo lo abre al lado, sin dejar el Índice.

**Cuando algo cambia:**

- lo que llega aparece en su lugar, con un brillo suave;
- lo borrado se va;
- lo renombrado cambia;
- todo sin perder lo que se tenía desplegado ni la posición.

Con «sin animaciones», sin brillo.

## Qué se hace con una entrada

- **Tocar**: abre el texto del documento en el lector único (F45, mejora 12) **justo en ese
  título**, que se resalta un momento. En el teléfono, «atrás» vuelve al Índice donde estaba.
- **Mantener apretado**:
  - «Abrir en el original»: el PDF en esa página, o la página web en ese título;
  - «Preguntar al chat»: una conversación sobre ese capítulo, con su texto;
  - «Copiar el título»;
  - en una imagen, «Renombrar».
- **«Descargar el índice»** (⋮ de arriba): el índice que se está mirando, con los filtros y los
  niveles elegidos, en **PDF** (con los puntos y las páginas, listo para imprimir) o en
  **Markdown**.

## Escalable: miles de documentos sin esperar

- **Una tabla propia, `processed_headings`**, derivada: documento, nivel, título, título sin
  acentos para buscar, su lugar (la parte, la página y la posición) y su orden. Un libro de 300
  capítulos son 300 filas; mil libros, 300.000 filas, poco para SQLite.
- **Se escribe en la misma operación que el texto**: cuando se guarda, se edita, se vuelve a triar
  o se borra la sección Texto de un documento, se rehacen sus filas en la misma transacción, **y
  solo las de ese documento**. Así el Índice nunca queda atrasado ni a medias. Al borrar el
  documento, se van con él.
- **Lo que no se guarda dos veces:** el nombre de un documento y sus temas se leen de donde ya
  están. Renombrar o cambiar de tema se ve al instante, sin tocar `processed_headings`.
- **Lo que ya está procesado** se indexa una vez, al actualizar la app, **por tandas y en segundo
  plano**, con un punto de retome (si se cierra la app, sigue desde ahí). Mientras tanto, el Índice
  muestra lo que ya tiene y una línea con cómo va.
- **La pantalla nunca trae todo:**
  - el árbol se arma de a lo que se ve: los temas con sus cuentas en una sola lectura, y los
    capítulos de un documento solo al desplegarlo;
  - la búsqueda va por un índice de texto (FTS5) y devuelve las coincidencias con sus padres;
  - la lista se dibuja de a lo que entra en la pantalla.
- **Nada se le pide a la IA ni a internet** para armarlo: sale todo de lo que ya está guardado. La
  IA solo interviene antes, al triar un PDF sin marcadores (F45, decisión B).

## Decisiones (se pueden cambiar mientras no se llegue a su paso)

- **A. Un destino propio, «Índice», en Estudiar, justo debajo de Procesado.** *Alternativa:* una
  pestaña dentro de Procesado. No la recomiendo: el Índice recorre todo, y adentro de Procesado
  quedaría escondido detrás de la lista.
- **B. Un PDF usa primero sus marcadores** (los puso el autor y traen la página real), y si no
  tiene, los títulos que marcó la IA al triar.
- **C. Cada capítulo lleva su número de página**: la real en un PDF y la del texto procesado en
  los demás (la misma «Página 3 de 6» del lector). En Word también es la página del texto que se
  está mirando.
- **D. Un documento con varios temas aparece bajo cada uno**, marcado «también en…».
  *Alternativa:* solo bajo el primero. No la recomiendo: el que lo busca por el otro tema no lo
  encontraría.
- **E. Las imágenes guardan su título** (una columna nueva en `processed_images`), sacado de la
  fuente al triar y editable. Las que ya están toman el nombre de su archivo, limpio.
- **F. El Índice es derivado**: se puede borrar y rehacer entero desde Procesado sin perder nada,
  y de la Biblioteca no se toca nada (la regla de siempre).

## Pasos (cada uno, su commit y su push)

**Ola 1, tres agentes en paralelo:**

1. **Los títulos** (decisiones B y E):
   - el lector puro de títulos de un texto, con sus niveles corridos y lo que no es un título
     afuera;
   - los marcadores de un PDF (`loadOutline` de `pdfrx_engine`, que ya está), ubicados en el
     texto;
   - el título de cada imagen al triar.
2. **Los datos** (decisión F):
   - `processed_headings` y la columna de las imágenes, con su migración;
   - la escritura en la misma transacción que el texto;
   - el relleno por tandas de lo que ya está, con su punto de retome;
   - las consultas del árbol, de un documento y de la búsqueda, con pruebas de escala (2.000
     documentos y 300.000 títulos) y `EXPLAIN QUERY PLAN`.
3. **La pantalla**, sobre un falso de los datos: el destino, el árbol por tema y por documento,
   los niveles, el buscador, las filas con los puntos y la página, lo fijo arriba, los dos paneles,
   «Nuevo» y lo que cambia en vivo.

**Ola 2:**

4. **Ir al lugar exacto** (decisión C): abrir en el lector único en ese título, abrir en el
   original en esa página, el toque largo («Preguntar al chat», «Copiar», «Renombrar») y
   «Descargar el índice» en PDF y Markdown.
5. **El cierre**: la decisión 92 en arquitectura, la GUÍA, la suite entera, la medición en el
   emulador con una bóveda grande y la APK al teléfono si la pedís.

## Lo que no entra (para que quede dicho)

- El resumen, la síntesis, las palabras clave, las notas y los fragmentos: el Índice es de los
  documentos.
- Lo que está solo en la Biblioteca, sin procesar: el Índice sale de Procesado.
- Los audios y los videos sin texto: entran por su transcripción, como «Texto completo».
- Inventar capítulos: si un documento no tiene títulos ni marcadores, es una sola entrada.

## Avance

(vacío: se llena con cada paso)
