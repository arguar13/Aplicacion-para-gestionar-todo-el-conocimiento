# F40 — La línea de tiempo, organizada con IA, interactiva y dentro de Organizar

> **Estado: APROBADO** (2026-10-26, *«Apruebo ese futuro plan»* en el chat, antes de escribirlo).
> Las decisiones de abajo van como se proponen. Se pueden cambiar mientras no se llegue a su paso.
> Pedido del mismo día, en el chat:
>
> - *"que esa pestaña también tenga una opción para que se organice con IA (además de
>   manualmente) así sea más rápido, tipo que detecte de un texto, archivo, audio o lo que fuere
>   fechas o años y los ponga ahí"*.
> - *"que sea inteligente y la línea de tiempo muy interactiva elegante y se pueda filtrar por un
>   documento en específico o un tema en específico o que aparezca todo ahí por defecto"*.
> - *"ponlo en el Botón de Organizar … dentro de Organizar, lo ubicaras arriba del Atlas"*.

## Lo que hay hoy

- **Una fecha es del elemento entero.** «Fecha del hecho» es una propiedad: un `PropertyValue`
  con año, mes, día, precisión (día, mes, año, década, siglo), «circa» y a.C. El mismo valor
  («476») lo comparten todos los elementos que lo usan. No sabe de qué parte del texto sale ni
  qué pasó en esa fecha: en la línea, el hecho se llama como el elemento.
- **No hay rango.** «De 1914 a 1918» no existe; el ancho sale solo de la precisión.
- **La IA no pone fechas.** `AutoPropertiesStep` trabaja solo con categorías de texto, y
  `assignProperty` crea un valor sin fecha, que la línea de tiempo ignora. Lo más parecido es el
  derivado «Cronología», que arma **una nota**, no hechos en la línea.
- **La pantalla** (`TimelineScreen`, ruta `/timeline`) se abre encima de la barra desde un ícono
  de la Biblioteca y desde el Atlas. El dibujo está bien resuelto: un solo `CustomPaint`, un árbol
  de intervalos, carriles, pellizco, rueda, teclado y 10.000 hechos medidos. Filtra por texto,
  tipo y etiqueta, y por la rama del Atlas. **No filtra por un documento ni por un tema elegido
  ahí**, y tocar un hecho solo abre el elemento.
- **«Organizar»** en el celular es una lista: Bandeja, Atlas, Mapa (`NavStep.organize`).
- **Lo que se reutiliza:**
  - el texto de cualquier elemento (`extractableRendition`: lo extraído de un PDF o un libro, la
    transcripción de un audio o un video, el OCR de una foto, la página web);
  - las partes con su posición (`splitIntoParts`), los modelos local y en la nube con sus
    reintentos (F39, paso 5);
  - la cola de organizar con sus pasos e interruptores, y las pasadas con deshacer (`ai_runs`);
  - la ubicación de una cita en el texto (`anchorDerivedClaims`);
  - abrir el documento en una posición (lo usan lo estudiado y los resaltados);
  - la barrita de resaltar de F38.

## Qué se construye

### 1. El hecho fechado, con su cita en el texto

Un documento cuenta muchos hechos: la biografía de Darwin tiene 1809, 1831, 1859 y 1882. Cada uno
es un **hecho fechado** (`dated_events`, esquema v44), con:

- **un título corto** («Publica *El origen de las especies*»);
- **la fecha**, con la misma forma que «Fecha del hecho» (precisión, circa, a.C.) y, si hace falta,
  **una fecha de fin** («1914–1918»);
- **de dónde sale**: el elemento, su texto (`renditionId`), la posición y la cita (como
  `study_marks`), para abrir el documento justo ahí;
- **quién lo puso**: la persona o la IA, con su pasada (`aiRunId`), así deshacer una pasada lo
  saca y editarlo lo vuelve de la persona.

Va a la papelera con su elemento, viaja en la copia y en la unión de bóvedas, y entra en los
censos de las tablas (lo que pide cada tabla nueva).

**«Fecha del hecho» sigue igual** y se ve en la misma línea: es la fecha del elemento entero (una
carta de 1810). Un hecho fechado es una fecha **dentro** de un documento.

### 2. En «Organizar», arriba del Atlas

