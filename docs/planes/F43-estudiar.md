# F43 — «Estudiar»: un estudio para crear sobre lo procesado

> **Estado: APROBADO** (2026-10-28, «aprobado» en el chat, con las ilustraciones con IA de la
> decisión H y su aviso detallado —ver «H en detalle»—). En construcción.
>
> Pedido del dueño, con catorce capturas de NotebookLM (la pestaña «Studio», sus hojas de
> personalizar y cinco resultados abiertos) y una de Repasar de hoy: *"vamos a cambiar eso para
> hacerlo aun mas potente, no vamos a perder nada, solo vamos a potenciarlo … Ese botón se llamará
> en vez de Repasar, «Estudiar» … todo tiene que venir de la sección Procesado, nada de
> Biblioteca … Vamos a seguir el estilo exacto de la segunda imagen y con la misma disposición"*.

## Lo que hay hoy (y no se pierde)

- **La barra:**
  - Biblioteca · Organizar · Chat · Repasar · Ajustes.
  - Organizar abre su lista con Bandeja, Procesado, Atlas, Línea de tiempo, Mapa y Cuadernos.
- **Repasar:**
  - arriba, la racha, las estadísticas, «Crear tarjetas con IA» y exportar a Anki;
  - «¿Qué estudiar? Todo · Cambiar»;
  - la tarjeta «Para hoy» con Nuevas, Aprendiendo, Por repasar y «Empezar»;
  - abajo, «Mis tarjetas» y «Estadísticas».
- **Lo que la app ya sabe hacer y se reutiliza:**
  - el resumen, la síntesis y las palabras clave de un documento procesado (F36 y F41), en rosa
    en todas las oraciones (decisión 85);
  - escuchar con el amarillo en vivo sobre lo que suena y un visor que sigue la lectura
    (decisiones 86 y F39);
  - las tarjetas y su repaso con la tarjeta que se da vuelta (F31);
  - el quiz con distractores reales (F20);
  - la IA elegida (Gemma en el teléfono, o Gemini, OpenAI o Claude con sus cuentas, F32), con la
    cola de fondo y lo largo por partes (F21 y F27).

## Qué se construye

### 1. La barra: «Estudiar» en lugar de «Repasar», y el chat un lugar a la derecha

```
Biblioteca · Organizar · Estudiar · Chat · Ajustes
```

- **Organizar** se queda con lo que ordena: **Bandeja** y **Atlas**. El pedido no nombra al Atlas,
  así que no se mueve (ver la decisión A).
- **Estudiar** abre su lista, igual que Organizar, en este orden:
  1. Procesado
  2. Cuadernos
  3. Línea de tiempo
  4. Mapa
  5. **Repasar**
- La insignia de las tarjetas para hoy pasa al botón **Estudiar**, sumada como hoy suma Organizar
  la de la Bandeja.
- En la computadora, el riel de la izquierda muestra todos los destinos en el mismo orden.

### 2. Repasar, como el «Studio» de NotebookLM

```
┌──────────────────────────────────────────┐
│ Repasar                 🔥6  📈  ✨  ⇪   │  ← lo de hoy, igual
│ ╭──────────────────────────────────────╮ │
│ │ 📄 Éxodo — Comentario de Alonso   ▾  │ │  ← el selector (lo del óvalo naranja)
│ │    1 documento · 386 tarjetas         │ │
│ ╰──────────────────────────────────────╯ │
│ ┌ Para hoy ─ 20 · 6 · 6 ── ▶ Empezar ─┐ │  ← la de hoy, más compacta
│ ┌──────────┐┌──────────┐┌──────────┐    │
│ │ ¶ Texto  ││ ≡ Resumen││ ◆ Síntesis│    │  ← las tres de extraer
│ └──────────┘└──────────┘└──────────┘    │
│ ┌ ▭ Presentación ┐┌ ⊶ Mapa mental ───┐  │
│ ┌ ✦ Informes ────┐┌ ⧉ Tarjetas did. ─┐  │
│ ┌ ? Cuestionario ┐┌ ▥ Infografía ────┐  │
│ ┌ ☰ Tabla de datos ┐                    │
│ ─────────────── Lo creado ───────────── │
│ ▥ Éxodo: Liberación y Alianza        ⋮  │
│   1 fuente · Hace 4 días                 │
│ ☰ Análisis exegético del Éxodo       ⋮  │
│ ✦ Éxodo: el descubrimiento… ⟳ Generando │
│        Mis tarjetas  ·  Estadísticas     │
└──────────────────────────────────────────┘
```

- **El selector de arriba** reemplaza a «¿Qué estudiar? · Cambiar»: una píldora ancha y elegante
  con el ícono, el nombre y una línea de detalle.
  - Tocarla abre una hoja con buscador y cuatro pestañas: **Todo lo procesado**, **Documento**,
    **Cuaderno** y **Tema**.
  - Cada fila muestra cuánto tiene: tarjetas, creaciones y si ya tiene resumen.
  - Arriba van **los recientes**, los últimos cuatro que se eligieron.
  - **Todo sale de Procesado**: un documento es un procesado; un cuaderno, uno de los de F41, que
    ya solo guardan procesados; un tema, uno del Atlas, que F41 ya arma solo con lo procesado.
  - La Biblioteca no aparece en ningún lado.
- **El selector manda en toda la pantalla**: «Para hoy» cuenta lo de ese recorte, las tarjetas
  de crear trabajan sobre él, y «Lo creado» muestra lo suyo. Con «Todo lo procesado» se ve todo.
- **«Para hoy» no se pierde**: queda debajo del selector, en una sola franja con las tres cifras
  y «Empezar». «Mis tarjetas», «Estadísticas» y los íconos de arriba siguen igual.
- **Las tarjetas de crear**, con el estilo exacto de la captura: fondo apenas más claro que la
  pantalla, bordes muy redondeados, un ícono de color propio para cada una y el nombre.
  - Las tres de extraer van juntas en la primera fila, más compactas.
  - Las otras siete, de a dos; **Tabla de datos** queda sola, como en la captura.
  - En una pantalla ancha, tres o cuatro por fila.
- **«Lo creado»**, debajo, con lo más nuevo arriba. Cada fila lleva:
  - el ícono de su tipo, con su color;
  - el título, que pone la IA;
  - «N fuentes · Hace X días», o el tipo de informe como en la captura;
  - su menú ⋮: Renombrar, Volver a generar con otras opciones, Exportar o compartir, Ver fuentes
    y Borrar, que la manda a la papelera.
- **Mientras se genera**, la fila aparece enseguida con un brillo que recorre y «Generando…».
  Se puede salir de la pantalla: sigue en la cola, con el servicio en primer plano de F21.
  - Si falla, la fila dice por qué en una línea y ofrece «Reintentar».
  - Tocar una fila lista abre su visor (ver el punto 5).

### 3. La hoja de personalizar, una sola para todas

Tocar una tarjeta de crear abre su hoja, con el mismo esqueleto que las capturas:

- **Arriba:** el ícono, «Personalizar …» y la ✕ redonda.
- **En el medio**, solo las opciones de ese tipo (ver el punto 4), con las piezas de las
  capturas:
  - botones segmentados con ✓ («Menos · **Estándar** · Más»);
  - el desplegable **«Seleccionar idioma»**, en español por defecto;
  - **«Fuentes: N fuentes ▾»**, para destildar documentos del recorte elegido;
  - el campo **«Describí lo que querés crear»**, con un ejemplo de guía tenue;
  - **temas sugeridos** como fichas tocables («+ Moisés y Faraón»), sacados de las palabras
    clave y los temas del recorte.
