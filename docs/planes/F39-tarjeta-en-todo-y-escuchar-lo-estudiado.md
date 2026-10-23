# F39 — La tarjeta de estudiar en todo, el texto plegado, las fotos, escuchar solo lo estudiado y hacerlo a mano

> **Estado: APROBADO** (2026-10-23, *«Ahora sí continúa»* en el chat, con las decisiones A, B y C
> como están propuestas). Pedido del mismo día, en el chat:
>
> - *"cuando se trata de una página web o publicaciones en redes sociales, quiero que en esta
>   tarjeta agregues primero [Extraer] texto (como cuando se trata de un PDF o un libro) así ya no
>   tenga todo el texto desplegado abajo que ocupa mucho … y lo mismo para cuando se trate de
>   imágenes o audios o videos"*.
> - *"… que pase lo mismo con las fotos … debajo de «Extraer texto» así sea algo desplegable"*.
> - *"… que el audio tenga opción de además de leer todo el texto, de leer solo el resumen o solo la
>   síntesis o solo las palabras claves"*.
> - *"si no hay resumen, al desplegar o hacer click en resumen me aparezca una sugerencia de resumir
>   con el modelo de ai usado, y de resumir manualmente … dentro y fuera del documento … y también
>   síntesis y palabras claves"*.
> - Elegido en el chat: imágenes, audios y videos llevan **la tarjeta completa**, con Resumir,
>   Sintetizar y Palabras clave.
>
> Sumados el mismo día, mientras se trabajaba, en este orden (*"Todos los pedidos hazlos
> secuencialmente, sin saltearte nada"*):
>
> - *"cuando use el modelo de IA, no tenga errores porque hay veces que se para de la nada y me dice
>   error de conexión cuando en realidad siempre tengo buena conexión … y que sea más informativo
>   porque yo no sé cuánto le queda o qué problema hubo"*.
> - *"saca eso de la racha en ajustes, creo que no es necesario"*.
> - *"en Vínculos que haya opciones para mostrar los vínculos más fuertes, menos fuertes y todos,
>   algo así como los grados en los grafos"*.
> - *"en «Lo que hizo la IA» … que me deje ver qué hace la IA en este momento y cómo lo hace … qué
>   porcentaje va, cuánto tiempo va y cuántos tokens va … muy organizado … y muy elegante"*.
> - *"en Ajustes, en cambiar tema, que tenga más opciones porque solo tiene claro y oscuro … que
>   tenga sepia y muchas más opciones, así sea más elegante y atractivo"*.

## Lo que hay hoy

| Qué | Cómo está |
|---|---|
| **La tarjeta «Estudiar»** | Solo en documentos y páginas web. En un documento trae «Extraer texto» plegado; en una página web no, y el texto entero queda desplegado abajo. |
| **Publicaciones, imágenes, audios, videos, YouTube** | Sin tarjeta. El texto o la transcripción, entero y desplegado abajo. En un audio o video, la palabra que suena se resalta y «Volver al audio» lleva hasta ella. |
| **Fotos de una página o publicación** | En la sección «Contenido», más abajo, siempre a la vista. |
| **Escuchar** | El lector en voz alta lee **todo** lo que se ve. |
| **Sin resumen todavía** | Tocar «Resumir» analiza enseguida con el modelo elegido; las filas «Extraer resumen» están apagadas. Las palabras clave solo se pueden elegir a mano **dentro de una oración resaltada**. |

## Qué se construye

### 1. La tarjeta en todo lo que tiene texto, con el texto plegado adentro

- La tarjeta va en **documentos, páginas web, publicaciones, imágenes, audios, videos y YouTube**.
  Su título dice qué es: «Estudiar el documento», «Estudiar la página», «Estudiar la
  publicación», «Estudiar la imagen», «Estudiar el audio», «Estudiar el video».
- **«Extraer texto»** va primero en «Extraer», plegado, en todos. El texto entero ya **no** queda
  desplegado debajo de la tarjeta. En un audio o un video la fila dice «Extraer transcripción».
- **En un audio o un video**, la transcripción plegada sigue al audio igual que hoy. «Volver al
  audio», en el mini reproductor, **despliega la fila sola** y lleva a la palabra que suena.
- Lo que se resalte (resumen, síntesis, palabras clave) se ve en el texto de esa fila. En un PDF,
  una página o un Word se sigue viendo también sobre el original, como hoy.
- «Descargar» solo aparece donde el original se puede marcar: PDF, Word, EPUB, página web, texto y
  Markdown. En una foto, un audio o un video no aparece.

### 2. Las fotos, en la tarjeta

- En una página web o una publicación, debajo de «Extraer texto»: **«Fotos»**, plegada, con cuántas
  hay. Al desplegarla se ven en grilla, y tocar una abre lo mismo que hoy.
- Salen de «Contenido», que sigue mostrando lo demás que se bajó: documentos, audios y videos.

### 3. Sin resumen todavía: con la IA o a mano

- Si todavía no hay resumen y tocás **«Resumir»**, o desplegás **«Extraer resumen»**, aparece una
  sugerencia con dos caminos:
  - **«Resumir con Gemini 3.1 Flash Lite»**, que dice el modelo que tenés elegido. Hace lo de hoy.
  - **«Elegir a mano»**: entrás en un modo donde **tocás una oración y pasa al resumen**. Si la
    tocás de nuevo, sale. Arriba se ve «Eligiendo el resumen · Listo».
- Igual con **«Sintetizar»** («Elegir la síntesis a mano») y con **«Palabras clave»**. A mano, las
  palabras clave se pueden elegir **en cualquier oración**, aunque no haya resumen. Siguen siendo
  hasta 4 por oración.
- Vale **adentro del documento** (la barra de arriba en «Leer como libro», el PDF y la página) y
  **afuera**, en la tarjeta.
- Lo elegido a mano y lo de la IA conviven. «Volver a analizar» sigue preguntando antes, porque
  reemplaza lo de la IA. **Decisión A**: lo que elegiste a mano se queda, no lo borra.

### 4. Escuchar solo lo estudiado

- **En la tarjeta**: «Extraer resumen», «Extraer síntesis», «Extraer palabras clave» y «Extraer
  texto» traen **«Escuchar»** junto a «Copiar».
  - Con el resumen o la síntesis, cada oración se resalta en amarillo **en el texto** mientras
    suena, igual que hoy con el texto entero.
  - Con las palabras clave, se leen una tras otra.
- **Adentro del documento y en el detalle**: el reproductor del lector en voz alta suma
  **«Leer: Todo · Resumen · Síntesis · Palabras clave»**. Las opciones sin datos aparecen
  apagadas.

### 5. La IA sin cortes falsos, y diciendo qué pasa

- Buscar **por qué** un análisis largo se corta con «error de conexión» teniendo buena conexión, y
  arreglar eso: la causa, no reintentar a ciegas. Por ejemplo, una espera que vence, una respuesta
  cortada o un límite de la cuenta tomado como falta de red.
- Lo que sí es pasajero —la red que se cae un momento, el servicio ocupado— se reintenta solo, con
  espera creciente, y la franja lo dice: «Reintentando (2 de 4)…».
- Cada aviso dice **qué pasó de verdad**: sin conexión, la cuota de la cuenta, el servicio que
  respondió mal o la espera que venció. Y qué hacer.
- Mientras analiza: la parte que va, **el porcentaje y cuánto falta, aproximado**.

### 6. «Lo que hizo la IA», en vivo

- Arriba, si la IA está trabajando, **«Ahora»**: qué hace —«Resumiendo "Historia", parte 3 de
  12»—, con qué modelo, el porcentaje, el tiempo que lleva y los tokens que lleva.
- Plegado debajo, **«Cómo lo hace»**: los pasos de esa tarea (partir el texto, mandar cada parte,
  juntar) con el que va marcado.
- Lo que ya hizo sigue como hoy, en «Actividad». Cada tarea terminada suma su tiempo y sus tokens.
- Ordenado y sin cargar la pantalla: una sola tarjeta para lo que pasa ahora, y el detalle plegado.

### 7. Sin «Racha e historial» en Ajustes

- Sale el interruptor y la sección «Hábito». **Decisión D**: la racha y el historial se siguen
  viendo en Repasar, como con el interruptor prendido, que era lo de siempre.

### 8. Vínculos: los más fuertes, los menos fuertes o todos

- En el Mapa, en «Vínculos», un selector **«Más fuertes · Menos fuertes · Todos»**, como los grados
  del Grafo. Cuánto pesa un vínculo sale de lo que ya se guarda: el tipo, si lo confirmaste vos y
  cuántas veces se citan. Al hacer este paso se releva qué se guarda exactamente.

### 9. Más temas en Ajustes

- En «Cambiar tema», además de Claro, Oscuro y «Como el sistema», **varios temas con nombre**:
  - **Sepia**, papel cálido para leer largo;
  - **Noche** (negro puro, que en una pantalla OLED gasta menos);
  - otros de tono suave y elegante, por ejemplo **Bosque**, **Océano**, **Lavanda** y
    **Grafito**.
- Cada uno se muestra como una **muestra chica con sus colores**, para elegir viendo, y se aplica
  al instante en toda la app.
- Lo que tiene un color propio sigue legible en cada tema: los resaltadores de estudiar, los
  subrayados, el amarillo de lo que se lee y el papel del PDF.
- **Decisión E**: cuántos y cuáles. Propongo los seis de arriba más Claro y Oscuro, y que el
  lector («Leer como libro») siga el tema elegido.

### Pedidos sumados durante el encargo

- **Palabras clave en todas las oraciones**, de punta a punta del documento. Hoy la IA las propone
  solo en las oraciones del resumen o de la síntesis. Se pide una línea de palabras clave por
  **cada** oración, y se ven todas cuando están prendidas. Un documento ya analizado necesita
  «Volver a analizar» para traerlas, y eso deja lo elegido a mano. Va justo después de 3b.
- **Resumen, síntesis y palabras clave se superponen**: se prende una, dos, las tres o ninguna, en
  vez del interruptor de hoy, donde se ve el resumen o la síntesis y nunca los dos. Con los dos
  prendidos, la síntesis se pinta encima del resumen, porque es lo más esencial. Vale en todas las
  superficies y en lo que se descarga. Va con el arreglo de las palabras clave, porque tocan lo
  mismo.
- **Más colores para resaltar a mano** (F38): una paleta de 8 a 10 colores, legibles en claro y en
  oscuro y distintos de los de estudiar y del amarillo de lo que se lee. Lo hace un agente en su
  propia rama, en paralelo.
- **Los dos menús encimados al seleccionar en una página**: el de colores de la app y el del
  sistema («Copiar · Seleccionar todo») se tapan. Queda uno solo, el de la app, que suma Copiar y
  Seleccionar todo; si el sistema no deja ocultar el suyo, van uno encima del otro sin taparse. Va
  con 3c, porque es el mismo código de la página.
- **La página web igual al original**, letra por letra y foto por foto. En la Wikipedia guardada
  aparece desplegado arriba el índice que el original oculta, y queda una franja vacía a la
  derecha. Se buscan las causas (estilos que el original carga al abrirse, el ancho, lo que la app
  le agrega para estudiar) y se arreglan. Lo hace un agente en paralelo.
- **La vista previa del mapa del elemento, prolija**: con muchos vecinos hoy se enciman las
  tarjetas y las etiquetas. Se rediseña para que nada se tape y use todo el ancho, con los más
  importantes y un «+N». Lo hace un agente en paralelo.
- **La vista previa de un documento, fija en la primera página**: hoy, al bajar por el detalle, el
  gesto mueve el libro en vez de la pantalla. Queda la primera página quieta, y tocarla abre «Leer
  como libro». Lo hace un agente en paralelo.

## Decisiones para que confirmes

- **A.** «Volver a analizar» rehace lo de la IA y **deja lo que elegiste a mano**. Hoy borra
  también las palabras clave elegidas a mano. Propongo que deje de hacerlo.
- **B.** En un audio o un video, «Escuchar el resumen» usa la **voz del lector**, no el audio
  original. Saltar por el audio original a cada oración del resumen es otra cosa: si la querés, se
  puede sumar después.
- **C.** En una foto, el texto es el que se leyó de la imagen (OCR). Lo resaltado se ve en ese
  texto, no pintado sobre la foto.
- **D.** Sin «Racha e historial» en Ajustes: la racha y el historial se ven siempre en Repasar.
- **E.** Los temas: Claro, Oscuro y «Como el sistema», más Sepia, Noche, Bosque, Océano, Lavanda y
  Grafito, cada uno con su muestra. El lector a pantalla completa sigue el tema elegido. Se puede
  cambiar la lista antes de llegar a ese paso.

## Pasos (cada uno, su commit y su push)

1. La tarjeta en todo lo que tiene texto, con «Extraer texto» o «Extraer transcripción» adentro:
   - la transcripción sigue al audio, y «Volver al audio» la despliega;
   - lo estudiado se pinta en la transcripción.
2. «Fotos» en la tarjeta.
3. La sugerencia de «Resumir con …» o «Elegir a mano», y el modo de elegir oraciones y palabras a
   mano, adentro y afuera del documento. Esto incluye la decisión A.
4. «Escuchar» en las filas y «Leer: Todo · Resumen · Síntesis · Palabras clave» en el
   reproductor.
5. La IA sin cortes falsos, reintentos y avisos que dicen qué pasó y cuánto falta.
6. «Lo que hizo la IA» en vivo: qué hace, cómo, porcentaje, tiempo y tokens.
7. Sacar «Racha e historial» de Ajustes (decisión D).
8. Vínculos: más fuertes, menos fuertes o todos.
9. Más temas en Ajustes: Sepia, Noche y los demás, con su muestra.
10. Cierre: GUIA_DE_USO, las decisiones en `docs/arquitectura.md`, CONTEXTO y el «Avance»; suite
   entera y `verify_commit`; la APK al teléfono si la pedís.

## Avance

- **Paso 1 — hecho.** La tarjeta va en todo lo que trae un texto propio: se estudia todo menos
  una nota escrita a mano y una referencia. El título cambia según qué es. El texto va plegado en
  «Extraer texto», o en «Extraer transcripción» en un audio o un video, y ya no queda desplegado
  debajo de la tarjeta.
  - En la transcripción plegada, lo estudiado se pinta debajo de la palabra que suena.
  - Eligiendo palabras clave, un toque elige en vez de mover el audio.
  - «Volver al audio» la despliega sola.
  - Al armarse con el audio ya sonando, la transcripción sabe lo que suena desde el primer cuadro,
    sin esperar al próximo aviso del reproductor. Es la causa de fondo: desplegada, no tenía nada
    que mostrar.
  - Las marcas de tiempo `[3:15]` quedan fuera de las oraciones.
  - El lector en voz alta no lee el texto mientras está plegado.
  - Pruebas nuevas: la tarjeta de cada tipo; el despliegue en el mini reproductor; lo pintado y el
    toque en la transcripción; y una de punta a punta en el detalle de un audio.
  - Commit `083b55bd`, verificado solo con `verify_commit`. Las 20 mutaciones mueren.
- **Paso 2 — hecho.** «Fotos», plegada, con cuántas son, debajo de «Extraer texto» en la tarjeta.
  - La grilla es la de «Contenido», ahora pública (`AttachmentImageGrid`). Tocar una foto ofrece lo
    mismo que antes.
  - Con la tarjeta, «Contenido» deja afuera las fotos, también de su cuenta. Sin la tarjeta (una
    nota, una referencia), siguen ahí.
  - Va en todo lo que lleva tarjeta y trae fotos; en la práctica, páginas y publicaciones, que son
    las que bajan su «Contenido».
  - Las 8 mutaciones mueren. Commit `3a53b4f5`, verificado.
- **Paso 3, primera parte (3a) — hecho.** Elegir a mano en cualquier superficie: una sola regla,
  `studyPickAt`, y una sola función, `pickStudyAt`, que ya usaban para las palabras clave el
  detalle, la transcripción, «Leer como libro», el PDF y la página.
  - **Resumen o síntesis**: tocar una oración la pone entera; tocarla de nuevo la saca, la haya
    puesto la IA o la persona. Se parte igual que en el análisis, así que coincide con lo de la IA.
  - **Palabras clave**: en **cualquier** oración, haya o no resumen, hasta 4 por oración. Se ven
    todas sin capa prendida o mientras se eligen; con el resumen o la síntesis, las de sus
    oraciones. Lo mismo vale en lo que se descarga.
  - **Decisión A**: «Volver a analizar» borra solo lo de la IA (`clearAi`), y un análisis no
    duplica lo que la persona ya eligió.
  - El repositorio queda con `addUserMark` y `removeMark` para cualquier tipo, en lugar de
    `addKeyword` y `removeKeyword`.
  - Falta la manera de entrar a elegir el resumen o la síntesis: es la sugerencia de 3b.
- **Paso 3, segunda parte (3b) — hecho.** La sugerencia: sin nada todavía, tocar Resumir,
  Sintetizar o Palabras clave abre una hoja con **«Resumir con <modelo>»** —el nombre del modelo
  elegido, como en «Revisar con…»— y **«Elegir a mano»**.
  - **A mano**: prende la capa, pasa a elegirla y despliega el texto donde se toca. Un botón dice
    qué se elige y **Listo** termina; lo elegido queda prendido, también las palabras clave.
  - Si la IA ya analizó todo y no encontró nada de esa clase, queda solo «Elegir a mano».
  - Con algo ya hecho, el botón prende directo. Un análisis a mitad sigue; uno que nunca empezó
    —todo a mano— no arranca solo.
  - Las filas vacías de «Extraer» se despliegan y ofrecen lo mismo; mientras la IA analiza, avisan
    que va a aparecer ahí.
  - `chosenLanguageModelNameProvider`: el nombre del modelo elegido, al día. «Revisar con…» de F33
    pasa a usarlo.
  - **Causa de fondo encontrada**: en «Leer como libro» nadie miraba todavía lo estudiado al tocar
    Resumir, así que se leía «sin cargar» y se ofrecía armar un resumen que existía. Ahora la
    decisión lee lo guardado en el repositorio, no lo que la pantalla ya cargó.
  - `tool/mutar.py` reintenta la escritura si Windows tiene el archivo tomado un instante: antes
    se cortaba a mitad y dejaba el código mutado.
  - Las 19 mutaciones mueren.
- **Palabras clave en todas las oraciones, y los tres resaltados superpuestos — hecho.**
  - **El pedido**: una línea `CLAVE` por **cada** oración de la parte, de la primera a la última,
    estén o no en el resumen o en la síntesis. Se leen todas, en el orden del texto.
  - **La ventana de Gemma**: cada oración trae ahora su respuesta, así que la parte reserva por
    oración el lugar de su línea de palabras clave (`_perSentenceOverhead` = 62 caracteres) y la
    respuesta crece con la cantidad de oraciones (`studyReplyTokens`, hasta 3072). Si la parte no
    entra y se achica, el chat se cierra y se reabre con el tope de respuesta de lo que sí entra:
    antes el lugar se calculaba con la parte entera y podía quedar negativo.
  - **`StudyView` con tres interruptores** (`summary`, `synthesis`, `keywords`) en vez de una
    capa: juntos, de a uno, de a dos o ninguno. Con el resumen y la síntesis prendidos, la síntesis
    se pinta después —encima—. Vale en el detalle, la transcripción, «Leer como libro», el PDF, la
    página guardada y lo que se descarga.
  - Las palabras clave se ven **todas** cuando están prendidas; desaparece
    `studyKeywordMarksWithin`.
  - Apagar el resaltado que se está eligiendo a mano deja de elegirlo; prender otro, no.
  - En la página guardada, las palabras se envuelven solo dentro de las oraciones resaltadas: que
    cualquier palabra se pueda tocar es el paso 3c.
  - Los documentos ya analizados necesitan «Volver a analizar» para traer las palabras clave de
    todas las oraciones; lo elegido a mano queda.
  - Las 27 mutaciones mueren. Dos sobrevivían en la primera pasada —prender un resaltado
    prendía el otro, y la igualdad no miraba la síntesis— y se sumaron pruebas directas de
    `StudyView`.
- **Más colores para resaltar a mano — hecho.** Nueve, en una grilla de dos filas: amarillo,
  naranja, coral, arena, lima, turquesa, azul, violeta y gris, de los cálidos a los fríos.
  - Distintos a propósito de lo estudiado: el verde es un lima, el azul más violáceo que el
    celeste de la síntesis y el rojo un coral. En oscuro el amarillo claro se aclara un poco más,
    para no confundirse con el amarillo fuerte de lo que se lee en voz alta.
  - Se guardan **por nombre** (`textEnum`): sumar colores no toca lo guardado y no hace falta
    migrar. Lo resaltado con los cuatro de antes se ve igual; hay una prueba con la base v42.
  - Mantener apretada una muestra dice su nombre, también al lector de pantalla. Lo que se
    descarga marcado sale con los mismos nueve colores.
  - Las 18 mutaciones mueren.
- **Paso 9 — hecho.** «Cambiar tema» en Ajustes muestra el tema de ahora y, debajo, una muestra
  chica con los colores de cada uno, para elegir viendo: Sistema (claro y oscuro lado a lado),
  Claro, Oscuro y los seis con nombre —Sepia, Noche, Bosque, Océano, Lavanda y Grafito (decisión
  E)—. Tocar una muestra lo aplica al instante en toda la app y lo guarda.
  - Modelo: `AppThemeChoice` da el `ThemeData`, el modo y el brillo de cada tema
    (`app_theme_choice.dart`), y `AppThemePalette` trae los once colores de cada uno con el resto
    del esquema derivado (`app_theme_palette.dart`). Sepia y Lavanda son claros; Noche (negro
    puro), Bosque, Océano y Grafito, oscuros, así que lo que elige color por `Theme.brightness`
    acierta solo.
  - Guardado: `ThemeChoiceNotifier` usa la misma clave y los mismos nombres que antes, y lo
    guardado por la versión anterior se lee sin migrar nada; un valor desconocido vuelve a
    «Sistema».
  - Legibilidad: los resaltadores de estudiar, el amarillo de lo que se lee y el papel del PDF ya
    se leían bien en cualquier tema. Se arregló que un subrayado a mano de fondo, sobre un tema
    oscuro, tuviera letra clara (ahora oscura, y la coincidencia lleva su propia letra). En Sepia,
    `HighlightPalette.forTheme` carga el amarillo claro para que se distinga del papel crema; con
    el claro y el oscuro de siempre no cambia ningún tono.
  - «Leer como libro» ya tomaba hoja, fondo y letra del tema, y queda fijado con pruebas.
  - Pruebas: modelo (brillo, colores, contraste AA de texto, acentos y contenedores, letra sobre
    los resaltadores), notifier (migración y guardado), selector (muestras, elegir aplica y
    guarda), la `App` entera, el lector y los subrayados; 41 mutaciones, todas muertas; `analyze`
    en 19.
  - Al integrarlo con los nueve colores, su prueba de legibilidad encontró que el azul nuevo en
    oscuro daba 6,9 de contraste con la letra oscura; pasó a `0xFF879EFF` (7,2), el mismo tono.
- **Paso 7 — hecho.** Sale de Ajustes el interruptor «Racha e historial» y la sección «Hábito», y
  con ellos el provider y su clave guardada (`habit_features_enabled`), junto con las 3 cadenas de
  los `.arb`.
  - La racha y el historial se ven siempre en Repasar, en la entrada y en el resumen de la sesión,
    como con el interruptor prendido; un valor viejo guardado en «apagado» queda sin leerse y no
    rompe nada.
  - Pruebas: Ajustes ya no lo muestra, y Repasar muestra racha e historial aunque el valor viejo
    diga apagado. 4 mutaciones, todas muertas.
- **Paso 8 — hecho.** La vista «Vínculos» del Mapa tiene un selector «Más fuertes · Menos fuertes ·
  Todos» con chips al estilo del grado del Grafo. Arranca en «Todos» y se recuerda mientras la
  vista vive.
  - El peso sale de lo que ya se guarda, sin cambiar la base:
    - tipo: 1 si es `relatedTo`, 3 si es `contradicts`, 2 el resto;
    - respaldo: 1 si es de la persona o revisado, o la confianza de la IA por 0,5;
    - ancla: +0,5 si se sabe de qué fragmento sale;
    - repetidos: +1 por cada vínculo de más entre los mismos dos elementos.
  - `linkStrength` y `cutLinksByStrength` son puras. El corte es la mitad (redondeada hacia
    arriba) de cada punta, con empates estables: fecha más reciente, luego identificadores y tipo.
  - El repositorio corta antes de elegir qué dibujar. Lo cortado sigue contando como vinculado, y
    un aviso dice «Se muestran N de M vínculos».
  - Pruebas: unitarias del peso y del corte, de repositorio con las columnas reales, y de widget
    del selector y de la vista. 38 mutaciones, todas muertas (dos sobrevivían en la primera
    pasada —el desempate por `toId` y las aristas sin cortar— y se sumaron pruebas).
