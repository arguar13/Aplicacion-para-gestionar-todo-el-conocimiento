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
  - **Precisada el 5/11 por el usuario**: «Seguir escuchando» no muestra el título con la bóveda
    cerrada —dice «Protegido: tocá para seguir»—, y un interruptor en Ajustes › Widgets, «Mostrar
    el título con la bóveda cerrada», lo deja a la vista para quien lo quiera. De entrada,
    apagado: protege por defecto. Hecho en el paso 7a-bis.
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
  - **Precisada el 5/11 por el usuario**: con el teléfono bloqueado la tarjeta no dice qué suena
    —«Reproduciendo» y el nombre de la app, sin título ni imagen, con los mismos botones—, y un
    interruptor en Ajustes › Privacidad, «Mostrar el título en la pantalla de bloqueo», lo deja
    a la vista. De entrada, apagado. Hecho en el paso 7a-bis.

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

### Paso 1 (hecho): el marco de lectura

Veintiún commits, de `574527a7` a `d56d0716`, y el de este avance (decisión A). Va sobre F45 7b
(el original único de Procesado y la Biblioteca) y trae las mejoras 12 y 13 de F45. Se unió con
los pasos 2, 3, 6a y 7a.

- **El censo de funciones** (`reading_census_test.dart`): las 30 funciones de «Lo que hay hoy»,
  cada una con dónde quedó y una prueba que llega a ella en el marco. Al final se comprueba que
  no quedó ninguna sin alcanzar. La única pendiente son las notas en el texto, cuya interfaz
  hace F45 8b sobre este marco. *(Entraron con F45, paso 8b: «Nota» en la barrita, el globito en
  el margen y ⋮ «Notas (N)»; el censo queda en 30 de 30.)*
- **El marco** (`ReadingFrame`), uno solo:
  - la barra: ← y cuatro botones redondos con borde, del mismo tamaño —Contenido, IA, Aa y ⋮—,
    que no crecen con la letra. El título va grande, en el cuerpo;
  - la fila de IA, que el botón IA prende y apaga, y que se recuerda. Va en un renglón que se
    desplaza de costado:
    - Resumir · Sintetizar · Palabras clave, con su estado y su avance;
    - Preguntar a la IA, que abre el chat con la pregunta sobre el documento a medio escribir;
    - Podcast, que abre la hoja del paso 6a (`startPodcast`) sobre el documento procesado o sobre
      el recorte de lo creado. Fuera de lo procesado queda apagada y dice por qué;
  - el cuerpo, en una columna de ancho cómodo, sin la tarjeta de papel, con la letra de
    Apariencia y la línea que suena con el «Resaltado de lectura»;
  - abajo, «Escuchar» si no suena nada.
- **El reproductor es el anclado del paso 2**, uno solo en toda la app:
  - sonando, el marco le deja su lugar abajo (el `resting` de `readAloudPlayerExtentProvider`),
    así no tapa lo último que se lee;
  - el botón redondo no va en el marco (`ReadAloudDock`);
  - salen el reproductor propio de los visores de extraer (`ExtractPlayer` y
    `ExtractListenPlayer`) y el mini reproductor del marco: el anclado ya trae la barra que se
    arrastra, ±10 s, la cola y la voz;
  - ⋮ suma «Añadir a la cola» (`controller.enqueue`), y «Leer: …» está en Contenido.
- **La dirección de lo que suena** (`ReadableDocument.location`):
  - el documento la toma de la pantalla que lo ofrece (`ReadableRegion`, con la ruta de arriba
    del router);
  - la fuente del lector la dice a la tarjeta (`MediaSessionSource.location`). Un audio suelto
    no la dice;
  - tocar la tarjeta lleva a esa pantalla si no se está ahí;
  - «Seguir escuchando» (paso 7a) guarda esa dirección y no la de la pantalla de arriba.
- **Apariencia**, guardada para todos los lectores:
  - cinco letras que viajan con la app: Lora (la de entrada), Source Sans 3, Inter, Nunito y
    Atkinson Hyperlegible Next. Atkinson es la que se suma: licencia OFL, 240 KB entre la
    redonda y la itálica, y se baja con `tool/fetch_reading_fonts.sh`;
  - el tamaño, de 80 % a 160 % (la misma preferencia que tenían A− A+);
  - el color de lo que suena: Amarillo, Durazno, Lila o Lima;
  - el modo: Sistema · Claro · Oscuro · Sepia;
  - en un PDF o una foto, el zoom y el tono de la página: Original, Oscura (sin cambiar los
    colores de lo marcado) o Sepia.
- **⋮**: la miniatura, el título con ✎ y el tipo, y los grupos de cada lector. En rojo va lo que
  se borra (la copia del original, la creación, el documento procesado); la fuente nunca.
- **Contenido**:
  - el índice que arma el cuerpo: los capítulos de un libro, los documentos de una extracción;
  - las partes del documento y «Ver N fuentes»;
  - «Leer: Todo · Resumen · Síntesis · Palabras clave».
- **Todos los tipos de documento** se leen en el marco:
  - el original: PDF, página web en vista móvil, libro paginado, foto con «Imagen · Texto»,
    audio, video y YouTube con la transcripción;
  - el texto, el resumen y la síntesis de un documento procesado. Usan el mismo lector que
    «Lo creado», rotulado «Texto · N páginas», sin crear nada, y se editan desde ⋮;
  - lo creado: el texto completo, el resumen, la síntesis y el informe;
  - la fuente que se lee para destilar: una nota, una referencia, el pasaje de una tarjeta.
- **El desplazamiento** (mejora 13): una prueba que mide un mismo gesto confirmó la causa. El
  texto de corrido usa ahora la física de la plataforma; el impulso extra queda solo en el PDF.
- **Salen**:
  - la barra de «Lo creado» para lo que se lee: 🎧 y «Lectura» (`ExtractListenButton`,
    `ExtractReadingSheet`);
  - A− A+ (`ReaderFontScaleNotifier`);
  - la tarjeta de papel;
  - el panel de las fichas arriba del original. Queda solo en la pantalla de cortes del triaje;
  - el texto desplegable de Procesado.