- La línea de tiempo pasa a ser un destino de la barra: **Bandeja · Línea de tiempo · Atlas ·
  Mapa**. En una pantalla ancha va en el riel, en el mismo orden.
- «Ver en la línea de tiempo» del Atlas lleva a ese destino con la rama elegida como filtro.
- **Decisión A**: sale el ícono de la Biblioteca. Ya tiene su lugar fijo, y la barra de la
  Biblioteca queda más limpia.

### 3. Todo por defecto, o un tema, o un documento

- Arriba, una fila de chips: **Todo** (el de entrada), **Tema ▾** y **Documento ▾**. Cada uno abre
  una hoja con buscador. Con un documento elegido, se ven solo sus hechos y la línea encuadra su
  época.
- Siguen la búsqueda y el panel de tipo y etiquetas. Un chip con «×» dice qué filtro está puesto.
- Desde el detalle de un elemento con hechos, **«Ver en la línea de tiempo»** abre la línea
  filtrada por ese documento.

### 4. Una línea de tiempo interactiva y elegante

- **Tocar un hecho abre su ficha**, sin salir de la línea:
  - la fecha y el título;
  - la cita con la fecha resaltada;
  - de qué documento sale y ✨ si lo puso la IA;
  - **«Abrir en el documento»**, que lleva al lector justo en esa cita;
  - **Editar** y **Quitar**.

  Un hecho de «Fecha del hecho» abre el elemento, como hoy.
- **Cada documento con su color** cuando se ven varios, con la leyenda de los colores. Así una
  época se lee de un vistazo: qué viene de qué.
- **Los rangos se dibujan como tramos**: 1914–1918 de punta a punta, con el inicio y el fin
  marcados.
- **Un mini mapa** arriba del eje muestra dónde se juntan los hechos. Tocarlo o arrastrarlo salta
  a esa época.
- **Más gestos:** doble toque acerca ahí, y un hecho mantenido muestra su cita. Las transiciones
  del encuadre son animadas (al filtrar, al «Mostrar todo»).
- Se mantienen las cifras de hoy: 10.000 hechos sin trabarse, en un solo `CustomPaint`.

### 5. A mano, más rápido

- **«+ Agregar un hecho»** en la línea: se elige el documento (o ninguno), la fecha con el
  formulario de siempre, más la fecha de fin, y el título.
- **En la barrita de resaltar** (texto extraído, lector, PDF, página web), **«A la línea de
  tiempo»** convierte lo seleccionado en un hecho: la cita ya queda puesta. Si la selección trae
  una fecha («en 1859», «siglo XV», «hacia el 44 a.C.»), viene cargada, y solo falta confirmar el
  título.

### 6. Con la IA

- **El detector, en dos tiempos:**
  1. **Sin IA, y rápido.** Un buscador de expresiones de tiempo en español e inglés marca las
     oraciones que pueden tener una fecha: años, «siglo XIX», «la década de 1920», «44 a.C.»,
     «hacia 1500», «de 1914 a 1918», meses con día.
  2. **Con IA.** Solo esas oraciones, con un poco de contexto, van al modelo. Así un libro de 300
     páginas no se manda entero, y Gemma, con su ventana chica, alcanza. Por cada hecho, el
     modelo devuelve una línea: fecha normalizada, precisión, si es circa, fin si lo hay, título
     corto y la cita textual.
- **Nada se inventa:**
  - la cita tiene que estar en el texto (se ubica como las de los derivados);
  - la fecha tiene que leerse con el analizador estricto;
  - si la cita trae una fecha escrita, tiene que coincidir con la devuelta.

  Lo que no pasa estas pruebas se descarta. Se evitan repetidos: misma fecha y misma cita, o un
  hecho que la persona ya puso o ya quitó.
- **Dónde corre:**
  - **«Organizar con IA»** en la línea de tiempo: elige qué recorrer —**todo**, **un tema** o
    **un documento**— y lo pone en la cola. El avance se ve en la línea y en «Lo que hizo la IA»
    (F39, paso 6).
  - **Un interruptor nuevo** de la IA que organiza sola: **«Fechas para la línea de tiempo»**.
    Prendido, todo lo nuevo sale ya con sus hechos.
  - **En el detalle**, «Buscar fechas con IA» para ese elemento.
