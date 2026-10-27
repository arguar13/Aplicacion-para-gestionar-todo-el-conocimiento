# F42 — Un chat moderno, inmersivo y elegante

> **Estado: APROBADO** (2026-10-27, «Aprobado» en el chat).
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

(Vacío hasta aprobarlo.)