- **Verificado:**
  - analyze en 19;
  - 5.558 pruebas de la lectura, los visores, Procesado, la narración, la Biblioteca, lo
    creado, Crear, Estudiar, la app, `core` y los widgets, ya sobre `main` con los pasos 2, 3,
    6a y 7a y el 8a de F45;
  - dos pruebas viejas cambiaron con el diseño: «Ir a lo que suena» va con su nombre debajo del
    reproductor (la barra lleva solo sus cuatro botones), y las licencias de las letras cuentan
    la de Atkinson. Una de tiempos (`reader_pagination_off_thread_test`) falló una vez con la PC
    cargada y pasó en las corridas siguientes;
  - murieron las 32 mutaciones, todas por pruebas que fallan. Entre ellas: el botón flotante
    dentro del marco, el marco que aparta también el reproductor anclado, el reproductor que tapa
    lo último que se lee, «Añadir a la cola» que lee ya, la ficha Podcast que no abre la hoja, la
    letra elegida que no se guarda, la página oscura sin invertir el negro, un capítulo de
    Contenido que no salta a su página, lo ofrecido sin su dirección y tocar la tarjeta que apila
    la misma pantalla otra vez.
- **Queda para después:**
  - **el margen abajo fuera del marco.** En el marco, el reproductor no tapa nada. En las listas
    de las demás pantallas (la Biblioteca, Procesado, Repasar) todavía puede tapar el último
    renglón. Darlo de una vez para toda la app no tiene un lugar limpio:
    - subir el borde seguro (`MediaQuery.padding`) agranda la barra de navegación;
    - fingir el teclado (`viewInsets`) confunde a lo que mira si está abierto.
    Hace falta una pieza que cada lista pida, o que el anfitrión de los avisos de F45 paso 1 dé
    ese margen;
  - un visor que se abre con `Navigator.push`, sin una ruta propia (el original de la
    Biblioteca, la foto, el audio), dice la dirección de la pantalla de abajo. Para volver
    justo a él hace falta darle una ruta;
  - descargar y exportar el audio (paso 5): no está en ⋮ (las notas (N) ya están, con F45,
    paso 8b);
  - Favoritos, Marcar como terminado e Imprimir no existen en la app. Necesitan su dato en la
    base (o un paquete de impresión), así que no se inventaron. Hoy, «Imprimir» es el PDF de lo
    creado;
  - en la página web, Apariencia cambia el modo y el color de lo que suena, pero no la letra,
    que es la de la página;
  - la miniatura de ⋮ es la imagen en una foto y el ícono del tipo en lo demás;
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
  - commit a commit (`verify_commit`): `2e6fba0c` y `bdbb0a4a` dan 20, por dos textos pegados
    sin espacio en la prueba del controlador del lector, que corrige `7d82b688`. La historia ya
    estaba subida y no se reescribió.
- **Queda para después:**
  - medir en el teléfono cuánto tarda cada voz en generar una oración (sobre todo Kokoro) y si la
    pausa entre oraciones se nota;
  - que el idioma guardado de la fuente (`Source.language`) llegue al lector: hoy se detecta del
    texto;
  - no se miró en el emulador ni en el teléfono.

### Paso 4 (hecho): clonar y crear voces

Nueve commits, de `eab4686a` a `af851c0f`, y el de este avance (decisión C; puntos 4 y 4b).

- **Las voces propias** (`MyVoice`): clonadas o creadas, en el teléfono o en ElevenLabs, en la
  pestaña Mías de la biblioteca, con su cara, sus rasgos para Filtrar y, las de la nube, su costo
  y su muestra guardada (oírla no gasta).
  - **El consentimiento va primero:** de quién es la voz, su nombre, la confirmación y la fecha.
    Una ficha clonada sin consentimiento no se carga (`fromJson` da `null`), tampoco la que llega
    al unir bóvedas. La voz de un famoso o de alguien sin permiso no se clona: no hay opción para
    eso, y la pantalla lleva a «Crear una voz».
  - `checkRealPerson` avisa si una descripción nombra a una persona real, con una heurística y sin
    listas de famosos.
- **Clonar en el teléfono no se ofrece** (`OnDeviceCloning.available = false`), y no por falta de
  medirlo: el único modelo de ZipVoice publicado para sherpa-onnx 1.13.8 es chino e inglés, y su
  frente pasa el texto a fonemas con espeak-ng en `en-us` fijo, así que el español sonaría como
  inglés. Hace falta un modelo con español y un frente que use `es`; con eso se mide en el
  teléfono, como dice `docs/benchmarks/F47-zipvoice-en-el-telefono.md`. La pantalla lo dice, con
  el porqué, y ofrece clonar en ElevenLabs.
- **Crear una voz en el teléfono**, gratis, mezclando las de Kokoro (`KokoroBlend`):
  - el timbre (las primeras 128 columnas del estilo) y la forma de hablar (las últimas 128) se
    mezclan aparte, siempre con dos voces o más en el timbre y ninguna por encima del 80 %;
  - la descripción pone los controles (`interpretVoiceDescription`, en español e inglés), la mezcla
    queda a la vista, con «Escuchar muestra» y «Otra variante»;
  - sherpa-onnx termina el proceso si el `voices.bin` no tiene exactamente los hablantes del
    modelo, así que cada creada ocupa un lugar de una copia del mismo tamaño (`KokoroStyleBank`),
    escrita en un isolate. El lugar se asigna al armarla (`blendSlots`, de la más vieja a la más
    nueva, hasta 54), no se guarda en la ficha: así las de dos bóvedas unidas no chocan. La que no
    cabe está en Mías pero no lee, y su tarjeta lo dice.
- **La nube para voces** (ElevenLabs, con la cuenta de quien la usa), apagada de entrada; apagada,
  la clave no sale aunque esté guardada:
  - clonar (instantánea) y diseñar (tres propuestas), con el costo antes de cada cosa; si guardar
    acá falla, se borra allá, y borrar empieza por allá («Borrar solo de este teléfono» si allá
    falla);
  - HTTP directo, sin paquete nuevo; la clave en el almacén seguro (`xi-api-key`) y cada error por
    su estado y su código;
  - leer con una voz de la nube (`CloudTextToSpeechService`): el siguiente tramo se pide mientras
    suena el de ahora, y la velocidad se cambia en el reproductor, sin volver a pagar;
  - `CloudReadingGate`: con más de 1.500 caracteres por leer pregunta una vez por documento, parte y
    voz, con los créditos que quedan; sin pantalla que pregunte, no se gasta.
- **La grabación** (`VoiceRecorderChannel`, Kotlin): WAV PCM de 16 bits a 44,1 kHz, sin paquete de
  grabación; `analyzeRecording` mide la duración, la voz, el ruido y la saturación, y dice si
  conviene repetir. También se puede subir un audio.
