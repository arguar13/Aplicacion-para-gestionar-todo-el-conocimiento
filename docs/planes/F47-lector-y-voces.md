# F47 — Un solo lector para todo, la biblioteca de voces y el podcast

> **Estado: APROBADO** (2026-10-30, «Aprobado todo» en el chat), con las decisiones A a K como
> están. Va después de F45 y antes de F46 (decisión I); el paso 0 se adelanta, porque es chico.
>
> **Cambios del dueño, el 30/10, después de aprobar:**
> - **todo en el teléfono y sin gastos, por defecto**. Ninguna voz lee desde la nube, y el podcast
>   también se oye con voces del teléfono;
> - **la nube, solo si la elegís y solo para clonar y crear voces** (ElevenLabs), con el costo a
>   la vista antes;
> - **clonar la voz de quien elijas, con su permiso**, y **crear una voz nueva describiéndola**;
> - **cada idioma con sus voces nativas**, con su acento y su tono.
>
> Cambian las decisiones B, C y F, y se suma la L. **Aprobado** por el dueño el 30/10 («aprobado»).

Pedido del 30/10. La guía de diseño son las capturas 3 a 17 (la app Listen AI). Hay que conservar
todo lo que la app ya hace.

- **Un solo lector, profesional y elegante, para todo texto:** el original (un PDF, un libro, una
  página web o una foto), el texto extraído, el resumen, la síntesis y lo creado en Repasar.
  - Cambia la forma; no se pierde ninguna función.
- **Un reproductor anclado abajo**, con su cola, su temporizador para dormir, su velocidad y la
  voz a la vista.
- **Escuchar en segundo plano:** con la app minimizada o la pantalla apagada, con su tarjeta en
  la barra de notificaciones y en la pantalla de bloqueo.
- **Una biblioteca rica de voces, en cada idioma con su acento y su tono:**
  - las del teléfono;
  - voces neuronales sin conexión, gratis;
  - **voces clonadas**, la tuya o la de quien te dé permiso;
  - **voces creadas a tu gusto**, describiéndolas.
  - Con cualquiera de ellas se escucha un documento. Todo anda en el teléfono y sin gastos; la
    nube es opcional y solo para clonar y crear.
- **Un podcast a medida**, en Repasar y en cada documento, con una o dos voces.
- **Lo que le falta a Ajustes**, sacado de las dos últimas capturas.
- **Dos arreglos que van primero:** sin el lector en voz alta en las tarjetas de Repasar, y un
  botón bien visible para ver lo filtrado (las mejoras 20 y 21, que estaban en F45).

## Lo que hay hoy (y no se pierde)

Hoy son cuatro lectores distintos:
- el de «Lo creado» (`ExtractViewer`): «Texto completo», el resumen y la síntesis, con 🎧, la
  letra, ⋮ y «Ver N fuentes»;
- «Leer como libro» (`DocumentReaderView`), con A− A+, el paginado y las fichas Resumir ·
  Sintetizar · Palabras clave;
- el PDF (`PdfViewerView`), con su página de verdad;
- la página web guardada.

Cada uno tiene su propio reproductor, el panel flotante con «Leer: Todo · Resumen · Síntesis ·
Palabras clave». Lo de abajo se conserva, y el paso 1 empieza con un **censo de funciones**: una
prueba que nombra cada una y comprueba que en el lector nuevo se llega a ella.

- **El texto:**
  - las palabras clave en rosa;
  - el resumen y la síntesis marcados con su color y su punto, ocultables;
  - la línea que se lee, en amarillo, siguiendo a la voz;
  - la página que se ve;
  - el texto limpio, sin direcciones ni `![](…)` (F45, mejora 12).
- **Con lo que se selecciona:**
  - Copiar, Escuchar, Nota y resaltar a mano con sus colores (F38);
  - «A Procesado», mientras se corta del original (F41);
  - «A la línea de tiempo» (F40);
  - Explicar en el chat.
- **Las tres fichas** Resumir · Sintetizar · Palabras clave, con su estado y su avance (F45, paso
  4).
- **Ver la fuente:** «Ver N fuentes», las fichas de cada fuente y, desde una tarjeta, ir al pasaje.
- **Editar** lo procesado y **las notas en el texto** (F45, mejora 19, cuando estén).
- **Bajar:**
  - «Descargar con lo marcado» (F38 y F45, paso 3);
  - exportar lo creado;
  - imprimir.
- **El original:** el PDF con su maquetación, el libro paginado y la página web en vista móvil
  (F45, paso 4), con «Ampliar».
- **Leer en voz alta:**
  - «Leer: Todo · Resumen · Síntesis · Palabras clave»;
  - en un audio o un video, empezar por lo estudiado;
  - la velocidad y la voz;
  - seguir sonando al cambiar de pantalla.
- **El tema de lectura** (claro, oscuro, sepia), el tamaño de la letra y el lector de pantalla.

## Qué se construye

### 0. Dos arreglos que van primero (mejoras 20 y 21, del 30/10)

Las capturas son las del primer mensaje: el botón redondo en Repasar, y el panel «Filtros» de la
Biblioteca sin un botón para ver lo filtrado.

#### Mejora 20. Sin el lector en voz alta en las tarjetas de Repasar

- **Hoy:** en Repasar, abajo a la derecha, aparece el botón redondo del lector en voz alta. Lee la
  pregunta y, revelada, la respuesta. No tiene sentido: la tarjeta se repasa leyéndola y pensando
  la respuesta.
- **La causa:** la tarjeta de repaso se declara «texto para leer» desde F31 (`ReadableRegion` en
  `review_session_card.dart`), y el lector aparece en toda pantalla que se declara así.
- **Cambio:** la tarjeta deja de declararse. El botón no aparece en Repasar, ni en la pregunta ni
  con la respuesta, ni en las tarjetas de opción múltiple o de completar.
  - Si al entrar a Repasar algo se estaba leyendo (por ejemplo, un documento), el reproductor
    sigue hasta que la persona lo pare, como al cambiar de pestaña.
  - «Ver en la fuente» y «Explicar» quedan como están.
  - La GUÍA saca «el repaso de tarjetas» de las pantallas con lector y lo suma a las que no lo
    tienen.

#### Mejora 21. Filtros: un botón bien visible para ver lo filtrado

- **Hoy:** el panel «Filtros» de la Biblioteca aplica cada filtro al tocarlo, pero tapa la lista.
  No dice cuántos documentos quedan ni tiene un botón para verlos: hay que adivinar que se cierra
  arrastrándolo hacia abajo.