- **Abajo, fijo:**
  - **«Uso de IA»**: una barra con lo ya usado hoy en la cuenta y, más oscuro, lo que estima
    esta creación. Sale de lo que ya cuenta F32. Con Gemma no hay cuota: dice cuánto puede
    tardar.
  - **«Generar más tarde»**: va a la cola de fondo y se hace cuando el modelo esté libre.
  - **«Generar ahora»**.
- **Lo último que se eligió en cada tipo se recuerda**: la próxima vez la hoja abre así.

### 4. Las diez tarjetas de crear y sus opciones

| Tarjeta | Opciones | Qué produce |
|---|---|---|
| **Extraer texto completo** | Fuentes | El texto procesado entero, con las palabras clave en rosa. |
| **Extraer resumen** | Fuentes | Las oraciones que el resumen marcó, en orden, con las palabras clave en rosa. |
| **Extraer síntesis** | Fuentes | Lo mismo con la síntesis. |
| **Presentación** | Formato (*Detallada* · *Del presentador*), Plantilla, Duración (*Corta* · *Estándar*), Idioma, Fuentes, Descripción | Diapositivas con su diseño; en «Del presentador», notas para decir. |
| **Mapa mental** | Idioma, Fuentes, Tema | Un árbol de ideas que se abre y se cierra. |
| **Informes** | Formato (*Interactivo* · *Documento*), Plantilla (*Resumen de aprendizaje*, *Guía de estudio*, *Documento informativo*, *Glosario*, o una propia con ✎), Idioma, Fuentes | Un informe con secciones; el interactivo trae preguntas para probarse dentro de cada sección. |
| **Tarjetas didácticas** | Número (*Menos* · *Estándar* · *Más*), Dificultad (*Fácil* · *Medio* · *Difícil*), Incluir imágenes, Idioma, Fuentes, Tema | Un mazo con las tarjetas de siempre. |
| **Cuestionario** | Número, Dificultad, Incluir imágenes, Tipos de pregunta (*Opción única*, *Selección múltiple*, *Completar espacios*, *Respuesta breve*), Idioma, Fuentes, Tema | Un cuestionario con la explicación de cada opción. |
| **Infografía** | Idioma, Orientación (*Horizontal* · *Vertical* · *Cuadrado*), Estilo visual (*Automático* y las plantillas, en un carrusel con muestra), Detalle (*Conciso* · *Estándar* · *Detallado*), Fuentes, Descripción | Una lámina con título, bloques, íconos, cifras y colores. |
| **Tabla de datos** | Idioma, Fuentes, Descripción (qué columnas) | Una tabla, como la de la captura. |

**Los tres de extraer no le piden nada nuevo a la IA**: usan el resumen, la síntesis y las
palabras clave que el documento procesado ya tiene, o los encolan si faltan. Por eso son
**vistas vivas** y no copias: si el documento cambia, lo extraído también, y un libro entero no
se guarda dos veces (ver la decisión E).

### 5. Cada resultado, con su visor propio

Todos comparten la barra de arriba de las capturas:

- ←;
- el título;
- la ficha **«Ver N fuentes»**, que abre el documento procesado;
- compartir o exportar, pantalla completa, ⋮ y ✕.

Cada uno tiene además lo suyo:

- **Texto completo, resumen y síntesis:**
  - **La lectura:** el texto limpio, con las palabras clave en rosa en todas las oraciones.
  - **El modo escuchar:**
    - un reproductor grande y elegante abajo: play o pausa, oración anterior y siguiente, una
      barra de avance que se puede arrastrar, la velocidad y la voz;
    - el amarillo en vivo sobre lo que suena, la pantalla que acompaña sola y el rosa siempre
      encima;
    - es el lector de F39 y la decisión 86, con una piel nueva.
- **Presentación:**
  - las diapositivas en 16:9, de a una, deslizando con una transición suave, y una tira de
    miniaturas;
  - las notas del presentador, que se muestran u ocultan;
  - pantalla completa apaisada;
  - **cambiar la plantilla sin volver a generar**, porque el contenido y el diseño van separados;
  - exportar a PDF.
  - **Las plantillas**: unas seis, cada una con su tipografía, colores, fondo y forma de las
    viñetas, por ejemplo *Medianoche*, *Pergamino*, *Editorial*, *Aurora*, *Pizarra* y
    *Minimal*.
  - **Los diseños de diapositiva**: portada, viñetas, dos columnas, cita, cifra destacada,
    línea de pasos, comparación y cierre. La IA elige cuál va en cada una.
- **Mapa mental:**
  - un árbol horizontal con nodos redondeados que se abren y cierran con «›», como el de
    NotebookLM;
  - pellizco para acercar y alejar, y arrastre;
  - **tocar un nodo** ofrece «Preguntarle al chat sobre esto» y «Ver en el documento»;
  - exportar a imagen.
- **Informe:**
  - las secciones con su título, que se pliegan con «⌃», como en la captura de la Introducción;
  - viñetas, negritas y las palabras clave en rosa;
  - en el interactivo, al final de cada sección, dos o tres preguntas para probarse ahí mismo;
  - exportar a PDF o Markdown.
- **Tarjetas didácticas:**
  - **la misma tarjeta de Repasar**, que se da vuelta y se desliza, adaptada a hojear el mazo:
    «3 / 20», anterior y siguiente, y barajar;
  - **«Sumar a mi repaso»**, encendido por defecto: las tarjetas quedan en el documento
    procesado y entran en «Para hoy». Si se apaga, el mazo queda solo para hojear.
- **Cuestionario**, como la captura:
  - «6 / 14» y las opciones A, B, C y D;
  - al responder, la correcta en verde con **«¡Exacto!»** o la elegida en rojo, y **la
    explicación de cada opción** debajo;
  - Anterior y Siguiente;
  - al final, el puntaje y **«Repetir solo las que fallé»**;
  - **Completar espacios**: se escribe; se compara sin tildes ni mayúsculas.
  - **Respuesta breve**: con IA disponible, la IA dice si está bien y por qué. Sin IA, se muestra
    la respuesta esperada y uno se autocalifica.
- **Infografía:**
  - la lámina entera, con pellizco para acercar y los botones + y −;
  - cambiar el estilo sin volver a generar;
  - guardarla como imagen.
- **Tabla de datos:**
  - la primera columna fija y desplazamiento lateral;
  - tocar una celda larga la abre entera;
  - ordenar por columna;
  - copiar y exportar a CSV, que abre en Excel o Sheets.

### 6. Cómo se le pide a la IA (con el modelo elegido)

- **Siempre con el modelo que la persona eligió**: Gemma en el teléfono o el de la nube, por el
  mismo lugar que hoy usan las tarjetas y el quiz (`LanguageModelTasks`).
- **Lo largo, sin trabarse.** Antes de pedir, se arma el material que entra en la ventana del
  modelo, en este orden:
  1. el texto entero, si cabe;
  2. si no, las oraciones del resumen;
  3. si no, las de la síntesis;
  4. si tampoco, por partes: cada parte da su borrador y un último paso los une.

  Un libro de tres millones de letras funciona igual con Gemma que con Gemini, solo cambia
  cuánto se lee de primera mano.
- **La IA devuelve datos, no diseño**: un JSON con un esquema por tipo (diapositivas con su
  diseño, nodos del árbol, secciones, preguntas, filas…). Se lee con tolerancia y, si viene roto,
  se le pide una sola vez que lo corrija. El dibujo lo hace siempre la app. Por eso se cambia la
  plantilla sin gastar IA, el texto nunca sale con faltas de ortografía dibujadas, y funciona con
  los cuatro motores.