- **En el lector y el reproductor:** una voz propia lee solo si puede (Kokoro bajado, o la nube
  prendida con su clave) y cambia en el acto si deja de poder; sigue al idioma del texto como las
  demás; el reproductor dice «Voz clonada» o «En la nube».
- **En la bóveda:** las voces viven en `originales/voces-mias/<id>/` (`voz.json`, la grabación y la
  muestra), sin tabla nueva, y viajan en la copia. Unir bóvedas las trae sin pisar nada de acá ni
  traer las que se borraron acá (`borradas.json`); si la unión falla, se deshace. El `voices.bin`
  de las creadas no viaja: se arma de nuevo con sus fichas.
- **En el podcast** (con el enganche del paso 6b): `MySpeechVoiceRenderer`, dueño de `mia:<id>`,
  genera los tramos con las creadas (Kokoro, a su ritmo) y con las de la nube (el MP3 tal cual, que
  la pieza común pasa a WAV). Cobra en créditos, uno por carácter; una voz que todavía no se conoce
  cobra, para preguntar antes de gastar. Antes de generar, cada voz propia que cobra se aprueba con
  su puerta (`cloudReadingGateProvider.approve`); otra que cobre sigue con el aviso del paso 6b.
  Un «no» basta.
  - Carrera arreglada de raíz: la clave de la nube se carga sola al abrir, y generar apenas abierta
    la app daba la voz de la nube por faltante; ahora se espera a que se sepa (`loaded`).
- **Ajustes:** «Clonación de voz», «Crear una voz» y «La nube para voces» (el interruptor, la clave
  y lo gastado), también desde Mías. Todo a 360 dp con la letra al doble, en claro y en oscuro, y
  con el lector de pantalla.
- **De paso:** `tool/verify_commit.ps1` exporta también los recursos que declara `pubspec.yaml`;
  sin `GUIA_DE_USO.md`, `NOVEDADES.md` ni `assets/`, cada commit desde el paso 7a sumaba diez
  avisos `asset_does_not_exist` y no pasaba la línea base.
- **Verificado:**
  - analyze en 19, completo, sobre `4120c60d`;
  - 1.416 pruebas de la narración, la bóveda y la lectura; 2.552 de Ajustes, la app, los visores,
    lo creado con el podcast y la Ayuda (23 omitidas, y una que falla también en `main`: el censo
    de licencias de la Ayuda, por la letra Atkinson del paso 1); 1.328 de `core` con el censo de
    los avisos y la base;
  - murieron las 30 mutaciones: 19 del enganche del podcast y 11 de la unión de bóvedas;
  - `in_app_model_file_transfer_test` («se puede pausar») falló una vez y pasa sola 9 de 9: queda
    anotada como intermitente;
  - commit a commit (`verify_commit`): pendiente, con el resto de lo integrado el 5/11.
- **Queda para después:**
  - probarlo con una clave real de ElevenLabs en el teléfono;
  - clonar en el teléfono, cuando haya un ZipVoice con español;
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
  - commit a commit (`verify_commit`): `e45b01c2` da 20, por el import de `material.dart` sin
    uso en `podcast_kind.dart`, que saca `09aa91e9`. La historia ya estaba subida y no se
    reescribió.
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

### Paso 6b (hecho): el audio del podcast y su escucha

Diez commits, de `33e6a5c0` a `73bf31d5`, y el de este avance (decisiones B, E, F y L).

- **La pieza común para generar audio en el teléfono** (`SpeechAudioRenderer`, en
  `lib/features/narration/data/audio/`), la que reusa el paso 5:
  - de una lista de tramos `SpeechAudioPiece {text, voiceId, pauseAfter}` a un solo archivo;
    cada tramo con quien sabe hacer su voz (`SpeechVoiceRenderer`, por el prefijo del id);
  - **retomable por tramo**: cada uno en su WAV, nombrado por su texto, su voz y la versión de
    la voz, escrito aparte y renombrado al terminar; con la misma `workKey`, lo hecho no se
    rehace, y un tramo que cambió se genera solo él. Antes de generar nada se fija que estén
    todas las voces que faltan usar;
  - **el armado**, en otro isolate: recorta el silencio de cada motor (deja 40 ms), lleva todo a
    24 kHz mono y pone **exactamente** la pausa pedida (300, 550 o 1.200 ms en un podcast);
  - **el formato: M4A (AAC-LC, 64 kb/s, mono)**, con el codificador del sistema
    (`WavToM4a.kt`), que lee el WAV de a pedazos: un podcast de 15 minutos son ~7 MB en vez
    de 43 en WAV. **Sin dependencias nuevas.** No se usó `audio_decoder.convertToM4a`, que la
    app ya trae: decodifica el archivo entero a memoria, y con el audio de un documento de una
    hora un `OutOfMemoryError` —que no es una `Exception`— tumbaría el proceso con la cola
    adentro. Donde no hay codificador queda el WAV;
  - **lo que un motor deje en otro formato** —el MP3 de una voz de la nube— se decodifica con
    el `AudioToPcm.kt` de siempre (`SpeechClipDecoder`) antes de armar;
  - el avance (`onProgress(hechos, total)`, con un paso más para el armado), sin bloquear la
    interfaz: los motores trabajan en su isolate o en el sistema.
- **Las voces que sabe hacer**, en `speechVoiceRenderersProvider`:
  - `offline:<id del catálogo>`: Piper y Kokoro, con el mismo motor sherpa del lector, siempre
    a velocidad 1 (la velocidad se elige al escuchar);
  - `device:<acento>:<nombre>` (sin nombre, la del teléfono para ese idioma): **las del
    teléfono también**, con un `TextToSpeech` propio en Kotlin (`DeviceSpeechChannel.kt`). No
    con `flutter_tts`: avisa el fin de un archivo con el mismo «terminó» que el de una oración
    —el lector saltaría de oración con cada tramo del podcast—, y si el lector corta, la
    espera de `synthesizeToFile` no se completa nunca. Con su propia cola, generar un podcast
    no corta lo que se escucha. En la web y en Windows no se ofrece nada.
- **El avance guardado de una creación larga** (para el retome por vuelta y la voz):
  `StudyCreationRepository.checkpoint` / `saveCheckpoint`, un JSON de cada tipo con los
  archivos de la creación (`originales/<creación>/avance/`). **Sin esquema nuevo (no hizo falta
  la v50).** La cola se lo da al generador (`CreationJob.checkpoint`); «Reintentar» y el
  retome al abrir la app lo conservan, «Volver a generar» lo borra, y terminarla también.