- **Cambio, un pie fijo en el panel** (decisión K):
  - un botón relleno a lo ancho, **«Ver 12 resultados»**, que se queda abajo mientras se
    desplazan los filtros. La cifra se actualiza al tocar cada filtro, contada en la base y no
    trayendo los documentos;
  - al tocarlo, el panel se cierra y queda a la vista la lista ya filtrada, desde arriba;
  - sin filtros dice **«Ver todo (340)»**. Mientras cuenta, «Ver resultados», sin cifra y sin
    saltar de tamaño;
  - si nada pasa el filtro, dice **«Ningún resultado»**, apagado, y arriba sigue «Limpiar filtros»;
  - el pie es del marco común de los filtros, así que lo mismo pasa en **Procesado** y en la lista
    de **«Volver a triar»**;
  - en 360 dp con la letra al doble, en claro y en oscuro, con el lector de pantalla, que anuncia
    la cifra cuando cambia;
  - **el mismo pie en todo filtro de la app**: también en la biblioteca de voces (punto 3), con
    «Ver N voces».

### 1. Un solo marco de lectura (capturas 3, 4, 5, 6 y 9)

El mismo marco en el original, el texto extraído, el resumen, la síntesis y lo creado. Lo único
que cambia es el cuerpo: la página del PDF, la página web o el texto de corrido.

- **La barra de arriba, limpia:**
  - a la izquierda, ←;
  - a la derecha, cuatro botones redondos con borde, del mismo tamaño:
    - **Contenido** (el índice, las secciones y «Ver N fuentes»);
    - **IA** (prende y apaga la fila de IA);
    - **Aa** (Apariencia);
    - **⋮**.
  - El título va en el cuerpo, grande; la barra no lo repite.
- **La fila de IA**, que aparece debajo de la barra al tocar IA (captura 4):
  - las fichas de hoy, **Resumir · Sintetizar · Palabras clave**;
  - **Preguntar a la IA** (el chat sobre este documento);
  - **Podcast**.
  - En angosto se desplaza de costado.
- **El cuerpo:**
  - una columna de lectura de ancho cómodo, con márgenes generosos;
  - la tipografía elegida, por defecto una serif de lectura;
  - la línea que suena, con un fondo suave del color de «Resaltado de lectura».
  - Sin la tarjeta-papel ni el botón flotante.
- **Apariencia** (Aa, captura 5):
  - la **fuente**: el tipo, entre cinco de lectura incluidas en la app, y el tamaño, con un
    deslizador;
  - el **color**: el «Resaltado de lectura»;
  - el **modo**: Sistema · Claro · Oscuro · Sepia, con su muestra.
  - Se guarda para todos los lectores.
- **⋮, una hoja con todo lo demás** (captura 6):
  - arriba, la miniatura, el título con ✎ para renombrar y el tipo;
  - después, en grupos:
    - **Descargar audio** con la voz elegida, para escuchar sin conexión;
    - **Notas (N)**, **Resumir**, **Añadir a la cola**, **Marcar como terminado** y
      **Favoritos**;
    - **Temporizador para dormir**, **Exportar audio**, **Descargar con lo marcado**,
      **Exportar** e **Imprimir**;
    - al final, en rojo, **lo que se borra**: la copia, la creación o el documento procesado,
      nunca la fuente de la Biblioteca.
- **El original de la Biblioteca y el de Procesado:** el mismo marco, con su cuerpo de siempre y
  las marcas adentro (F45, mejora 15).
- **Todo tipo de documento**, sin excepciones. Cada uno con su cuerpo y el mismo marco, la misma
  fila de IA, Apariencia, ⋮ y reproductor:
  - una **página web guardada** y una **publicación**, en vista móvil (F45, paso 4);
  - un **PDF**, con su página de verdad;
  - un **EPUB**, un **Word**, un **texto** o un **Markdown**, como libro paginado;
  - una **foto** o un **escaneo**, con su imagen y el texto que se leyó;
  - un **audio**, un **video** o un **YouTube**, con su reproductor y la transcripción que se
    sigue;
  - una **nota** tuya y una **referencia** con su texto;
  - lo creado en Repasar: el texto completo, el resumen, la síntesis, el informe y el podcast.
  - Apariencia cambia lo que se puede cambiar en cada cuerpo: en el texto, la tipografía y el
    tamaño; en un PDF o una foto, el zoom y el modo de color de la página.

### 2. El reproductor anclado (capturas 3, 7, 8 y 15)

- **Abierto**, abajo y a lo ancho:
  - el título, que se desliza si no entra;
  - ⟲ **Repetir**, ☰ **Cola** y ⌄ **Achicar**;
  - la barra de avance, con el tiempo transcurrido y el total;
  - **la cara de la voz**, que abre la biblioteca de voces;
  - −10 s, ▶ grande en el color de acento y +10 s;
  - la velocidad, «1,0×».
- **Achicado** (captura 8): una línea con ▶, el título, +10 s y ⌃.
- **El tiempo:**
  - con una voz del teléfono se estima por las palabras y la velocidad;
  - con audio ya generado, es el real.
  - ±10 s salta a la oración más cercana a ese tiempo.
- **«Leer: Todo · Resumen · Síntesis · Palabras clave»** se conserva, ahora en «Contenido» y en la
  cola.
- **Velocidad** (captura 15):
  - una regla de 0,5× a 3,0× con la cifra grande;
  - atajos 1,0 · 1,2 · 1,5 · 2,0 · 3,0, sin candados.
- **Cola** (captura 7): lo que suena; «Siguiente», con «Limpiar cola» y para reordenar
  arrastrando; Repetir y el Temporizador para dormir (15, 30, 45 o 60 min, o al terminar esto).
- **Lectura enfocada** (Ajustes): el reproductor se achica solo mientras te desplazás.
- **Sigue sonando** al cambiar de pestaña. El mini reproductor queda encima de la barra de
  navegación, como el del audio (captura 16).

### 2b. En segundo plano y en la notificación

- **Sigue sonando** con la app minimizada, con otra app abierta o con la pantalla apagada. Lee el
  documento entero o la cola hasta el final, o hasta el temporizador.
- **Una tarjeta de reproducción en la barra de notificaciones** (la de los reproductores de música,
  la de Android):
  - la portada: la miniatura del documento o la cara de la voz;
  - el título y la voz, por ejemplo «Leyendo con Marisa · 1,0×»;
  - −10 s, ▶/⏸ y +10 s, y siguiente en la cola;
  - la barra de avance, que se puede arrastrar;
  - tocarla abre el documento en la línea que suena.
- **En la pantalla de bloqueo**, la misma tarjeta, y en los auriculares y en el reloj, ▶/⏸ y
  saltar.
- **Se porta bien con el resto del teléfono:**
  - una llamada o el GPS hablando lo pausan o le bajan el volumen;
  - desconectar los auriculares lo pausa;
  - al terminar, la tarjeta se va sola.
- **Un solo servicio en primer plano**, de tipo «reproducción de medios», con el permiso que
  pide Android. No es el de procesar, que sigue aparte.
- La misma tarjeta para todo lo que suena en la app: el lector, un podcast, un audio y la voz del
  chat.

### 3. La biblioteca de voces (capturas 10, 11, 12 y 13)

- **Una sola lista**, con las pestañas **Todas · Favoritas · Mías** (las clonadas y las creadas) y
  «Te puede interesar» arriba: voces del idioma del documento, con buena calidad.
