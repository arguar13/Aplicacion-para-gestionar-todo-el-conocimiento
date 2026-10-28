# F42 — Un chat moderno, inmersivo y elegante

> **Estado: CONSTRUIDO** (aprobado el 2026-10-27 con «Aprobado» en el chat; cerrado el 2026-10-28,
> decisión 88 en `docs/arquitectura.md`).
>
> Pedido del dueño, con una captura del chat actual y cinco de apps reales (Gemini, Copilot,
> Claude y ChatGPT) como guía de estilo, no para copiarlas: *"La interfaz de nuestro chat está
> medio «retro» y quisiera hacerla más moderna o elegante … como para hacerlo más inmersivo y
> realista y moderno … no tienes que hacerla exactamente igual, es solamente para que te guíes
> como lo quiero y el estilo y organización, y si quieres agrega más funciones"*.

## Lo que hay hoy (y no se pierde)

- **Arriba:** el título «Chat», el historial, la cuenta de la nube y el robot del modelo.
- **Debajo:** el selector **Con mi bóveda · Conversación libre** y el alcance **«Toda la bóveda ▾»**
  (un cuaderno).
- **El vacío:** un ícono en un círculo y una frase centrada.
- **Abajo:** el clip de adjuntar, el campo y el botón de enviar.
- **Lo que ya hace:** respuestas que aparecen mientras se escriben, «Detener», citas de la bóveda
  con sus tarjetas, una foto por mensaje, historial de conversaciones, el modelo que se carga al
  abrir y la IA que organiza sola, que espera.

## Qué se construye

### 1. Arriba, limpio

- **A la izquierda, ☰**: abre el **panel de conversaciones**.
  - Arriba van Biblioteca, Cuadernos y Procesado como atajos.
  - Después, las conversaciones agrupadas por día («Hoy», «Ayer», «domingo, oct 25»), con
    buscador.
  - Cada una tiene su menú ⋮: renombrar, fijar y borrar.
  - Al pie, el nombre del dueño y **«Nueva»**.
- **Al centro, una píldora con el modelo**, por ejemplo «Gemma ▾» o «Gemini 3.1 Flash Lite ▾».
  - Tocarla abre la hoja para elegir modelo y cuenta: lo que hoy hacen el robot y la «C».
  - Debajo, en chico, el modo y el alcance: «Con tu bóveda · Toda la bóveda».
- **A la derecha, ✎**: conversación nueva.

### 2. El vacío, que recibe

- **Un saludo grande y tranquilo**: *«Hola, Armando. ¿Qué querés saber de lo tuyo?»*, con el
  nombre que el dueño ponga en Ajustes. Sin nombre, según la hora: *«Buenas noches»*.
- **Fondo con un brillo suave**, un degradé del color del tema que respira despacio. Respeta
  «sin animaciones» y los nueve temas.
- **Tres o cuatro sugerencias tocables**, armadas con lo suyo: *«Resumime lo último que
  procesé»*, *«¿Qué dice Laudato si' sobre…?»*, *«Preguntame sobre Don Quijote»*.

### 3. El campo, flotante

- **Una cápsula redondeada que flota abajo**: «+» a la izquierda, el campo *«Preguntale a tu
  bóveda…»*, y a la derecha 🎤 y enviar. Mientras escribe, enviar se vuelve «Detener».
- **El «+» abre la hoja «Agregar al chat»**:
  - **Cámara · Fotos · Archivos**, en tarjetas;
  - **Cuaderno**: elegir el alcance, como «Agregar al proyecto» de Claude;
  - **Con mi bóveda**: un interruptor, que reemplaza al selector de arriba;
  - **Pensar más**: un interruptor, para un modelo que lo permita; si no, se ve apagado y dice
    por qué.
- **🎤 Dictar**: habla a texto en el campo, con el reconocimiento del teléfono. Si no hay, el
  botón no aparece.
- **Teclado**: Enter envía y Shift+Enter hace un salto de línea, en la computadora.

### 4. La conversación

- **Lo tuyo, en una burbuja a la derecha. La respuesta, a todo lo ancho y sin burbuja**, como en
  las apps de referencia, con buena tipografía: títulos, listas, negritas y código.
- **Mientras escribe**: un indicador vivo y elegante en vez de los tres puntos de siempre, y las
  palabras entrando con un fundido suave.
