# F47 — Un solo lector para todo, la biblioteca de voces y el podcast

Pedido del 30/10. La guía de diseño son las capturas 3 a 17 (la app Listen AI). Hay que conservar
todo lo que la app ya hace.

- **Un solo lector, profesional y elegante, para todo texto:** el original (un PDF, un libro, una
  página web o una foto), el texto extraído, el resumen, la síntesis y lo creado en Repasar.
  - Cambia la forma; no se pierde ninguna función.
- **Un reproductor anclado abajo**, con su cola, su temporizador para dormir, su velocidad y la
  voz a la vista.
- **Una biblioteca rica de voces:**
  - las del teléfono;
  - voces neuronales sin conexión;
  - las de la nube, con las cuentas que ya están;
  - **tu propia voz clonada**.
  - Con cualquiera de ellas se escucha un documento.
- **Un podcast a medida**, en Repasar y en cada documento, con una o dos voces.
- **Lo que le falta a Ajustes**, sacado de las dos últimas capturas.

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
- **El original de la Biblioteca y el de Procesado:** el mismo marco, con su cuerpo de siempre (la
  página del PDF, la web, el libro o la foto) y las marcas adentro (F45, mejora 15).

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

### 3. La biblioteca de voces (capturas 10, 11, 12 y 13)

- **Una sola lista**, con las pestañas **Todas · Favoritas · Clonadas** y «Te puede interesar»
  arriba: voces de tu idioma con buena calidad.
- **Cada voz es una tarjeta:**
  - su cara;
  - el nombre, con la bandera del acento;
  - «ES · Cálido · Expresivo», con el ícono de para qué es ideal;
  - ♡ favorita;
  - ▶ una muestra corta;
  - de qué motor es: **Teléfono**, **Sin conexión**, **Nube** o **Clonada**.
- **Filtrar**, con el pie «Borrar · Aplicar» (el mismo de la mejora 21 de F45):
  - el idioma;
  - el acento (México, España, Argentina, Colombia, Chile, Perú…);
  - para qué es ideal: narrar, informar, aprender, conversar o relajarse;
  - el timbre;
  - el estilo;
  - el género;
  - la edad.
- **Los cuatro motores** (decisión B):
  1. **Las voces del teléfono**: las de hoy, gratis y sin conexión.
  2. **Voces neuronales sin conexión**, que suenan casi humanas. Son las de Piper y Kokoro,
     sobre `sherpa_onnx`, que la app ya usa para Whisper. Para español hay de Argentina, España
     y México.
     - Cada voz se baja **solo si la pedís**, como Gemma, con su tamaño a la vista.
     - Se borra desde Ajustes.
  3. **Voces de la nube**, con las cuentas que ya están (F32):
     - Gemini, con unas 30 voces y estilo por instrucción;
     - OpenAI, con 11 a 13 voces.
     - Claude no tiene voz.
     - Lo que se genera se guarda por oración: escuchar de nuevo no se paga.
  4. **Clonadas**: ver el punto 4.
- **Las caras:** sin fotos de personas reales. Cada voz tiene un retrato propio, abstracto, con su
  color, sus iniciales y su onda (decisión D).

### 4. Clonar una voz (captura 14)

- **«Clonación de voz»**, en Ajustes y en la pestaña Clonadas.
  - Una presentación: qué es, cómo se usa y que se puede borrar cuando quieras.
  - Antes de grabar, el **consentimiento**: solo tu voz, o la de alguien que te dio permiso.
- **Grabar 1 o 2 minutos**, leyendo un texto que propone la app, o **subir un audio**.
  - La app mide el ruido y avisa si conviene repetir.
- **Con ElevenLabs** (decisión C), con tu propia cuenta y tu clave, que se suma como las de F32.
  - La clonación instantánea está desde el plan Starter, de unos USD 6 por mes.
  - Gemini y OpenAI no clonan para cualquiera: OpenAI lo reserva a clientes habilitados.
- **La grabación queda en tu bóveda.** Borrar la voz la borra acá y en ElevenLabs.
- Lo que lee una voz clonada se rotula «Voz clonada» en el reproductor.

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
- **«Elegí las voces»**: una, o dos en Conversación, de la biblioteca, incluida la tuya clonada.
- **Cómo se hace:**
  - la IA de turno escribe el guion **solo con lo del material**, con la cita de cada dato;
  - se genera la voz de cada tramo;
  - se guarda en la bóveda como una creación de «Lo creado».
  - Va en segundo plano, retomable y con el servicio de siempre, como las creaciones de F43.