- **Decisión B**: la IA **pone los hechos directamente**, marcados con ✨, sin pasar por la
  Bandeja. Como cada uno trae su cita, se revisa en la propia línea, y deshacer la pasada los
  saca todos. Una revisión previa de a uno sería lenta, y lo pedido es rapidez. Lo que la
  persona quita queda en la memoria de «no era», para que la IA no lo vuelva a poner.
- Una pasada cuenta sus hechos en «Lo que hizo la IA» («12 fechas») y se deshace como las demás.

## Decisiones

- **A.** El ícono de la Biblioteca sale. La línea de tiempo queda solo en Organizar y en los
  accesos del Atlas y del detalle.
- **B.** La IA pone los hechos directo, con ✨ y deshacer, sin revisión previa.
- **C.** «Fecha del hecho» queda como está. Las fechas de un elemento siguen siendo suyas, y los
  hechos dentro de un documento son la tabla nueva. No se migra nada.
- **D.** Los hechos fechados se piden en español y en inglés. Una fecha sin año («el martes
  siguiente») no se pone.

## Pasos (cada uno, su commit y su push)

1. La línea de tiempo en Organizar, arriba del Atlas (decisión A), con los accesos del Atlas y
   del detalle.
2. El detector sin IA, el analizador estricto de fechas y el pedido al modelo, con su lectura.
   Todo puro y probado aparte.
3. Los datos: `dated_events` (v44, después del v43 del paso 6 de F39), con papelera, copia,
   unión de bóvedas y deshacer de pasadas. La línea lee los dos orígenes.
4. Los filtros Todo · Tema · Documento, la ficha del hecho, «Abrir en el documento», los colores
   por documento, los rangos, el mini mapa y los gestos nuevos.
5. A mano: «+ Agregar un hecho» y «A la línea de tiempo» en la barrita de resaltar.
6. Con la IA: el paso de la cola, el interruptor, «Organizar con IA» con su alcance y «Buscar
   fechas con IA» en el detalle.
7. Cierre: GUIA_DE_USO, la decisión en `docs/arquitectura.md`, CONTEXTO y el «Avance»; suite
   entera y `verify_commit`; la APK al teléfono si la pedís.

## Avance

- **Pasos 1 y 4, parte sin datos nuevos — hecho.** La línea de tiempo es un destino de Organizar,
  arriba del Atlas: **Bandeja · Línea de tiempo · Atlas · Mapa**, en la lista del celular y en el
  riel. El ícono de la Biblioteca salió (decisión A).
  - Es la rama `ShellBranch.timeline`, sumada al final del enum y del router para no correr índices.
  - **El filtro tiene un solo dueño**, `timelineFilterProvider`: un valor `TimelineFilter` con el
    recorte, la búsqueda y el panel, del que sale la consulta de la biblioteca. El Atlas («Ver en la
    línea de tiempo») y el detalle de un elemento con fechas lo fijan antes de navegar. Esa es la
    causa de fondo: la pantalla vive en el `IndexedStack` y no se vuelve a construir, así que el
    filtro no podía viajar por el constructor ni por la dirección.
  - Arriba, una fila de chips: **Todo** (de entrada), **Tema ▾** y **Documento ▾**, cada uno con
    una hoja con buscador. El filtro puesto se ve como un chip con «×», y se elige un recorte a la
    vez. Una rama del Atlas tiene su propio chip.
  - **El eje se mueve, no salta:** al filtrar y en «Mostrar todo», la vista se desliza hasta
    encuadrar lo que quedó (centro lineal, ancho geométrico). No se desarma mientras responde la
    consulta nueva y respeta las animaciones apagadas.
  - **Doble toque** acerca ahí, con el paso del «+». Se arma a mano para no retrasar el toque simple
    sobre un hecho.
  - **Mini mapa** sobre el eje, con la densidad de todo el rango y la ventana marcada: tocar
    desliza y arrastrar sigue al dedo. Se calcula una vez por lista de hechos: con 10.000 hechos
    no se recalcula al acercar ni al mover.
  - **Puerta para el paso 4 completo:** el lienzo entrega el evento entero al tocarlo y acepta
    `colorOf` para los colores por documento. Faltan la ficha del hecho, los rangos como tramos y
    la leyenda de colores, que dependen de los hechos fechados del paso 3.
  - Las 77 mutaciones mueren.
  - **Al integrarlo:** con el riel un poco más ancho, el cuerpo del detalle quedó más angosto que
    el estilo de cita más largo, y el desplegable «Estilo» se desbordó (7 pruebas de navegación).
    Se arregló en el desplegable mismo, en un commit aparte (`fix(citations)`): toma su ancho
    natural y nunca más que la línea, y si no entra se corta con «…». Lo fijan dos pruebas y dos
    mutaciones, las dos muertas.