- **Debajo de cada respuesta**, con íconos discretos: copiar, escuchar (el lector en voz alta),
  volver a generar, y 👍/👎 (se guarda local, nunca se manda a nadie).
- **Las citas de la bóveda como chips numerados** dentro del texto ([1], [2]). Tocar uno abre la
  fuente en su lugar. Debajo, «Fuentes» plegable con sus tarjetas.
- **Mantener apretado un mensaje**: copiar, editar y reenviar (los tuyos), seleccionar texto.
- **Inmersivo**: con el teclado abierto, la barra de abajo de la app se esconde y el chat usa
  toda la altura. Al bajar con el dedo, aparece «↓» para volver al final.

### 5. Detalles que lo hacen real

- **Transiciones suaves** entre el vacío y la conversación, y al abrir el panel.
- **Vibración corta** al enviar y al terminar una respuesta, si el teléfono la tiene.
- **Accesibilidad**: lectores de pantalla en cada botón, contraste en los nueve temas y letra
  grande sin que nada se desborde.

## Decisiones (se pueden cambiar mientras no se llegue a su paso)

- **A. No se copia ninguna app**: se toma la organización (☰ · modelo al centro · ✎, el vacío con
  saludo, la cápsula con «+») y se hace con el diseño de Sinapsis y sus temas. No lleva logos ni
  marcas de nadie.
- **B. El nombre del saludo** se pone en Ajustes, en «Cómo te llamo», que es opcional. La app no
  lo saca de ninguna cuenta.
- **C. El modo y el alcance bajan al «+»**, pero se ven siempre debajo de la píldora del modelo,
  para no olvidar dónde se está preguntando.
- **D. Ninguna función se pierde**: cada una de las de hoy tiene su lugar nuevo, y una prueba lo
  fija.

## Pasos (cada uno, su commit y su push)

1. **El armazón:**
   - la barra de arriba (☰, la píldora con el modelo y el modo, ✎);
   - el panel de conversaciones con días, buscador, fijar y renombrar;
   - «Cómo te llamo» en Ajustes.
2. **El vacío y el campo:**
   - el saludo, el brillo y las sugerencias;
   - la cápsula con «+», 🎤 y enviar/Detener;
   - la hoja «Agregar al chat».
3. **La conversación:**
   - burbujas y respuesta a todo lo ancho, el indicador vivo y el fundido;
   - las acciones de cada respuesta y las citas numeradas con «Fuentes»;
   - mantener apretado, el modo inmersivo y «↓».
4. **Cierre:**
   - la GUÍA, la decisión en `docs/arquitectura.md`, CONTEXTO y el «Avance»;
   - la suite y `verify_commit`;
   - la APK si la pedís.

Los pasos 1 y 2 van en paralelo, cada uno con su agente. El 3 empieza apenas el 1 deja el
armazón en main.

## Avance

### Paso 1 — el armazón (hecho)

- **La barra de arriba** (`chat/presentation/widgets/chat_top_bar.dart`): ☰ a la izquierda, al
  centro la **píldora con el modelo** —con un punto que dice si puede contestar— y debajo, en
  chico, **dónde se pregunta** («Con tu bóveda · Toda la bóveda», «Con tu bóveda · Tesis»,
  «Conversación libre»); ✎ a la derecha, apagado si la conversación ya está vacía. Crece con la
  letra grande en vez de cortar la píldora.
- **La hoja del modelo** (`ai_models/presentation/widgets/ai_model_picker.dart`): proveedor,
  modelo y cuenta —lo que hacían el robot y la «C»—, y «Más ajustes de la IA». Reusa el menú de
  cuentas de F32 y, de la pantalla del modelo, salieron a este archivo el aviso de privacidad, la
  lista de proveedores ofrecidos y el nombre del modelo elegido: un solo lugar para los dos.
- **«Dónde pregunto»** (`chat_scope_sheet.dart`): el selector «Con mi bóveda · Conversación
  libre» y el «Toda la bóveda ▾» salieron de la barra; mientras el paso 2 no los pone en el «+»,
  se cambian tocando la línea debajo de la píldora. `ChatScopeOptions` y `ChatNotebookScopeList`
  quedan listos para meterlos en la hoja «Agregar al chat».