- **Al escucharlo:** el mismo reproductor, con la transcripción que se sigue y cada cita
  tocable, que lleva al pasaje.
- Se rotula «Hecho con IA».
- **Sin la nube:** Gemma escribe el guion y lo lee una voz sin conexión. Tarda más, pero no cuesta
  nada.

### 6. Escuchar sin conexión y lo que cuesta

- **Descargar audio** de un documento o de un podcast, con la voz elegida.
  - Con una voz de la nube, **antes se dice cuánto cuesta**, estimado, con lo gastado hoy (F32).
  - Se pide confirmación.
- **Exportar audio** a un archivo para compartir: el de un podcast, o el de un documento ya
  descargado.

### 7. Ajustes (capturas 16 y 17)

Lo que se suma:

- **Voz y lectura**, una sección nueva:
  - Biblioteca de voces (con la voz de ahora);
  - Clonación de voz;
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
- **B. Cuatro motores de voz en una sola biblioteca:** teléfono, sin conexión, nube y clonadas.
  - Ninguna voz ni modelo se baja sin que lo pidas.
  - Lo que se manda a la nube es el texto que se va a leer, como hoy con la IA, y lo dice la
    primera vez.
- **C. Clonar con ElevenLabs, con tu propia cuenta.**
  - *Alternativa:* clonar en el teléfono (ZipVoice, sobre `sherpa_onnx`). Todavía no está
    confirmado que ande bien en español ni que la versión para Flutter lo traiga. Se mide en el
    paso 4 y, si anda, se suma como quinta opción.
- **D. Caras propias, abstractas, sin fotos de personas reales.** Una foto de alguien real dice
  que esa voz es de esa persona, y no lo es.
- **E. El podcast es una creación más de «Lo creado» (F43):** con su fila, su retome, su cita a
  las fuentes y su lugar en la cola.
  - Con dos voces, Gemini las hace juntas en un pedido, que suena más natural.
  - Con otros motores, tramo por tramo.
- **F. El audio generado se guarda.** Escuchar de nuevo no cuesta, y lo largo de la nube avisa su
  costo antes.
- **G. Los widgets, con `home_widget`, solo en Android.** Es una dependencia nueva del código, no
  software que se instale en la PC ni en el teléfono.
  - *Alternativa:* dejarlos para después.
- **H. La velocidad va de 0,5× a 3,0×, sin candados.**
- **I. El orden:**
  - F47 va **después de F45 y antes de F46**, porque cambia todas las pantallas de lectura y
    conviene que el Índice nazca con el marco nuevo.
  - *Alternativa:* F46 primero, como estaba aprobado.

## Pasos (cada uno, su commit y su push)

Cada paso lleva su GUÍA, sus pruebas (solo con dobles, a 360 dp con la letra al doble, en claro
y en oscuro, con el lector de pantalla) y sus mutaciones. Se integran en `main` de a uno.

**Ola 1:**

1. **El marco de lectura:**
   - el censo de funciones;
   - la barra con sus cuatro botones, la fila de IA, el cuerpo, Apariencia y ⋮;
   - en el original, el texto extraído, el resumen, la síntesis y lo creado, sin el botón
     flotante en ellos;
   - con las mejoras 12 y 13 de F45.
2. **El reproductor anclado:**
   - abierto y achicado;
   - el tiempo, ±10 s y la velocidad con su regla;
   - la cola, Repetir y el Temporizador para dormir;
   - Lectura enfocada.
3. **La biblioteca de voces:**
   - la lista, las tarjetas, Filtrar, Favoritas y las muestras;
   - las caras;
   - las voces sin conexión, a pedido.

**Ola 2:**

4. **Las voces de la nube y clonar:**
   - Gemini y OpenAI, con el caché por oración;
   - ElevenLabs con su cuenta, la grabación y el consentimiento;
   - la medición de ZipVoice.
5. **Descargar y exportar audio**, con el costo antes.
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
   - la prueba con tus voces y tus cuentas en el teléfono, si la pedís.

## Lo que no entra (para que quede dicho)

- **Voces de personas reales sin su permiso**: la app no las clona ni las imita.
- **Las cuentas de Google** (Drive y Gmail) y **las tiendas** (calificar y compartir): ver el
  punto 7.
- **Traducir al leer**: la voz lee el texto en su idioma. Elegir una voz de otro idioma no lo
  traduce.

## Avance

(vacío: se llena con cada paso)