- **Pedido durante el encargo: el detalle en blanco desde el Atlas — arreglado de raíz.** El
  material de una rama del Atlas abría en blanco el detalle de cada elemento. Pasaba desde
  cualquier pantalla que se abre encima de la barra (el material de un tema, la lectura, el mapa
  local…).
  - **Causa:** el detalle vivía dentro de la Biblioteca. Al empujarlo desde una ruta de la raíz,
    go_router apilaba un segundo shell con la misma clave de página.
  - **Arreglo:** el detalle se dibuja en el `Navigator` de la raíz, con una llave por router. Es
    un solo destino, igual desde todos lados, y va a pantalla completa, sin la barra de abajo,
    también desde la Biblioteca. La dirección `/library/:id` y el «atrás» por enlace directo
    siguen igual.
  - **Lo que no era:** la lista del material de una rama traía todo bien; la insignia «1» es la
    rama misma.
  - **Pruebas:** quedan fijados el recorrido completo (rama por etiquetas y por temas, fuente y
    nota, ida y vuelta) y el detalle abierto desde cada origen. Las 2 mutaciones mueren.
  - **Al irse del detalle a otra rama,** ahora el detalle se suelta. Las pruebas que lo hacen
    dejan correr el temporizador con el que drift cierra sus consultas; una de ellas es la del
    enlace a la línea de tiempo.
  - **Prueba frágil corregida, en un commit aparte:** en la tanda amplia, la de la nota guardada
    en una transacción esperaba 50 ms de reloj real a que terminara el generador de duplicados.
    Ahora espera a que termine de verdad.

- **Paso 2 — hecho.** El detector de fechas, el analizador estricto y el pedido al modelo: todo
  puro y probado aparte, sin tocar el esquema ni la pantalla.
  - **El detector** (`findTemporalExpressions`) marca, en español y en inglés, años, «siglo XIX»,
    «la década de 1920», «44 a.C.», «hacia 1500», rangos y meses con día.
    - No toma por año una cantidad, una página, un teléfono ni una hora.
    - «Los años 20» solo se lee si hay cerca un año que diga el siglo (decisión D).
  - **El analizador** (`parseNormalizedDate`) lee la fecha normalizada que devuelve el modelo
    (`1859`, `1809-02-12`, `s. XIX`, `década 1920`, `c. 1500`, `1914..1918`). Rechaza lo ambiguo o
    lo que no existe: mes 13, 31 de febrero, año 0, siglo 0, un año con signo.
  - **El selector** arma los pasajes (la oración fechada más la anterior, del mismo párrafo) y los
    reparte en pedidos del tamaño que acepta el modelo elegido. Un texto sin fechas no manda nada.
  - **La tarea del modelo**, `datedEventsOf`:
    - pide una línea `HECHO` por hecho;
    - se ajusta a la ventana como `markPart`;
    - deja dicho cuántos pasajes leyó.
  - **La lectura de la respuesta** (`parseDatedEventsReply`) descarta lo que el texto no dice:
    ubica la cita en el texto entero y comprueba que la fecha, y su fin, sean los que la cita
    escribe.
  - El detector recorre 3 millones de caracteres con 100.000 expresiones en unos 4 s.
  - 344 pruebas nuevas; las 98 mutaciones mueren.