- **Cada voz es una tarjeta:**
  - su cara;
  - el nombre, con la bandera del acento;
  - «ES · Cálido · Expresivo», con el ícono de para qué es ideal;
  - ♡ favorita;
  - ▶ una muestra corta;
  - de dónde es: **Teléfono**, **Sin conexión**, **Clonada** o **Creada**, y si es de la nube,
    con su costo.
- **Filtrar**, con el mismo pie de todos los filtros (punto 0, mejora 21): «Limpiar» arriba y
  «Ver N voces» abajo, aplicándose al tocar:
  - el idioma;
  - el acento (México, España, Argentina, Colombia, Chile, Perú…);
  - para qué es ideal: narrar, informar, aprender, conversar o relajarse;
  - el timbre;
  - el estilo;
  - el género;
  - la edad.
- **De dónde salen las voces** (decisión B), por defecto todas en el teléfono y gratis:
  1. **Las voces del teléfono**: las de hoy, sin conexión.
  2. **Voces neuronales sin conexión**, que suenan casi humanas. Son las de Piper y Kokoro,
     sobre `sherpa_onnx`, que la app ya usa para Whisper.
     - Cada voz se baja **solo si la pedís**, como Gemma, con su tamaño a la vista.
     - Se borra desde Ajustes.
  3. **Clonadas** y **creadas**: ver los puntos 4 y 4b. En el teléfono si se puede, o en la
     nube si la elegís.
- **Cada idioma con sus voces nativas, su acento y su tono** (decisión L):
  - Piper tiene voces en más de 30 idiomas, y en español hay de Argentina, España y México.
    Kokoro suma inglés, español, francés, italiano, portugués, japonés, hindi y chino;
  - **la voz sigue al idioma del texto**: un documento en inglés se lee con una voz inglesa y uno
    en francés con una francesa. Elegís una voz por idioma, y la app la recuerda;
  - si en un idioma no bajaste ninguna voz, lo dice y te ofrece la mejor de ese idioma, o la del
    teléfono mientras tanto;
  - **el tono**: cada voz trae el suyo (cálido, sereno, enérgico…). En las de Kokoro, además, se
    ajustan el ritmo y la expresividad;
  - en un texto con partes en dos idiomas, cada parte se lee con la voz de su idioma.
- **Varias voces en un mismo documento**, si querés: una para el texto y otra para lo que va
  entre comillas, las citas y los diálogos. En un podcast, una por persona que habla (punto 5).
- **Las caras:** sin fotos de personas reales. Cada voz tiene un retrato propio, abstracto, con su
  color, sus iniciales y su onda (decisión D).

### 4. Clonar una voz (captura 14)

- **«Clonación de voz»**, en Ajustes y en la pestaña Mías.
  - Una presentación: qué es, cómo se usa y que se puede borrar cuando quieras.
- **La voz de quien elijas, con su permiso:** la tuya, la de un amigo, alguien de tu familia o un
  profesor.
  - Antes de grabar, la app pide confirmar que es tu voz o que esa persona te dio permiso, y
    guarda ese consentimiento junto a la voz, con su nombre y la fecha.
  - La voz de una persona famosa o de alguien que no lo autorizó no se clona: es suplantarla.
    Para algo parecido está crear una voz (punto 4b).
- **Grabar 1 o 2 minutos**, leyendo un texto que propone la app, o **subir un audio**.
  - La app mide el ruido y avisa si conviene repetir.
- **Dónde se clona** (decisión C):
  - **en el teléfono, gratis y por defecto**, con ZipVoice sobre `sherpa_onnx`. Se mide primero si
    anda bien en español; si no da la calidad, la opción no se ofrece hasta que la dé;
  - **en la nube, solo si la elegís**: ElevenLabs, con tu propia cuenta y tu clave. Antes dice lo
    que cuesta (la clonación instantánea está desde unos USD 6 por mes) y que el audio de la
    muestra se sube a ElevenLabs. **Leer con esa voz también pasa por ElevenLabs**, y gasta su
    cuota: el reproductor lo marca, y lo largo avisa su costo antes.
- **La grabación queda en tu bóveda.** Borrar la voz la borra acá, y en ElevenLabs si estaba allá.
- Lo que lee una voz clonada se rotula «Voz clonada» en el reproductor.

### 4b. Crear una voz nueva, describiéndola

- **«Crear una voz»**, junto a «Clonar», en la pestaña Mías.
- **La describís**: «hombre joven, rioplatense, cálido y entusiasta, como un relator de fútbol»,
  o la armás con controles:
  - el idioma y el acento;
  - el género y la edad;
  - el timbre (grave, claro, aterciopelado…);
  - el estilo (sereno, expresivo, con autoridad…);
  - el ritmo.
- **Escuchás una muestra**, la ajustás y le ponés nombre y cara.
- **Dónde se crea** (decisión C):
  - **en el teléfono, gratis y por defecto**: Kokoro deja mezclar voces y ajustar su carácter, y
    con eso se arma una voz nueva que no es la de nadie;
  - **en la nube, solo si la elegís**: el diseño de voces de ElevenLabs, que parte de la
    descripción en palabras. Tiene el mismo costo avisado, y leer con ella pasa por ElevenLabs.
- Una voz creada no imita a una persona real. Si la descripción nombra a alguien, la app lo dice
  y propone describir el estilo en lugar del nombre.

### 5. El podcast a medida (captura 16)

- **Dónde:**
  - en Repasar, una tarjeta nueva, **Podcast**, en la grilla de crear;
  - en el lector, en la fila de IA.
  - En los dos casos, sobre el recorte o el documento de ese momento.
- **El formato:**
  - **Breve**, para lo esencial;
  - **Clase**, para aprender, con preguntas;
  - **Relato**, contado como una historia;
  - **Conversación**, dos voces que charlan y se repreguntan.
- **El idioma**, la **duración** (Corto ~3 min · Medio ~8 · Largo ~15) y **¿De qué trata?**:
  - tres propuestas sacadas del material;
  - un cuadro para pedir un enfoque propio;
  - «+» para sumar otro documento.
- **«Elegí las voces»**: una, o dos en Conversación, de la biblioteca, incluidas las clonadas y
  las creadas. Son voces nativas del idioma del podcast, con su acento.
- **Cómo se hace:**
  - la IA de turno escribe el guion **solo con lo del material**, con la cita de cada dato;
  - se genera la voz de cada tramo;
  - se guarda en la bóveda como una creación de «Lo creado».
  - Va en segundo plano, retomable y con el servicio de siempre, como las creaciones de F43.
- **Al escucharlo:** el mismo reproductor, con la transcripción que se sigue y cada cita
  tocable, que lleva al pasaje.
- Se rotula «Hecho con IA».
- **La voz, en el teléfono:** el audio lo generan las voces sin conexión, gratis. Si elegís una voz
  clonada o creada en la nube, antes se avisa el costo.
- **El guion** lo escribe la IA de turno, la que elegiste en Ajustes, como toda creación de «Lo
  creado». Con Gemma, todo queda en el teléfono.