### 7. Lo que se guarda

- **Una tabla nueva, `study_creations`** (esquema v48, aditivo), con:
  - el tipo;
  - el título;
  - el recorte y los documentos usados;
  - las opciones elegidas;
  - el contenido en JSON (en los de extraer, solo la referencia);
  - el estado: en cola, generando, lista o con error;
  - las fechas.
- **Entra en los tres censos**: la papelera, la copia de la bóveda y la unión de bóvedas.
- **Borrar una creación la manda a la papelera.** Si se borra un documento procesado, sus
  creaciones siguen ahí, con «fuente borrada» en la ficha.

## ¿Hace falta otra IA para los gráficos?

**Para casi todo, no.** La presentación, la infografía, el mapa mental, la tabla y el informe los
dibuja la app con plantillas propias: tipografías, colores, formas, íconos de Material, cifras
destacadas y líneas de pasos. El modelo elegido solo escribe el contenido. Así:

- funciona con Gemma sin internet;
- no cuesta nada extra;
- el texto sale perfecto;
- se puede cambiar el diseño después.

**Solo las ilustraciones de las capturas de la infografía** (la plastilina, lo kawaii, los
dibujos geométricos) son **imágenes generadas por un modelo de imágenes**. Eso:

- **Claude no lo hace.** Gemini y OpenAI sí, con modelos de imagen propios, y usarían las mismas
  claves que ya cargaste en F32.
- **Cuesta aparte por imagen.** En la cuenta gratis de Gemini puede no estar disponible: lo
  verifico con la documentación oficial antes de construirlo.
- **Necesita internet.**

**Propuesta (decisión H):** las plantillas dibujadas por la app como base, y un interruptor
**«Ilustraciones con IA»** en la infografía y la presentación. Solo aparece si hay una cuenta de
Gemini o de OpenAI, pinta una ilustración por bloque en el estilo elegido, y el texto lo pone
siempre la app encima. Las imágenes de las tarjetas y del cuestionario no piden nada: son **las
imágenes del propio documento procesado** (F41), y con un modelo de la nube que mira fotos, la IA
elige cuál va con cada pregunta.

## H en detalle: «¿Tu IA puede hacer esto?» (aprobado con ilustraciones, 2026-10-28)

Pedido del dueño al aprobar: *"obviamente quiero las ilustraciones con ia (pero que me avise que si
con el modelo que tengo va a poder generar imagenes o presentaciones o sino que me de mas opciones
que sea detallada la retroalimentacion y que me diga con que ia puedo hacer imagenes y con cual no y
cuanto consume en tokens en porcentaje y en cuota diaria), que las opciones de la infografia o
presentaciones sea muy variada y muy versatil para todo los gustos"*.

### Qué puede cada IA (verificado en la documentación oficial el 2026-10-28)

| IA | Escribe el contenido (texto, presentación, informe…) | Ilustraciones |
|---|---|---|
| **Gemma** (en el teléfono) | Sí, sin internet; con un libro largo, por partes y más lento | **No** |
| **Claude** | Sí | **No**: Claude no genera imágenes |
| **Gemini** | Sí | **Sí, solo con facturación activa**: la capa gratis no incluye los modelos de imagen. Nano Banana 2.1 (`gemini-nano-banana-2.1`, ≈ US$ 0,034 por imagen 1K, 1.120 tokens), Nano Banana 2 Lite (`gemini-3.1-flash-lite-image`, el más barato, ≈ US$ 0,034), Nano Banana Pro (`gemini-3-pro-image`, ≈ US$ 0,134) |
| **OpenAI** | Sí | **Sí, con la organización verificada** en su consola: `gpt-image-2.5-flare` (rápido) o `gpt-image-1-mini` (el más barato) |

- **Los precios y los nombres se guardan en una tabla con su fecha.** La pantalla dice «precios
  al 28/10/2026».
- **Qué modelos de imagen tiene cada cuenta sale de la lista del propio proveedor**, la misma que
  ya se trae en F32 y que hoy descarta los de imagen. Si el proveedor saca uno nuevo, aparece.
- **El primer pedido de imagen prueba la cuenta de verdad.** Si responde «sin facturación» o
  «organización sin verificar», la app lo recuerda y lo dice con esas palabras, no con un error
  genérico.

### Modelos de código abierto para imágenes (pedido del dueño, 2026-10-28)

Lo que pidió el dueño:

- *"si hay modelos de codigo abierto para generar imagenes que me los sugiera con su link"*;
- y después la aclaración: *"una categoria como una opcion «Exigente» … porque mi movil es de
  gama alta, pero debe ser opcional y aclarando las exigencias, y con los pasos para poder usar
  cada uno, siempre que sea facil, ademas es para uso personal, no voy a usar un servidor propio
  solo en mi movil … de esos tres elimina uno si es que ves que es muy exigente o si no es de
  facil aceso"*.

**El teléfono del dueño** es un Redmi Note 13 Pro+, con un Dimensity 7200: un procesador de gama
media alta.

- **Qwen-Image sale.** Tiene 20.000 millones de parámetros: no entra en ningún teléfono y es el
  más pesado incluso en la nube.
- **FLUX.1 [schnell] y Stable Diffusion 3.5 Large se quedan, pero por Hugging Face.** Corren en la
  nube con un token propio, que se pega una vez en Ajustes → IA. Tienen 12.000 y 8.000 millones
  de parámetros: en el teléfono no entran en la memoria o tardarían minutos por imagen.
- **No hay «Servidor propio»**: el dueño no lo va a usar.
- **Categoría nueva, «Exigente — en el teléfono»:** opcional, con las exigencias a la vista.
  - **Los modelos:** abiertos y chicos, que se bajan desde la app con un toque, como Gemma, y
    corren sin internet con stable-diffusion.cpp (licencia MIT), en el procesador:
    - **SDXS-512**, el más rápido;
    - **SD-Turbo**, el de mejor calidad, con licencia de Stability solo para uso no comercial,
      que alcanza para el uso personal.
  - **Lo que se mide antes de prometer:** en un Galaxy S24, SDXS tarda unos 6 s por imagen y
    SD-Turbo unos 12 s. En un teléfono de gama media con 6 GB, SDXS tarda 26–29 s y SD-Turbo se
    cierra por falta de memoria. En el Dimensity 7200 se mide de verdad y la app muestra el tiempo
    medido.
  - **Las exigencias, a la vista:**
    - 8 GB de RAM como mínimo, 12 GB recomendados;
    - entre 1 y 2,5 GB de espacio;
    - calienta y gasta batería mientras genera;
    - 512 px, con calidad de ilustración simple, buena para los estilos geométrico, acuarela o
      línea. El texto lo pone siempre la app.
  - **Los pasos**: Ajustes → IA → «Imágenes en el teléfono (Exigente)» → «Bajar» → «Probar». La
    app dice si tu teléfono puede, con cuánta RAM y con qué modelo.
  - **Si el teléfono no da** (memoria o un cierre), la app lo dice y lo apaga sola. Nunca deja
    la creación a medias: el lugar de la ilustración queda dibujado.
- **En «¿Qué puede cada IA?»** van los dos grupos, cada modelo con su enlace a la ficha oficial,
  su licencia en una línea y lo que exige: **«De código abierto — en la nube (Hugging Face)»** y
  **«Exigente — en el teléfono»**.

### El aviso, antes de generar

En la hoja de la Presentación y de la Infografía, encima de «Generar ahora», va una tarjeta
**«Con tu IA actual»**:

