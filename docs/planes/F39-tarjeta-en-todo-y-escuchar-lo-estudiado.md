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
