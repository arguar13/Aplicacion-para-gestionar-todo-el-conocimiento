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

*"si hay modelos de codigo abierto para generar imagenes que me los sugiera con su link"*.

- **En «¿Qué puede cada IA?»** va una sección **«De código abierto»**. Cada modelo lleva:
  - su enlace a la ficha oficial en Hugging Face;
  - **su licencia en una línea**: si permite uso comercial o solo personal;
  - qué necesita para correr.
- **La lista, que se verifica contra cada ficha y su LICENSE al construir:**

  | Modelo | Licencia |
  |---|---|
  | Qwen-Image | Apache 2.0 |
  | Z-Image | Apache 2.0 |
  | FLUX.1 [schnell] | Apache 2.0 |
  | FLUX.2 klein 4B | Comercial abierta, según su ficha |
  | Stable Diffusion 3.5 | Licencia comunitaria de Stability |
  | Sana | Liviano, corre con 8 GB de video |

- **Ninguno cabe ni corre bien dentro del teléfono**: piden una placa de video. Por eso la app
  ofrece dos formas de usarlos:
  1. **Hugging Face como proveedor de imágenes**: con un token propio, la app pide la imagen a
     esos mismos modelos abiertos por la API de Hugging Face. Tiene créditos gratis chicos por
     mes; se verifica al construir y se dice tal cual.
  2. **«Servidor propio»**: la dirección de un servidor en la computadora de la persona que
     hable el formato de imágenes de OpenAI (por ejemplo, LocalAI con FLUX o Stable Diffusion).
     Usa el mismo cable que OpenAI con otra dirección. Gratis, sin cuota, y nada sale de la casa.
- **Cada uno entra en el aviso «Con tu IA actual»** como una alternativa más, con su costo: «sin
  costo, en tu computadora» o «créditos de Hugging Face».

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
3. **La IA de imágenes y el aviso**:
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

6. **Repasar nuevo**:
   - el selector y su hoja;
   - «Para hoy» compacto;
   - la grilla;
   - «Lo creado» con sus estados y su menú;
   - la hoja de personalizar común, con «Uso de IA» y la tarjeta «Con tu IA actual».

**Ola 3, un agente por tipo:**

7. **Extraer texto completo, resumen y síntesis**, con su visor y el modo escuchar.
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