- **Paso 3 — hecho.** Los hechos fechados ya tienen dónde vivir: `dated_events` (esquema v44),
  con título, fecha, fin opcional, la cita en el texto y quién lo puso.
  - **La fecha** tiene la forma de «Fecha del hecho», que no se toca ni se migra (decisión C). El
    circa es del hecho entero.
  - **Se va con su elemento y con su texto.** Al soltar un texto, el hecho viaja en la papelera
    del contenido y vuelve con él; trae su pasada si sigue existiendo.
  - **Al volver a extraer,** la cita se reubica por su fragmento. Si ya no está, el hecho conserva
    su fecha y su título, sin «Abrir en el documento».
  - **Viaja en la unión de bóvedas:**
    - entra por id, o por la misma fecha y la misma cita;
    - se re-apunta al texto que guardó la cita;
    - respeta lo que la persona quitó y lo que adoptó.
  - **La IA:**
    - `addFromAi` pone los hechos de una pasada con su pasada, su fragmento y la marca ✨, sin
      repetir lo que ya está ni lo que la persona quitó.
    - Editar un hecho lo vuelve de la persona.
    - Quitar uno de la IA lo anota en la memoria de «no era» (el elemento, la fecha de inicio y la
      cita normalizada), y se puede deshacer.
  - **«Lo que hizo la IA»** cuenta las fechas («12 fechas», `dates_created`). Deshacer la pasada
    saca las que siguen siendo de la IA.
  - **La línea de tiempo:** `TimelineEvent` distingue los dos orígenes, y `watchEvents` los
    combina con los mismos filtros y la papelera. El fin define `from` y `to`.
  - **Entrada del repositorio:** recibe `DatedEventInput`, que lleva la forma citada. El paso 6
    arma uno desde cada `DatedEventDraft` del paso 2.
  - **Lo que no cuenta todavía:** la vista previa de la fusión no muestra cuántos hechos trae,
    igual que pasa con lo estudiado.
  - **Cifras:** 10.000 hechos fechados se leen en menos de 3 s. Las 88 mutaciones mueren.

- **La vista previa de unir bóvedas cuenta los hechos fechados y lo estudiado — hecho.** Era lo
  que el paso 3 había dejado sin contar.
  - **Causa:** cada tabla de la unión necesita su cifra en cuatro lugares escritos a mano: la
    vista previa, `hasNothingNew`, el resultado y `changedNothing`. Ningún censo los vigilaba, y
    `study_marks` y `dated_events` quedaron afuera.
  - **Efectos:**
    - una copia que solo traía hechos o marcas se anunciaba «nada nuevo, no hace falta unirla»;
    - si igual se unía, el resultado decía «no cambió nada».
  - **Arreglo:** la regla de qué entra (`SetUnionRules`) es una sola, y la comparten la unión y la
    vista previa, así que no pueden discrepar. La vista previa la corre sin escribir (`dryRun`) y
    sin crear nada en la conexión.
  - **Censo:** `merge_counts_census_test` hace fallar cualquier tabla nueva de la unión que no
    tenga su cifra en la vista previa y en el resultado, o el motivo de por qué no.
  - **Pruebas:** 18 de paridad entre la vista previa y lo que la unión escribe; las 23 mutaciones
    mueren.

- **Las pruebas que fallaban con la máquina cargada, deterministas — hecho.**
  - **«El silencio vence»** (`cloud_http_test`) medía con el reloj real: 150 ms de silencio contra
    pedazos cada 80 ms. Ahora el tiempo lo maneja un `FakeAsync`, que fija el borde exacto: a
    149 ms sigue vivo y a 150 vence.
  - **La bajada de Gemma** esperaba el pedido con vueltas de 5 ms. Ahora lo espera de verdad.
  - **La compactación de la bóveda** medía la memoria del proceso entero, que se ensucia con lo
    que corre al lado. Ahora mide dónde vive la copia de trabajo de `VACUUM`: el archivo temporal
    en disco, que es justo lo que decide `temp_store = FILE`. El control, sin el PRAGMA, deja el
    temporal en cero.
  - **Estabilidad medida:** con 14 procesos quemando CPU y uno escribiendo en el disco, antes
    fallaban 3 de 5 corridas y ahora pasan 5 de 5.
  - **Mutaciones:** las 6 mueren. Entre ellas, sacar el PRAGMA y no reiniciar la cuenta del
    silencio con cada pedazo.