- **Qué va a poder hacer**, con ✓ y ✗: «✓ Escribir las diapositivas con Gemini 3.1 Flash ·
  ✗ Ilustraciones: tu cuenta de Gemini no tiene facturación activa».
- **Cuánto va a consumir:**
  - los tokens estimados de lectura y de escritura;
  - las imágenes: cuántas, de qué tamaño y su precio aproximado;
  - **el porcentaje de la cuota diaria**: «≈ 18 % de tu cuota de hoy, ya usaste 42 %».
- **La cuota diaria de cada cuenta la fija la persona** en Ajustes → IA: pedidos, tokens e
  imágenes por día, o un tope en dólares. Los proveedores no informan cuánto queda de la capa
  gratis (F32), así que el porcentaje es contra lo que la persona puso. Hasta que lo ponga, se usa
  el límite publicado de la capa gratis, rotulado «estimado».
- **Si la IA actual no puede**, se ofrecen **las opciones concretas**, en este orden:
  1. **Seguir sin ilustraciones**: las plantillas dibujadas por la app, que se ven terminadas
     igual.
  2. **Usar otra cuenta ya cargada que sí puede**: «Usar Gemini (cuenta Trabajo) para las
     ilustraciones». El texto lo sigue escribiendo la IA elegida.
  3. **Agregar una clave de Gemini u OpenAI**, que abre la hoja de claves de F32, con dos líneas
     sobre la facturación o la verificación.
- **La misma tabla «¿Qué puede cada IA?»** se ve completa en Ajustes → IA y desde un «ⓘ» en la
  tarjeta, con cada cuenta de la persona marcada como **puede**, **no puede** o **sin probar**.
- **Si una cuenta se queda sin cuota a mitad**, lo ya hecho se guarda. Las ilustraciones que
  faltan quedan con su lugar dibujado y «Completar ilustraciones», que sigue después con la misma
  cuenta o con otra.

## Plantillas: variadas y para todos los gustos

**El contenido y el diseño van separados** (decisión G): todo lo que sigue se cambia en el visor
sin volver a generar, y se previsualiza en miniatura antes de elegir.

### Presentación

- **Dieciséis plantillas, en cinco familias:**
  - **Clásicas:** *Editorial*, *Pergamino*, *Académica*.
  - **Modernas:** *Minimal suizo*, *Bento*, *Aurora* (degradés suaves), *Vidrio* (capas
    translúcidas).
  - **Oscuras:** *Medianoche*, *Neón*, *Pizarra*.
  - **Cálidas y creativas:** *Acuarela*, *Pastel*, *Papel recortado*.
  - **Sobrias de trabajo:** *Corporativa*, *Datos* (cifras y gráficos), *Ejecutiva*.
- **Lo que se personaliza en cada una:**
  - **la paleta**: seis por plantilla, más un color propio;
  - **la tipografía**: cinco pares de títulos y texto, con fuentes libres incluidas en la app;
  - **la densidad**: aireada, estándar o compacta;
  - **la transición**: fundido, deslizar, zoom suave o ninguna;
  - **el formato**: 16:9 o 4:3;
  - la numeración y un pie con el título.
- **Doce diseños de diapositiva**: portada, sección, viñetas, dos columnas, cita, cifra destacada,
  línea de pasos, comparación, cronología, imagen con texto, cuadrícula de conceptos y cierre.
- **Con ilustraciones**: una por diapositiva que la pida, en el estilo que se elija (*Igual que la
  plantilla*, *Fotográfico*, *Acuarela*, *Plastilina*, *Línea*, *Isométrico*).

### Infografía

- **Dieciocho estilos.** Los dibujados por la app no necesitan IA de imágenes:
  - *Automático* (la IA elige según el tema), *Editorial*, *Geométrico*, *Minimal suizo*,
    *Bento*, *Pizarra*, *Neón oscuro*, *Pergamino*, *Corporativo*, *Pastel*, *Infantil* y
    *Datos*.
  - Con ilustraciones con IA: *Plastilina*, *Kawaii*, *Acuarela*, *Isométrico*, *Cómic* y
    *Fotográfico*. Sin una IA que pueda, se ofrecen igual con su versión dibujada.
- **Diez composiciones**: bloques bento, columnas, zigzag, línea de tiempo, proceso, radial,
  comparación, pirámide, panel de cifras y mapa de conceptos. *Automática* elige según el
  contenido.
- **Gráficos dibujados por la app** cuando el contenido trae números: barras, anillo, progreso y
  pictograma.
- **Lo que se personaliza**: la paleta, la tipografía, la orientación (horizontal, vertical o
  cuadrado), el detalle (conciso, estándar o detallado), los íconos de un juego propio y el fondo
  (liso, textura o degradé).
- **Exportar**: PNG en alta resolución, o PDF.

## Mejoras pedidas el 28/10, con la fase ya en marcha

Pedido del dueño con seis capturas del teléfono, más un agregado: *"que los documentos de la
sección Procesado se conecten a los documentos de la sección Repasar … y viceversa. También lo
mismo con los cuadernos"*. Todo lo demás de Procesado queda igual.

### M1. Los avisos de la IA se cierran con una ✕

- **Hoy:** el aviso «Un momento… Se pasó el tope por minuto: sigue sola en 28 segundos» queda
  abajo hasta que vence la espera, y no hay cómo sacarlo.
- **Pasa a ser:** todos los avisos de la IA (`AiNoticeListener`) llevan una **✕ a la derecha**
  que los cierra en el acto. Además el de la espera **cuenta hacia atrás** en vivo y se va solo
  cuando la IA sigue.
- Se revisan los demás avisos largos de la app (más de 6 segundos o con un botón): todos con su ✕.

### M2. En Ajustes → «IA y modelos», primero se elige la IA

- **Hoy:** la sección empieza por «Lo que hizo la IA» y «Organizar con IA», y los modelos quedan
  al final.
- **Pasa a ser:**
  - **Primero «Modelo de lenguaje»**, «Transcripción de audio y video» y «Modelo del motor de
    relaciones»;
  - **después**, lo que la IA hace con ellos: «Lo que hizo la IA», «Organizar con IA» y sus
    llaves, y las ilustraciones y la cuota diaria (paso 3).

### M3. En Procesado, el original se ve ahí mismo, como en la Biblioteca

- **Hoy:** «La copia del original» es una tarjeta con «Ver el original», y hay que tocarla cada
  vez.
- **Pasa a ser:** el documento procesado **muestra el original incrustado**, igual que el
  detalle de la Biblioteca (`EmbeddedFileViewer`). Se ve con las marcas encima y con sus botones
  de estudio (M5), y el ícono de pantalla completa abre el visor de siempre.
- El tamaño y los datos de la copia (PDF · 26 kB · copiado el…) pasan a una línea debajo, y
  «Borrar la copia del original» sigue en «Más».

### M4. Fuera «Estudiar el documento» de Procesado (y de la Bandeja)

- **Qué se quita:** la tarjeta «Estudiar el documento» (`ProcessedStudySlot` con
  `StudyDocumentCard`, más «Extraer resumen / síntesis / palabras clave») **sale de cada
  documento procesado**.
  - Extraer resumen y síntesis es tarea de **Repasar**.
  - Marcar a mano y con IA queda **en el original** (M5).
- **La Bandeja:** al triar ya no se elige quedarse con el resumen, la síntesis o las palabras
  clave. Esas casillas salen de la hoja de triar.
- **Nada se pierde:**
  - las marcas que ya existen siguen guardadas y se ven en el original (M5) y en Repasar;
  - los documentos ya procesados que trajeron un resumen o una síntesis como sección los
    conservan;
  - la Biblioteca no cambia.