- **Terminar sin la IA** (`CreationGenerator.finisherWithoutModel`): lo que queda se termina
  sin el modelo y sin armar el material —no espera a la IA ni a la cuota de fondo, y no falla
  porque se hayan borrado sus fuentes—.
- **El audio del podcast**, como una etapa más de la misma creación (decisión E): con el
  guion terminado se guarda entero (`PodcastVoiceProgress`) y `ServicePodcastVoicer` le da
  voz con la pieza común —`podcast-<creación>` es el trabajo—, con la fila «Generando la voz»,
  el retome de siempre (hasta tres veces) y el servicio en primer plano. Queda en
  `originales/<creación>/audio/` (decisión F) y el contenido lo nombra con `audio_ref`: la
  unión de bóvedas lo copia, y al guardar uno nuevo el viejo se barre. Si la voz no se pudo
  (una que falta, un motor, el disco), **el guion queda** con su porqué (`audioIssue`).
- **El retome por vuelta**: cada vuelta escrita se guarda (`PodcastScriptProgress`, con la
  clave del pedido, el material y el reparto en vueltas); un Largo con Gemma que se corta en
  la vuelta 6 de 8 sigue en la 7. Si cambió algo —el material, la ventana del modelo—,
  empieza de cero.
- **La escucha**, en el reproductor anclado de siempre: un `ReadableDocument` con su
  `RecordedSpeech` (el archivo, cuánto dura, dónde empieza cada tramo y qué voz lo dice).
  Con eso el lector no le pide nada a la voz: hace sonar el archivo (`SpeechTrackPlayer`,
  sobre `video_player`/ExoPlayer, que cambia la velocidad sin cambiar el tono):
  - el tiempo y la barra son los reales, contados a la velocidad de ahora como con la voz;
    ±10 s salta 10 s de lo que se oye; la velocidad cambia sin cortar; la cola, Repetir y el
    temporizador funcionan igual, porque es un documento más de la cola;
  - el tramo que suena y la cara de su voz siguen al audio; si el audio se pausa solo —una
    llamada—, el lector lo dice; un archivo que falta o falla no se finge;
  - **la tarjeta de la notificación**: el `MediaSessionSource` del lector, que ya es «el que
    suena» (y lo que usa «Seguir escuchando» de 7a por `focusedMediaSourceProvider`), dice
    «Escuchando a … · 1,0×» y **no pide el foco de audio**: ExoPlayer ya lo pide. No se
    sumó una segunda fuente para el podcast: sería un segundo reproductor de lo mismo,
    peleando el foco con el lector por el mismo reproductor anclado;
  - **su dirección** (`ReadableDocument.location`, del paso 1) es la de su visor,
    `/creations/<id>`, también cuando se abre con «Escuchar» y no desde la pantalla: la
    tarjeta y «Seguir escuchando» vuelven ahí.
- **El visor**: «Escuchar» se prende cuando el audio es de este guion con estas voces (la
  huella, `podcastAudioFingerprint`) y está en el teléfono; mientras suena, «Pausar», y en
  pausa, «Seguir escuchando». **La transcripción se sigue**: el tramo que suena en el amarillo
  del lector, y la vista lo acompaña con la política de siempre (`ReadAloudFollow`, «Volver a
  la lectura»). Sin audio, se dice por qué sin fingir —de otra versión del guion, no está en
  el teléfono, una voz que falta (con su «Bajar»), el motor, el disco, uno de antes del
  audio— y **«Generar el audio»** lo pide por la misma cola, sin la IA y conservando el
  título; lo confirma con el aviso común (`showAppSnackBar`, F45 paso 1). Con el audio listo, el podcast se ofrece al lector (`ReadableRegion`): la cola lo
  suma como cualquier texto.
- **Las voces de la biblioteca en la hoja** (`podcastVoiceOptionsProvider`, sobre
  `voiceLibraryProvider`): solo las nativas del idioma (decisión L); primero las sin conexión
  bajadas, por calidad, después las del teléfono y al final las que falta bajar, con su
  tamaño; elegir una de esas ofrece «Bajar» ahí mismo. Lo que nadie sabe hacer en el
  dispositivo no se ofrece, y la hoja dice que ahí no se genera el audio.
- **De paso, una carrera**: la lista de voces se armaba antes de saber qué paquetes estaban
  bajados, y una sin conexión ya bajada quedaba como «falta bajarla» y se elegían otras;
  ahora espera los paquetes instalados.
- **El contrato para el paso 5** (descargar el audio de un documento y exportarlo):
  - armar los `SpeechAudioPiece` del documento —un tramo por oración o por pedazo, con la voz
    del idioma de cada uno (decisión L) y la pausa que corresponda— y pedir
    `ref.read(speechAudioRendererProvider).render(SpeechAudioRequest(workKey: 'doc-<id>',
    pieces: …), cancellation: …, onProgress: …)`;
  - el resultado (`SpeechAudioResult`) trae la ruta en el teléfono, el `mimeType`, la
    duración y **dónde empieza cada tramo** (`starts`): con eso, un `RecordedSpeech` y el
    lector lo hace sonar con el resaltado, sin escribir nada más;
  - copiarlo a la bóveda (`FileStore.saveStream` de `File(path).openRead()`) y después
    `discard(workKey)`; las carpetas abandonadas se barren solas a las dos semanas;
  - lanza `SpeechAudioException` (`voiceMissing`, `engine`, `file`) con la voz que faltó o
    falló, y `ProcessingCancelledException` al cancelar; en los dos casos lo hecho queda para
    el próximo intento con la misma clave;
  - antes de generar, `costOf(pieces)` dice si alguna voz cobra, y
    `speechAudioApprovalProvider` pregunta.