### 6. Escuchar sin conexión y exportar

- **Descargar audio** de un documento o de un podcast, con la voz elegida: se genera en el
  teléfono y se guarda en la bóveda, nunca en la nube.
  - Con una voz de ElevenLabs, si la elegiste, antes se dice cuánto cuesta y se pide confirmación.
- **Exportar audio** a un archivo para compartir: el de un podcast, o el de un documento ya
  descargado.

### 7. Ajustes (capturas 16 y 17)

Lo que se suma:

- **Voz y lectura**, una sección nueva:
  - Biblioteca de voces (con la voz de ahora);
  - Clonación de voz y Crear una voz;
  - **Voces por idioma**: la elegida para cada idioma;
  - **La nube para voces**: apagada de entrada. Al prenderla, se carga tu clave de ElevenLabs y
    se ve lo gastado;
  - la velocidad por defecto;
  - **Lectura enfocada** (el reproductor se oculta al desplazarte);
  - la tipografía y el resaltado de lectura;
  - **Voces descargadas**, con su tamaño y para borrarlas.
- **Ayuda:**
  - **Guía de uso**, la `GUIA_DE_USO.md` dentro de la app, con su índice y su búsqueda;
  - **Novedades**, lo de cada versión;
  - **Acerca de**, con la versión y las licencias.
- **Widgets** de la pantalla de inicio de Android (decisión G):
  - **Seguir escuchando**;
  - **Para hoy · N tarjetas**;
  - **Guardar rápido**.

Lo que no se suma, y por qué (para que quede dicho):

- **Calificar la app** y **Compartir la app**: la app no está en una tienda; no hay a dónde
  llevar.
- **Solicitar una función**: la app es tuya; los pedidos son estos planes.
- **Cuentas vinculadas: Google** (convertir archivos y correos en audio): pide permisos de tu
  Drive y tu Gmail, y es una fase en sí. Queda para después, si la querés.

## Decisiones (se pueden cambiar mientras no se llegue a su paso)

- **A. Un solo marco de lectura para todo texto, que reemplaza a los cuatro de hoy.**
  - El paso 7a de F45 (mejoras 12 y 13: el lector único y el desplazamiento) **se hace acá**,
    como paso 1, para no construir dos veces.
  - El 7b de F45 (crear en un solo lugar, las marcas adentro y el original idéntico) va antes,
    porque el marco se apoya en él.
- **B. Todo en el teléfono, por defecto y sin gastos.** Las voces del teléfono y las neuronales
  sin conexión (Piper y Kokoro) leen documentos y podcasts. Ninguna voz se baja sin que la pidas.
  Las voces de Gemini y OpenAI no entran: leer en la nube cuesta, y no hace falta.
- **C. Clonar y crear, primero en el teléfono; la nube, solo si la elegís y solo para eso.**
  - En el teléfono, clonar con ZipVoice y crear mezclando voces de Kokoro. Se mide la calidad en
    español antes de ofrecerlo.
  - En la nube, ElevenLabs con tu cuenta, con el costo dicho antes de clonar, de crear y de leer
    algo largo con esa voz.
  - Siempre con el consentimiento de la persona; nunca la voz de alguien sin su permiso.
- **D. Caras propias, abstractas, sin fotos de personas reales.** Una foto de alguien real dice
  que esa voz es de esa persona, y no lo es.
- **E. El podcast es una creación más de «Lo creado» (F43):** con su fila, su retome, su cita a
  las fuentes y su lugar en la cola.
  - Las voces se generan tramo por tramo en el teléfono, con pausas y respiros naturales entre
    las personas que hablan.
- **F. Nada se sube a la nube por defecto.** El audio generado se guarda solo en tu bóveda, en el
  teléfono. Lo único que puede salir es la muestra de una voz que elijas clonar o crear en
  ElevenLabs, y el texto que lea esa voz, siempre con el costo avisado antes.
- **G. Los widgets, con `home_widget`, solo en Android.** Es una dependencia nueva del código, no
  software que se instale en la PC ni en el teléfono.
  - *Alternativa:* dejarlos para después.
- **H. La velocidad va de 0,5× a 3,0×, sin candados.**
- **I. El orden:**
  - F47 va **después de F45 y antes de F46**, porque cambia todas las pantallas de lectura y
    conviene que el Índice nazca con el marco nuevo.
  - *Alternativa:* F46 primero, como estaba aprobado.
- **J. Segundo plano y notificación con `audio_service`.** Arma la sesión de medios de Android (la
  tarjeta, la pantalla de bloqueo, los auriculares y el reloj) para cualquier cosa que suene,
  también la voz del teléfono, que no es un archivo. Es una dependencia nueva del código.
  - *Alternativa:* escribir la sesión de medios a mano en Kotlin (Media3), como el servicio de
    procesar. Es más código propio para lo mismo.
  - **Cambiada en el paso 2 por la alternativa**, a mano con la `MediaSession` de Android y sin
    dependencias nuevas: `audio_service` destruye el motor de Flutter al irse su servicio, y ese
    motor es el mismo de la cola de procesamiento (F29). El porqué, en el Avance del paso 2.

- **K. Los filtros se siguen aplicando al tocarlos, y el botón de abajo cierra el panel con la
  cifra de lo que se va a ver.** Así la cifra dice de antemano si un filtro deja algo, y no se
  pierde un filtro por cerrar el panel sin confirmar. *Alternativa:* nada se aplica hasta tocar
  «Aplicar», con «Cancelar» para volver atrás. No la recomiendo: cerrar el panel arrastrándolo o
  con «atrás» perdería lo elegido, y sin la cifra no se sabe si va a quedar algo.
- **L. Cada idioma con sus voces nativas.** La voz sigue al idioma del texto, con una elegida por
  idioma; un texto con partes en dos idiomas se lee con las dos.

## Pasos (cada uno, su commit y su push)

Cada paso lleva su GUÍA, sus pruebas (solo con dobles, a 360 dp con la letra al doble, en claro
y en oscuro, con el lector de pantalla) y sus mutaciones. Se integran en `main` de a uno.

**Ola 1:**

0. **Los dos arreglos** (mejoras 20 y 21, decisión K): fuera el lector en voz alta de las
   tarjetas de Repasar y el pie «Ver N resultados» del panel de filtros, en la Biblioteca, en
   Procesado y en «Volver a triar». Va primero porque es chico y se nota enseguida.
1. **El marco de lectura:**
   - el censo de funciones;
   - la barra con sus cuatro botones, la fila de IA, el cuerpo, Apariencia y ⋮;
   - en el original, el texto extraído, el resumen, la síntesis y lo creado, sin el botón
     flotante en ellos;
   - con las mejoras 12 y 13 de F45.
2. **El reproductor anclado y en segundo plano:**
   - abierto y achicado;
   - la tarjeta en la notificación y en la pantalla de bloqueo, los auriculares y la app
     minimizada;
   - el tiempo, ±10 s y la velocidad con su regla;
   - la cola, Repetir y el Temporizador para dormir;
   - Lectura enfocada.