### M5. Los botones de estudio en el original, interactivos

Los tres botones de arriba del original (Resumen, Síntesis, Palabras clave) pasan a ser el lugar
de marcar:

- **Resumen y Síntesis**:
  - **Sin marcas:** el botón abre una hoja chica con dos opciones grandes: **«Con IA»**, que usa
    el modelo elegido con su aviso de lo que consume, y **«A mano»**, que entra al modo de
    elegir oraciones tocándolas en el texto.
  - **Con marcas:** el botón prende y apaga el resaltado. Su menú (⋯ o mantener apretado) ofrece
    rehacer con IA, retocar a mano, ocultar y borrar las marcas.
- **Palabras clave**:
  - se hacen igual, con IA o a mano;
  - **una vez hechas quedan marcadas por defecto**, en rosa, cada vez que se abre el documento;
  - se pueden **ocultar**, y queda recordado por documento.
- **Se superponen:** las palabras clave se ven encima del resaltado del resumen o de la síntesis
  (las dos capas a la vez, sin taparse), y el resumen con la síntesis también.
- **Estilo:** botones grandes con su color de resaltador, un indicador de cuántas marcas tiene
  cada uno, el estado (sin hacer, generándose con su avance, hecho, oculto) y la leyenda de
  colores. Funcionan en los 9 temas, con letra grande y a 360 dp.

### M6. Procesado y Cuadernos, conectados con Repasar (en los dos sentidos)

- **De Procesado a Repasar:** cada documento procesado lleva una sección **«En Repasar»** con lo
  creado sobre él:
  - presentaciones, resúmenes, infografías, cuestionarios y el resto, con el ícono y el color de
    cada tipo;
  - lo que lo incluye como fuente, aunque se haya creado sobre un cuaderno o un tema;
  - sus tarjetas para hoy.
  Tocar una creación abre su visor. **«Crear en Repasar»** abre Repasar con el documento ya
  elegido en el selector.
- **De Cuadernos a Repasar:** cada cuaderno lleva la misma sección sobre todo lo creado con el
  cuaderno como recorte, con «Crear en Repasar» con el cuaderno elegido.
- **De Repasar a Procesado y Cuadernos:** en «Lo creado» y en cada visor, **las fuentes de cada
  creación se ven como chips tocables** (el documento, el cuaderno o el tema) y abren su
  pantalla. Si una fuente se borró, el chip lo dice («fuente borrada»).
- Todo sale de los datos del paso 2 (`study_creations` con su recorte y sus fuentes): no hace
  falta una tabla nueva.

### M7. Los títulos con letras rotas («DeclaraciÃ³n»)

- **Visto en las capturas:** el título «DeclaraciÃ³n de los Derechos del Hombre…» es texto UTF-8
  leído como Latin-1.
- **Arreglo de raíz:** se busca dónde se decodifica el nombre (el archivo, los metadatos del PDF
  o el encabezado de la descarga) y se corrige ahí.
- **Lo ya guardado:** se repara con una migración que corrige solo los títulos que tienen esa
  firma exacta y que vuelven a ser texto válido al recodificarlos.

### M8. El resumen y la síntesis de Repasar son los mismos que en el documento (aclaración del 29/10)

- **Una sola fuente**: las marcas de estudio del documento procesado (F36).
  - Lo que se marque en el original (M5), con IA o a mano, es exactamente lo que muestran
    «Resumen» y «Síntesis» en Repasar.
  - Lo que se genere desde Repasar queda marcado en el original.
  - Nunca hay dos versiones (decisión E).
- **Los visores de texto de Repasar** (texto completo, resumen y síntesis) traen en su hoja la
  opción **«Resaltar las palabras clave»**, prendida por defecto, en rosa. Es la misma
  preferencia que el «mostrar por defecto» de M5.
- **Cada uno con su lector de voz**, en su propia pantalla: se escucha el texto, el resumen o la
  síntesis con el renglón que se lee resaltado en amarillo en vivo (decisión 86).

### M9. «Lo creado»: mantener apretado y deslizar

- **Cada fila**, plana como en NotebookLM: el ícono del tipo en su color, el título en un
  renglón y «N fuentes · Hace 5 d».
- **Mantener apretado** abre un menú flotante redondeado, con el fondo atenuado:
  - **Compartir** y **Descargar**, en el formato de cada tipo (PDF, PNG o texto);
  - **Cambiar nombre**;
  - **Ver petición y fuentes**: con qué opciones, qué modelo y cuándo se hizo, y las fuentes
    como chips tocables;
  - **Eliminar**, que la manda a la papelera con «Deshacer».
  - Si corresponde, también Regenerar, Reintentar y Cancelar.
- **Deslizar a la izquierda** muestra, a la derecha y pegados al borde, dos botones cuadrados en
  tonos de la superficie: **Descargar** y **Eliminar**. La fila queda abierta o cerrada sin
  quedar a medias, de a una por vez. Lo mismo se puede hacer desde el menú, para quien no
  desliza.

## Decisiones (se pueden cambiar mientras no se llegue a su paso)

- **A. Atlas se queda en Organizar**, junto a la Bandeja. El pedido no lo nombra entre los que
  pasan a Estudiar.
- **B. «Para hoy» se queda en Repasar**, compacto y debajo del selector, y obedece al selector.
  Así no se pierde nada y el repaso diario sigue a un toque.
- **C. Tocar una tarjeta de crear abre su hoja**, ya lista con lo último que se eligió. «Generar
  ahora» queda a un toque; no hay generar a ciegas.
- **D. El selector solo ofrece lo procesado**: Todo, Documento, Cuaderno y Tema. «Espacio» y
  «Etiqueta» salen del selector de Repasar porque son de la Biblioteca. Las tarjetas que ya
  existen siguen en «Todo» y en su documento.
- **E. Los tres de extraer son vistas vivas** sobre el resumen, la síntesis y las palabras clave
  del procesado. Lo demás se guarda como contenido fijo, con «Volver a generar».
- **F. Las tarjetas didácticas suman al repaso por defecto**, como cualquier tarjeta del
  documento, con un interruptor para dejarlas solo de hojear.
- **G. Un esquema de datos por tipo, y el diseño en la app**: cambiar plantilla o estilo nunca
  vuelve a llamar a la IA.
- **H. Ilustraciones con IA, aprobadas**, con el aviso «Con tu IA actual» y las alternativas
  (ver «H en detalle»). Sin una IA que pueda, todo se ve terminado igual con lo dibujado.
- **I. Sin 👍 y 👎**: en NotebookLM le avisan a Google. Acá no hay a quién mandarlo, y no se manda
  nada a ningún servicio.
- **J. Estudiar sale del documento procesado** (mejoras del 28/10, M4 y M5): cambia la
  decisión I de F41. Marcar el resumen, la síntesis y las palabras clave se hace en el original,
  y crear a partir de ellas, en Repasar. Las marcas ya hechas no se tocan.

## Pasos (cada uno, su commit y su push)

Se construye en tres olas de agentes en paralelo, cada uno en su rama. Cada paso se integra en
`main` con su suite, su push y su verificación.

**Ola 1, todo lo que no depende de nada:**

1. **La barra**: el paso «Estudiar» con sus cinco destinos, Organizar con Bandeja y Atlas, el
   chat a la derecha de Estudiar, la insignia, el riel de la computadora, la GUÍA y las pruebas.
2. **Los datos de «Lo creado»**:
   - `study_creations` (v48) en los tres censos;
   - el recorte de Procesado (documento, cuaderno, tema) y sus fuentes;
   - el armado del material que entra en la ventana del modelo;
   - el pedido de JSON con su esquema, por partes y con una corrección;
   - la cola de crear, con «ahora» y «más tarde».