- **El estado del chat tiene un dueño**: `chatSelectionProvider`
  (`chat/presentation/providers/chat_selection.dart`) guarda el modo, el cuaderno y la
  conversación abierta de cada modo, con las reglas de siempre (otro cuaderno arranca una
  conversación nueva, abrir una vieja vuelve a su modo y su cuaderno). La pantalla lo escucha y
  cierra lo que ya no corresponde: la respuesta en curso se corta si su conversación deja de
  estar abierta —cambiar de modo no la corta—, y la sesión del modelo de un modo se cierra si
  cambia su conversación.
- **El panel de conversaciones** (`chat_conversations_panel.dart`) reemplaza al historial de la
  derecha: atajos a Biblioteca y Cuadernos (Procesado se suma cuando F41 deje su ruta en main),
  buscador sin acentos, **las de los dos modos juntas** agrupadas por día («Hoy», «Ayer»,
  «domingo, 6 de septiembre») con las fijadas arriba, ⋮ por fila (renombrar, fijar/desfijar,
  borrar con «Deshacer» en el lugar de la fila) y al pie el nombre y «Nueva». Es una ruta emergente
  que entra deslizándose desde la izquierda, encima de todo, y respeta «sin animaciones».
  - **Fijar sin migración**: lo fijado vive en las preferencias del teléfono, por id
    (`chatPinsProvider`). Es una forma de mirar el historial, no un dato de la conversación, y
    así no se toca el esquema que está subiendo F41. Si algún día tiene que viajar con la
    bóveda, pasa a una columna de `conversations`.
  - **Renombrar** usa la columna `title` que ya existía (`renameConversation`, sin migración) y
    no mueve la conversación de lugar.
- **«Cómo te llamo»** en Ajustes, sección «Vos» (`settings/.../owner_name.dart` y
  `owner_name_tile.dart`): opcional, solo en este teléfono, nunca sacado de una cuenta. Lo usan el
  pie del panel y, desde el paso 2, el saludo: `ownerNameProvider`.
- **`chat_screen.dart`** quedó solo con las llamadas: salieron `_HistoryDrawer`,
  `_ConversationSubtitle` y `_NotebookScopeSelector`, y el estado suelto de modo, cuaderno y
  conversaciones. El vacío, el aviso del modelo y el campo no se tocaron: son del paso 2.
- **Ninguna función se perdió**: abrir una conversación vieja, empezar una nueva, borrar, cambiar
  de modelo y de cuenta, de modo y de cuaderno —cada una con su prueba—, más las nuevas (días,
  fijadas, buscador, renombrar, deshacer, nombre). Las pruebas miran también la letra grande, el
  lector de pantalla y el contraste AA en los nueve temas.
- **Para el paso 2**: con letra muy grande, el cuerpo del chat de hoy (el aviso del modelo, el
  vacío y el campo) se desborda; es de su zona y lo resuelve el campo nuevo.

### Paso 2 — el vacío y el campo (construido)

**El vacío que recibe.**
- El saludo grande: *«Hola, {nombre}.»* con el degradé del tema (liso con «alto contraste») y
  debajo *«¿Qué querés saber de lo tuyo?»* —*«¿De qué querés hablar?»* en conversación libre—.
  Sin nombre, según la hora: «Buen día» de 5 a 12, «Buenas tardes» de 12 a 20, «Buenas noches»
  el resto. El nombre es el de «Cómo te llamo» (`ownerNameProvider` del paso 1) y cambia en el
  acto si se edita en Ajustes.
- El brillo: dos manchas de luz del primario y el terciario del tema, pintadas una sola vez en su
  capa; respira la opacidad y la escala de esa capa, que se resuelven al componer, sin repintar.
  **Respira tres veces y queda quieto** (y vuelve a respirar la próxima vez que aparece el vacío):
  una animación sin fin hace dibujar al motor 60 cuadros por segundo con el chat sobre la mesa.
  Quieto con «sin animaciones»; sin brillo con «alto contraste».
- Las sugerencias, de lo último guardado **y ya procesado** (lo pendiente no tiene texto que
  resumir), en el alcance elegido: «Resumime «…»», «Preguntame sobre «…»», «¿Qué dice «…»
  sobre…?» y el tema con más cosas —o el cuaderno elegido—. Las preguntas enteras se mandan al
  tocarlas; las que terminan en «…» quedan en el campo. En conversación libre, tres comienzos.
