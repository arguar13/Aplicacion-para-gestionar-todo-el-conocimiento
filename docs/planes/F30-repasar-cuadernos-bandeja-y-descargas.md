# F30 — Repasar y Cuadernos con IA, la Bandeja de texto, bajar todo, y un chat rápido

> **Estado: aprobado** (2026-10-04), en el chat («aprobado»), con todas las recomendadas: **A**
> —✨ «Crear tarjetas con IA» en Repasar, con alcance—, **B** —crear con IA, sugeridos y llenar—,
> **C** —solo lo que tiene texto, y las tres opciones de los libros con papelera de 30 días—, **D**
> —todo adentro del mismo elemento— y **E** —tope de 500 MB por elemento—. Pedidos del usuario,
> después de probar la app en el teléfono:
>
> - *"en la sesión de repasar también haya una opción que deje que la IA haga las flashcards o lo
>   que sea necesario para repasar, además de la opción manual"*;
> - *"la sección de cuadernos, que además de ser manual, haya una opción donde la IA también me los
>   haga de forma inteligente"*;
> - *"en la bandeja, que utilice los textos, no audio ni video, solamente que trabaje con texto,
>   con su metadata; en el caso de libros, que dé la opción de que pase el texto, o solo el libro,
>   o ambos"*;
> - *"cuando se trate de enlaces de publicaciones o páginas, que haga lo posible por descargar todo
>   el contenido: libros enteros, imágenes, audios; si tiene archivos zip, que los descomprima; todo
>   conservado en el elemento, en su formato original, bien acomodado, y una transcripción para cada
>   elemento"*;
> - *"el chat es ultra lento: demora como un minuto por mensaje; no quiero cambiar el modelo"*;
> - *"que la app en general sea eficiente con la RAM de mi móvil"*.
>
> **Ya resuelto, sin plan** (eran errores): los EPUB no se leían (`240dbe1`), el Mapa amontonado
> (`d5afbc9`) y la clave en cada apertura (`0fb32a7`, ahora una vez por encendido).

## Lo que hay hoy (relevado en el código)

| Qué | Lo que pasa de verdad |
|---|---|
| **Repasar vacío** | No hay tarjetas, no es un problema de fechas: toda tarjeta nace lista para hoy. La IA las hace sola (F27), pero los 80 recursos de ejemplo son «biblioteca existente», que solo se recorre **con el teléfono cargando**. Además, la IA descarta toda tarjeta cuya cita no aparezca **textual** en el texto, y Gemma suele parafrasear: puede dar 0 tarjetas sin ningún aviso. |
| **✨ de tarjetas en un elemento** | Le manda el texto **entero** al modelo, que acepta unas 2.000 palabras: en un libro o un video largo falla. |
| **Pedir tarjetas para varios** | No existe: se piden de a un elemento. En Repasar no hay ningún botón para generarlas. |
| **Cuadernos** | Solo a mano, de a un elemento por vez, o «por consulta» con una vista guardada. Ninguna IA los crea ni los llena. La nota que la IA genera desde un cuaderno **no queda adentro** del cuaderno, y con más de ~15 elementos se pasa de lo que el modelo acepta. |
| **Bandeja** | La tarjeta ya muestra texto, no reproductores. Pero entra todo —también un audio sin transcribir, que queda solo con el título— y **no muestra los metadatos**: autor, fecha, sitio, páginas o duración. |
| **Texto con Markdown crudo** (tu captura de Wikipedia, `[![](//thumb…`) | La librería que extrae el artículo ignora la dirección de la página: las imágenes quedan con direcciones incompletas, y la tarjeta muestra ese marcado como texto. |
| **Libros (EPUB, PDF)** | Se guardan el archivo y su texto. No existe ninguna de las tres opciones; «Borrar el archivo y quedarme con el texto» no se ofrece para documentos. |
| **Bajar una página** | Guarda el texto y la página en un solo HTML con sus imágenes adentro. No sigue los enlaces a PDF, EPUB o MP3, no descomprime .zip, pierde las imágenes con carga diferida, y de un carrusel de Instagram baja solo la primera foto. Un elemento tiene un solo archivo. Las descargas no miran el espacio libre ni tienen tope. |
| **Chat** (~1 min por mensaje) | **No muestra nada hasta que la respuesta está entera**; la respuesta no tiene tope de largo; no se sabe si Gemma corre en la GPU o cayó a la CPU, mucho más lenta, sin avisar; la IA que organiza **no se pausa** con el chat abierto y el modelo de vínculos corre en paralelo; el modelo se carga recién con el primer mensaje. Dos errores más: después de 2 o 3 turnos la conversación puede pasarse de lo que el modelo acepta, y **las fotos adjuntas se descartan sin aviso**. |
| **RAM** | Gemma (~3,7 GB) y el modelo de vínculos **nunca se liberan**, ni con la app en segundo plano. La Biblioteca carga el texto completo de cada elemento —libros enteros— para mostrar la lista. Las miniaturas de 40×40 decodifican la foto entera: unos 48 MB por fila. |