3. **La IA de imágenes y el aviso** (Gemini, OpenAI y Hugging Face):
   - los cables de imagen de Gemini y OpenAI;
   - la tabla «¿Qué puede cada IA?» con precios fechados;
   - la prueba de la cuenta;
   - la cuota diaria por cuenta en Ajustes;
   - el estimador de tokens, imágenes y porcentaje.
4. **El diseño de las presentaciones**: las dieciséis plantillas, los doce diseños de
   diapositiva, paletas, tipografías (fuentes libres en la app), densidad, transiciones y el
   PDF, como piezas que dibujan un mazo de datos.
5. **El diseño de las infografías**: los dieciocho estilos, las diez composiciones, los gráficos,
   los íconos y la exportación a PNG y PDF, como piezas que dibujan una lámina de datos.

**Ola 2:**

3b. **Imágenes en el teléfono, la categoría «Exigente»**: SDXS-512 y SD-Turbo con
    stable-diffusion.cpp, la descarga, la medición en el teléfono, las exigencias y los pasos.

6. **Repasar nuevo**:
   - el selector y su hoja;
   - «Para hoy» compacto;
   - la grilla;
   - «Lo creado» con sus estados y su menú;
   - la hoja de personalizar común, con «Uso de IA» y la tarjeta «Con tu IA actual»;
   - Repasar se abre con un recorte ya elegido (para «Crear en Repasar», M6);
   - en «Lo creado», mantener apretado y deslizar (M9).

14. **Pulido (M1, M2 y M7)**: la ✕ y la cuenta atrás en los avisos, el orden de Ajustes → «IA
    y modelos» y los títulos con letras rotas, de raíz y con su reparación.
15. **Procesado y el original (M3, M4 y M5)**: el original incrustado, fuera «Estudiar el
    documento» de Procesado y de la hoja de triar, y los botones de estudio interactivos en el
    original (con IA o a mano, palabras clave marcadas por defecto, ocultar, superposición).

**Ola 2½, cuando estén los pasos 6 y 15:**

16. **Procesado y Cuadernos ↔ Repasar (M6)**: «En Repasar» en cada documento procesado y en
    cada cuaderno, «Crear en Repasar», y las fuentes como chips en «Lo creado» y en los visores.

**Ola 3, un agente por tipo:**

7. **Extraer texto completo, resumen y síntesis**, con su visor y el modo escuchar, las mismas
   marcas que el documento y las palabras clave resaltadas por defecto (M8).
8. **Tarjetas didácticas y Cuestionario**, con los cuatro tipos de pregunta.
9. **Mapa mental y Tabla de datos.**
10. **Informes**, con sus plantillas, interactivo y documento.
11. **Presentación**: generarla, el visor y las ilustraciones.
12. **Infografía**: generarla, el visor y las ilustraciones.

**Al final:**

13. **El cierre**:
    - la decisión 89;
    - la GUÍA, CONTEXTO y la suite entera;
    - la APK en el teléfono, si se pide.

## Lo que no entra (para que quede dicho)

- **Resumen de audio y de video** (un pódcast o un video generados): el pedido los cambia por los
  tres de extraer.
- **Mandar 👍 y 👎** a cualquier servicio.

## Avance

*(Se completa paso a paso al construir.)*

### Paso 1 (hecho): la barra con «Estudiar»

- Biblioteca · Organizar · Estudiar · Chat · Ajustes. Organizar se queda con la Bandeja y el
  Atlas; Estudiar abre Procesado, Cuadernos, Línea de tiempo, Mapa y Repasar, con la insignia de
  las tarjetas para hoy. El riel ancho sigue el mismo orden y la GUÍA explica cómo llegar a cada
  lugar.

### Paso 2 (hecho): los datos de «Lo creado», esquema v48

- **`study_creations`** (v48, aditiva, con los conteos como compuerta): tipo, título, recorte,
  fuentes (ids sueltos, sin cascada: borrar un procesado deja la creación con «fuente borrada»),
  opciones y contenido en JSON —nulo en las tres de extraer, que son vistas vivas (decisión E)—,
  estado con su motivo y su avance, «ahora» o «más tarde», intentos y papelera.
- **Los tres censos**: la papelera (sección «Creaciones de Estudiar», restaurar, borrar para siempre
  y vaciar), la copia (la base entera) y la unión (entra lo que no hay; lo de la otra a medias
  entra fallido por interrumpido; una que las dos tienen queda con la versión más nueva si está
  terminada; la vista previa y el resultado la cuentan).
- **El recorte** (`CreationScope`: todo, documento, cuaderno, tema con sus ramas y espacio) se
  resuelve con las consultas de siempre (`ProcessedRepository.matchingIds`,
  `NotebookRepository.memberIds`). **«Para hoy»** lo cuenta con `StudyScope.processed`: las
  tarjetas de cada documento **y** las de su fuente («De la fuente»); «Todo lo procesado» es
  `StudyScope.all()`. El selector viejo de Repasar ya ofrece «Un procesado».
- **El material** (`CreationMaterialBuilder`): el texto entero, el resumen, la síntesis o por
  partes (como mucho 24, repartidas por todo el texto). Un libro de 3.000.000 de caracteres se
  arma en 26–32 ms (PC, flutter test): con Gemma, 1.771 partes de 2.040 caracteres (se lee el
  1,3 % de primera mano, sin resumen ni síntesis); con Gemini, 51 partes de 60.000 (el 46 %).
  Cortarlo corre en otro hilo.
- **El pedido de JSON** (`StructuredWriter.writeStructured`, en `LanguageModelTasks`, genérico):
  lectura tolerante, una corrección, por partes con unión de a grupos, cancelable, con el turno
  de la persona o de la cola de fondo, sin pasarse nunca de la ventana.
- **La cola** (`CreationQueue`): «Generar ahora» antes que «más tarde»; lo de fondo espera la
  cuota sin fallar; lo pendiente se retoma al abrir la app (tres intentos), con el servicio en
  primer plano. Cada tipo suma su generador con una línea en `creationGeneratorsProvider`.

### Paso 3 (hecho): la IA de imágenes y el aviso

- Los cables de imagen de Gemini (Interactions, `store: false`), OpenAI (Image API) y Hugging
  Face (proveedores de inferencia del Hub), con la tabla fechada de precios y de modelos abiertos
  y las cuentas de Hugging Face.
- El servicio de ilustraciones (`illustrationServiceProvider`) y el estimador de «Con tu IA
  actual» (`creationEstimateProvider`): qué cuenta dibuja y con qué modelo, tokens, imágenes,
  dólares y el porcentaje de la cuota de hoy, con las alternativas tocables (`AiCapabilityCard`).
  «¿Qué puede cada IA?», «Uso de IA» y la cuota de cada cuenta en Ajustes → IA.

### Paso 3b (hecho): «Exigente — en el teléfono»

- SDXS-512 y SD-Turbo (GGUF) con stable-diffusion.cpp fijado a una versión, por FFI en otro hilo;
  la descarga se pausa y se comprueba con su huella, y el veredicto «puede / justo / no alcanza»
  sale de la memoria y el procesador. «Medir en mi teléfono» guarda el tiempo real por imagen.
- El motor nativo solo entra si la APK se arma con `-Psinapsis.imagenesEnElTelefono=true`
  (suma unos 38 MB). La APK sin la bandera compila; en un teléfono real no se probó todavía.

### Paso 4 (hecho): el diseño de las presentaciones