- El aviso del modelo no se perdió: una tarjeta tranquila debajo de las sugerencias y, ya en una
  conversación, una línea arriba del campo.

**El campo flotante.** Una cápsula con «+», el texto (hasta seis líneas), 🎤 y el botón redondo
de enviar, que se prende con algo que mandar y es «Detener» mientras el modelo escribe; se puede
ir escribiendo el próximo mensaje. Las fotos y documentos adjuntos, adentro de la cápsula, con su
✕. Enter manda y Shift+Enter es un salto de línea **en la computadora**; en el teléfono algunos
teclados de pantalla mandan el Enter como una tecla, y ahí tiene que ser el salto de línea que
muestran. Mientras un método de entrada compone, Enter no manda.

**«Agregar al chat».** Cámara (solo donde hay una: no en Windows) · Fotos (la galería del
sistema, `PhotoLibraryChooser` sobre `image_picker`, que ya estaba) · Archivos (el selector de
siempre: documento o imagen, clasificado por sus bytes). Una foto por mensaje: con una adjunta,
las tarjetas de fotos se apagan y lo dicen. Debajo, **Dónde pregunto** —con lo elegido a la
vista, «Con tu bóveda · Tesis»— y **Pensar más**; lo que se cambia vale en el acto.
- **El modo y el cuaderno se eligen de una sola forma** (decisión C, sin dos versiones): la fila
  «Dónde pregunto» del «+» y la línea debajo de la píldora abren **la misma hoja**
  (`showChatScopeSheet`, con `ChatScopeOptions` y `ChatNotebookScopeList` del paso 1) y cambian
  el mismo estado (`chatSelectionProvider`). La línea sigue siendo el resumen siempre a la vista;
  tocarla no abre «Agregar al chat», porque ahí manda adjuntar —cámara, fotos, archivos— y quien
  toca «dónde pregunto» quiere cambiar justo eso. El interruptor «Con mi bóveda» y la fila
  «Cuaderno» que el plan ponía en el «+» quedaron en esa fila: dos interruptores propios habrían
  sido una segunda forma, distinta, de hacer lo mismo.

**«Pensar más», de punta a punta.** Los tres clientes de la nube ya regulaban cuánto piensa el
modelo, siempre al mínimo; «Pensar más» es la misma perilla en el otro extremo: `thinkingLevel:
high` en Gemini 3 y 4, `thinkingBudget: -1` en 2.5, `reasoning_effort: high` en los de OpenAI
que razonan y `effort: high` en Claude 5, con 16.384 tokens de margen. Quién la tiene vive en un
solo lugar (`thinkMoreSupport`), que usan la hoja y los formatos. Gemma no tiene un modo para
pensar más: el interruptor se ve apagado y lo dice; el gancho queda en
`ModelConversation.send(thinkMore:)`. Vale mientras el chat está abierto y no se guarda: pensar a
fondo gasta más cuota, y se elige a sabiendas.

**🎤 Dictar, sin dependencias nuevas.** Un canal propio (`DictationChannel`, Kotlin) sobre el
`SpeechRecognizer` del sistema, como los otros canales de la app. Ningún paquete de habla a texto
deja preguntar si hay reconocedor sin pedir el permiso del micrófono —lo piden al inicializarse,
o sea al abrir el chat—; el canal propio pregunta sin permiso (el 🎤 aparece solo si hay) y lo
pide la primera vez que se toca. Lo oído se escribe mientras se dice, después de lo que había; un
anillo late con la voz. En iOS, Windows y la web no hay reconocedor (`NullDictation`): el botón no
aparece.

**Pruebas.** Con dobles en todo: el saludo con y sin nombre, la hora, el brillo que respira y se
queda quieto, «sin animaciones» y «alto contraste»; las sugerencias que se mandan y las que se
completan, en la bóveda, en un cuaderno y en conversación libre; el aviso del modelo en el vacío
y en la conversación; enviar apagado sin texto, escribir mientras el modelo escribe, Detener;
Enter y Shift+Enter en la computadora y en el teléfono; Cámara, Fotos, Archivos y sus permisos;
el modo y el cuaderno desde el «+»; «Pensar más» con Gemma, con un modelo que no razona y con uno
que sí, hasta el pedido de cada proveedor; dictar, con sus errores; el contraste en los nueve
temas; y **la pantalla entera —barra, vacío con el aviso, campo y la hoja del «+»— con letra al
doble en una pantalla chica, sin desbordes** (lo que el paso 1 dejó avisado). Lo que hace la
persona —mandar, elegir dónde se pregunta por la línea o por el «+», adjuntar— está una sola vez
en `test/support/chat_actions.dart`, que usan todas las pruebas del chat.