## Lo que hago sin esperar la aprobación (son errores o mejoras sin decisión tuya)

1. **El Markdown crudo**: las direcciones de imágenes y enlaces se completan con la de la página, y
   la tarjeta de la Bandeja y la lectura muestran texto limpio.
2. **El ✨ de tarjetas** lee los textos largos por partes, como ya lo hace la IA automática.
3. **El chat, más rápido sin cambiar el modelo**:
   - Las palabras aparecen **a medida que se escriben** (la espera hasta ver la primera baja de un
     minuto a unos pocos segundos).
   - Un tope de largo para la respuesta.
   - Con el chat a la vista, la IA que organiza y el modelo de vínculos **esperan**.
   - El modelo se carga **al abrir el chat**, no con el primer mensaje.
   - Un contexto más justo: los pasajes que importan de cada fuente, no sus primeras 400 letras.
   - Medir en tu teléfono si corre en la GPU o en la CPU, y elegir el más rápido de verdad.
   - Arreglar los dos errores: la conversación larga y las fotos adjuntas.
4. **La RAM**:
   - Las miniaturas se decodifican a su tamaño, no a la foto entera.
   - La Biblioteca carga solo lo que muestra; el texto completo, recién en el detalle.
   - Gemma y el modelo de vínculos **se liberan** cuando Android avisa que falta memoria, y después
     de un rato sin uso con la app en segundo plano.

Todo con pruebas, y lo del chat y la RAM medido en tu teléfono antes de darlo por cerrado.

## Decisiones que necesito que confirmes

- **A. Repasar con IA.**
  - *(Recomendado)* **Un botón ✨ «Crear tarjetas con IA» en Repasar**, que pregunta para qué: toda
    la biblioteca, un tema, una etiqueta o un cuaderno. Corre en segundo plano, con su notificación,
    **sin esperar el cargador**, y solo hace tarjetas —no vínculos ni etiquetas—. Las tarjetas llevan
    ✨ y se pueden deshacer, como todo lo de la IA. La cita de cada tarjeta se acepta **aunque la IA
    la parafrasee**, mientras se ubique en el texto; si no, va a «Para revisar» en vez de perderse.
    Si Repasar está vacío, dice **por qué** (falta un modelo, esperando el cargador, N elementos sin
    tarjetas) con el botón al lado.
  - Alternativa: solo el aviso de por qué está vacío, con «Organizar con IA» —hace todo, no solo
    tarjetas, y tarda más—.