3. **La biblioteca de voces:**
   - la lista, las tarjetas, Filtrar, Favoritas y las muestras;
   - las caras;
   - las voces sin conexión, a pedido, en cada idioma con su acento, y la voz que sigue al
     idioma del texto.

**Ola 2:**

4. **Clonar y crear voces:**
   - la grabación y el consentimiento;
   - en el teléfono: la medición de ZipVoice en español y Kokoro para crear;
   - en la nube, opcional: ElevenLabs con tu cuenta, clonar y diseñar, con el costo a la vista.
5. **Descargar y exportar audio**, generado en el teléfono.
6. **El podcast:**
   - la tarjeta en Repasar y la ficha en el lector;
   - el guion con citas y las voces;
   - lo guardado y la escucha con la transcripción.
7. **Ajustes:** Voz y lectura, Ayuda (la guía dentro de la app, Novedades y Acerca de) y los
   widgets.

**Cierre:**

8. **El cierre:**
   - la suite entera;
   - la decisión 93 en la arquitectura y la GUÍA;
   - la prueba con tus voces en el teléfono, si la pedís.

## Lo que no entra (para que quede dicho)

- **Voces de personas reales sin su permiso**, también las de famosos: la app no las clona ni las
  imita. Crear una voz describiendo un estilo sí se puede (punto 4b).
- **Leer con voces de la nube de Gemini u OpenAI**: no hacen falta, y cuestan (decisión B).
- **Las cuentas de Google** (Drive y Gmail) y **las tiendas** (calificar y compartir): ver el
  punto 7.
- **Traducir al leer**: la voz lee el texto en su idioma. Elegir una voz de otro idioma no lo
  traduce.

## Avance

### Paso 0 (hecho): Repasar sin el lector y el pie de los filtros

Cinco commits, de `b1d1c045` a `b4f2ddf3` (mejoras 20 y 21, decisión K).

- **Repasar, sin el lector en voz alta** (mejora 20, `review_session_card.dart`):
  - la tarjeta ya no ofrece leerse, en ninguna de sus tres formas, y nada resalta sus caras;
  - «Ver en la fuente» y «Explicar» quedan iguales;
  - lo que venía sonando sigue al entrar a Repasar, con el reproductor abierto o minimizado, y
    revelar la tarjeta no lo corta;
  - la decisión 58 de la arquitectura y los comentarios que decían que las tarjetas se leen,
    corregidos.
- **El pie «Ver N resultados»** (mejora 21), en el marco común de los filtros
  (`ListFiltersSheet`), así que llega a la Biblioteca, a Procesado, a «Volver a triar» y al
  material de un tema en el Explorador (que tenía su propia copia del marco y pasó al común):
  - los filtros se aplican al tocar (decisión K); el pie dice cuántos quedan, contados en la base
    sin traer documentos: «Ver N resultados», «Ver todo (N)» si nada acota (lo buscado también
    acota) y «Ver resultados» mientras cuenta, sin mostrar nunca la cifra vieja ni saltar de
    tamaño;
  - con cero, «Ningún resultado», apagado, con «Limpiar filtros» arriba;
  - cerrar con el pie vuelve la lista arriba; cerrado de otra forma, los filtros valen igual y la
    lista queda donde estaba;
  - para el lector de pantalla, un solo nodo con la frase y la región viva, que anuncia cada
    cambio;
  - de paso: el panel respeta la zona segura, y el título y «Limpiar filtros» ya no desbordan a
    360 dp con la letra al doble.
- **El Mapa y la Línea de tiempo no llevan el pie:** filtran un dibujo, no una lista, y la Línea
  de tiempo cuenta fechas. Si se quiere, con qué frase es una decisión del dueño. La biblioteca de
  voces lo lleva en su paso, con «Ver N voces».
- **Verificado:**
  - analyze en 19;
  - 3.265 pruebas del Explorador, las tarjetas, la Biblioteca, la narración, Organizar, Procesado,
    la app y la base;
  - murieron las 16 mutaciones. Entre ellas: la tarjeta que vuelve a ofrecer leerse, la cifra
    vieja mientras cuenta, el pie que salta de tamaño (sobrevivía hasta probarlo con una cifra
    de dos líneas), el cero prendido, la lista que no vuelve arriba y la región viva sin la frase.
  - commit por commit (`verify_commit`), cada uno compila solo. `85627b76` y `54b2530d` dan 20
    avisos, uno más que la línea base: un tipo de más en el `onPressed` de `list_controls.dart`,
    que corrige el commit siguiente, `b4f2ddf3`. No se reescribió la historia.
- **Queda para después:**
  - en la Biblioteca, el tablero y el calendario no tienen un «arriba» que recuperar;
  - en «Volver a triar», a 360 dp con la letra al doble, la explicación de arriba ocupa toda la
    pantalla (viene de antes);
  - no se miró en el emulador ni en el teléfono.

### Paso 2 (hecho): el reproductor anclado y en segundo plano

Cinco commits, de `1bed0d51` a `9b291f71`, y el de este avance (decisiones H y J, esta última
cambiada: ver abajo).

- **El dominio**, puro y probado:
  - `ReadingTimeline`: el tiempo por las palabras (150 por minuto a 1×) y la velocidad; ±10 s
    salta a la oración más cercana y siempre mueve. Reemplaza la medición del ritmo de F25.
  - `ReadingQueue` con Repetir (no, la cola, esto) y `SleepTimer` (15, 30, 45 o 60 min, o al
    terminar esto).
  - La regla de 0,5× a 3,0×, de a una décima, con los atajos 1,0 · 1,2 · 1,5 · 2,0 · 3,0 y sin
    candados (decisión H).
  - **De paso, un error viejo:** a `flutter_tts` se le pedía siempre la mitad de la velocidad,
    que es lo justo solo en Android. En la web 1× sonaba a la mitad y en Windows 2× sonaba a
    1,5×. Ahora `flutterTtsRate` traduce la escala de cada plataforma, solo adentro de
    `FlutterTtsService`; las voces sin conexión (sherpa) reciben el multiplicador tal cual.
- **El reproductor** (`ReadAloudAnchoredPlayer`, que ya monta `ReadAloudOverlay`):
  - **abierto:** el título que se desliza (dos pasadas, quieto sin animaciones), ⟲, ☰, ⌄, la
    barra con sus tiempos, la cara de la voz, −10 s, ▶ grande, +10 s y «1,0×»;
  - **achicado:** ▶, el título, +10 s y ⌃; arrastrarlo hacia abajo deja de leer, y el lector de
    pantalla tiene la acción «Dejar de leer»;
  - **la cola:** «Ahora suena» con «Leer: Todo · Resumen · Síntesis · Palabras clave» y «Dejar
    de leer», lo de la pantalla para sumar o leer ya, reordenar arrastrando, Repetir y el
    temporizador;
  - **la regla de la velocidad**, que se arrastra; el lector de pantalla la sube y la baja de a
    una décima;
  - **Lectura enfocada**, en Ajustes → «Voz y lectura», debajo de «Voces por idioma» y «Voces
    descargadas»: el reproductor se achica solo mientras te desplazás.