- La base del diseño de todo lo creado (`lib/features/creations/design/`): seis pares de letras
  libres empaquetados, la paleta con el contraste comprobado, los íconos por nombre, el lienzo que
  escala y el texto que se ajusta sin desbordar nunca, texturas, la ilustración de reserva dibujada
  por la app y el rasterizador.
- El mazo como datos (doce diseños de diapositiva, JSON tolerante, esquema para la IA, el diseño
  guardado aparte), las dieciséis plantillas en cinco familias, el visor con transiciones y
  miniaturas, la galería con muestras en vivo, la hoja de personalizar y el PDF con la página de
  notas del presentador.

### Paso 5 (hecho): el diseño de las infografías

- La lámina como datos: ocho tipos de bloque (cifra, hecho, paso, comparación, hito, concepto,
  cita y gráfico), cada uno con su nivel para el detalle; los números leídos como los escribe un
  texto («3.000.000», «40 %»); el JSON tolerante y el esquema para la IA.
- Los dieciocho estilos (seis paletas cada uno, con el contraste comprobado; los ilustrados con su
  pista para la IA de imágenes y terminados con su versión dibujada), las diez composiciones y los
  gráficos (barras, anillo, avance y pictograma, que se leen en voz alta).
- «Automático» y «Automática» se resuelven por el contenido, de forma determinista. Galería,
  carrusel con muestra, hoja de personalizar, y PNG ×2 y PDF de una página.

### Paso 6 (hecho): Repasar nuevo

- El selector de Procesado (todo, documento, cuaderno y tema del Atlas, con buscador y los
  recientes; la Biblioteca no aparece) reemplaza al viejo (fuera Espacio, Etiqueta y Elemento,
  decisión D). «Para hoy» compacto, y toda la pantalla es una sola lista que se desplaza, sin el
  desborde de antes.
- La grilla de las diez tarjetas (un color vivo por tipo, de a dos en el teléfono) y la hoja de
  personalizar común: idioma, fuentes, descripción, tema con sugeridos, las opciones de cada tipo,
  «Uso de IA» con el material real y «Con tu IA actual»; se recuerda lo último elegido por tipo.
- «Lo creado» (M9): filas planas, mantener apretado abre el menú (Descargar, Cambiar nombre, Ver
  petición y fuentes, Eliminar con «Deshacer»), deslizar a la izquierda muestra Descargar y
  Eliminar. Compartir usa la hoja de compartir del sistema (`share_plus`, sumada a pedido del
  dueño el 29/10), con el archivo armado en memoria y su nombre de verdad; en Linux, donde esa
  hoja no acepta archivos, no se ofrece.
- El visor común (`/creations/:id`) con «Ver N fuentes» como chips tocables (M6, de Repasar a
  Procesado y Cuadernos), y Repasar se abre con un recorte ya elegido (`/review?scope=`). Cada
  tipo se suma con una línea en `creationKindSpecsProvider`.

### Paso 7 (hecho): Extraer texto completo, resumen y síntesis

- **Vistas vivas (decisión E, M8)**: las tres leen el texto propio y las marcas de estudiar de cada
  documento (`procesado:…`), sin copia; si se marca o se edita algo, cambian solas
  (`extractOwnTextProvider` relee al cambiar el documento y, si el texto quedó igual, no rearma
  nada). Con varios documentos van en el orden de las fuentes, cada uno con su título; uno borrado
  dice «Fuente borrada» y uno sin texto lo dice.
- **Lectura**: una lista que arma solo lo que se ve —un libro entero, partido en otro hilo, no
  traba—, con la letra y el tamaño del lector de libros, los títulos en Lora y cada documento
  sobre su hoja más clara (radio 28). Las oraciones del resumen o la síntesis se juntan por
  párrafo del documento; las palabras clave, en rosa (decisión 85).
- **Lo que falta se marca en el documento mismo**: «Marcar con IA» (o «Marcar los N con IA») corre
  el mismo análisis del original (`studyAnalysisProvider`, M5), de a un documento por vez, con
  «Con tu IA actual» (`AiCapabilityCard`) y su avance en vivo; también «Abrir el documento».
- **«Resaltar las palabras clave»**, en la hoja «Lectura» con el tamaño de letra: es la misma
  preferencia del original y vale en los dos sentidos.
- **Modo escuchar**: el mismo lector de siempre (decisión 86), con un reproductor grande abajo
  —reproducir o pausar, oración anterior y siguiente, la barra que se arrastra, velocidad, voz y
  «3 de 40»—. Lo que suena va en amarillo con el rosa encima y la lista acompaña sola, de un salto
  si está lejos o sin animación si así se pidió; si se la mueve a mano aparece «Volver a la
  lectura». El lector flotante se hace a un lado mientras tanto (`ReadAloudDock`, nuevo, y
  `ReadAloudController` suma ir a una oración, a la anterior, a la siguiente y a un punto de la
  barra).
- **Archivo**: Markdown con un apartado por documento y las palabras clave en negrita si se
  resaltan; «Compartir» pasa este mismo archivo.

### Paso 10 (hecho): Informes

- **Plantillas**: Resumen de aprendizaje, Guía de estudio, Documento informativo y Glosario, cada
  una con su estructura de secciones y su guía para la IA, elegidas como tarjetas. La propia se
  escribe con ✎, la hoja vuelve a abrir con ella y «Las que ya usaste» sale de los informes ya
  guardados en «Lo creado» —sin otro guardado, así viaja con la bóveda—.
- **Formato**: Interactivo —dos o tres preguntas por sección con «¡Exacto!» o «No es esa», el
  porqué de la elegida, la correcta con su letra, puntaje por sección y total, y «Volver a
  intentar»— o Documento. Las opciones se mezclan siempre igual: la «B» de la pantalla es la del
  PDF.
- **Generar**: un `writeStructured` con su JSON leído con tolerancia (claves en castellano o
  inglés, textos como cadena, lista o viñetas, la correcta como letra, número o texto; una
  pregunta incompleta se descarta sin tumbar el informe). Lo largo va por partes y la unión lo
  rearma en la estructura de la plantilla; con Gemma la respuesta se ajusta a la ventana. El
  glosario lo ordena la app: junta, saca repetidos, ordena y agrupa por letra.
- **Visor**: secciones numeradas que se pliegan con «⌃», índice que salta y pliega o despliega
  todo, viñetas, citas y negritas en Lora y Source Sans 3, y las palabras clave en rosa sacadas de
  las marcas de estudiar de las fuentes (o, si no hay, las que destacó la IA), con la misma
  preferencia de mostrarlas. Las preguntas no llevan rosa, para no dar pistas.
- **Descargar o compartir**: PDF A4 de texto con las fuentes de la app incrustadas, las palabras
  clave en rosa y las respuestas en una página aparte, o Markdown con las palabras clave en
  negrita.

### Paso 12 (hecho): la Infografía

- **Generar**: la IA escribe la lámina (`writeStructured`, esquema de la infografía) con el
  detalle, la orientación, el estilo y la descripción; «Automático» con ilustraciones elige uno de
  los ilustrados. Un libro largo va por partes —hasta seis bloques cada una— y el último paso elige
  y ordena los mejores. El avance llega al 70 % con el texto y sigue por cada ilustración
  (`CreationStep.illustrating`, «Dibujando las ilustraciones…»); se puede cancelar.