- **B. Cuadernos con IA.**
  - *(Recomendado)* Tres cosas:
    - **«Crear con IA»**: escribís de qué querés el cuaderno («mi tesis sobre Roma»), la IA busca en
      tu biblioteca y te propone los elementos ya marcados; destildás lo que no va y se crea.
    - **Cuadernos sugeridos** a partir de tus temas y etiquetas, que **se mantienen al día solos**
      con lo que entra.
    - **«Llenar»** un cuaderno: una guía de estudio que queda **adentro** del cuaderno, y sus
      tarjetas de repaso.
  - Alternativa: además, cuadernos **vivos**: cada elemento nuevo que encaja se agrega solo, con ✨ y
    «No era». Más trabajo (cambio de base de datos); se puede sumar después.
- **C. La Bandeja, solo texto.**
  - *(Recomendado)* **Entra solo lo que ya tiene texto**: un audio o un video, cuando ya está su
    transcripción; una foto, cuando ya se leyó su texto. Cada tarjeta muestra el texto limpio y sus
    **metadatos** —autor, fecha, sitio, páginas o duración, idioma— y nunca un reproductor.
    En los **libros y documentos**, triar pregunta qué pasa a la siguiente fase:
    - **Texto y libro** (lo de hoy).
    - **Solo el texto**: se borra el archivo original y queda el texto (libera espacio).
    - **Solo el libro**: se borra el texto y queda el archivo, que no se vuelve a extraer solo.

    Lo borrado va a la **papelera de la app por 30 días**, recuperable desde el detalle, y el aviso
    trae «Deshacer».
  - Alternativa: la elección **no borra nada**; solo decide qué usan la lectura, el chat y la
    exportación, y liberar espacio queda como acción aparte.
- **D. Bajar todo de páginas y publicaciones.**
  - *(Recomendado)* **Todo adentro del mismo elemento**, en su formato original y ordenado:
    - Qué se baja: las imágenes del artículo (también las de carga diferida y SVG), los **archivos
      enlazados desde el contenido** (PDF, EPUB, DOCX, MP3, MP4…), los videos y audios incrustados,
      y todas las fotos de un carrusel.
    - Los **.zip se descomprimen** solos, con las protecciones de la bóveda contra rutas hostiles y
      archivos inflados.
    - El elemento muestra una sección **«Contenido»**, agrupada por tipo (documentos, audios, videos,
      imágenes), y cada archivo trae **su propio texto**: lo extraído de un libro, la transcripción de
      un audio o video, el texto leído de una imagen.
    - **Límites**: solo lo enlazado desde el cuerpo del artículo (no el menú ni el pie); nada de la
      red local; **un tope por elemento** (ver E) y siempre según el espacio libre; de a un archivo
      por servidor, respetando cuando el servidor pide esperar.
    - Solo lo que la página ofrece públicamente: nada detrás de un muro de pago ni con protección
      anticopia.
  - Alternativa: **cada archivo como un elemento propio**, vinculado a la página. Reusa más de lo
    que hay, pero llena la Biblioteca de elementos sueltos.
- **E. El tope por elemento** (para D).
  - *(Recomendado)* **500 MB**, cambiable en Ajustes; si una página ofrece más, baja lo que entra
    —primero documentos, después audios, imágenes y por último videos— y te dice qué quedó afuera,
    con «Bajar el resto».
  - Alternativas: 200 MB, o sin tope pero preguntando antes de pasar de 500 MB.

## Orden de trabajo

1. Sin esperar: el Markdown crudo, el ✨ de tarjetas por partes, el chat (streaming, tope, pausa
   de la cola, precarga, contexto, los dos errores) y la RAM (miniaturas, listas livianas, liberar
   modelos). Con pruebas, commit y push de cada uno.
2. Repasar con IA (decisión A).
3. Cuadernos con IA (decisión B).
4. La Bandeja de texto y las tres opciones de los libros (decisión C).
5. Bajar todo (decisiones D y E): primero los archivos enlazados y los .zip, después las imágenes
   y los videos, al final los carruseles.
6. La guía de uso, la decisión de arquitectura de cada parte, y la prueba en tu teléfono: medir el
   chat (primera palabra, palabras por segundo, GPU o CPU) y la RAM antes y después.