### Paso 3 — la conversación (construido)

**Dónde vive.** La conversación salió de `chat_screen.dart` a sus piezas, en
`chat/presentation/widgets/`: `chat_message_list.dart` (la lista, «↓», lo que se ofrece al lector),
`chat_user_bubble.dart` (la burbuja, editar y reenviar), `chat_answer_message.dart` (la respuesta
guardada), `chat_answer.dart` (el texto con formato y el fundido), `chat_markdown_blocks.dart` (los
bloques), `chat_answer_actions.dart`, `chat_citations.dart` (chips, «Fuentes», tarjetas),
`chat_message_menu.dart` (mantener apretado), `chat_typing_indicator.dart` y
`chat_stage_transition.dart`. En la pantalla quedan la llamada y lo que es suyo: preguntar,
volver a generar y reenviar —que comparten un solo `_ask`—, las vibraciones y las fuentes de la
respuesta que se escribe.

**La respuesta, con tipografía y sin paquetes nuevos.** Hasta acá el chat mostraba el Markdown
crudo. No se sumó un paquete de Markdown: el texto de la respuesta tiene que seguir siendo el de
las posiciones que pinta el lector en voz alta (F25), y eso ya lo resuelve `RenderedMarkdown`, el
de toda la app. Lo nuevo es la capa de bloques (`parseChatBlocks`): títulos de seis niveles,
párrafos con sus saltos, listas con viñetas o números y anidadas, citas, código entre cercas con
su lenguaje, separadores y tablas, cada bloque con sus posiciones en el texto crudo; lo de adentro
lo sigue leyendo `RenderedMarkdown`, que suma un `codeStyle` para el fondo del código en línea. El
cuerpo va a 1,55 de interlineado, los títulos en peso 700, el código en un recuadro con «Copiar el
código», las tablas y el código deslizables de costado, y en pantallas anchas la conversación se
centra en 760 px.

**Mientras escribe, sin costo cuadrático.** Cada evento del modelo es todo el texto hasta ahí:
leerlo entero con cada palabra cuesta el largo al cuadrado. `ChatBlockStream` retoma desde el
anteúltimo bloque —el único, con el último, que el renglón que se escribe puede cambiar— y deja
los asentados como los mismos objetos; la pantalla guarda el widget de cada bloque armado
(`Expando`) y solo rearma los que todavía cambian, los que se están fundiendo y el que toca el
amarillo del lector. Una prueba mide que cuatro veces más texto cueste cerca de cuatro veces más,
y otra que el primer párrafo sea el mismo widget mientras crece el último. El fundido es un
`Ticker` que corre solo mientras algo se está fundiendo (320 ms, con su propio reloj de cuadros) y
se apaga solo; con «sin animaciones» no corre. Antes de la primera palabra, un punto de luz que
respira con los colores del tema y «Buscando en tu bóveda…» o «Pensando…», con un brillo que la
recorre; quieto con «sin animaciones», y región viva para el lector de pantalla.

**Citas y fuentes.** El «[1]» del modelo —también «[1, 2]»— es un chip numerado con su propio
nodo para el lector de pantalla («Fuente 1: …»); un número que no existe queda como texto. Tocar
un chip o una tarjeta abre la fuente en su pasaje (`RoutePaths.reading` con el rango, el mismo
salto de las tarjetas de F11); sin pasaje, su detalle. Los chips están desde que se escribe: la
pantalla le pasa a la lista las fuentes de esa vuelta. «Fuentes» se pliega; sin el modelo, cuando
las fuentes son la respuesta, se ven desplegadas.

