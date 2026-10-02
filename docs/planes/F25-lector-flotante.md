# F25 — El lector flotante: la app lee en voz alta cualquier texto

> **Estado: propuesto** (2026-10-02), esperando aprobación en el chat ("aprobado"). Pedido del
> usuario: *"en todas las pestañas haya un icono flotante en la esquina inferior derecha donde al
> apretarlo aparezca un mini reproductor de audio pero que sirva para leer el texto, únicamente
> leer el texto; tendrá controles para elegir la voz, el acento, la velocidad, adelantar 10
> segundos o retroceder, cerrar o minimizar, pausar y reproducir; que sea muy profesional y
> aparezca en todas las interfaces donde esté contenido de texto —no en ajustes ni en la papelera
> ni en la biblioteca—; que tenga su propio resaltado amarillo por cada línea que lee y sea
> eficiente y óptimo"*. El botón "Escuchar" de debajo de cada texto ya se quitó a pedido: este lo
> reemplaza.

## Lo que hay hoy (relevado en el código)

El lector de voz (`NarrationPlayer`, sobre `flutter_tts` 4.2.5) lee **oración por oración** sin
saber dónde está cada una en el texto, no resalta nada, no tiene pausa de verdad —"pausar" es no
pedir la oración siguiente—, ni ±10 s, ni acento: solo voz y velocidad. Vive dentro de cada
pantalla y se apaga al salir.

## Qué se construye

1. **Un botón flotante abajo a la derecha**, redondo, con el ícono de leer, **solo en las pantallas
   que muestran texto** (decisión B). Cada una de esas pantallas *declara* el texto que se puede
   leer; el botón aparece mientras haya uno declarado. Así funciona también en las pantallas que se
   abren por encima —el lector de libros, el modo lectura—, y no aparece donde no hay texto.
2. **Al tocarlo, el mini reproductor de lectura**, una pastilla como la del audio (F23):
   reproducir/pausar (pausa de verdad: retoma en la palabra donde quedó), **retroceder y avanzar
   10 s**, la **velocidad** (0,5× a 2×, en el mismo panel elegante del reproductor de audio), y un
   botón de ajustes con la **voz** y el **acento** —el acento es el idioma y la región de la voz:
   español de Argentina, de España, de México, inglés de EE. UU., etc., según las voces instaladas
   en el teléfono, con una muestra para escucharlas—. **Minimizar** lo vuelve a dejar como el botón
   redondo, con un anillo que muestra cuánto leyó, y sigue leyendo; **cerrar** lo detiene.
3. **El resaltado amarillo por línea**: la línea que está leyendo —el renglón del texto; uno largo
   se lee y se resalta de a oraciones— se ve en amarillo, el mismo de F23. El texto se lee tal cual
   se ve: sin las marcas "[3:15]" de las transcripciones y sin los símbolos de formato.
4. **±10 s de verdad.** El motor de voz no tiene una línea de tiempo; se arma una: Android avisa
   qué palabra está diciendo (`setProgressHandler`), así que se mide cuántas palabras por segundo
   dice esa voz a esa velocidad, y retroceder o avanzar 10 s salta esa cantidad de palabras, al
   comienzo de la palabra (decisión A).
5. **Uno a la vez con el audio.** Si suena un audio o un video y se empieza a leer, el audio se
   pausa, y al revés.
6. **Eficiente.** La lectura va línea por línea —nunca el texto entero de una vez al motor—, la
   pantalla se redibuja solo cuando cambia la línea, y lo que ya se leyó no se vuelve a preparar.
   Sigue leyendo con la pantalla apagada mientras la app esté abierta.

## Decisiones que necesito que confirmes

- **A. Qué significa "10 segundos".**
  - *(Recomendado)* **10 segundos de habla**, medidos sobre la voz y la velocidad elegidas (arriba,
    punto 4): se siente igual que en un reproductor de audio.
  - Alternativa: **una línea** para atrás o para adelante. Más simple, pero una línea puede durar 2
    segundos o 40.
- **B. Dónde aparece el botón.**
  - *(Recomendado)* Donde se lee texto de un elemento: **el detalle de un elemento** (su texto, sus
    notas de bloques, la nota del usuario), **el modo lectura**, **el lector de libros y
    documentos** (lee la página que se ve y sigue con la siguiente), y **el editor de notas**.
    **No** en la biblioteca, la bandeja, el mapa, el atlas, los cuadernos como lista, el repaso de
    tarjetas, el chat, los ajustes ni la papelera.
  - Alternativa: también en **el chat** (leer las respuestas) y **el repaso de tarjetas** (leer la
    pregunta y la respuesta).

## Orden de trabajo

1. El motor de lectura: el texto partido en líneas **con su lugar en el texto**, pausa real,
   avance por palabra (`setProgressHandler`), ±10 s, voces por acento.
2. Quién declara qué texto se puede leer, y el botón flotante global.
3. El mini reproductor de lectura —el mismo diseño del reproductor de audio— y su panel de voz,
   acento y velocidad.
4. El resaltado amarillo por línea en cada pantalla con texto.
5. Pruebas (con un motor de voz falso), y prueba en el teléfono.