- **Paso 6 — hecho.** La IA busca las fechas de los textos y las pone directo en la línea, con su
  cita y su ✨, sin pasar por la Bandeja (decisión B).
  - **El paso de la cola** (`AutoDatesStep`) lee el mismo texto que abre la lectura y arma los
    pedidos al tamaño del modelo elegido en ese momento.
    - Un texto sin fechas no usa el modelo ni deja una pasada vacía en «Lo que hizo la IA».
    - Guarda al terminar cada pedido: los hechos aparecen a medida que se leen.
    - Dice cuántas partes lleva, para el porcentaje y los tokens de «Ahora».
    - **Retomable:** si el modelo se corta a mitad de un libro, la cola retoma en la misma pasada
      desde el pasaje donde quedó, sin volver a pagar lo leído. Si el texto o la forma cambiaron
      mientras esperaba, empieza de cero. Es memoria de la sesión, y `addFromAi` no duplica si se
      perdió.
    - Un libro largo (40.000 caracteres o más) se parte en otro hilo con `compute`, para no trabar
      la interfaz.
  - **La cola tiene su fila de fechas** (`AiRunScope.dates`, `findDates`): sin interruptores de
    tipo, sin el modelo de vínculos, sin cargador. Cada elemento es una pasada de solo fechas, que
    se deshace y no cuenta como haberlo organizado. Respeta la pausa y los cortes del paso 5 de F39.
  - **El interruptor «Fechas para la línea de tiempo»** (`ai_organize_dates`) viene prendido, como
    los demás: todo lo nuevo se organiza ya con sus fechas. Apagado, igual se pueden pedir a mano.
  - **«Organizar con IA» en la línea:** una hoja elige **Todo · Tema · Documento** (cualquier
    documento listo, tenga fechas o no). El recorte puesto viene preelegido, y una rama del Atlas es
    una opción más. La franja de debajo de los chips dice cuántos elementos van y cuántas fechas
    salieron, se puede cancelar, y los hechos aparecen solos. Sin modelo, clave o cuota, el aviso
    dice qué falta, como las otras acciones de la IA.
  - **«Buscar fechas con IA»** en «Más» del panel del elemento, solo si está listo y tiene texto.
    Las notas de bloques no pasan por «Más» y quedan cubiertas por el interruptor y por la línea.
    - **Arreglo de raíz:** la hoja «Más» ahora se desplaza; con la fila nueva se desbordaba 30 px
      en pantallas bajas.
  - **Pruebas:** del paso, la cola, Ajustes, «Más», la hoja, la franja y el cableado, todas con un
    modelo falso. Las 106 + 7 mutaciones mueren; tres equivalentes se sacaron del código. La tanda
    amplia de la integración: 4.748 pruebas en verde.

- **El detector ya no se frena con las décadas cortas — hecho.** La prueba del libro entero falló
  una vez con la máquina cargada, y detrás había una causa real.
  - **Causa:** para ponerle siglo a «los años 20», `_resolveShortDecades` comparaba cada década con
    todos los años del texto. Un libro que nombra miles de décadas tardaba al cuadrado: con cuatro
    veces más texto, doce veces más tiempo.
  - **Arreglo:** los años ya vienen en orden y sin solapes, así que los candidatos son a lo sumo
    dos, el último de antes y el primero de después. Un solo recorrido los encuentra. A igual
    distancia gana el de antes, como siempre.
  - **La prueba mide cómo crece, no cuánto tarda:** lo mejor de tres, intercalado, de un texto y
    de otro cuatro veces mayor, con décadas cortas. Con la máquina cargada, los dos tamaños se
    frenan juntos. Hoy da 3,8 y el recorrido viejo 11,8; el límite es 7.
  - **Pruebas nuevas:** qué año elige la década (el de después si está más cerca, el de antes si
    empatan, el último de varios) y el borde de 1.500 caracteres de cada lado. Las 8 mutaciones
    mueren, entre ellas volver al recorrido viejo.