- **El enganche del paso 4** (voces propias `mia:<id>`, `offline` o `cloud`):
  - un `SpeechVoiceRenderer` que sea dueño del prefijo `mia:`, sumado a
    `speechVoiceRenderersProvider`. Las `offline` se generan como una del catálogo
    (`MyVoicesService.offlineVoiceOf` y `engineConfigOf`, con `speed × pace`) y las `cloud`
    con `VoiceCloud.speak`: **su MP3 se escribe tal cual** en el `outputPath`, y la pieza común
    lo decodifica; `isReady` con lo que diga `readyMyVoiceNamesProvider`, `versionOf` con lo
    que cambie la voz, y **`priceOf` con lo que cobra la nube**;
  - para la hoja: que `voiceLibraryProvider` traiga las propias con su `VoiceProfile.id`
    (`mia:<id>`) —el podcast las ofrece tal cual, sin cambiar nada más—;
  - el costo antes de generar: con un `priceOf`, la hoja del podcast y «Generar el audio»
    calculan el costo (`SpeechAudioCost`, con los caracteres de cada voz en
    `charactersByVoice`) y preguntan por `speechAudioApprovalProvider`. De fábrica es un
    aviso con el costo; **el paso 4 lo cambia por su puerta**
    (`cloudReadingGateProvider.approve(voice, characters)` voz por voz).
- **Verificado:**
  - analyze en 19, completo;
  - sobre `main` en `a1991355` (con 7a), 4.437 pruebas de la narración (397), lo creado
    (1.956), estudiar (250), los visores (324), `core` con la base (1.295), la app (128) y
    Ajustes (87); rebasado sobre `ca4e9c52` (con F47 paso 1 y F45 paso 1), 2.740 de lo
    tocado: la narración (403), lo creado (1.957), la unión de bóvedas (376) y el censo de
    avisos (4), con `--concurrency=2`;
  - murieron las 39 mutaciones. Una sobrevivía —el tiempo de un audio sin dividir por la
    velocidad— porque la prueba lo miraba solo a 1×: se le sumó la cuenta a 2×. Entre las
    otras: lo hecho que se rehace, las voces que no se miran antes, la versión de la voz que
    no cuenta, el MP3 sin decodificar, la pausa y el margen del armado, el avance que «Volver
    a generar» conserva, lo sin IA que espera al modelo o a la cuota de fondo, `audio_ref`
    fuera de la unión, la vuelta que se vuelve a pedir, el título renombrado pisado, la huella
    sin la pausa, la velocidad que corta, la pausa sola que no se ve, el foco pedido dos veces,
    la hoja que no espera lo bajado o no pregunta el costo, el archivo fingido, el audio de
    otra versión sin decir y la transcripción que no se sigue;
  - el APK de depuración (`dev`) compiló con el Kotlin nuevo (`WavToM4a.kt` y
    `DeviceSpeechChannel.kt`), sin avisos en ellos; no se instaló en ningún teléfono.
- **Queda para después:**
  - medir en el teléfono cuánto tarda en generarse un podcast con cada voz (sobre todo Kokoro y
    las del teléfono) y cuánto pesa, y oír si las pausas recortadas suenan naturales;
  - con una voz sin conexión del lector (paso 3) suenan tramos con `video_player`, que pide
    el foco de audio, mientras la tarjeta del lector también lo pide: dos pedidos de la misma
    app pueden pisarse. Con el podcast no pasa (no lo pide). Mirarlo en el teléfono;
  - en la web el almacén no tiene ruta en el disco: un podcast con audio que llegó a la web
    dice «no está en este teléfono» (ahí tampoco se puede generar);
  - «Exportar audio» del podcast (paso 5, con lo mismo) y exportar el guion como texto;
  - cambiar solo las voces de un podcast ya escrito, sin rehacer el guion: hoy es «Volver a
    generar con otras opciones»;
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

### Paso 7a-bis (hecho): lo que se ve sin abrir la app

Dos decisiones del usuario del 5/11, las dos con el mismo criterio —protege de entrada, y un
interruptor lo deja a la vista para quien lo quiera—:

- **«Seguir escuchando» y la bóveda cerrada** (decisión G, precisada): lo que quedó «para decidir
  con el dueño» en el 7a. Cuatro commits, de `e1fc0c5a` a `be10dc94`, y el primer avance
  (`00855ab6`).
- **La tarjeta de lo que suena en la pantalla de bloqueo** (decisión J, precisada): lo que ese
  primer avance había dejado anotado para decidir. Cuatro commits más, de `14991dbf` a
  `e682a8be`, y el de este avance.

Todo sobre `5c8ad18f` (el paso 1, F45 p1 con el aviso común y el 6b del podcast); no se sumó
ningún aviso.

#### «Seguir escuchando» y la bóveda cerrada

- **El interruptor**, «Mostrar el título con la bóveda cerrada», al pie de Ajustes › Widgets, en
  lugar del aviso de antes (`f47P7WidgetsPrivacy`, borrado). Debajo, a todo el ancho, lo que pasa
  según cómo esté: apagado, «Con la bóveda cerrada, también al reiniciar el teléfono, «Seguir
  escuchando» dice «Protegido»»; prendido, «Cualquiera que mire la pantalla de inicio ve lo último
  que escuchaste». Va solo ahí y no también en Ajustes: es cómo se ve uno de los widgets, y quien
  no los usa no tiene nada que decidir. Se guarda en las preferencias de la app
  (`continue_listening.show_while_locked`), como lo escuchado, y cambiarlo cambia el widget en el
  momento.
- **Con la bóveda cerrada** el widget dice «Protegido: tocá para seguir» (en inglés, «Protected:
  tap to continue»); al abrirla vuelve el título. Tocarlo sigue igual: abre la app, pide la clave
  y después va adonde se escuchó.
- **El widget decide solo, también con la app muerta.** Al reiniciar el teléfono la bóveda queda
  cerrada sin que Dart se entere, así que no alcanza con avisarle al cerrar. Dart le deja al
  widget, junto al título, si se ve con la bóveda cerrada y **en qué encendido del teléfono está
  abierta la bóveda** (`continue_listening_show_locked` y `continue_listening_open_boot`), y el
  widget lo compara cada vez que se dibuja con el encendido de ahora.
  - **El criterio es el de la bóveda, sin copia:** el encendido es el contador de arranques de
    Android (`Settings.Global.BOOT_COUNT`), que la bóveda anota al abrirse y compara al abrir la
    app para entrar sin la clave. Se lee en un solo lugar, `DeviceBoot.kt`, que lo da por el canal
    `app.sinapsis/device_boot` a la bóveda y al widget, en el mismo texto que ve Dart (el número
    en decimal). Un censo comprueba que ningún otro archivo de Kotlin lo lee. Reiniciado el
    teléfono, el contador sube: la bóveda pide la clave y el widget oculta el título, siempre a la
    par.
  - **La regla**, una función pura de cada lado con los mismos tres casos
    (`ContinueListeningDisplay.shownIn` en Dart y `HomeWidgets.continueListeningShown` en
    Kotlin): sin nada escuchado, «Todavía no escuchaste nada»; a la vista por elección, el título;
    si no, el título solo si el encendido en que la bóveda está abierta es el de ahora. En
    cualquier otro caso, lo genérico: la bóveda cerrada, un encendido que no se sabe o lo que dejó
    la versión del 7a sin estas claves. Ante la duda, oculta.
  - **Además**, el widget se vuelve a dibujar con el arranque del teléfono (`BOOT_COMPLETED`, que
    solo manda el sistema), sin esperar a que lo pida la pantalla de inicio.
  - **El orden al guardar:** cada clave se guarda por separado y el sistema podría dibujar el
    widget entre una y otra; primero va lo que restringe y el título al final, así que cuando algo
    pasa a ocultarse no hay un instante en que se vea.
  - **«Bloquear bóveda»** lo oculta en el momento: Dart manda que no hay encendido abierto. No hay
    otros cierres: la bóveda no se cierra por tiempo ni al pasar al fondo (lo comprueba
    `vault_session_per_boot_test`), solo a mano o al apagar o reiniciar el teléfono.
  - Mientras la app arranca y todavía no sabe si la bóveda quedó abierta, no le manda nada al
    widget: sigue con lo último, que de por sí no muestra de más.
