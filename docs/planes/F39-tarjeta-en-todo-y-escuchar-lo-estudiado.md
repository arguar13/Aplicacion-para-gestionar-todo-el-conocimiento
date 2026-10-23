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

## Decisiones para que confirmes

- **A.** «Volver a analizar» rehace lo de la IA y **deja lo que elegiste a mano**. Hoy borra
  también las palabras clave elegidas a mano. Propongo que deje de hacerlo.
- **B.** En un audio o un video, «Escuchar el resumen» usa la **voz del lector**, no el audio
  original. Saltar por el audio original a cada oración del resumen es otra cosa: si la querés, se
  puede sumar después.
- **C.** En una foto, el texto es el que se leyó de la imagen (OCR). Lo resaltado se ve en ese
  texto, no pintado sobre la foto.

## Pasos (cada uno, su commit y su push)

1. La tarjeta en todo lo que tiene texto, con «Extraer texto» o «Extraer transcripción» adentro:
   - la transcripción sigue al audio, y «Volver al audio» la despliega;
   - lo estudiado se pinta en la transcripción.
2. «Fotos» en la tarjeta.
3. La sugerencia de «Resumir con …» o «Elegir a mano», y el modo de elegir oraciones y palabras a
   mano, adentro y afuera del documento. Esto incluye la decisión A.
4. «Escuchar» en las filas y «Leer: Todo · Resumen · Síntesis · Palabras clave» en el
   reproductor.
5. Cierre: GUIA_DE_USO, la decisión en `docs/arquitectura.md`, CONTEXTO y el «Avance»; suite entera
   y `verify_commit`; la APK al teléfono si la pedís.

## Avance

(vacío hasta que arranque)