- **Pasos 4 (resto) y 5 — hecho.** La ficha del hecho, los colores por documento con su leyenda,
  los tramos, la cita al mantener apretado, «Agregar un hecho» y «A la línea de tiempo» en la
  barrita de resaltar.
  - **La ficha del hecho:** tocar un hecho fechado abre una hoja, sin salir de la línea.
    - Fecha, título, ✨ si lo puso la IA, y la cita con la fecha resaltada (en negrita y con fondo,
      no solo por color). La ubica `locateEventDate`: la expresión de la cita que lee lo mismo que
      el hecho; si la cita no la escribe, no resalta nada.
    - De qué documento sale; tocarlo abre su detalle.
    - **«Abrir en el documento»** va al lector justo en la cita, por el mismo camino de las
      tarjetas y las notas extraídas. Sin ancla no se ofrece, y si el texto cambió la ficha lo dice.
    - **Editar** abre el formulario y guardar adopta el hecho. **Quitar** avisa con «Deshacer», que
      lo devuelve con su pasada y olvida el «no era».
    - Una «Fecha del hecho» sigue abriendo el elemento.
  - **Colores por documento:** con varios documentos a la vista, cada uno tiene su color (24 en la
    paleta), siempre el mismo, porque sale solo del id. Se ajusta a cada tema hasta 3:1 de
    contraste contra el fondo y la superficie. La leyenda «Documentos» arranca plegada, ordena por
    cantidad de hechos, resume el resto en «y N más», y tocar una fila recorta la línea.
  - **Tramos:** un hecho con fin va de punta a punta, con el cuerpo tenue y las dos puntas firmes,
    en el mismo `CustomPaint`. 10.000 hechos, un tercio tramos, siguen dibujando menos de 400 cajas.
  - **Mantener apretado:** título, fecha, cita y documento, sin abrir la ficha; dura 6 s con el
    dedo y va arriba si debajo no entra.
  - **El formulario** (alta y edición): documento, qué pasó, la fecha con el formulario de siempre
    y un interruptor de tramo con «Hasta», que no ofrece «aproximada». Valida con `DatedEventInput`
    (`problemKind`, traducido por campo).
    - **Sin documento:** `item_id` sigue obligatorio, porque todo cuelga del elemento (papelera,
      copia, unión de bóvedas, deshacer). El hecho va a la nota viva «Hechos sueltos», que se crea
      al guardar la primera vez y se reutiliza.
  - **«Agregar un hecho»** en la barra de arriba (con texto desde 420 dp, ícono en un teléfono
    angosto) y en el estado vacío; el documento del recorte viene elegido.
  - **«A la línea de tiempo» en la barrita**, en el texto extraído, el lector, el PDF y la página
    web: la cita queda con su forma de texto y sus posiciones del contenido crudo, como los
    resaltados. Si trae fecha, viene cargada (con su fin si es un rango); sin fecha, el formulario
    abre vacío. El aviso trae «Ver», a la línea recortada a ese documento.
  - **De paso se corrigió:** la lista de «Documento» usaba el título del hecho y no el del
    documento; dos hechos del mismo documento y fecha compartían clave de semántica; el hover
    comparaba solo por elemento y fecha; `AnimatedSize` con duración cero tiraba una excepción.
  - **Pruebas:** más de 300 nuevas. De 101 mutaciones mueren 100; la otra es equivalente (cerrar
    la barrita antes del formulario, que el modal ya cierra).
  - **Integración con el paso 6:** en la barra conviven ✨ «Organizar con IA» y «Agregar un
    hecho»; la franja de avance y la leyenda de documentos, cada una en su lugar.

- **Cuadernos, en «Organizar» debajo del Mapa; «Preguntar», el chat directo — hecho.** Pedido del
  dueño durante F40, con dos capturas: el botón del medio abría una lista con Chat y Cuadernos.
  - Un cuaderno junta un grupo de elementos, que es una forma de ordenarlos: va al final de
    «Organizar» (Bandeja · Línea de tiempo · Atlas · Mapa · Cuadernos).
  - Con el chat solo, el botón del medio sigue la regla de F34: se ve como el chat («Chat», su
    ícono) y lo abre directo, sin lista. La clave `navStepAsk` sale, y `NavStep.ask` pasa a los
    pasos de un destino solo. En la web, sin chat, la barra queda con cuatro pasos.
  - Pruebas de la lista, de la barra, del riel y de la web. De las mutaciones mueren las dos
    observables; la tercera, darle aspecto propio a «Preguntar», es código que con un solo destino
    no se ejecuta.