- **«Para hoy» no cambia:** con la bóveda cerrada sigue mostrando la cifra. Es un número, no dice
  de qué son las tarjetas; ocultarlo le quitaría al widget su razón de ser sin proteger nada.
  «Guardar rápido» no muestra nada propio.
- **Archivos del widget:** `home_screen_widgets.dart` (`ContinueListeningDisplay` y
  `ContinueListeningShown`),
  `home_widgets_providers.dart` (el interruptor, el encendido de ahora y lo que se manda),
  `android_home_screen_widgets.dart`, `null_home_screen_widgets.dart`, `home_widgets_binding.dart`
  (solo lo que escucha `initState`; `_onPlaying` no se tocó), `home_widgets_screen.dart`;
  `DeviceBoot.kt` (nuevo), `HomeWidgets.kt`, `HomeWidgetProviders.kt`, `SinapsisEngine.kt`, el
  manifiesto y los textos de los widgets en castellano y en inglés; los `.arb`.

#### La tarjeta de lo que suena en la pantalla de bloqueo

- **De entrada, con el teléfono bloqueado la tarjeta no dice qué suena:** «Reproduciendo» y el
  nombre de la app, sin título, sin subtítulo y sin imagen. La barra, el tiempo y los botones
  (−10 s, ▶/⏸, +10 s y «siguiente» si hay cola) siguen iguales y andan: son las mismas acciones.
  Al desbloquear vuelve todo. Desbloqueado, la tarjeta es la de siempre.
- **El interruptor**, «Mostrar el título en la pantalla de bloqueo», en una sección nueva de
  Ajustes, **Privacidad**, justo antes de la Bóveda y solo donde hay tarjeta (Android). Se pensó
  en «Voz y lectura», pero la tarjeta es de todo lo que suena —el lector, un audio, un video, la
  voz del chat—, no solo de la lectura, y el paso 7b va a rehacer esa sección; igual quedó en una
  pieza suelta (`LockScreenTitleTile`) por si se la quiere mover. Debajo, a todo el ancho, lo que
  pasa en cada caso. Se guarda en las preferencias de la app
  (`media_session.show_title_on_lock_screen`) y llega a Android al abrirse la app —antes de que
  suene nada— y cada vez que cambia (`lockScreenTitleSyncProvider`, que mantiene `App`); la
  tarjeta que está a la vista cambia en el momento. Hasta que llega, Android oculta.
- **Por dónde se veía el título, y cómo se cerró cada camino** (`LockScreenPrivacy.kt`, la regla
  en una función pura, y `MediaPlaybackService.kt`):
  1. **La notificación, con «mostrar todo el contenido»** (lo de fábrica en casi todos los
     teléfonos): una notificación privada **se muestra entera igual**; `VISIBILITY_PRIVATE` solo
     oculta con «ocultar contenido sensible». Por eso no alcanzaba con cambiar la visibilidad: con
     el teléfono bloqueado, la tarjeta misma pasa a lo genérico.
  2. **La notificación, con «ocultar contenido sensible»:** va con `VISIBILITY_PRIVATE` y una
     `setPublicVersion(...)` genérica, con los mismos botones, que el sistema muestra en su lugar.
     Cubre además el instante antes de que el servicio se entere de que se bloqueó.
  3. **La sesión de medios:** desde Android 11 los controles de medios de la pantalla de bloqueo
     y de los ajustes rápidos se arman con los **metadatos de la `MediaSession`** —título,
     artista, imagen—, no con el texto de la notificación; de Android 7 a 10 la pantalla de
     bloqueo muestra la notificación, pero algunos teléfonos ponen de fondo la imagen de la
     sesión. Por eso, bloqueado, los metadatos también son los genéricos, sin imagen.
  - **«Bloqueado»** es la pantalla apagada —también la siempre encendida, que para Android no es
    interactiva— o el bloqueo a la vista (`!PowerManager.isInteractive ||
    KeyguardManager.isKeyguardLocked`). El servicio escucha mientras vive `SCREEN_OFF`,
    `SCREEN_ON` y `USER_PRESENT`: al apagarse la pantalla ya pasa a lo genérico, antes de que
    nadie la vea; al prenderse dentro del tiempo de gracia del bloqueo, como no hay bloqueo,
    vuelve; y al desbloquear, vuelve. Si arranca con el teléfono bloqueado —un botón de los
    auriculares—, arranca genérica.
  - **Lo que no cubre:** con el interruptor apagado, lo que lee la sesión con el teléfono
    bloqueado —el auto por Bluetooth, el reloj— también ve «Reproduciendo» (quien lo quiera ver
    ahí, lo prende); y una app con acceso a las notificaciones del teléfono ve la notificación
    entera, como en cualquier reproductor: es un permiso que da la persona.
- **Archivos de la tarjeta:** `LockScreenPrivacy.kt` (nuevo), `MediaPlaybackService.kt`,
  `MediaSessionChannel.kt` (el método `lockScreen`), `media_strings.xml` en castellano y en inglés;
  `lock_screen_title.dart` (nuevo: la preferencia y su envío), `media_session.dart`
  (`showTitleOnLockScreen`), `method_channel_media_session.dart`, `null_media_session.dart`,
  `app.dart`, `lock_screen_title_tile.dart` (nuevo) y `settings_screen.dart`; los `.arb`.