**Acciones.** Copiar; escuchar con el lector flotante (`readSelectionAloud` sobre todo el mensaje,
y el mismo botón lo cierra); volver a generar, solo en la última y nunca mientras se escribe:
borra la respuesta (`ChatConversationRepository.deleteMessage`, sin migración) y la vuelve a
pedir con la misma pregunta y sus adjuntos releídos del almacén, sin repetir la pregunta en el
historial —si la foto ya no está, lo dice y no toca nada—; 👍/👎 en las preferencias del teléfono
(`chatFeedbackProvider`, las últimas mil), que nunca salen de ahí. Las respuestas se ofrecen al
lector como Markdown, así no se dicen los `**`.

**Mantener apretado.** Copiar, seleccionar texto (lo que se ve, sin marcas, en una hoja con
`SelectableText`) y, en los mensajes propios, editar y reenviar: la burbuja se vuelve un campo y
«Reenviar» lo manda corregido, con sus adjuntos, como un mensaje nuevo al final. No se reescribe
el historial: la sesión del modelo no puede olvidar una vuelta, y lo conversado queda como pasó.

**Inmersivo.** `AdaptiveScaffold` saca la barra de abajo cuando el teclado ya la tapa entera
(su alto de Material 3 más el borde que quede): antes no, para que lo de arriba no salte mientras
el teclado sube. «↓» aparece al alejarse 240 px del final y lleva al final de verdad
(`scrollChatToEnd`): la lista arma solo lo que se ve y el largo que conoce es una estimación, así
que después de ir se corrige hasta que el final deja de moverse —también al abrir una
conversación, que antes podía quedar unos renglones antes del final—, y para si la persona agarra
la lista. Vibración corta (`HapticFeedback.lightImpact`) al mandar y al terminar.

**Transiciones.** El vacío y la conversación se funden y la conversación sube apenas al entrar
(`ChatStageTransition`, 360 ms); el brillo del fondo se va con el mismo fundido. Pasar de una
conversación a otra no es un cambio de escena: la lista es la misma. El panel ya entraba
deslizándose desde el paso 1. Todo respeta «sin animaciones».

**Ninguna función se perdió (decisión D).** Lo de siempre, en su lugar nuevo y con su prueba: la
respuesta que crece y se guarda, Detener, lo escrito antes de un error con su aviso (ahora en un
recuadro con su fondo: el rojo del tema sobre el papel no llegaba a AA en un tema claro), el
buscador sin modelo con su explicación, «no encontré nada», la foto del mensaje
(`ChatAttachmentTile`, del paso 2), el amarillo del lector en preguntas y respuestas, y las
tarjetas de las fuentes —que ahora se despliegan—.

**Pruebas.** Con dobles en todo: los bloques letra por letra y palabra por palabra contra leerlos
enteros, el costo lineal, la tipografía de cada bloque, los chips y adónde llevan, el amarillo en
cada pedazo, el fundido y que se apague, «sin animaciones», que los bloques asentados no se
rearmen; las acciones, el 👍/👎 en las preferencias, mantener apretado, editar y reenviar (con
foto), volver a generar (con foto, y sin ella), «↓», las vibraciones, la transición, la barra con
el teclado; el contraste AA de cada par de colores en los nueve temas, la conversación dibujada en
cada uno, y una respuesta con todo con letra al doble sin desbordes. Las mutaciones van en el
informe del paso.

### Paso 4 — cierre (hecho)

- La decisión 88 en `docs/arquitectura.md`, con lo que se descartó y lo que no quedó probado, y
  F42 en «Construido».
- CONTEXTO y la GUÍA al día. Los pasos 2 y 3 ya habían sumado a la GUÍA el vacío, el campo, «Agregar
  al chat», «Pensar más», el dictado y «La conversación».
- `verify_commit`: los pasos 1 (`5159001e`), 2 (`18dcf918`) y 3 (`fc1f08c1`) compilan y pasan el
  analizador solos, con 19 avisos, la línea base.
- Suite entera sobre main con los tres pasos (`71481248`): **10.988 pasan, 46 omitidas, 3
  fallas**, ninguna del chat. Las tres son de Anki y del lector de libros:
  - las de Anki pasaron solas; venían de la carga de la máquina, con varios agentes corriendo
    pruebas a la vez, y se arreglaron de raíz en un commit aparte;
  - la de paginar en otro hilo mide tiempos y pasó sola.
- Falta mirarlo en el teléfono: el dictado con el reconocedor real, la vibración, el teclado
  inmersivo y cómo se ven el fundido, el indicador y el brillo. La APK se instala solo si el
  dueño la pide.