- **Con la biblioteca de voces (paso 3):**
  - la cara del reproductor es la de la voz que lee, con su nombre en «Leyendo con …», y tocarla
    abre la biblioteca (`openVoicePicker` → `showVoiceLibrary`);
  - la voz del sistema, que no tiene perfil en la biblioteca, tiene una cara propia que siempre
    es la misma;
  - ±10 s y la cola leen con la voz del idioma donde caen, y cambiar la velocidad vuelve a decir
    la oración y vuelve a preparar el pedazo siguiente a la velocidad nueva.
- **En segundo plano, la tarjeta de lo que suena** en la notificación, en la pantalla de bloqueo,
  en los auriculares y en el reloj:
  - el contrato está en `lib/core/audio/media_session.dart` (`MediaSessionState`, los comandos,
    las interrupciones y `MediaSessionSource`, lo que implementa cada cosa que suena);
  - `MediaSessionHub` muestra lo que tiene el foco de audio de la app y manda solo lo que cambia
    a la vista; la barra la adelanta el teléfono y se corrige si se aparta más de 2 s;
  - una llamada pausa y al cortar sigue; otra app que se queda con el sonido pausa y no vuelve;
    desconectar los auriculares pausa; al terminar, la tarjeta se va;
  - hoy suenan ahí el lector (con la voz del chat) y un audio o un video, que siguen sonando en
    segundo plano con su título y su tiempo real;
  - **la portada** es la cara de la voz, dibujada una vez por voz como PNG; mientras lee la misma
    voz se manda la misma imagen.
- **La decisión J, cambiada: sin `audio_service`.** Su código busca el motor de Flutter por su
  propio nombre y lo destruye cuando su servicio se va y no hay actividad. El motor de la app es
  el del proceso (F29), así que cerrar la app desde «recientes» habría matado la cola de
  procesamiento (F21 y F29). Se hizo la alternativa de la misma decisión: la sesión de medios a
  mano, con `MediaSession` y `Notification.MediaStyle` de Android y **sin dependencias nuevas**.
  El servicio es de tipo «reproducción de medios» (`FOREGROUND_SERVICE_MEDIA_PLAYBACK` y
  `WAKE_LOCK`), aparte del de procesar; el porqué queda escrito en `MediaSessionChannel.kt`.
- **Los avisos van por encima del reproductor:** lo que ocupa se publica en
  `readAloudPlayerExtentProvider` con dos cifras: `current`, lo que ocupa ahora, y `resting`, lo
  que ocupa en la forma elegida, sin el achicarse pasajero de la Lectura enfocada. Con `resting`
  suben hoy los `SnackBar`, por el tema: con una sola cifra, el tema de toda la app cambiaba a
  mitad de un desplazamiento y Flutter tiraba un error de semántica.
- **Para el podcast (paso 6b):** implementa `MediaSessionSource` y se registra en
  `mediaSessionSourcesProvider` con el mismo testigo con que toma `audioFocusProvider`; la
  portada ya está en el contrato.
- **Verificado:**
  - analyze en 19;
  - 2.795 pruebas de la narración, Ajustes, la app, `core`, los visores, la Biblioteca, extraer
    y Repasar con el lector, y las 454 del chat, después de unir el paso 3; antes de unirlo
    habían pasado 3.025, con el chat;
  - murieron las 33 mutaciones: 25 del paso (diez del dominio, siete del reproductor y ocho de la
    tarjeta) y 8 de la unión con el paso 3. Entre ellas: la cara que no abre la biblioteca, el
    pedazo leído con la voz de antes, la velocidad que no vuelve a preparar, sherpa recibiendo la
    escala de `flutter_tts` y la portada que se redibuja con cada cambio (colgó las pruebas, y
    cuenta como muerta);
  - el APK de depuración compiló los tres sabores con el Kotlin nuevo.
- **Queda para después:**
  - **para el paso 1 (el marco):** la ruta del documento en `ReadableDocument`, para que tocar
    la tarjeta lo abra en la línea que suena (hoy trae la app al frente con el reproductor
    abierto); un margen abajo para que el reproductor no tape lo último de cada lista; «Añadir a
    la cola» en ⋮, con `controller.enqueue`; llevar «Leer: …» a «Contenido»; y sacar el botón
    redondo de los lectores;
  - **para F45 paso 1:** el anfitrión de los avisos lee `readAloudPlayerExtentProvider.current`;
  - en iOS no hay tarjeta y la voz del teléfono no pasa de su techo: no se escribió código para
    iOS;
  - no se miró en el emulador ni en el teléfono.

### Paso 3 (hecho): la biblioteca de voces

Siete commits, de `7b26d6d8` a `7d82b688`, y el de este avance
(decisiones B, D y L).

- **El catálogo** (`OfflineVoiceCatalog`), relevado de la versión `tts-models` de sherpa-onnx el
  30/10:
  - **26 paquetes de Piper, 28 voces**: español de Argentina (Daniela), España (Davefx, Sharvard
    F y M, Carlfm) y México (Claude, Ald); inglés de Estados Unidos (Lessac, Ryan, HFC mujer y
    hombre) y del Reino Unido (Cori, Alba, Northern English); portugués de Brasil (Faber, Cadu,
    Jeff) y de Portugal (Tugão); francés (Siwis, Tom, Jessica y Pierre); italiano (Paola,
    Riccardo) y alemán (Thorsten, Kerstin, Ramona, Eva K). El modelo original de cada una, el que
    documenta sherpa-onnx; de 26 a 116 MB.
  - **Kokoro multilingüe v1.0 en 8 bits, 132 MB, 28 voces**: inglés de Estados Unidos (11) y del
    Reino Unido (4), español (3), francés (1), italiano (2), portugués de Brasil (3) e hindi (4).
  - Cada paquete con su tamaño y su huella SHA-256, que se comprueban al bajarlo.
  - **Sin confirmar, y por eso sin poner:** el género de las de Piper cuyo modelo no lo dice (solo
    se puso en HFC, Northern English y Sharvard, y en todas las de Kokoro); el tono, el timbre, el
    estilo, la edad y para qué es ideal de todas (nadie los publica); la calidad de las de Kokoro
    en español y en portugués (sin nota en `VOICES.md`).
  - **Afuera:** GLaDOS (imita un personaje), las de Kokoro con nota D o F —todas las de chino—, las
    de japonés (sherpa-onnx las pronuncia con espeak-ng, sin comprobar que alcance), y las
    `-int8`/`-fp16` de Piper, más livianas pero sin medir en el teléfono.
- **El motor sin conexión** (`sherpa_onnx` 1.13.8, ya en la app por Whisper): VITS para Piper,
  Kokoro con su `sid` y su `lang` de espeak-ng (o su léxico, en inglés), en un isolate con hasta
  dos voces armadas. Cada tramo es un WAV que suena con `video_player`; el siguiente se genera
  mientras suena el de ahora. Solo en Android: en la web y en Windows no se ofrece y lee la del
  sistema (implementación nula).