#### Verificado

- **analyze en 19**, completo, sobre `5c8ad18f`. En el primer intento de la pantalla de los
  widgets quedaban dos de más (`containsSemantics`, obsoleto): se cambió por `isSemantics`, como
  la prueba de al lado, antes de cerrar el commit.
- **1.084 pruebas en verde** de `test/core/audio`, Ajustes, la app (`test/app`, con
  `home_widgets_binding_test`), los widgets, la bóveda, la Ayuda y el censo de avisos, con
  `--concurrency=2`. Falla una, el censo de licencias de las letras de la Ayuda, que ya falla en
  `main` y no es de este paso.
- **38 pruebas nuevas:**
  - **del widget, 22:** 13 de la regla y de lo que se le manda (de entrada oculto; cerrada, el
    genérico; abierta en este encendido, el título; reiniciado el teléfono o sin saber el
    encendido, el genérico; el interruptor, al instante y guardado; a la vista por elección,
    siempre el título), 3 del binding con la bóveda cerrada (abrirla y bloquearla, el
    interruptor, el toque que pide la clave y después va adonde se escuchó), 1 del orden al
    guardar, 4 de la pantalla (en claro y en oscuro a 360 dp con la letra al doble, prender y
    apagar, el lector de pantalla) y 2 censos;
  - **de la tarjeta, 16:** 6 de la preferencia y su envío (de entrada apagada, guardada, llega al
    abrirse la app y al cambiar, prendida desde antes, nada donde no hay tarjeta, el método del
    canal), 3 censos del lado de Android y 7 de Ajustes › Privacidad (en claro y en oscuro a
    360 dp con la letra al doble, prender y apagar, justo antes de la Bóveda, ausente sin
    tarjeta, el lector de pantalla).
- **Lo que encontró la prueba de la pantalla de los widgets:** con la explicación como subtítulo
  del interruptor, a 360 dp con la letra al doble quedaba en una columna de 172 px más alta que
  la pantalla. Pasó abajo, a todo el ancho, y los textos se acortaron; Privacidad nació igual.
- **Murieron las 18 mutaciones:** sin «a la vista por elección», el encendido que no se compara,
  la preferencia del widget prendida de entrada, el encendido mandado con la bóveda cerrada,
  mandar algo antes de saber si la bóveda quedó abierta, el encendido guardado con el título, la
  explicación que no cambia, el binding que no manda lo genérico, el widget de Kotlin que se
  compara consigo mismo, el arranque fuera del manifiesto; la preferencia de la tarjeta prendida
  de entrada, que no llegue al abrirse la app, el canal que siempre dice «mostrar», Privacidad
  donde no hay tarjeta, el interruptor que no prende, y en Kotlin la tarjeta sin versión
  pública, arrancando a la vista y sin enterarse del desbloqueo.
- **Las reglas de Kotlin** no tienen prueba propia: el proyecto no tiene pruebas de JVM y
  sumarlas era infraestructura nueva. Quedan en funciones puras, comentadas caso por caso
  (`HomeWidgets.continueListeningShown` y `LockScreenPrivacy`), y los censos comprueban lo que
  las une con Dart: los mismos tres casos del widget, el encendido de `DeviceBoot`, el receptor
  del arranque, el método `lockScreen` del canal y que la tarjeta use la regla, escuche la
  pantalla, tenga su versión pública y arranque oculta.
- **El APK de depuración compila** (`dev`, con todo el Kotlin de este paso, sobre `917a11c0`).
  El rebase sobre `5c8ad18f` unió sin conflicto `SinapsisEngine.kt` (main le sumó la voz del
  teléfono para el 6b) y no se volvió a compilar. No se miró en el emulador ni en el teléfono.

#### Queda para después

- probarlo en el teléfono: reiniciar con el widget puesto y ver que dice «Protegido» antes de
  abrir la app; con algo sonando, bloquear y ver «Reproduciendo» en la pantalla de bloqueo, con
  «mostrar todo el contenido» y con «ocultar contenido sensible», que los botones anden y que al
  desbloquear vuelva el título; y en un Android 11 o más nuevo, los controles de medios de los
  ajustes rápidos con el teléfono bloqueado.

### Paso 7b (hecho): Ajustes › «Voz y lectura» entera

Dos commits, `3f2af1e9` (el código, los textos y las pruebas) y `ea594b4a` (la GUÍA), y el de
este avance. Hecho sobre `a7ffb552` y rebasado sobre `d8a452f7` (F45 8b, las notas en el
texto): solo chocaron los `.arb`, resueltos con lo de `main` primero y las claves `f47P7b*`
al final, sin repetidas.

- **Lo que había:** las piezas ya estaban en una sección «Voz y lectura» de los pasos 2, 3 y 4
  (`voiceSettingsTiles`), en el orden en que fueron llegando —la Lectura enfocada al final, «Voces
  descargadas» entre la nube y la Lectura enfocada— y con dos íconos iguales (la biblioteca y
  clonar). Faltaban la voz de ahora, la velocidad y la tipografía con el resaltado. No había
  entradas repetidas en otras secciones: «Apariencia» de Ajustes es el idioma y el tema de la
  app, no la lectura.
- **Una sola sección, en el orden en que se piensa** (Vos · Apariencia · **Voz y lectura** ·
  Citas · …, como dejó el 7a):
  1. **con qué voz se lee:** «Biblioteca de voces», «Voces por idioma» y, en Android, «Voces
     descargadas»;
  2. **las voces propias:** «Clonación de voz», «Crear una voz» y «La nube para voces», que solo
     sirve para eso (decisión C) y por eso va con ellas;
  3. **cómo se escucha y cómo se lee:** «Velocidad de lectura», «Lectura enfocada» y
     «Tipografía y resaltado».
  - Las voces quedan en `voiceSettingsTiles` y lo de escuchar en `readAloudSettingsTiles`, las dos
    en la narración; la tipografía es del marco de lectura (`ReadingAppearanceSettingsTile`, en
    `reading/presentation/frame/`). Las arma `SettingsScreen`, así la narración no pasa a depender
    del marco, que ya depende de ella.
  - Clonar pasa al ícono del micrófono: la biblioteca ahora lleva la cara de la voz, y las dos
    filas tenían el mismo.