- **Ilustraciones con IA (H)**: la cabecera y los bloques con lugar para dibujo, con la pista del
  estilo y el aspecto que corresponde, **nunca más de las estimadas** y con la cuenta que se vio en
  el aviso. Una que falla nunca tumba la lámina: queda el dibujo de la app con su porqué; si la
  falla es de la cuenta o la cuota, no se insiste. Cancelar borra lo dibujado en esa vuelta, y
  volver a generar borra lo que la lámina nueva ya no usa.
- **Dónde viven**: en el almacén de los originales (`originales/<creación>/ilustraciones/`), así
  sobreviven al reinicio, entran en la copia y viajan en la unión de bóvedas (`studyCreationFilesSql`
  busca las rutas `illustration_ref` del contenido). Borrar una creación para siempre —una o la
  papelera entera— se lleva su carpeta (`FileStore.deleteAllOf`, genérico para cualquier tipo).
- **Hoja**: el carrusel de estilos con su muestra; un estilo ilustrado sin ilustraciones avisa que
  se verá en su versión dibujada. La estimación cuenta las imágenes (1 + 5/7/9 en un estilo
  ilustrado).
- **Visor**: la lámina entera con pellizco y −, «Ver la lámina entera» y +; «Cambiar el estilo»
  cambia en vivo y se guarda sin la IA (`StudyCreationRepository.amend`, nuevo y genérico); «Guardar
  como imagen» da un PNG al doble y Descargar o Compartir preguntan PNG o PDF. Un aviso dice cuántas
  ilustraciones faltan y por qué, y «Completar ilustraciones» o rehacer una muestran antes el costo
  («Con tu IA actual» solo con imágenes) y su avance.
- **«Ver petición y fuentes»** dice el estilo visual elegido, por el gancho genérico
  `CreationKindSpec.requestLines`.

### Paso 14 (hecho): Pulido (M1, M2 y M7)

- Todo aviso con botón, largo o que se queda lleva su ✕ (`AppSnackBar`), y un censo lo exige; el
  de la espera de la IA cuenta hacia atrás en vivo. Los avisos con «Cuentas» ya se van solos.
- Ajustes → «IA y modelos»: primero los tres modelos, después lo que hizo la IA.
- «DeclaraciÃ³n», de raíz: el XMP del PDF se lee en UTF-8, el diccionario Info según su marca
  (con PDFDocEncoding de verdad) y el nombre de las descargas web según su `filename*`; lo ya
  guardado se repara una vez al abrir la bóveda, como una edición versionada.

### Paso 15 (hecho): Procesado y el original (M3, M4 y M5)

- **El original a la vista** (`ProcessedOriginalSection`): en el mismo marco que el detalle de la
  Biblioteca (`EmbeddedViewerFrame`, ahora público), con lo marcado encima; el botón grande y un
  toque en la hoja abren `ProcessedOriginalScreen`. Debajo, «PDF · 26 kB · copiado el…»; borrar la
  copia sigue en «Más». Sin copia, nada cambia. La tarjeta `ProcessedOriginalCard` salió.
- **Fuera «Estudiar el documento»** (decisión J): sale `ProcessedStudySlot`, y de
  `StudyDocumentCard` el camino `studiedRows` que solo usaba Procesado (las filas «Extraer
  resumen / síntesis / palabras clave» y sus claves de texto). La hoja de triar ya no ofrece esas
  tres secciones (`triageSectionsOffered`); procesar las sigue aceptando, así que lo ya guardado se
  lee igual y volver a triar no lo toca. La Biblioteca no cambia.
- **Marcar en el original** (`OriginalStudyBar`, arriba del original incrustado y del entero):
  - la copia deja de ser de solo lectura: lo elegido sobre ella se lleva a la posición del texto
    propio (`ProcessedStudyLayout.ownOf`) y se guarda en el procesado con la clave `procesado:…`;
    lo que cae en una página editada no tiene dónde ir y lo dice;
  - «Con IA» corre el análisis de siempre sobre el texto propio, con «Con tu IA actual»
    (`planStudyAnalysis` → `creationEstimateProvider` → `AiCapabilityCard`); ya terminado, es
    rehacer lo de la IA;
  - con marcas, prender y apagar queda recordado por documento
    (`processedOriginalHiddenProvider`, en el teléfono); las palabras clave hechas se ven siempre;
  - el menú (⋯ o mantener apretado): rehacer con IA, retocar a mano, ocultar o mostrar, y borrar
    (`StudyRepository.clearKind`, nuevo en los cuatro repositorios);
  - estado (sin hacer, generándose con su avance que se llena sin girar, hecho, oculto), cuántas
    marcas y la leyenda.
- **Una sola fuente de verdad**: lo marcado en el original son las marcas de estudiar del
  documento (F36, clave `processedStudyKeyFor`, en sus partes): las mismas que Repasar muestra
  como vistas vivas del resumen, la síntesis y las palabras clave (decisión E). No hay otro
  guardado. La preferencia «palabras clave a la vista», por documento, la lee cualquier pantalla
  con `processedKeywordsShownProvider(documentId)`; se cambia con
  `processedOriginalHiddenProvider(documentId).notifier.setHidden(...)`.
- **Se superponen sin taparse**: una oración del resumen y de la síntesis se ve celeste con la línea
  verde del resumen (`PaintedRange.underline`) en el texto, el PDF y la página web; la palabra
  clave queda rosa encima.
- **Dos arreglos de raíz que salieron en el camino**: sacarle una palabra a una oración de palabras
  clave copiada la marcaba editada y escondía todas sus palabras (ahora las que quedan pasan a
  elegidas); y el botón grande «Leer como libro» desbordaba con la letra al doble en 360 dp
  (también en la Biblioteca).

### Paso 16 (hecho): De Procesado y Cuadernos a Repasar, y de vuelta (M6)

- **«En Repasar» en cada documento procesado**: una tarjeta propia (`ScopeCreationsSection`) al
  final, después de las secciones y antes del Mapa y las Tarjetas de repaso —el documento se lee en
  el orden del trabajo: la fuente, el original marcado, lo procesado y cómo estudiarlo—. Trae lo
  creado sobre él y lo que lo usó como fuente desde un cuaderno o un tema, las cinco más nuevas
  con las mismas filas de «Lo creado» (`CreationTile`) y «Ver las N en Repasar» si hay más; sus
  tarjetas para hoy con «Empezar» a la sesión del recorte (`openScopeReview`); «Crear en Repasar»
  con el documento ya elegido. En la papelera no se ve, como el Mapa y las tarjetas.
- **En cada cuaderno**: la misma tarjeta arriba de sus documentos, sobre lo creado con el
  cuaderno (el panel pasó a una sola lista que se desplaza); un cuaderno vacío la muestra solo si
  ya tiene algo creado (`hideWhenEmpty`).
- **Vacío que invita a crear**: los íconos de presentación, resumen, infografía, cuestionario y
  mapa mental, un texto propio para documento, cuaderno o tema, y el botón grande.
- **Ida y vuelta**: tocar una creación abre su visor y «atrás» vuelve al documento o al cuaderno;
  las fichas de las fuentes del visor y de «Ver petición y fuentes» llevan de vuelta, y una fuente
  que ya no está dice «Fuente borrada» y no abre nada. Las direcciones directas siguen andando.
- **Sin tabla nueva**: la regla es la misma de Repasar (`watchByScope`, ids enteros con
  `json_each`: `doc-a` no confunde `doc-a1`), probada con 1.000 y 4.000 creaciones y un tiempo que
  crece lineal.
- **Dos arreglos de raíz**: el botón flotante del cuaderno repetía la etiqueta Hero al abrir un
  visor encima (`heroTag: null`), y la fila deslizada tapa sus botones con el color de la tarjeta
  que la contiene, no con el fondo de la pantalla.