- **Bajar a pedido**, con la transferencia de todos los modelos y su retome al abrir la app; el
  `.tar.bz2` se abre en un isolate sin tragarse errores ni escribir afuera. Se borra desde Ajustes
  → «Voces descargadas».
- **La biblioteca** (`showVoiceLibrary(context)`), que reemplaza la hoja «Voz y acento»: Todas ·
  Favoritas · Mías, «Te puede interesar», las tarjetas con su cara, ♡ y ▶, Filtrar con «Ver N
  voces» y Mías vacía, lista para el paso 4.
- **La voz sigue al idioma del texto**, pedazo por pedazo, con una elegida por idioma (en las
  preferencias, sin tabla nueva); Ajustes → «Voces por idioma».
- **Para el paso 2:** la cara de la voz es `VoiceFaceView.of(voz)` con `currentVoiceProfileProvider`
  (la voz que lee ahora), y tocarla abre `showVoiceLibrary(context)`.
- **No entró:** «Varias voces en un mismo documento» (texto y comillas). Hace falta partir cada
  pedazo en tramos con su voz y que el resaltado, los ±10 s y la cola sigan al tramo: es lo que
  arma el paso 6 (el podcast, decisión E, tramo por tramo y una voz por persona). Queda ahí.
- **Verificado:**
  - analyze en 19;
  - 2.912 pruebas de la narración, Ajustes, los modelos de IA, `core`, la app, la Biblioteca y el
    visor de Repasar;
  - murieron las 20 mutaciones. Una sobrevivía —sacar la velocidad de la clave de lo preparado—
    porque la clave repetía lo que cambiar la velocidad ya descarta: se sacó lo repetido y se
    mutó lo que queda. Entre las otras: la voz que no sigue al idioma del pedazo, una del teléfono
    de otro idioma, una voz borrada que sigue leyendo, el filtro que no cuenta, la favorita que no
    se guarda, la cara que cambia, una voz que se baja sin pedirla, un paquete con otra huella o
    sin modelo, y abrir un paquete afuera de su carpeta.
- **Queda para después:**
  - medir en el teléfono cuánto tarda cada voz en generar una oración (sobre todo Kokoro) y si la
    pausa entre oraciones se nota;
  - que el idioma guardado de la fuente (`Source.language`) llegue al lector: hoy se detecta del
    texto;
  - no se miró en el emulador ni en el teléfono.

### Paso 6a (hecho): el podcast, hasta el guion

Seis commits, de `5e8f3d09` a `547430b3` (decisiones B, E, F y L). La segunda parte —el audio de
cada tramo y la escucha— es el paso 6b.

- **Una creación más de «Lo creado»** (decisión E): el tipo `podcast` entra en `study_creations`,
  cuyo tipo es texto, así que el esquema no cambia. Usa la cola de F43 tal cual: su fila, «ahora /
  más tarde», el retome hasta tres veces, el servicio en primer plano y la papelera.
- **La tarjeta «Podcast» en Repasar** (la grilla pasa a 11) y su hoja, la común de lo creado, que
  ganó dos piezas que cualquier tipo puede pedir:
  - «+ Sumar otro documento», que abre el selector de arriba de Repasar; lo sumado va a las
    fuentes de esa creación, no al recorte;
  - un tema con nombre propio —en el podcast, «¿De qué trata?»—, con tres propuestas sacadas de
    las palabras clave del material.
- **El guion se escribe por vueltas:** lo que no entra en una respuesta del modelo se escribe en
  varias (con Gemma, 2 en Corto y 8 en Largo; con uno de la nube, un Medio sale en una). La primera
  abre, la última cierra, cada una sabe cómo terminó la anterior, y si el material va por partes
  cada vuelta lee su tramo, en orden.
- **La duración se mide en palabras** y nunca pasa de 1,5 palabras de podcast por palabra leída:
  si el material no da para lo pedido, no se rellena, y el visor lo dice.
- **Cada tramo se comprueba contra el material**, con la forma de F43 (se queda lo que se
  sostiene y se le pide a la IA, una sola vez, que corrija con el porqué):
  - una cita vale solo si está entera en lo que leyó esa vuelta (sin mayúsculas, tildes ni signos;
    la elipsis marca pedazos salteados, en orden); menos de 4 palabras o de 24 letras no cuenta, y
    su documento sale de dónde se la encontró, no de lo que dice la IA;
  - se quita, con su porqué, el tramo de datos sin cita, el de citas que no están y el de una
    cifra que el material no tiene (1.200, 1,200 y 1200 cuentan igual); un saludo, una pregunta o
    una transición de hasta 30 palabras, sin cifras, no necesita cita;
  - vuelve a la IA la vuelta fuera de 70–140 % de lo pedido, la que se quedó sin tramos y la
    Conversación de una sola voz; si corregida tampoco cumple, falla con «Reintentar»;
  - lo quitado queda guardado, tachado y con su motivo, y el visor lo cuenta.
- **Las voces, como dato** (`{speaker, voiceId}` con prefijo de origen, `device:es-AR:<nombre>`),
  para que la biblioteca sume las suyas sin migrar. Se ofrecen solo las del teléfono que leen sin
  conexión (decisiones B y F: las de internet mandarían el guion afuera); siguen al idioma del
  podcast (decisión L), y en Conversación se eligen solas dos distintas.
- **Las pausas**, por tramo y listas para el audio: 300 ms con la misma voz, 550 ms al cambiar y
  1.200 ms donde la IA pidió una larga.
- **Lo guardado:** el guion como transcripción, cada cita tocable que lleva al pasaje, «Hecho con
  IA» con el modelo (F43 no lo tenía), y el botón de escuchar apagado con «El audio se genera en el
  paso siguiente», sin fingir un audio.
- **De paso:** el buscador de pasajes y el salto al pasaje salieron del mapa mental a un lugar
  común que usan los dos; el mapa mental se comporta igual.
- **Para el marco (paso 1):** `startPodcast(context, scope)` abre la misma hoja desde la ficha del
  lector.
- **Verificado:**
  - analyze en 19;
  - 3.769 pruebas de lo creado, las tarjetas, Repasar, la app y la base, con la cola de verdad
    sobre SQLite;
  - murieron las 21 mutaciones. Entre ellas: el tramo sin cita que pasa, la cita incompleta o que
    se conforma con su comienzo, la cifra inventada, la duración que no se respeta, una sola voz en
    Conversación, las dos personas con la misma voz, la cita que no lleva al pasaje, el trabajo que
    no se retoma y el botón que finge un audio. Una salió «colgada» con la PC cargada; sola muere
    en 11 s.