- **La biblioteca, con la voz de ahora:** a la izquierda, **la misma cara del reproductor**
  (`ReadAloudVoiceFace`, sobre `currentVoiceProfileProvider`: con la nube si la voz es de la nube
  y la propia de la voz del sistema), y debajo «Lee ahora: Daniela» o «Lee ahora: la voz del
  teléfono», la misma frase de arriba de la biblioteca. Tocarla la abre (`showVoiceLibrary`).
  Si se borra la voz sin conexión que leía, la fila pasa sola a la del teléfono.
- **La velocidad: una sola, no una «por defecto» aparte.** La app ya guarda la velocidad que se
  elige en el reproductor (`narration_speed`) y con ella empieza todo lo que se lee. Sumar otra
  cifra «por defecto» dejaría dos velocidades que se separan —la de Ajustes y la última del
  reproductor— sin que se vea cuál manda. Así que «Velocidad de lectura» dice la guardada
  («1,0×») y abre **la misma hoja del reproductor** (`ReadAloudSpeedSheet`, con la regla de 0,5× a
  3× y los atajos), con una aclaración que solo lleva desde Ajustes (`note`): con esta empieza a
  leer todo, y cambiarla en el reproductor también la cambia acá. Si algo está sonando, cambia en
  el acto.
- **La tipografía y el resaltado: la Apariencia del marco, no una copia.**
  `ReadingAppearanceSheet.saved` es la misma hoja del paso 1 sin un documento detrás: la letra y
  su tamaño con la muestra, **el tono de la página** (rotulado «El tono de la página de un PDF o
  de una foto»), el resaltado de lo que suena y el modo. No lleva el zoom, que es de la página que
  se está viendo: el campo `controller` pasó a ser opcional, y el constructor de siempre lo sigue
  pidiendo. La fila dice lo elegido —«Lora · 100 % · Amarillo»—; el nombre de cada color salió a
  `readingHighlightName`, que usan la hoja y la fila.
- **Voces descargadas, con lo que ocupan:** la fila dice cuántas voces hay y cuánto ocupan entre
  todas («N voces · tamaño», `downloadedVoicesSummaryProvider`): las del catálogo cuyo paquete
  está (las 28 de Kokoro cuentan 28) y los bytes de cada paquete abierto, contados como en la
  hoja. Se vuelve a contar al bajar o borrar una. Sin ninguna, «Ninguna todavía», como antes.
- **«Mostrar el título en la pantalla de bloqueo» se queda en Privacidad.** La tarjeta de la
  pantalla de bloqueo es de **todo lo que suena** —el lector, un podcast, un audio, un video, la
  voz del chat—, no solo de la lectura: en «Voz y lectura» parecería que un video o un audio no
  quedan cubiertos. Además, Privacidad agrupa lo que se ve sin desbloquear, justo antes de la
  Bóveda, y es donde se lo busca cuando preocupa quién mira el teléfono. Ponerla en las dos
  secciones sería una entrada repetida. La GUÍA lo dice en «Voz y lectura», para quien la busque
  ahí.
- **No se tocaron** la guía dentro de la app ni los widgets (7a): la guía se arma sola de
  `GUIA_DE_USO.md`, y no se sumaron títulos.
- **Verificado:**
  - analyze en 19, completo, antes y después del rebase sobre `d8a452f7`. En la primera
    corrida daba 20, por un `final` que pedía `const` en la prueba nueva: corregido antes de
    cerrar el commit;
  - antes del rebase, 821 pruebas de Ajustes, la Ayuda, la lectura y la narración, y 118 de
    «Que siga con la app cerrada» y la pantalla de la Biblioteca (las otras que abren Ajustes);
    después del rebase, **963 en verde** de Ajustes, la Ayuda, la lectura, la narración, la
    app y «Que siga con la app cerrada», con `--concurrency=2`;
  - **lo que encontró la app:** la prueba de la navegación adaptable
    (`adaptive_scaffold_test`, «Biblioteca y Ajustes abren directo») fallaba al cerrar: Ajustes
    ahora muestra la voz de ahora, que es la del lector en voz alta, y esa prueba armaba el
    motor de voz de verdad (`flutter_tts`), sin el canal en las pruebas. En la app el lector
    ya está vivo siempre (`ReadAloudOverlay`, en `App`), así que Ajustes no suma nada; la
    causa era la prueba sin el doble: se le dio el `FakeTextToSpeechService` que usan las
    demás;
  - **21 pruebas nuevas** (`settings_voice_reading_test.dart`): la sección entera en claro y en
    oscuro a 360 dp con la letra al doble; el orden, una sola vez cada fila y todas antes de
    Citas; el título de la pantalla de bloqueo en Privacidad; la voz de ahora (la del teléfono,
    una del teléfono elegida con su cara, una sin conexión bajada) y que abre la biblioteca; la
    velocidad guardada, la hoja con su aclaración y un atajo que la guarda y la usa el lector, que
    es una sola con la del reproductor y que el reproductor no lleva la aclaración; la tipografía
    con lo elegido, la hoja con todo menos el zoom, lo elegido guardado y en la fila, y la hoja en
    claro y en oscuro; las descargadas con cuántas y cuánto, sin ninguna, fuera de Android, y
    borrar la que lee desde su hoja, que vuelve a contar y deja leyendo a la del teléfono; y el
    lector de pantalla, que oye cada fila como botón con su nombre y lo de ahora;
  - **murieron las 16 mutaciones**: la biblioteca sin la voz de ahora y sin su cara; la
    velocidad de Ajustes sin su aclaración, la fila que dice siempre «1,0×» y el reproductor
    con la aclaración de Ajustes; la fila de la tipografía sin el resaltado, la Apariencia de
    Ajustes sin la letra o sin el tono de la página, y el nombre del Lila equivocado; las
    descargadas que cuentan paquetes y no voces, lo que ocupan contando solo el último
    paquete, sin ninguna que no lo dice y la fila donde no hay voces sin conexión; lo de
    escuchar antes que las voces, la tipografía fuera de la sección y la tarjeta de bloqueo
    repetida en «Voz y lectura».
- **Queda para después:**
  - `NOVEDADES.md` lista de F47 solo los pasos 0 y 7a: falta sumar el marco, el reproductor, las
    voces, el podcast y «Voz y lectura» en el cierre (paso 8);
  - la hoja de las descargadas pide el tamaño de cada paquete en cada armado, y el resumen de la
    fila lo recorre con `listSync`; con muchos archivos (Kokoro trae los de espeak-ng) conviene
    medirlo en el teléfono;
  - no se miró en el emulador ni en el teléfono.