- **Queda para después:**
  - **el paso 6b:**
    - el audio de cada tramo con las voces sin conexión;
    - la escucha en el reproductor anclado, con la transcripción que se sigue;
    - las voces de la biblioteca en `podcastVoiceOptionsProvider`;
    - el costo antes, si se elige una voz de la nube;
  - **el retome por vuelta:** hoy un Largo con Gemma que se corta en la vuelta 6 de 8 vuelve a
    empezar; guardar las vueltas pide un método nuevo en el repositorio de creaciones;
  - **con Gemma y un documento mediano**, el material puede ser solo el resumen o la síntesis (el
    armado de F43 elige lo que entra), y el podcast sale más corto; el visor lo dice;
  - exportar el guion como texto;
  - no se miró en el emulador ni en el teléfono.

### Paso 7a (hecho): Ayuda y los widgets

Ocho commits, de `ed236298` a `b43a3f97`, y el de este avance (decisión G). La segunda
parte —Ajustes → «Voz y lectura» entera— es el paso 7b.

- **De paso, un arreglo de base:** el armado de los bloques de Markdown del chat (títulos, listas,
  citas, código y tablas) salió de `chat_answer.dart` a `MarkdownBlockStyle` y
  `MarkdownBlockView`, para que la guía y las novedades se lean con la misma letra. El chat se ve
  igual.
- **La guía de uso dentro de la app** (Ajustes → Ayuda):
  - `GUIA_DE_USO.md` y `NOVEDADES.md` se empaquetan desde la raíz, sin copias; una prueba
    comprueba que lo empaquetado es igual al archivo;
  - se parte en capítulos por sus «##», con las secciones («###») en el índice; el «Índice»
    escrito a mano de la guía se deja afuera, porque la app arma el suyo. Un censo comprueba que
    cada «##» y cada «###» aparecen, en orden;
  - un capítulo por vez, con «Anterior» y «Siguiente», y «atrás» vuelve al índice; los párrafos
    cortados a mano se leen de corrido y el texto se puede seleccionar;
  - **la búsqueda** no distingue mayúsculas ni acentos y toma cada salto de renglón como un
    espacio; desde el índice lista cada resultado con su renglón, y dentro de un capítulo una
    barra dice «3 de 17» y salta de uno a otro, cruzando capítulos; el resultado de ahora va en
    amarillo y los demás con el fondo de resaltado.
- **Novedades y «Acerca de»:**
  - `NOVEDADES.md`, una etapa por «##», de F47 (en curso) a «F1 a F12 · La base», armado con los
    planes, sus Avances y las decisiones de la arquitectura, sin nada que no se pudiera
    respaldar; arriba, la versión que está corriendo;
  - la versión sale de `package_info_plus` (ya venía por `sentry_flutter`; se declaró directo en
    la misma 9.0.1), con el sufijo del sabor en Android;
  - las licencias, con el tema de la app y con las ocho letras empaquetadas (OFL), que antes no
    se mostraban; un censo comprueba que cada letra de `fonts:` tiene su licencia.
- **Los tres widgets de Android** (`home_widget` 0.10.0, BSD-3; decisión G), con una
  implementación nula en la web y en Windows, y Ajustes → Widgets con «Agregar» en cada uno (si el
  teléfono no deja, explica cómo hacerlo a mano):
  - **«Para hoy»:** el mismo número de la insignia de Repasar, válido hasta el fin del día de
    estudio (las 4:00); se actualiza con la bóveda abierta, ante cada cambio y al volver a la app,
    y el sistema lo redibuja cada hora. Con la cifra de ayer dice «Tocá para ver lo de hoy»; con
    cero, «Estás al día»;
  - **«Guardar rápido»:** abre Guardar en «Texto para pegar» con el cursor en el cuadro; lo que
    llega compartido desde otra app sigue mandando;
  - **«Seguir escuchando»:** lo último que empezó a sonar con el foco de audio de la app, el mismo
    que muestra la tarjeta de la notificación del paso 2 (`focusedMediaSourceProvider`, junto al
    hub): el lector, un audio o un video, y lo que se sume a la tarjeta, como el podcast. Cuenta al
    empezar algo nuevo (otra fuente u otro título); pausar y seguir no cuenta, ni lo que suena sin
    el foco. La dirección es la pantalla de arriba de todo cuando empieza a sonar; al widget solo
    va el título.
  - **Los toques** van por un canal propio (`app.sinapsis/home_widgets`) con un pedido pendiente,
    como el aviso diario: `home_widget` perdería el toque que abre una actividad nueva sobre un
    Dart que ya andaba, porque el motor sobrevive a la actividad (F29). Con la bóveda cerrada, el
    pedido espera a que se abra;
  - los diseños, con los colores del tema claro y oscuro de la app (un censo los compara con
    `AppTheme`), y los textos en castellano y en inglés.
- **Ajustes, en orden:** Vos · Apariencia · Voz y lectura · Citas · IA · Segundo plano · Bóveda ·
  Desarrollo (solo en la versión de desarrollo) · Widgets (solo en Android) · Ayuda · «Bloquear
  bóveda».
- **Verificado:**
  - analyze en 19;
  - antes de unirlo con el paso 2, 2.407 pruebas de Ajustes, la app, `core`, la Ayuda, los
    widgets, el chat, Guardar y la narración; después, 2.696 (sumando el visor);
    ya sobre el paso 8a de F45 y el arreglo del chat, 2.739 de Ajustes, la app, `core`, la
    Ayuda, los widgets, la narración, el chat, el visor y las notas en el texto; dos de tiempos
    que fallaron con la PC cargada pasaron después, junto con las 520 del chat y la Ayuda;
  - murieron las 28 mutaciones: 22 del paso y 6 de la unión con la sesión de medios. La de «la
    sección de widgets aunque no haya widgets» sobrevivía porque, con la letra al doble, la
    sección quedaba fuera de la vista: la prueba pasó a mirar Ajustes entero. Entre las otras: el
    índice escrito a mano que entra como capítulo, buscar sin plegar los acentos, la frase
    partida en dos renglones que no se encuentra, «siguiente» que no da la vuelta, la dirección
    mandada al widget en vez del título, un toque con la bóveda cerrada que se pierde, el fin del
    día equivocado, el color oscuro separado del tema, contar lo que está en pausa y no seguir a
    la fuente nueva cuando cambia el foco;
  - el APK de depuración compila.
- **Para decidir con el dueño:** «Seguir escuchando» guarda el título sin cifrar y lo muestra en la
  pantalla de inicio aunque la bóveda esté cerrada. La pantalla de los widgets lo avisa.
- **Queda para después:**
  - **el paso 7b**, «Voz y lectura» entera: la biblioteca con la voz de ahora, clonar y crear,
    la nube para voces (ElevenLabs), la velocidad por defecto, la tipografía y el resaltado de
    lectura. «Voces por idioma», «Voces descargadas» y «Lectura enfocada» ya entraron;
  - cuando el marco (paso 1) dé ruta a lo que lee el lector, sumar `location` a
    `MediaSessionSource` para que cada fuente diga su dirección;
  - los enlaces `[…](#…)` del cuerpo de la guía se ven pero no se tocan: hacerlo pide cambiar
    `RenderedMarkdown`, que usa toda la app;
  - no se miró en el emulador ni en el teléfono.
