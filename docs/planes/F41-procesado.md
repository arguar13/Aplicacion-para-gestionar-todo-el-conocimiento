# F41 — «Procesado»: la información pura que elegís al triar

> **Estado: CONSTRUIDO** (2026-10-28), decisión 87 en `docs/arquitectura.md`. Aprobado en su
> segunda versión el 2026-10-27 («Aprobado, y agregá más agentes para avanzar más rápido» en el
> chat).
>
> La primera versión, aprobada el mismo día, entendía «Procesado» como una segunda Biblioteca con
> lo triado y lo descartado. El dueño la corrigió antes de que se construyera nada: «tirar» era
> «triar». Procesado no junta fuentes, junta **la información que el dueño saca de cada una**.
>
> Pedido del dueño (2026-10-27), en el chat:
> - *"En la pestaña Organizar, vamos a crear otra interfaz, debajo de la Bandeja y arriba de la
>   Línea de tiempo, que sea igual a la Biblioteca"* → nombre: **«Procesado»**.
> - *"Que ahí vaya todo lo triado y también las notas que extraigo o el texto extraído o el
>   resumen o síntesis (palabras clave no) según lo que yo elija al momento de triar, que ahí no
>   vaya audios ni videos ni referencias bibliográficas porque para eso está la Biblioteca, aquí
>   va a ir información pura, y dentro de cada archivo va a haber un enlace que me va a redirigir
>   al documento respectivo de la Biblioteca por si quiero consultar la info original"*.
> - *"Que los cuadernos de la pestaña Organizar se hagan únicamente con los documentos
>   Procesados"*.
> - *"Que dentro de cada archivo procesado vaya también el texto que manualmente yo seleccione
>   para cortar del original … cuando voy a triar un determinado archivo (cada documento o video o
>   audio o libro o lo que sea que sea nuevo en Biblioteca debe aparecer ahí) además de las
>   opciones que ya trae, me deje extraer manualmente ciertas partes de un libro o de un texto
>   para mandarla a su respectivo documento de Procesado"*.
> - *"Que haya una opción de «Volver a triar», por si ya trié algo y quiero agregarle algo más o
>   actualizar algo que ya había procesado … y se agregue o actualice o reemplace en el documento
>   procesado … al volver a triar me debería aparecer todos los documentos que existen en la
>   Biblioteca así elijo cuál triar"*.
> - *"Que sea elegante la sección de triado, interactiva y versátil"*.
> - *"Y el Atlas, la Línea de tiempo y el Mapa, que se hagan en base a los archivos que ya se
>   procesaron, no con la Biblioteca original"*.
> - *"Que en la Bandeja haya también una opción para pasar toda la información sin modificar a la
>   pestaña Procesado … en ese caso solo guardaríamos todo el texto original con el enlace a su
>   respectivo documento original ubicado en la Biblioteca, nada de audios ni videos ni
>   referencias"*.
>
> Respuestas del dueño a las preguntas previas:
> - El documento procesado es una **copia propia y editable**. Cambia solo al volver a triar.
> - Los **Cuadernos que ya existen se vacían**: de acá en más se arman solo con Procesado.
> - Lo nuevo **entra a la Bandeja apenas se guarda**, aunque todavía no tenga texto.
> - Lo **descartado queda solo en la Biblioteca**, como hoy.
> - **Atlas, Línea de tiempo y Mapa salen del texto procesado**: la IA organiza cada documento
>   procesado (temas, vínculos, fechas) con el texto que se eligió, no la fuente.
> - Lo **ya organizado en la Biblioteca no se pasa**: las tres pantallas **empiezan de cero** y se
>   llenan con lo que se procesa. Lo viejo no se borra (sigue en la fuente); solo deja de
>   alimentarlas.
>
> Y un principio que el dueño fijó después: *"Recordá que de la Biblioteca nada se borra, debe
> permanecer siempre como una base de datos de consulta, para eso está lo procesado"*.
>
> **Ajuste del dueño, con el paso 1 ya construido** (2026-10-27):
> - *"Cuando se trate de documento de texto o una página web, me gustaría que además de texto
>   también pudiera dejar elegir que pase también el documento original o página original"* →
>   **una copia propia del archivo** (respuesta a la pregunta: no verlo desde la Biblioteca, sino
>   copiarlo).
> - *"En el caso de texto yo podría elegir resumen, síntesis o palabras claves o que pasen los tres
>   o lo que yo elija"* → las **palabras clave entran**, y se ven **de las dos formas**: la lista
>   compacta arriba y, plegables, las oraciones con la clave marcada.
> - *"En el caso de resumen o síntesis … en el caso de conservar el documento original, que también
>   se marquen en el documento original en Procesado"* → la copia del original muestra marcado lo
>   que se eligió.
> - Y el Atlas va **arriba** de la Línea de tiempo en «Organizar».
> - *"Si yo no hiciera un resumen en los documentos antes de procesar, que una vez que los procese
>   y me quede con el documento original o todo el texto extraído, que también me dejara hacer un
>   resumen ahí, independientemente de si ya lo hice o no antes de procesar, así no dependa tanto
>   del archivo original"* → el documento procesado **se estudia solo** (decisión I).
>
> **Segundo ajuste del dueño, con los pasos 1 a 3 construidos** (2026-10-28), con cuatro capturas
> del detalle de un video de la Biblioteca marcadas en naranja:
> - *"Cuando entro a un elemento desde la sección de Biblioteca, quiero que todo lo que te marque
>   … desaparezca y pase a formar parte de cada elemento procesado. Porque se supone que de ahí lo
>   voy a estudiar"* → lo marcado es: **«Extraer resumen», «Extraer síntesis» y «Extraer palabras
>   clave»** de la tarjeta de estudiar, el mosaico **«Resumir»** del panel de la fuente, el
>   **Mapa** y las **Tarjetas de repaso**. Salen del detalle de la fuente y van al documento
>   procesado (decisión K).
> - *"Que en elementos procesados yo pueda guardar y conservar las imágenes y que me deje elegir
>   qué imágenes conservar … ya sea porque el documento original sea una imagen, una página o una
>   publicación … que yo pueda elegir si conservo todas o si conservo algunas o cuáles"* → una
>   sección **Imágenes**, con todas, ninguna o las que se elijan, una por una (decisión L).
> - Con otras cuatro capturas: *"Todos los botones que te marco con sus respectivas funciones
>   quitamos de ahí y ponlos directamente en los elementos ya procesados, para más coherencia"* →
>   también salen de la fuente **«Organizar con IA»** y **«Buscar fechas con IA»** (de «Más
>   acciones»), el panel **«La IA organizó esto»** (con «Para revisar», «Deshacer todo» y
>   «Revisar con otro modelo»), **«Borrar archivo, quedarme con el texto»** y, arriba, **✨
>   «Generar nota derivada»** y **«Generar quiz»** (decisión K).

## Lo que hay hoy

- La **Bandeja** muestra de a una las fuentes que ya tienen texto. Cada una se resuelve con
  «Triado», «Descartar», «Extraer nota» o «Vincular a nota viva». Para libros y documentos,
  «Triado» pregunta qué se queda: texto y libro, solo el texto, o solo el libro (F30).
- **«Extraer nota»** crea notas atómicas sueltas en la Biblioteca.
- Los **derivados** (F16, decisión 49) son notas que nacen nuevas, ancladas a su fuente, sin
  tocar el original. Esa es la base de un documento procesado.
- Ya existen **resumen, síntesis y palabras clave** de cada texto (F36, F39), los **resaltados a
  mano** con su barrita en las cuatro superficies (F38) y las **notas de bloques** editables (F26).
- Los **Cuadernos** (F16) juntan elementos de la Biblioteca, a mano o por consulta, y acotan el
  chat a ellos.

## El principio: la Biblioteca es la base de consulta, Procesado es lo trabajado

**De la Biblioteca nada se borra.** Cada fuente queda siempre entera: su archivo, su texto, sus
datos y su ficha bibliográfica. Triar, volver a triar o editar un documento procesado **nunca**
toca la fuente. Procesado es una copia aparte, y su enlace vuelve siempre al original intacto.

## Qué se construye

### 1. El documento procesado

- **Uno por fuente.** Es una copia propia, editable, que guarda **texto**, y, si lo elegís, la
  copia del documento o la página original. Nunca audio, video ni la ficha bibliográfica.
- **Tiene secciones**, cada una con su origen:
  - **Texto**: el texto extraído entero, o la transcripción.
  - **Resumen** y **Síntesis**: las oraciones elegidas, en el orden del texto.
  - **Notas**: lo que antes era «Extraer nota».
  - **Fragmentos**: los pasajes que cortaste a mano, cada uno con su ancla en el original.
  - **Palabras clave** (ajuste del dueño): la lista compacta, en el orden del texto, y debajo,
    plegables, las oraciones con su clave marcada. Cada una lleva a su lugar.
  - **Original** (ajuste del dueño), solo para documentos de texto —PDF, Word, EPUB, texto— y
    páginas web: **una copia propia del archivo** o de la página guardada, que se abre en el
    mismo visor de siempre. Sobre esa copia se ve marcado lo que se eligió: el resumen, la
    síntesis y las palabras clave, con los colores de estudiar, y los fragmentos.
- **Un enlace «Ver el original en la Biblioteca»** lleva a la fuente. Cada fragmento lleva además
  «Abrir en el original», justo en su lugar, por el mismo camino de las tarjetas y las citas.
- **Es un elemento de la bóveda**, así que viaja en la papelera, la copia y la unión de bóvedas, y
  la búsqueda y el chat lo leen.
- **No aparece en la Biblioteca:** vive en Procesado.

### 2. La pantalla «Procesado», en Organizar

- El orden queda **Bandeja · Procesado · Atlas · Línea de tiempo · Mapa · Cuadernos**, con su
  ícono y su línea: *«La información que sacaste de cada fuente»*.
- Se ve como la Biblioteca y reusa sus piezas: buscador, filtros (tema, tipo de fuente de origen,
  qué partes tiene), orden y selección múltiple. Cada fila tiene:
  - título e ícono del origen;
  - chips con las partes que tiene: Texto · Resumen · Síntesis · Notas · Fragmentos;
  - cuándo se actualizó.
- **El documento abierto** muestra las secciones plegables, cada una editable, con el enlace al
  original arriba y «Volver a triar» a mano.
- **Vacío:** *«Todavía no procesaste nada. Triá una fuente en la Bandeja.»* Si hay fuentes que se
  triaron antes de que existiera Procesado, ofrece **«Volver a triar»** para pasarlas.

### 3. La Bandeja: triar es elegir qué va a Procesado

- **Entra todo lo nuevo de la Biblioteca apenas se guarda**: documentos, libros, páginas, audios,
  videos, fotos.
  - Lo que todavía no tiene texto muestra *«Transcribiendo…»* o *«Leyendo la foto…»*. Las opciones
    de texto se habilitan solas cuando llega, y «Descartar» se puede de entrada.
  - Una referencia bibliográfica sin texto no entra: no tiene información que procesar.
- **«Triado» abre la hoja «¿Qué va a Procesado?»:**
  - **Texto extraído**, **Resumen**, **Síntesis**, **Palabras clave**: se prende cada uno, en
    cualquier combinación.
  - **El original** (documentos de texto y páginas web): se prende aparte, y avisa cuánto ocupa la
    copia. Si todavía no hay resumen o
    síntesis, ofrece **«Resumir con <modelo>»** o **«Elegir a mano»**, como la tarjeta de estudiar.
  - **Notas**: «Extraer nota», de siempre, ahora cae en la sección Notas del documento procesado.
  - **Fragmentos a mano**: **«Cortar del original»** abre el texto en modo cortar. Seleccionás
    pasajes con la barrita de siempre, con la acción **«A Procesado»**. Cada corte se ve marcado
    en el texto y en una lista viva abajo, donde se puede quitar.
  - **Salen de la Bandeja las opciones de F30** «Solo el texto» y «Solo el libro». Mandaban el
    archivo o el texto de la fuente a la papelera, y eso contradice el principio. Triar ya no
    suelta nada de la fuente. Lo que ya se soltó así sigue en la papelera de la app, recuperable
    como siempre.
  - **«Listo»** arma el documento procesado y la fuente queda triada, con «Deshacer».
- **«Pasar todo sin modificar»:** un toque, sin abrir la hoja. El documento procesado guarda el
  **texto original entero**, sin resumen, síntesis ni notas, con su enlace a la fuente. Nunca lleva
  audio, video ni la ficha bibliográfica. Se puede completar después con «Volver a triar».
- **Elegante, interactiva y versátil:**
  - la tarjeta de siempre con sus gestos;
  - una hoja con vista previa en vivo de lo que va a quedar, con cuántas oraciones y palabras
    tiene cada parte;
  - funciona con el teclado en la computadora;
  - respeta «sin animaciones».
- **Descartar** sigue igual: queda solo en la Biblioteca.

### 4. «Volver a triar»

- **Está arriba en la Bandeja, siempre**, y también en el documento procesado y en el detalle de
  cada fuente.
- **Desde la Bandeja abre un selector con todos los documentos de la Biblioteca**, con buscador y
  filtros. Lo ya procesado se marca con un chip.
- **Al elegir uno, se abre la misma hoja «¿Qué va a Procesado?»** con lo que el documento ya
  tiene. Por cada parte se elige:
  - **Agregar**: suma lo nuevo, por ejemplo más fragmentos o más notas, sin repetir lo que ya
    está.
  - **Actualizar**: trae la versión de ahora del resumen o la síntesis, y conserva lo que editaste
    a mano donde no choca.
  - **Reemplazar**: pisa la parte entera.
  - **Quitar**: saca la parte.

  Siempre con vista previa y «Deshacer».

### 5. Los Cuadernos, solo con Procesado

- **Los cuadernos que ya existen se vacían** al actualizar la app. Conservan su nombre y su modo,
  y un aviso en cada uno explica por qué y cómo volver a llenarlo.
- **«Agregar»**, **«Por consulta»**, **«Crear con IA»** y **«Sugeridos»** trabajan solo sobre
  documentos procesados.
- **El chat acotado a un cuaderno lee solo el texto procesado.**

### 6. Atlas, Línea de tiempo y Mapa, con lo procesado

- **La IA organiza los documentos procesados, no las fuentes.**
  - Al triar o volver a triar, el documento entra a la cola de «Organizar con IA» con los mismos
    interruptores de siempre: temas, vínculos entre procesados y fechas para la línea de tiempo.
  - Lo hace solo con el texto que elegiste.
- **Las fuentes de la Biblioteca ya no se organizan solas** al guardarse: la Biblioteca queda como
  consulta pura. Lo que ya tenían (temas, vínculos, fechas) **no se borra**: sigue a la vista en el
  detalle de la fuente, pero no alimenta las tres pantallas.
- **El Atlas, el Mapa, el grafo local y la Línea de tiempo leen solo documentos procesados.**
  - Los filtros Todo · Tema · Documento de la línea pasan a ser de procesados.
  - Los accesos desde el detalle abren el documento procesado de esa fuente, si existe.
  - «Organizar con IA» y «Buscar fechas con IA» trabajan sobre procesados.
- **Empiezan de cero**, como elegiste. Cada pantalla vacía explica que se llena al triar, con un
  botón a la Bandeja.

## Decisiones (se pueden cambiar mientras no se llegue a su paso)

- **A. El procesado es un elemento nuevo de la bóveda, derivado de su fuente**, como los de F16.
  No es una tabla aparte sin papelera ni copia. Así hereda la búsqueda, el chat, la papelera, la
  copia y la unión de bóvedas sin rehacerlos. **Uno por fuente**, con una restricción en la base.
- **B. Cada sección guarda su origen y su ancla.** Eso es lo que permite elegir entre Agregar,
  Actualizar y Reemplazar sin adivinar.
  - Cómo se guarda un texto enorme, como un libro entero en «Texto», se decide en el paso 1
    midiendo.
  - Ningún libro puede trabar la app: es la lección del arreglo de los libros largos.
- **C. «Extraer nota» deja de crear notas sueltas en la Biblioteca:** las notas van a su documento
  procesado. Las que ya existen quedan donde están.
- **D. Lo triado antes de F41 no se procesa solo:** el vacío de Procesado ofrece «Volver a triar».
  Inventar qué partes querías sería decidir por vos.
- **E. Una referencia bibliográfica entra a la Bandeja solo si trae texto**, por ejemplo un PDF
  adjunto.
- **F. Temas, vínculos y fechas son del documento procesado.** Son los mismos datos y las mismas
  tablas de hoy, colgados del documento procesado en vez de la fuente. Por eso la papelera, la
  copia, la unión de bóvedas y el deshacer de pasadas siguen sirviendo sin rehacerse. Lo de las
  fuentes queda guardado y fuera de las tres pantallas.
- **H. El original en Procesado es una copia propia del archivo** (ajuste del dueño). Ocupa su
  espacio y viaja con el documento procesado en la papelera, la copia y la unión de bóvedas. Como
  el texto de la copia es el mismo, las marcas de resumen, síntesis y palabras clave usan las
  mismas posiciones. Soltar el archivo de la fuente a mano no toca la copia, y al revés.
- **I. El documento procesado se estudia solo** (ajuste del dueño). Dentro de él, «Resumir»,
  «Sintetizar» y «Palabras clave» trabajan sobre su propio texto (la sección Texto o la copia del
  original), con la misma tarjeta de estudiar: «Resumir con <modelo>» o «Elegir a mano». No hace
  falta haber estudiado la fuente antes. Lo que se hace ahí es del procesado: cuenta como propio,
  así que «Actualizar» desde la fuente no lo pisa (solo «Reemplazar»), y se marca sobre la copia
  del original igual que lo traído de la fuente.
- **J. «Extraer como nota» de una fuente va siempre a su documento procesado**, desde donde sea:
  la Bandeja, el detalle, el modo lectura o cualquier visor (ajuste del dueño: «lo más profesional
  y coherente»). Es la decisión C llevada a todos lados: un mismo gesto no puede dejar la nota en
  dos lugares según la pantalla.
  - **Si la fuente todavía no tiene documento procesado, se crea en ese momento con esa sola
    nota**, sin triar la fuente. Extraer es un pedido explícito de la persona, así que no se
    inventa nada (decisión D). Y la fuente sigue en la Bandeja como estaba: triar sigue siendo
    elegir qué más va, y la hoja muestra las notas que ya tiene, sin pisarlas.
  - El aviso dice «Nota guardada en Procesado» con «Ver» y «Deshacer». Deshacer saca solo esa
    nota, y el documento, si se había creado para ella.
  - Lo que no es una fuente no cambia. Una nota propia sigue sacando notas sueltas vinculadas,
    porque no tiene documento procesado. Dentro de un documento procesado, lo extraído va a sus
    propias notas (decisión I). Una fuente en la papelera no acepta notas: lo dice y ofrece
    restaurarla.
- **K. La fuente queda de consulta; se estudia en Procesado** (segundo ajuste del dueño). El
  detalle de una fuente deja de mostrar lo que es estudiarla: «Extraer resumen», «Extraer
  síntesis» y «Extraer palabras clave», el mosaico «Resumir», el Mapa y las Tarjetas de repaso.
  Todo eso vive en su documento procesado, que ya se estudia solo (decisión I).
  - **También salen de la fuente** (segunda tanda de capturas): «Organizar con IA» y «Buscar
    fechas con IA» de «Más acciones»; el panel «La IA organizó esto» con «Para revisar», «Ver»,
    «Deshacer todo» y «Revisar con otro modelo»; «Borrar archivo, quedarme con el texto»; y en
    la barra de arriba ✨ «Generar nota derivada» (F16) y «Generar quiz». Todos van al documento
    procesado con su misma función, sobre lo procesado:
    - organizar y buscar fechas trabajan el texto procesado (paso 6), y su panel muestra lo que
      la IA hizo con el documento procesado;
    - la nota derivada y el quiz salen del texto procesado;
    - «Borrar archivo, quedarme con el texto» pasa a ser **«Borrar la copia del original,
      quedarme con el texto»**: libera el espacio de la copia (decisión H) y nunca toca el
      archivo de la fuente, que en la Biblioteca no se borra (decisión G).
  - **Lo que queda en la fuente**: el original y su texto («Extraer transcripción»), escuchar,
    «Leer» y «Copiar», «Volver a extraer el texto», «Quitar marcas de tiempo», los resaltados a
    mano, «Relacionado», exportar, la papelera, y la tarjeta de estudiar con Resumir · Sintetizar
    · Palabras clave marcando el original. Eso último hace falta porque es de donde la hoja de
    triar trae el resumen, la síntesis y las palabras clave (paso 3).
  - **Lo que la IA ya organizó en una fuente no se borra** (temas, vínculos, tarjetas, fechas,
    sugerencias para revisar): sigue guardado, pero deja de verse en la fuente y no alimenta
    Atlas, Mapa ni Línea de tiempo (decisión F).
  - Una nota propia no cambia: sigue con su ✨, su quiz y su panel, porque no es una fuente.
  - **El documento procesado suma su Mapa** (el grafo local de sus vínculos entre procesados,
    paso 6) **y sus Tarjetas de repaso**, hechas con IA o a mano **de su propio texto**.
  - **Nada se borra.** Las tarjetas que ya tiene una fuente siguen en Repasar, con su historial,
    y se ven en su documento procesado, en un grupo «De la fuente», plegado. Para verlas no hace
    falta moverlas: su «Abrir en el original» sigue llevando al pasaje de la fuente.
  - **Sin documento procesado**, el detalle de la fuente lo dice en una línea: «Para estudiarlo,
    triálo», con el botón que abre la hoja.
- **L. Las imágenes van a Procesado elegidas una por una** (segundo ajuste del dueño). Una sección
  nueva, **Imágenes**, para una fuente que es una imagen o que trae imágenes: una página web
  guardada o una publicación.
  - En la hoja de triar se ven en una grilla, con «Todas», «Ninguna» y la elección de cada una
    tocándola. Con muchas, se cargan de a tandas y en miniatura.
  - Cada imagen elegida es **una copia propia**, como el original (decisión H): ocupa su espacio,
    la hoja dice cuánto, y viaja con el documento en la papelera, la copia y la unión de bóvedas.
  - En el documento procesado, una galería: se abre a pantalla completa, se quita una con
    «Deshacer» y se suman más con «Volver a triar».
  - Las imágenes de dentro de un PDF, un Word o un EPUB no entran en este ajuste.
- **G. Triar nunca borra ni suelta nada de la fuente** (el principio de arriba). La hoja de F30
  sale de la Bandeja. Cualquier otro camino que hoy suelte el archivo o el texto de una fuente se
  revisa en el paso 3, y queda solo si lo pide el dueño a mano y de a uno.

## Pasos (cada uno, su commit y su push)

1. **Los datos.**
   - El documento procesado: un tipo nuevo, sus secciones con origen y ancla, el enlace a la
     fuente y la restricción de uno por fuente, con su versión de esquema.
   - Los censos de papelera, copia y unión de bóvedas.
   - El caso de uso «procesar», con agregar, actualizar, reemplazar y quitar por parte.
   - Fuera de la Biblioteca, dentro de la búsqueda y el chat.
   - Todo probado aparte, con mutaciones.
1b. **Los datos del ajuste del dueño** (esquema v46):
   - la sección Palabras clave y la copia del original, con sus marcas;
   - estudiar el procesado solo (decisión I): resumen, síntesis y palabras clave de su propio texto;
   - sus censos de papelera, copia y unión de bóvedas;
   - y, en la misma versión de esquema, el vaciado de los cuadernos del paso 5, con su marca.
2. **La pantalla Procesado y el documento:**
   - el destino entre Bandeja y Atlas;
   - la lista como la Biblioteca;
   - el documento con sus secciones editables y el enlace al original;
   - el vacío.
3. **La Bandeja nueva:**
   - todo lo nuevo entra, esperando su texto;
   - la hoja «¿Qué va a Procesado?», con «Extraer nota» y «Cortar del original»;
   - la vista previa en vivo.
4. **«Volver a triar»:** el selector con toda la Biblioteca y la misma hoja con agregar,
   actualizar, reemplazar y quitar por parte, desde la Bandeja, el documento procesado y el
   detalle.
5. **Los Cuadernos solo con Procesado:** vaciar los que existen con su aviso, el selector, «Por
   consulta», «Crear con IA», «Sugeridos» y el chat acotado.
6. **Organizar lo procesado:**
   - la cola de la IA sobre documentos procesados, no sobre fuentes;
   - Atlas, Mapa, grafo local y Línea de tiempo leen solo procesados, empezando de cero;
   - los accesos del detalle y los vacíos.
7. **Las imágenes en Procesado** (decisión L), después del 1b y del 4:
   - los datos, en un esquema nuevo, con sus censos de papelera, copia y unión de bóvedas;
   - la grilla de la hoja y la galería del documento.
8. **La fuente de consulta** (decisión K), después de los pasos 5 y 6:
   - lo que sale del detalle de la fuente;
   - el Mapa y las Tarjetas de repaso del documento procesado, con «De la fuente».
9. **Cierre:**
   - la GUÍA, la decisión en `docs/arquitectura.md`, CONTEXTO y el «Avance»;
   - la suite entera y `verify_commit`;
   - la APK al teléfono si la pedís.

Una vez que el paso 1 esté en main, los pasos 1b, 2, 3, 5 y 6 van **en paralelo**, cada uno con su
agente. Los pasos 2, 3 y 5 suman lo del 1b cuando entre. El 4 sigue al 3. El 7 sigue al 1b y al 4, y el 8
sigue al 5 y al 6.

## Avance

### Paso 1 (hecho): los datos, esquema v45

- **El documento procesado es un elemento de la bóveda** (decisión A): una fila de `item` con su
  `note` de un tipo nuevo, `NoteKind.processed`, y su fila en `processed_documents` con el enlace
  a la fuente (`source_item_id`, **único**: uno por fuente lo garantiza la base) y el tipo de la
  fuente. No tiene formas, ni archivo, ni ficha: solo texto. El tipo se pone al nacer y no cambia
  nunca (`KnowledgeEntryWriter.setNoteKind` lo rechaza en los dos sentidos).
  - **Su id sale de la fuente** (`processedDocumentIdFor`, un UUID v5): dos dispositivos que
    procesan la misma fuente llegan al mismo elemento, y la unión de bóvedas lo junta en vez de
    chocar con la restricción.
  - **De la Biblioteca nada se borra**: si alguien vacía la papelera con la fuente adentro, el
    procesado queda con su texto y su enlace pasa a `null`. Una prueba fija que procesar —crear,
    agregar, actualizar, reemplazar, quitar, editar, deshacer— no cambia ninguna fila de la fuente
    (elemento, fuente, formas, marcas, versiones, chunks, temas, propiedades).
- **Sus secciones son partes con origen y ancla** (decisión B, `processed_parts`): Texto
  (páginas), Resumen y Síntesis (oraciones en el orden del texto), Notas y Fragmentos. Cada parte
  dice si es copiada de la fuente o escrita por la persona, si se editó, y dónde estaba en el
  original (forma + posiciones del texto entero, como `study_marks`/`dated_events`). Si la forma de
  la fuente se va, la parte conserva su texto y sus posiciones, y pierde solo el enlace.
- **Cómo se guarda un libro entero** (medido con 3 millones de caracteres, flutter test en la PC,
  la base en su propio hilo como en la app; el teléfono es varias veces más lento):

  | guardado          | guardar | corregir 1 letra | leer 1 página | buscar |
  |-------------------|--------:|-----------------:|--------------:|-------:|
  | una sola fila     |  170 ms |           280 ms |         50 ms |   2 ms |
  | páginas de 2.000  |  340 ms |             8 ms |          9 ms |   3 ms |
  | páginas de 8.000  |  151 ms |             8 ms |          4 ms |   2 ms |
  | páginas de 32.000 |  124 ms |            11 ms |          2 ms |   2 ms |

  Se eligieron **páginas de 8.000** (`kProcessedTextPageChars`): un libro son 390 filas, guardarlo
  cuesta lo mismo que una fila y corregir o leer cuesta lo que mide una página. Paginar y comparar
  un texto largo corre en otro hilo (`compute`, desde 60.000 caracteres, el umbral de `1d4cf338`);
  la lista y el documento abierto nunca traen el texto (las partes se piden por sección y de a
  tramos). Pruebas de crecimiento: la fila de la lista y una página cuestan lo mismo con un libro
  cuatro veces más largo.
- **El caso de uso «procesar»** (`ProcessSourceUseCase`): crear con las partes elegidas, «pasar
  todo sin modificar» (solo el texto entero) y, por sección, agregar (sin repetir: el mismo tramo o
  el mismo texto), actualizar, reemplazar y quitar, con vista previa (partes y palabras) y
  «Deshacer». **La regla de «Actualizar»**: lo editado a mano se queda siempre; lo copiado sin
  editar se queda si la fuente lo sigue trayendo igual (la misma parte, sin reescribir nada) y si
  no se va; de la versión de ahora entra lo demás, salvo lo que se superpone con algo editado —ahí
  gana la edición—. En el texto, lo de la fuente se pagina alrededor de las páginas editadas, así
  que «Actualizar» sobre un texto que no cambió no cambia nada. Procesar uno que está en la
  papelera lo saca de ahí con lo que tenía; deshacer lo devuelve.
- **Fuera de la Biblioteca, dentro de la búsqueda y el chat**: la consulta de la Biblioteca deja
  afuera lo procesado (`notProcessedSql`); la papelera lo muestra. Las partes tienen su propio
  índice de texto (`processed_part_search`, por parte), que leen la lista de Procesado y el chat;
  sin alcance, el chat no repite una página copiada tal cual de una fuente que está a la vista.
  La salud de las notas no lo cuenta como semilla.
- **Los censos**: los conteos de todas las tablas como compuerta de la migración; la papelera del
  contenido guarda qué partes anclaban un texto soltado y se lo devuelve al recuperarlo
  (`content_trash.processed_parts`); al volver a extraer, el ancla se reubica por el pasaje que
  marcaba (con un solo buscador para todo el texto, `ExcerptLocator`); la unión de bóvedas suma
  documentos y partes sin repetir, con el texto uno solo, re-apunta el ancla a la forma que guardó
  ese texto y vuelve a enlazar una fuente que regresa; vista previa y resultado cuentan las partes,
  y las tablas nuevas están en «nunca se achica» y en las referencias rotas.
- **La API para los pasos que siguen**: `ProcessedRepository` (lista con `ProcessedQuery`,
  `matchingIds`, `watchDocument`, `watchForSource`, `watchParts` de a tramos, `partsOf`,
  `materialOf`, `editPart`/`removePart`/`restorePart`), `ProcessSourceUseCase` (`call`,
  `passUnchanged`, `preview`, `undo`) y sus providers en `processed_providers.dart`.
- **Fuera de la Bandeja por su tipo**: es una nota, no una fuente, así que no entra a la Bandeja,
  a su contador ni a «Por revisar», que miran solo fuentes. No hace falta ningún filtro aparte.
- Pruebas: 100 en `test/features/processed`, 6 de la unión, 5 de la migración, 1 del buscador de
  pasajes y los censos (columnas de la unión, cifras de la vista previa y del resultado, lecturas
  de `item`). Pasan 5.259 en `test/core`, bóveda, Biblioteca, cuadernos, chat, estudiar, línea de
  tiempo, Bandeja, procesado, papelera del contenido, transformación, salud, Atlas y enlaces.
  Mutación 76/77: la que sobrevive es equivalente —que el buscador arme el texto sin cortes de
  renglón una sola vez y no una por fragmento da el mismo resultado; solo cuesta menos—.

### Paso 1b (hecho): el ajuste del dueño en los datos, esquema v46

- **Palabras clave** (`ProcessedSection.keywords`, entre Síntesis y Notas): cada parte es una
  oración con sus palabras adentro (`ProcessedPart.spans`, guardadas en `processed_parts.spans`).
  Las oraciones son las que corta `splitStudySentences` y las palabras, las marcas `keyword` de
  la fuente (F36, F39, decisión 85), en las mismas posiciones. Con eso salen las dos vistas: la
  lista compacta (`part.keywords`, en el orden del texto) y la oración con su clave marcada.
  Agregar, actualizar, reemplazar y quitar siguen las reglas del resumen. «Actualizar» renueva
  una oración si cambiaron sus palabras.
- **La copia del original** (decisión H) es una **forma propia del procesado**: un `rendition`
  con su archivo, en `originales/<procesado>/original/`, y su fila en `processed_originals`.
  Se eligió así porque una forma ya la cuentan, sin tocarlos, `isFileReferenced`, la copia de la
  bóveda (la carpeta `originales/`), la unión (`OriginalFilesMerge`) y el borrado de verdad.
  - **Qué se copia:** solo documentos de texto (PDF, Word, EPUB, texto) y páginas web
    archivadas. `ProcessedSourceMaterial.original` dice si la fuente lo ofrece, cuánto ocupa y en
    qué visor se abre: `pdf`, `html` o `document`, que es el lector.
  - **Cómo se copia:** la copia la hace el sistema (`FileStore.copy`), sin pasar por la memoria
    ni por el hilo de la interfaz. Donde no hay disco se copia por partes de 1 MB. Si guardar no
    llega, la copia se borra.
  - **Cada pedido:** agregar copia, una sola vez. Reemplazar copia de nuevo. Actualizar vuelve a
    copiar solo si el archivo de la fuente es otro (otra ruta o tamaño: un original de la
    Biblioteca no se reescribe). Si es el mismo, solo anota con qué texto se corresponde.
  - **Lo que sale:** quitar o reemplazar mandan la copia de antes a la papelera del contenido
    del procesado, de donde se recupera, y deshacer la devuelve.
  - **Independencia:** soltar el archivo de la fuente no toca la copia, y al revés.
  - **Su id sale del procesado**, como el del procesado sale de su fuente. Así la unión de
    bóvedas no trae una segunda copia.
- **Lo elegido, marcado sobre la copia** (`watchOriginalMarks`): el resumen, la síntesis y las
  palabras clave son marcas de estudiar (`DocumentStudy`), y los fragmentos van aparte.
  - Todo va en las posiciones del texto de la fuente y con su `sourceKey`, el mismo de los
    overlays.
  - Solo se pinta mientras el texto de la fuente siga siendo el de la copia (`content_hash`). Si
    no, no se pinta nada, y tampoco lo que se editó.
- **El procesado se estudia solo** (decisión I).
  - **El texto:** su texto propio son las páginas de «Texto» o, sin ellas, con la copia del
    original, el texto de la fuente (`studyTextOf`). Cada parte sabe dónde está en él
    (`text_start`/`text_end`), y corregir una página corre lo que le sigue sin traer el libro.
  - **La máquina:** la de siempre (resumir con modelo, elegir a mano, el respaldo local de las
    palabras clave) corre sobre ese texto con la clave `procesado:<id>`. `KeyedStudyRepository`
    manda esa clave a `ProcessedStudyRepositoryImpl`, que guarda en el procesado (`studied` lo de
    la IA, `chosen` lo de la persona) y no en `study_marks` de la fuente.
  - **Lo propio:** lo estudiado ahí es propio. «Actualizar» desde la fuente no lo pisa, solo
    «Reemplazar». Si su página es la de la fuente, también lleva a la fuente (`sourceOffsetOf`) y
    se marca sobre la copia.
- **Los cuadernos se vacían** en la migración. De `notebook_item` sale todo lo que no es un
  procesado (al migrar no hay ninguno). El cuaderno que tenía algo queda marcado con
  `notebooks.emptied_for_processed_at`: el que tenía un elemento o el que era por consulta. Los
  cuadernos no viajan en la unión de bóvedas, así que una copia vieja no los vuelve a llenar.
- **Los censos:**
  - la migración es aditiva: rehace `processed_parts` con sus filas y su clave del índice, y el
    índice entero;
  - los conteos de todo lo demás son compuerta, y los de los cuadernos se comprueban contra lo
    que se sacó a propósito;
  - la unión suma `processed_originals`, con el lugar en el texto solo si el texto es el que
    entra;
  - la vista previa y el resultado cuentan la copia del original;
  - las tablas nuevas están en «nunca se achica» y en las referencias rotas.
- **En las pantallas de los pasos 2 y 3**, las palabras clave entran por los mismos `switch`
  exhaustivos: en la hoja «¿Qué va a Procesado?» se eligen enteras, como el resumen, con
  «Resumir con el modelo» o «Elegir a mano» mientras la fuente no tiene ninguna, y lo que trae
  la fuente se cuenta en palabras clave; en el documento abierto son una sección más, con su
  ícono (la llave de estudiar), sus oraciones y «Copiar». «Escuchar» no tiene capa propia
  para ellas —`ReadScope.keywords` lee las palabras sueltas, y acá cada parte es la oración
  entera—: se escuchan con el botón flotante.
- Pruebas: 63 nuevas —la copia del original 22, estudiar el procesado 13, palabras clave 7, la
  correspondencia entre el texto propio y el de la fuente 5, la migración a v46 6, copiar un
  archivo 3, la unión de bóvedas 3 y el planificador 4—. La suite amplia (núcleo, bóveda, Biblioteca, cuadernos, chat,
  estudiar, línea, Bandeja, Procesado, papelera, transformar, salud, Atlas, enlaces, visores y
  narración): 5.985 pruebas. Las pruebas de la hoja y de la Bandeja que contaban las secciones
  de la fuente o esperaban ver arriba lo que una sección más empuja hacia abajo dicen ahora lo
  que miran; dos que dependen del tiempo (la medición del modelo del chat y una de escala)
  fallaron con la máquina cargada y pasan solas.
  `flutter analyze`: 19, la línea base.
- Mutación 48/48: las que sobrevivieron la primera vez (borrar la copia si guardar falla,
  correr lo que sigue a una página corregida, buscar una palabra repetida después de la
  anterior, el avance del estudio, recuperar de la papelera sin pisar la copia de ahora y la
  vista previa del original) tienen ahora su prueba.

**Paso 3 (primera parte): lo que no depende del documento procesado.** La Bandeja quedó lista para
recibir la hoja «¿Qué va a Procesado?» cuando lleguen los datos del paso 1.

- **Todo lo nuevo entra apenas se guarda.** `InboxStatus.pending` pasa a ser `captured` o
  `processed`: lo que todavía se procesa ya espera. Un solo criterio, en `_isPending`, para el mazo,
  la lista, la insignia, el panel de salud y Filtros → «Por revisar»; `hasTextSql` dejó de decidir
  quién entra y ahora solo dice si el texto llegó.
- **Lo que espera su texto.** Un estado nuevo, `PendingText`, con cuatro valores: listo, llegando,
  falló y sin texto. Sale de dos datos que ya existían (si hay texto y en qué está el
  procesamiento), sin columnas nuevas. Lo leen la tarjeta (`watchPendingText`) y la lista
  (`PendingSource.text`).
  - La tarjeta muestra *«Transcribiendo…»*, *«Leyendo la foto…»* o *«Extrayendo el texto…»*, con la
    barra si se sabe cuánto va.
  - Si falló, muestra el motivo real y «Reintentar» o «Descargar el modelo», por el mismo camino
    que el panel de la fuente.
  - Si se procesó sin texto, lo dice y ofrece «Volver a extraer el texto» si el original se puede
    releer.
  - **`InboxActions`** decide en un solo lugar qué se puede hacer, para botones, gestos y teclas.
    «Descartar» se puede siempre. Triar, vincular y revisar sugerencias necesitan texto, y extraer
    necesita el del elemento. Mientras tanto quedan apagados, con su motivo, y se prenden solos, en
    vivo. `SwipeCard` no decide hacia un sentido sin pista.
- **El orden es el de llegada** (`createdAt`, con el `id` para desempatar), no `updatedAt`. Así la
  tarjeta que se mira mientras espera sigue arriba cuando le llega el texto.
- **Volver a la Bandeja** (`returnToInbox`) se usa para deshacer y para «Volver a la Bandeja».
  Devuelve la fuente al estado de espera que le toca ahora, según su procesamiento, y no a uno fijo:
  algo descartado mientras se transcribía pudo terminar antes del deshacer. `InboxStep` perdió
  `previousState`. «Volver a la Bandeja» se ofrece tenga texto o no (`InboxStanding.canReturn`),
  salvo en una referencia.
- **Decisión E.**
  - Una referencia sigue naciendo triada, porque no trae texto.
  - Cuando se le adjunta el archivo, el espejo la hace entrar a la Bandeja como recién guardada.
    `nextMirrorState` recibe el tipo anterior, y la regla aplica solo desde `triaged`.
- **Sale la hoja de F30** (`inbox_keep_sheet.dart`, sus 11 textos, `InboxStep.trashedContentIds` y
  la recuperación al deshacer). Triar ya no suelta nada. Lo ya soltado sigue en la papelera de la
  app, recuperable. «Borrar archivo…» y «Borrar el texto…» de la hoja «Más» quedan, porque son a
  mano y de a una fuente.
- **Auditoría del principio:** no queda ningún camino automático que suelte el archivo o el texto de
  una fuente. Quedan los explícitos, de a una fuente:
  - la hoja «Más»;
  - «Volver a extraer»;
  - fusionar un duplicado confirmado;
  - borrar y vaciar la papelera.

  Quedan además, a decidir por el dueño:
  - el barrido de los 30 días de lo ya soltado;
  - la unión de bóvedas, que replica en este dispositivo un archivo que la otra copia soltó a mano.
- **Para los pasos que siguen:** el criterio de la Bandeja es `kind == source`. Si el documento
  procesado del paso 1 fuera una fuente, tiene que quedar afuera de `_isPending`.

Verificación:

- `flutter analyze`: 19.
- 35 mutaciones, todas muertas. Tres se cuentan como muertas porque se colgaron: la de la tarjeta
  que no escucha los textos, que espera un evento que no llega, y dos del rótulo de la tarjeta, que
  fallan y dejan el temporizador de drift.
- Sin probar en el emulador ni en el teléfono.

### Paso 2: la pantalla Procesado y el documento

- **El destino**, en «Organizar», justo después de la Bandeja y arriba del Atlas: Bandeja · Procesado ·
  Atlas · Línea de tiempo · Mapa · Cuadernos. Ícono `summarize`, que no usa ningún otro destino, y su
  línea: *«La información que sacaste de cada fuente»*. La rama va **al final de `ShellBranch`**
  (`processed`), como la línea de tiempo, así que no corrió ningún índice. Con diez destinos el riel de
  escritorio no entraba en una ventana baja: ahora se desplaza (`scrollable`) en vez de desbordar.
- **La lista, como la Biblioteca.** Las piezas que la Biblioteca tenía privadas se mudaron a
  `list_controls.dart` y las usan las dos pantallas, sin copias: la búsqueda con el botón de filtros y su
  número, el marco del panel de filtros con «Limpiar filtros», el rótulo de cada sección, «Cargar más» y
  la barra del modo de selección.
  - Filtros por tema (el `SpaceFilterSection` de siempre), por el tipo de la fuente de origen y por las
    partes que tiene; orden por lo último trabajado, por cuándo se procesó o por título.
  - Cada fila (`ProcessedDocumentCard`): el ícono del origen, el título, los chips de las partes —para el
    lector de pantalla, en una sola frase— y «Actualizado el…». Con el lenguaje de una nota: lo procesado
    es lo que sacó la persona.
  - Selección de a varios: «Elegir temas» y «Eliminar», por el mismo camino que cualquier elemento
    (decisión A).
  - La lista es `processedDocumentsProvider(ProcessedQuery)` en tandas de 100: nunca trae el texto.
- **El documento abierto** (`RoutePaths.processedDocument(id)`, dibujado en la raíz como el detalle de un
  elemento):
  - arriba, su fuente: «Ver el original en la Biblioteca»; si la fuente está en la papelera lo dice y
    ofrece «Abrir la papelera»; si se borró de verdad, dice que el documento conserva lo que se sacó;
  - **sus secciones, recorridas genéricamente**: las que el documento tiene, en el orden de
    `ProcessedSection`, cada una plegable (`ProcessedSectionPanel`) con cuánto tiene y cuántas partes se
    editaron. Lo que cambia por sección —su ícono y su nombre, si arranca desplegada, qué se escucha, si
    se copia entera, cómo se ve el cuerpo— está en `switch` exhaustivos: sumar Palabras clave y Original
    es sumar sus casos. Lo elegido arranca desplegado; el texto, plegado si hay algo más. Plegada, una
    sección no pide nada a la base. Respeta «sin animaciones»;
  - cada parte (`ProcessedPartTile`) con «Editar» y «Quitar», los dos con «Deshacer»
    (`editPart`/`removePart`/`restorePart`), y la marca «Con cambios tuyos» o «Escrita por vos»;
  - **el texto, de a una página** (`ProcessedTextPages`): `processedPartsProvider` con un tramo de uno,
    con primera, anterior, «Página n de N» (que salta a una), siguiente, última y las flechas del
    teclado. El lector paginado de los visores no encaja: arma sus páginas partiendo el texto entero en
    memoria, que es lo que esto evita. Lo demás, de a tandas de 50;
  - cada fragmento con «Abrir en el original» a la vista, y lo demás con ancla en su menú, por el mismo
    camino de las tarjetas y las citas (`RoutePaths.reading` con el tramo). Sin fuente viva no aparece;
  - en la papelera se lee igual, lo dice y se restaura de un toque.
- **«Volver a triar»**: un solo punto, `retriageAction` en `retriage.dart`, que hoy devuelve `null`; el
  botón (`RetriageButton`) se ve **apagado, con «Volver a triar: próximamente»** en su ayuda, que el
  lector de pantalla anuncia. Apagado y no escondido: el plan lo promete ahí, esconderlo correría la
  pantalla cuando llegue, y un botón que hace como que anda enseña a desconfiar de los que sí andan. El
  paso 4 lo implementa en ese punto y todos se prenden solos.
- **Escuchar** (`processedReadableProvider`): el botón flotante lee el documento entero, sección por
  sección, como el detalle de un elemento, y empieza en la página que se mira (`startAt`). El resumen y
  la síntesis se escuchan también solos. Cada parte es su propio `sourceKey`, así que lo que suena se
  resalta en su lugar. Se arma fuera de la pantalla: las partes vienen de la base, en su hilo, y se
  parten en otro (`compute`) si son largas.
- **El vacío**: *«Todavía no procesaste nada. Triá una fuente en la Bandeja.»* con «Ir a la Bandeja».
  Si hay fuentes triadas (decisión D) lo dice y ofrece «Volver a triar», por el mismo punto.
  `EmptyStateView` sumó un segundo camino (`secondary`) y dejó de animar su entrada con «sin
  animaciones».
- **Abrir por id**: la ruta del detalle (`/library/:id`) es el despachador de todo lo que abre un
  elemento por su id —la búsqueda, las citas del chat, la papelera, el Mapa, la Línea—. Un `redirect`
  ahí (`processedDocumentRedirect`) manda un documento procesado, vivo o en la papelera, a su pantalla;
  si la base falla, sigue al detalle. Nadie más tiene que acordarse.
- **Preparado para la decisión I y el paso 1b**: la tarjeta de estudiar de siempre
  (`StudyDocumentCard`) está puesta en el documento (`ProcessedStudySlot`) y se muestra sola cuando
  `processedStudyTextProvider` dé el texto del procesado; hasta entonces devuelve `null`. Las acciones de
  cada sección (`_SectionActions`) son el lugar de sus atajos.

**Lo que faltaba del paso 2** —Palabras clave de las dos formas y el Original— entró con el 1b, en la
segunda tanda (más abajo). Conectar `processedStudyTextProvider` es «Resumir» en el documento: del
paso 8.

Verificación:

- `flutter analyze`: 19.
- Pruebas: 19 del documento abierto, 9 de la lista, 7 de abrir por id, 3 del vacío compartido, y las de
  navegación ajustadas (destinos, riel, ramas). Pasan 3.556 en `test/app`, `test/core/design`, procesado,
  Biblioteca, Mapa, Línea, Atlas, Bandeja, grafo, lectura, tarjetas, IA, captura, salud, relaciones,
  sugerencias, Explorador, cuadernos, papelera y narración.
- 34 mutaciones, todas muertas. La que primero sobrevivió —pedir tres páginas para mostrar una— se mató
  con una prueba que fija que se pide una sola.
- Sin probar en el emulador ni en el teléfono: el lector en voz alta con un motor de voz real, y un libro
  de verdad en el teléfono.

### Paso 2, segunda tanda (hecho): el Original, su conmutador y las palabras clave

Sobre el 1b. Para el paso 8: acá **no** se tocaron las acciones que salen de la fuente (decisión K);
abajo dice dónde engancharlas.

- **La copia del original en el documento** (decisión H).
  - Arriba, debajo de la fuente, su tarjeta (`ProcessedOriginalCard`): qué es (PDF, página web
    archivada o documento), cuánto ocupa, cuándo se copió y **«Ver el original»**. Es también el lugar
    de lo que se haga con la copia misma —«Borrar la copia del original», del 8—.
  - **«Ver el original»** (`RoutePaths.processedOriginal(id)`, en la raíz) abre la copia en el visor de
    siempre según `ProcessedOriginal.kind`: el de PDF, el de páginas o el lector. Encima, lo elegido:
    resumen, síntesis y palabras clave con los colores de estudiar, y los fragmentos con el de los
    cortes. Arriba, un interruptor por color.
  - **Cómo se pinta sin tocar la fuente.** El visor mira la copia por **su propia clave**,
    `procesado-original:<id>` (`processedOriginalStudyKeyFor`), como a cualquier texto. Esa clave tiene
    su repositorio en `KeyedStudyRepository`: `ProcessedOriginalStudyRepository` da lo elegido
    (`watchOriginalMarks`) como lo estudiado y **solo se lee**, así que cualquier escritura falla
    diciéndolo y nada cae en la fuente. Sus fragmentos salen de `processedOriginalCutsProvider`, que
    `watchProcessedCuts` usa para esa clave. `studyViewProvider` abre esa clave con todo a la vista
    (`kMarkedCopyStudyView`).
    - Se descartó sobreescribir `documentStudyProvider` en un `ProviderScope`: los providers que
      dependen de él (los de escuchar) piden `dependencies` y Riverpod lo frena. La clave propia es la
      costura que ya existía (decisión I) y no deja dos verdades.
  - **Si el texto de la fuente cambió** (`content_hash`), `watchOriginalMarks` no da nada: no se pinta y
    una línea lo dice. Un PDF o una página se ven igual. Un Word, un EPUB o un texto, que el lector
    muestra por su texto, ofrecen «Abrir con otra app».
  - **Para el 8**: la barrita de los visores sigue ofreciendo sus acciones sobre la copia, con
    `itemId` = el procesado y la clave de la copia. Resaltar ahí no tiene dónde guardarse (la clave no
    es una forma) y lo avisa; «Extraer nota», «Tarjeta» y «Línea de tiempo» quedan apuntando al
    procesado, como pide K: revisarlas cuando se muden. *(Resuelto en el paso 8: la copia es de
    solo lectura, y la barrita queda con Copiar, Escuchar y «Extraer como nota».)*
- **El conmutador «El original» en la hoja «¿Qué va a Procesado?»**, en «De la fuente».
  - Solo aparece si la fuente lo ofrece (`ProcessedSourceMaterial.original`: documentos de texto y
    páginas archivadas) o si el documento ya tiene la copia. Dice cuánto ocupa con `formatFileSize`.
  - Va aparte de las secciones, porque es un archivo y no partes: `ProcessedTriage.original` (un
    `ProcessedChange`) y `originalEdit`. «Listo» se prende con solo eso, y entra en «Va a quedar».
  - Con la copia ya hecha ofrece Actualizar, Reemplazar o Quitar, y prenderlo es Actualizar: Agregar
    no haría nada. La hoja lo sabe del documento (`summary.hasOriginal`), como sus cuentas por sección
    (paso 4), o de `showProcessedTriageSheet(originalExists:)`. Con el teclado, el número que sigue a
    las secciones.
  - «Listo» lo pasa: `ProcessedTriageDone` es ahora `(edits, original)`, y `TriageIntoProcessed` —al
    triar y al volver a triar (`retriage`)— lo manda a `ProcessSourceUseCase(…, original:)`. Es el único
    cambio en la Bandeja y en «Volver a triar».
- **Palabras clave, de las dos formas** (`ProcessedKeywordsView`).
  - Arriba, la lista compacta (`compactKeywords`): cada palabra una vez, sin distinguir mayúsculas,
    en el orden del texto. Tocarla la abre en su lugar de la fuente, si la oración no se editó.
  - Plegadas, las oraciones, cada una con su clave marcada en el rosa de estudiar. Eso lo hace
    `ReadAloudText`, que sumó capas fijas (`paints`). Una oración editada más corta no marca fuera de
    sí (`keywordSpansOf`).
- **«Original» en la lista**: es un chip más de la fila (`hasOriginal`) y un filtro más
  (`ProcessedQuery.withOriginal`), que vale como cualquiera de las partes.
- **Lo que queda para otros**: `ProcessedStudySlot` define su propio `processedStudyTextProvider`
  (el hueco del paso 2, que devuelve `null`) con el mismo nombre que el del 1b en
  `processed_providers.dart`. Conectar la tarjeta de estudiar del procesado es «Resumir» en el
  documento: del 8, que puede borrar el del hueco y usar el del 1b. *(Resuelto en el paso 8.)*

Verificación:

- `flutter analyze`: 19.
- Pruebas nuevas: 9 del original (`processed_original_screen_test`), 5 del conmutador en la hoja, 3 de
  las palabras clave, 1 del chip y el filtro, y 2 de triar y volver a triar con la copia. Pasan 3.381
  en `test/app`, `test/core/design`, procesado, Bandeja, estudiar, visores, Biblioteca, organizar,
  narración, lectura, tarjetas y línea de tiempo. Tras rebasar sobre el paso 4, pasan 2.085 en
  `test/app`, procesado, Bandeja, estudiar, visores, Biblioteca y organizar; la de escala del 1b
  (`process_source_scale_test`) falló con la máquina cargada y pasa sola.
- 28 mutaciones, todas muertas. La que primero sobrevivió —no marcar los fragmentos sobre la copia—
  tiene ahora su prueba en lo que se pinta, no en el provider.
- Sin probar en el emulador ni en el teléfono: el PDF de verdad (pdfrx no corre en las pruebas) y la
  página en el `WebView`.

**Paso 3 (el resto): triar es elegir qué va a Procesado.**

- **«Triado» abre la hoja «¿Qué va a Procesado?»** (`ProcessedTriageSheet`, en
  `processed/presentation/widgets/triage/`), sobre la tarjeta de siempre: por el botón, el gesto
  a la derecha y la flecha. Con «Listo», `TriageIntoProcessed` procesa y tría **las dos cosas o
  ninguna**: si el estado no se puede cambiar, el procesado se deshace. «Cancelar» o cerrar la hoja
  deja la fuente en la Bandeja.
  - **De la fuente**: el texto (o la transcripción), el resumen y la síntesis, cada uno con su
    interruptor, en cualquier combinación. Sin resumen o síntesis, la hoja muestra el mismo
    `StudySuggestion` de la tarjeta de estudiar y usa `applyStudySuggestion`: «Resumir con
    <modelo>» arranca el análisis, con la misma franja (`StudyProgressStrip`, que pasó a ser
    pública), y «Elegir a mano» abre el texto en modo elegir oraciones. Elegir cualquiera prende la
    sección. La hoja sostiene `studyViewProvider` mientras está abierta: si no, lo elegido a mano se
    soltaba antes de llegar al texto.
  - **Lo tuyo**: notas —escritas en un diálogo o extraídas del original— y fragmentos cortados, cada
    uno en su lista con «Quitar».
  - **Vista previa en vivo** por sección (`ProcessSourceUseCase.preview`), una por vez
    (`processedTriagePreviewProvider`): prender el resumen no vuelve a paginar el texto de un libro.
    Mientras la IA arma el resumen, la clave lleva una marca de sus oraciones y la vista previa se
    rehace con cada una. Al final, «Va a quedar» en chips; abajo, fijo, las palabras en total.
  - **Teclado**: 1–9 prenden las secciones de la fuente, C corta, N escribe una nota, Ctrl+Enter es
    «Listo», Escape cierra. Sin animaciones, la hoja aparece sin deslizarse. Con la letra al doble
    en 360 de ancho no se desborda: la vista previa va al final de la lista, y lo fijo es solo el
    total y los botones.
- **Decisión C**: mientras se corta, «Extraer como nota» de la barrita va a las notas del documento
  procesado y no crea nada en la Biblioteca. Lo resuelve `extractRangeAsNote` mismo, así que los
  cuatro visores lo hacen sin saber de Procesado. Fuera de la Bandeja quedaba la nota suelta de
  siempre; el dueño lo resolvió con la decisión J (ver más abajo).
- **«Cortar del original»** (`ProcessedCutScreen`): la fuente en su visor de siempre.
  - Se ve el PDF real o la página guardada (con «Ver el texto extraído» para pasar a su texto) o el
    lector de Word, EPUB y texto, que pagina un libro. Un audio, un video o una foto muestran su
    texto en ese mismo lector.
  - Declara de qué fuente se corta con un `ProviderScope` propio (`processedCutSourceProvider`).
    Solo adentro, la barrita (`HighlightToolbar.onToProcessed`) suma **«A Procesado»**, ancho y
    arriba de los colores.
  - Lo cortado se marca encima de todo, en durazno con la letra oscura. Va por `watchStudyPaints`
    (texto extraído, lector, PDF) y por las marcas de la página web: ningún visor cambió su manera
    de pintar.
  - Abajo, la lista viva con «Quitar» y «Listo». Lo cortado vive en `processedTriageProvider`, la
    misma hoja: volver no pierde nada.
  - «Extraer nota» de la tarjeta (gesto arriba, flecha arriba) abre la hoja directo ahí.
- **«Pasar todo sin modificar»**: un botón en la tarjeta y Shift+→, sin la hoja
  (`TriageIntoProcessed.passUnchanged`). Guarda el texto entero, con su enlace; nunca audio, video
  ni la ficha. `InboxActions.passUnchanged` lo prende solo con texto propio; si no, el botón dice
  por qué.
- **Deshacer**: `InboxStep.processUndo` guarda el comprobante del procesado. `InboxHistory` lo
  deshace primero; si falla, la fuente queda triada con su documento, sin contradecirse. Salió
  `InboxStepKind.extracted`, y entró `passedUnchanged`.
- **El contrato para «Volver a triar» (paso 4)**:
  - `showProcessedTriageSheet(context, sourceItemId:, onDone:, existing:, initial:, changes:,
    startCutting:)`;
  - `existing` es `Map<ProcessedSection, int>`, las partes que el documento ya tiene;
  - `initial` es `Map<ProcessedSection, SectionEdit>`, lo que la hoja trae pedido;
  - `onDone` recibe el `Map<ProcessedSection, SectionEdit>` armado y devuelve el `Failure` o
    `null`.
  - Con `changes` de más de un valor, cada sección que ya tiene partes muestra Agregar ·
    Actualizar · Reemplazar · Quitar; «Actualizar» solo donde la fuente tiene versión. Los pasajes
    que trae sin texto se leen de la fuente al abrir.
  - El modelo es `ProcessedTriage` (inmutable, `edits` es lo que va al caso de uso).
- **Para el paso 1b**: la hoja recorre las secciones de la fuente. Sumar Palabras clave y el
  Original es un caso más en cuatro `switch` sin `default`: `triageShapeOf` (las dos, `whole`),
  `triageSectionsOffered`, `triageSectionLabel`/`triageSectionIcon`/`triagePartsText` y
  `triageStudyKindOf` (las palabras clave, `StudyMarkKind.keyword`). Falta solo la línea del tamaño
  de la copia del original, debajo de su interruptor. `ProcessedTriage._editOf` las arma como
  cualquier sección entera.

Verificación:

- `flutter analyze`: 19.
- Pruebas nuevas:
  - la hoja: 16;
  - la pantalla de cortar: 7;
  - el texto extraído en modo cortar: 2;
  - la Bandeja a Procesado, de punta a punta: 5;
  - `TriageIntoProcessed`: 4;
  - el historial: 2;
  - `ProcessedTriage` y lo que ofrece la fuente: 21;
  - la barrita: 4, y la barrita del PDF y la página: 4.
- Las de la Bandeja se pasaron a la hoja: «Triado» tría con «Listo», y «Extraer nota» abre el
  original.
- Pasan 4.770 de inbox, processed, viewer, organize, study, library, reading, timeline, core,
  narration y flashcards.
- 43 mutaciones, todas muertas. Dos sobrevivieron la primera vez y se mataron sumando lo que faltaba
  probar: un documento con secciones vacías todavía no existe, y Shift+→ sin texto ni siquiera lo
  intenta (el caso de uso ya lo rechazaba, así que solo se notaba en el aviso de fallo).
- Sin probar en el emulador ni en el teléfono, ni con un PDF o una página web real en modo cortar:
  el visor del PDF y el `WebView` no corren en las pruebas. Lo que sí se probó es la barrita que
  usan (`documentHighlightToolbar`) en modo cortar y el lector de texto entero.

**La decisión J: «Extraer como nota» de una fuente va siempre a su documento procesado.**

- **Un solo lugar decide adónde va**: `extractRangeAsNote`, por el que pasan los cuatro visores
  (texto extraído, lector, PDF, página web) y el modo lectura. Ninguna pantalla cambió.
  - Mientras se tría, sigue yendo a la hoja.
  - Si no, pregunta qué es el elemento (`ProcessedRepository.extractTargetOf`) y lo resuelve
    `ExtractNoteToProcessed`, en `processed/domain/usecases`.
- **De una fuente viva**: el pasaje, tal cual y con su ancla, a la sección Notas por
  `ProcessSourceUseCase` (`SectionEdit.add`, sin repetir).
  - Si no tenía documento, nace con esa sola nota.
  - **No la tría** ni toca su estado de la Bandeja.
  - El aviso dice «Nota guardada en Procesado», con «Ver» (`RoutePaths.processedDocument`, con
    el router de la pantalla; sin uno no se ofrece) y «Deshacer». Deshacer usa el `ProcessUndo`:
    saca solo esa nota, y el documento si nació para ella.
  - Lo repetido avisa «Ese pasaje ya está en Procesado».
- **De una fuente en la papelera**: no guarda nada, lo dice y ofrece «Restaurar»
  (`LibraryRepository.restore`).
- **De una nota propia**: la nota suelta vinculada de siempre.
- **De un documento procesado** (decisión I): a sus propias notas, como algo suyo. Es
  `ProcessedDraft.written`, sin ancla en la fuente: el texto que se ve ahí es del documento.
  - Pasa por su fuente, así que si la fuente se borró de verdad, o está en la papelera, no se
    puede y lo dice.
  - Hoy ninguna pantalla del documento procesado extrae con la barrita: queda listo para
    cuando la tenga.
- **El modo lectura** cuenta y lista también las notas del documento procesado de la fuente.
  - Tocarlas abre el documento.
  - «Ir al fragmento» lleva a su lugar cuando su ancla es de este texto.
  - Las notas sueltas de antes siguen en la lista, donde estaban.
- **Para el paso 4**: una fuente pendiente puede tener ya su documento procesado, nacido de una
  nota extraída.
  - La hoja de triar todavía abre con `existing` vacío. Funciona: agregar no repite, y la nota
    queda.
  - Pero no muestra lo que ya hay. Pasarle `existing` desde `processedDocumentForSourceProvider`
    en `InboxScreen._triage` es lo que la decisión J pide («la hoja muestra las notas que ya
    tiene, sin pisarlas»), y queda para el paso 4.

Verificación:

- `flutter analyze`: 19.
- Pruebas nuevas:
  - el caso de uso: 10;
  - adónde va desde el texto extraído: 3 (papelera con «Restaurar», nota propia, el documento
    que nace);
  - el modo lectura: 5 (la nota va al procesado sin triar, «Deshacer» del primero y del segundo,
    lo repetido, «Ver» con el router de la app);
  - la barrita del PDF y la página: 1.
- Las de los visores sin base de datos usan `FakeExtractNote`, que contesta «nota propia».
- 16 mutaciones, todas muertas.
- Pasan 4.828 de inbox, processed, viewer, organize, study, library, reading, timeline, core,
  narration y flashcards.

### Paso 4: «Volver a triar»

- **Un solo punto, `retriageAction`** (`processed/presentation/retriage.dart`): con una fuente, la
  hoja de esa fuente; sin ella, el selector y después la hoja. Lo usan los cuatro accesos, y los
  botones del paso 2 se prendieron solos. Salió «Volver a triar: próximamente».
  - **Arriba en la Bandeja, siempre** —también vacía—, con la R.
  - **En el documento procesado**, al lado del enlace. Con la fuente en la papelera queda apagado y
    dice que primero se restaure (`RetriageButton.disabledReason`): procesar una fuente en la
    papelera falla.
  - **En el vacío de «Procesado»** (decisión D), abre el selector.
  - **En el detalle de una fuente** triada o descartada, en la línea de la Bandeja
    (`InboxStandingLine`), al lado de «Volver a la Bandeja». Lo que espera tiene «Triar ahora»; una
    nota propia no tiene esa línea.
- **El selector** (`RetriagePicker`): la consulta de la Biblioteca, con su mismo
  `LibraryQueryNotifier` —buscar ordena por relevancia, cada filtro vuelve a la primera tanda,
  «Cargar más» de a cien— en un proveedor propio que se suelta al cerrarse, así que no toca los
  filtros de la Biblioteca. Usa las piezas de `list_controls.dart`: el buscador con su botón de
  filtros, el marco del panel, el rótulo de cada sección y «Cargar más». Filtros: tema, tipo y
  Bandeja («Triado» junta lo de antes de F41).
  - **Solo fuentes** (`retriageCandidatesOf`): sin un filtro de la Bandeja se piden los tres
    estados, que en la consulta de la Biblioteca es `item.kind = source`. Sin columnas ni SQL nuevos.
  - **El chip «Procesado»** sale de `processedSourceIdsProvider`, el del paso 1: los ids de las
    fuentes con documento vivo, nunca el texto ni las filas.
  - Cada fila es un solo botón para el lector de pantalla, con título, tipo y «Procesado» en una
    frase. Escape cierra sin elegir.
- **La misma hoja, que lee lo que el documento ya tiene.** `existing` pasó a ser opcional: sin él,
  la hoja lo lee al abrirse (`processedDocumentForSourceProvider`: las cuentas de la fila de
  «Procesado», vivo o en la papelera, nunca el texto) con la ruedita de siempre. Se abre en el
  acto, sin esperar a la base antes.
  - **Decisión J, la parte de la Bandeja**: «Triado» abre la hoja así, con todos los cambios. Una
    fuente con documento —por una nota extraída antes— muestra lo que tiene y arranca en
    «Agregar»: no se pisa nada.
  - **Las listas que ya tienen partes** (notas, fragmentos) muestran Agregar · Reemplazar · Quitar
    sin sumarles nada antes. Si no, quitar las notas pedía cortar una primero.
  - **La vista previa dice cuánto cambia** sobre lo que ya hay: «suma 2 · saca 1», «sin cambios» o
    «Queda vacía». Sale del mismo `SectionPreview.tally` del paso 1.
- **Guardar** (`TriageIntoProcessed.retriage`): si la fuente ya estaba triada o destilada, solo el
  documento; si no —esperaba o se descartó—, el documento y el triado, las dos cosas o ninguna, por
  el mismo camino que la Bandeja. `RetriageOutcome.triagedFrom` dice desde dónde se trió. El estado
  se lee de una vez (`InboxRepository.statusOf`, nuevo) y no con `.first` de un stream de la base.
  Cortar esos streams espera a que drift suelte su aviso de cambios, y en las pruebas de pantalla
  eso no llegaba nunca. Por lo mismo, la hoja escucha el documento (`listenManual`) en vez de
  pedirle el primer valor.
  - `undoRetriage` deshace primero el documento y después devuelve la fuente adonde estaba: a la
    Bandeja (`returnToInbox`) o a descartada. Si el documento no se puede deshacer, la fuente no se
    mueve.
  - El aviso: «Procesado actualizado», «Triado y a Procesado» o «Sin cambios en Procesado» (este,
    sin «Deshacer»). «Ver» abre el documento, salvo que ya se lo esté mirando.
  - El «Deshacer» es el del aviso. No entra al historial del mazo, que es de las tarjetas.
- **Para los pasos que siguen**: la hoja recorre las secciones sola, así que las del 1b entran sin
  tocar nada de acá. No se agregó ningún `switch` sobre `ProcessedSection`.

Verificación:

- `flutter analyze`: 19, y `verify_commit` aprueba el commit solo.
- Pruebas nuevas:
  - «Volver a triar» de punta a punta, contra la base del arnés: 18. Cubren el selector, la R y
    Escape, de a cien, una fuente triada, una que espera, «Ver», «Sin cambios», cerrar sin
    guardar, la decisión J, los cuatro accesos, la letra al doble en un teléfono angosto y con y
    sin animaciones.
  - `TriageIntoProcessed.retriage` y `undoRetriage`: 7.
  - La hoja: 3, con las listas que ya tienen partes y lo que dice la vista previa.
- Las del paso 2 que esperaban el botón apagado se pasaron a prendido.
- Pasan 1.485 de inbox, processed, library, app, study y notebooks, ya sobre el paso 1b.
- Mutaciones: 35, todas muertas o sacadas por equivalentes. Sobrevivieron tres la primera vez:
  - Escape en el selector: lo cierra la hoja misma (`DismissIntent`), así que se sacó el atajo
    propio.
  - Mostrar Agregar · … en una sección entera apagada: nunca se dibuja apagada, así que se sacó la
    rama.
  - «Sin animaciones»: la prueba solo miraba que el selector estuviera. Ahora compara su lugar en
    el primer cuadro con el final, y otra prueba fija que con animaciones sube desde abajo.
- Sin probar en el emulador ni en el teléfono.

### Paso 5 (hecho): los Cuadernos, solo con Procesado

- **Un solo lugar decide qué es miembro de un cuaderno: `NotebookRepository`.**
  - `addItems` (y `addItem`, que pasa por él) inserta con una sola consulta que filtra
    `isProcessedSql` y lo vivo: una fuente, una nota, uno en la papelera o un id que no existe se
    quedan afuera, sin error. Nada
    se cuela entre mirar y escribir. Ningún otro código escribe `notebook_item`.
  - `resolveQuery` devuelve ahora una `ProcessedQuery`, no una `LibraryQuery`; `memberIds` da los
    ids con `ProcessedRepository.matchingIds`, el mismo motor de la pantalla Procesado, y falla si
    el cuaderno no existe. El chat, los repasos (`StudyScopeResolver`), «Tarjetas con IA» y
    «Llenar con IA» preguntan ahí: ninguno evalúa un cuaderno con el motor de la Biblioteca, que
    deja afuera lo procesado.
- **«Por consulta» sobre procesados** (`processedQueryForView`). La vista se guardó en la
  Biblioteca; cada filtro se traduce a lo que significa en un procesado: el texto, en su título y
  sus partes; el tipo, el de la fuente de origen; temas, etiquetas y propiedades, los del
  procesado (decisión F); lo pendiente, lo fallido y lo de la Bandeja no traen ninguno, como una
  nota en la Biblioteca. `ProcessedQuery` suma `tagIds` y `propertyValueIds`, con sus ramas
  (`valuesWithDescendantsSql`), y la lista de Procesado escucha `item_property_values`.
- **«Agregar»**: un selector nuevo de documentos procesados (`PickProcessedDialog`), con buscador en
  Procesado, varios a la vez, lo que ya está marcado y quieto, y su vacío que manda a triar.
- **«Crear con IA»**: busca por palabras solo entre los procesados vivos (el buscador del chat con
  ese alcance). Por sentido, los vectores son de las fuentes: `ItemVectorIndex.nearestTo` suma
  `among`, se busca solo entre las fuentes de los procesados vivos y cada una cuenta por su
  procesado. Así el tope no se llena con fuentes que después se descartarían. Sin ningún
  procesado, no se busca.
- **«Sugeridos»**: los temas y las etiquetas cuentan solo procesados vivos, y los títulos de
  ejemplo también.
- **El chat acotado lee solo el texto procesado.** Con los miembros de un cuaderno como alcance,
  `ChunkPassageRetriever` no trae ningún fragmento de una fuente: ni de una de la Biblioteca ni de
  la que dio el procesado (prueba en `chat_scoped_to_notebook_test`). Un procesado que coincide
  solo por el título daba un pasaje vacío; ahora da su primera parte, en el orden en que se lee.
  Las citas de un procesado salen sin posición y abren `itemDetail(id)`, que el paso 2 redirige
  a la pantalla del procesado (`processedDocumentRedirect`). Las
  sugerencias del chat vacío, con un cuaderno, salen de lo último procesado.
- **Lo que muestra un cuaderno**: cada fila es un documento procesado, con el ícono de la fuente de
  origen en su círculo, el título y los chips de sus partes. El lector de pantalla lee la fila en
  una frase (título, origen, partes); el ícono y los chips no se leen sueltos, y la «X» sí.
  Tocarla abre el documento en su pantalla (`RoutePaths.processedDocument`), por un solo punto:
  `notebook_navigation.dart`, que sabe a dónde lleva un cuaderno.
- **El vacío** (el `EmptyStateView` de toda la app) explica que se llena con documentos
  procesados, a mano o por su vista, y ofrece «Ir a Procesado» y, debajo, «Ir a la Bandeja».
- **«Llenar con IA»**: la nota lee de cada procesado lo primero copiado tal cual de su fuente y
  anclado al texto principal de la fuente, con la misma coordenada que una cita; lo escrito o
  editado no se cita. Las afirmaciones quedan ancladas a la fuente de la Biblioteca. La nota queda
  en la Biblioteca y la hoja lo dice: no puede ser miembro.
- Arreglado de paso: el desplegable de vistas del diálogo «Cuaderno nuevo» desbordaba con una pista
  larga (`isExpanded`).
- **Las tarjetas de un procesado salen de su texto procesado** (decisión I), nunca de la fuente.
  - Un solo lugar arma el texto de las tarjetas: `readProcessedCardText`
    (`processed_card_text.dart`). Son sus partes en el orden en que se leen, separadas por un
    renglón en blanco.
  - Cada tramo sabe de qué parte sale y, si es copia intacta, dónde está en el original
    (`sourceAnchorOf`).
  - Un libro se junta en otro hilo desde `kProcessedInlineChars`. No inventa formas de texto.
  - Lo usan el paso de tarjetas de la IA (`AutoFlashcardsStep`, que ya no cae a la fuente) y la
    cobertura (`FlashcardCoverageReaderImpl`, con `processedHasCardTextSql`, la misma regla en
    SQL).
  - Así «Tarjetas con IA», las tarjetas de «Llenar con IA» y el ✨ de Repasar cuentan y hacen las
    de los procesados.
  - Las tarjetas de un procesado quedan sin fragmento, como las de una nota: la tabla de tarjetas
    apunta a posiciones del elemento, y un procesado no tiene forma de texto.
  - De qué secciones salen lo dice un `switch` (`isCardSection`): una sección nueva obliga a
    decidirlo. Entran todas, también Palabras clave: cada parte es una oración con sus claves
    marcadas, lo que la persona eligió conservar. Que alguna se repita con el Texto solo le da
    más peso. Un procesado con solo palabras clave da tarjetas (prueba).
  - **Dos textos distintos, que no se confunden:** el que se resume y se estudia en el procesado
    (1b, `ProcessedRepository.studyTextOf`) son las páginas de Texto, o el de la fuente con la
    copia del original. El de las tarjetas (`readProcessedCardText`) es todas las secciones de
    las que salen tarjetas. Las clases se llaman distinto a propósito: `ProcessedStudyText` y
    `ProcessedCardText`.
  - Mutaciones de esta parte: 13. Murieron 12. La que queda es equivalente: juntar el texto
    siempre en este hilo da el mismo resultado, solo cuesta más con un libro.

- **El aviso del cuaderno vaciado** (v46, `notebooks.emptied_for_processed_at`): se ve en el detalle
  mientras la marca no sea `null`. Explica por qué quedó vacío y cómo volver a llenarlo, con un
  texto para uno a mano y otro para uno por consulta. Trae «Ir a la Bandeja» y «Entendido».
  «Entendido» (`NotebookRepository.dismissEmptiedNotice`) deja la marca en `null`, sin otra
  columna y sin tocar la fecha del cuaderno, así que no vuelve.
- Los chips de las partes usan los nombres de «Procesado» (`ProcessedSectionPresentation`), con
  Palabras clave: un solo par ícono-nombre en toda la app.

**Falta:**

- **«Ver en la fuente» desde una tarjeta de un procesado**: por ahora la tarjeta queda sin
  fragmento, como las de una nota de bloques. Para llevar al original haría falta una columna en
  `flashcards` con el ancla de la fuente (`ProcessedCardText.sourceAnchorOf` ya la sabe dar).
- El benchmark del chat acotado arma ahora 500 procesados («pasar todo sin modificar»); no se
  corrió.

Verificación:

- `flutter analyze`: 19.
- Pruebas: la suite entera antes de rebasar, 10.738 pasan y 4 fallan. De esas 4, una se arregló
  (el censo de lecturas de `item`: el filtro de `addItems` ahora decide lo vivo). Otra ya está
  arreglada en main (`1cb63cbc`, los triggers del banco). Las otras dos son de tiempo y temporales
  bajo carga (Anki, paginar en otro hilo) y pasan solas. Después de rebasar: cuadernos, chat,
  procesado, notas, tarjetas y el censo (ver el informe del commit).
- Mutaciones: 32, todas muertas. Una sobrevivió al principio —«Crear con IA» sin el alcance de
  procesados—: lo de afuera se caía después, pero ocupaba el tope; se sumó la prueba que la mata.
  Del aviso y de las palabras clave en las tarjetas: 6, todas muertas.
- Sobre el 1b (v46): pasan 2.183 de cuadernos, procesado, tarjetas, IA que organiza, notas, chat y
  el censo.
- Sin probar en el emulador ni en el teléfono.

### Paso 7: las imágenes en Procesado, esquema v47 (decisión L)

- **Una sección más, Imágenes** (`ProcessedSection.images`), la única que no es texto
  (`holdsFiles`). Es sección para quien pide —la hoja, el caso de uso, «Volver a triar», los chips
  de la fila y el filtro «qué partes tiene»— porque eso es para la persona; se guarda aparte porque
  no es una parte de texto: nada de `processed_parts`, ni de su índice de texto, ni del lector en
  voz alta. Los `switch` de cada sección la nombran (`triageShapeOf` con una forma nueva,
  `TriageSectionShape.gallery`, `triageSectionsOffered`, los textos, el panel, los de la copia del
  original y de estudiar el procesado, y el de las tarjetas: de una imagen no sale ninguna,
  `isCardSection`).
- **Cómo guarda hoy sus imágenes cada fuente**, y de dónde se listan (`SourceImagesReader`, una sola
  forma, de a tramos y sin abrir ninguna):
  - una imagen o una captura, y un enlace directo a una foto: su archivo (`original_blob_path`);
  - una publicación: su primera foto es su archivo, si no trae video; las demás del carrusel van a
    su «Contenido» (F30);
  - una página guardada: las fotos de su artículo, en su versión más grande, en su «Contenido»
    (F30). La página archivada trae además una copia de cada una incrustada como datos, junto con
    los íconos y la decoración de toda la página: esas no se listan. Son las mismas fotos,
    repetidas, y sacarlas obligaría a leer y decodificar un archivo de hasta 25 MB para armar una
    grilla.
  - Fuera quedan los SVG (no hay con qué dibujarlos para elegir mirando) y, como pide el plan, las
    imágenes de dentro de un PDF, un Word o un EPUB.
- **Cada imagen elegida es una copia propia, por el mismo camino que la copia del original
  (decisión H):** una forma del procesado (`renditions`, de tipo imagen, sin `position`: no es
  «Contenido» y nada la transcribe), copiada con `FileStore.copy` a `originales/<procesado>/imagenes/`,
  con su id derivado del procesado y del archivo de la fuente (`processedImageRenditionIdFor`), y su
  fila en `processed_images` (lugar en la galería, de qué archivo salió y cuánto pesaba; la misma
  imagen no entra dos veces en un documento, lo garantiza la base). Por ser una forma la cuentan
  `isFileReferenced`, el borrado de verdad, la copia de la bóveda (toda la carpeta `originales/`) y
  la unión (`OriginalFilesMerge`). Soltar el archivo de la fuente no toca la copia, y al revés.
- **Quitar una imagen** —de la galería, o al reemplazar o quitar la sección— la manda a la papelera
  del contenido del procesado, como la copia del original: la fila guarda lo de su
  `processed_images` (`content_trash.processed_image`) y su archivo espera 30 días. «Deshacer» la
  devuelve a su lugar, corriendo las demás; la papelera del contenido la recupera en su galería, no
  como el archivo de una fuente.
- **El caso de uso** planea la galería aparte de las partes (`planImagesChange`, pura): agregar suma
  al final lo que no está, reemplazar deja exactamente lo elegido en el orden de la fuente
  —conservando la copia de lo que ya estaba— y quitar saca todo; «Actualizar» no aplica (otro
  archivo es otra imagen). «Todas» no enumera nada en la hoja (`ImageChoice.all(except:)`): la lista
  se lee de la fuente al guardar. Las copias se hacen antes del guardado, fuera de la base; si el
  guardado no llega, se borran. Deshacer saca lo que entró —y borra esas copias del disco—, devuelve
  lo que salió y deja cada una en su lugar. La vista previa dice cuántas van y lo que va a ocupar lo
  que se suma, sin copiar nada.
- **La hoja**: dentro de «De la fuente», cuántas trae y cuánto pesan, «Todas», «Ninguna», cuántas
  van elegidas y una grilla de miniaturas que se eligen tocándolas, de a 60 con «Mostrar más», cada
  una decodificada al tamaño en que se ve. Con Tab se llega a cada una y se elige con Espacio o
  Enter; el lector de pantalla dice cuál es, de cuántas, su nombre y si está elegida. La letra al
  doble en 360 de ancho no la desborda, y sin animaciones cambia de una vez. Al volver a triar
  ofrece Agregar · Reemplazar · Quitar, y Quitar esconde la grilla. El total de abajo suma lo que
  van a ocupar.
- **La Bandeja**: una foto sin letras se puede triar —lleva sus imágenes y las notas—, una vez que
  terminó de leerse (`offersImages`). Vincular y extraer siguen necesitando texto. «Pasar todo sin
  modificar» sigue siendo solo el texto, como lo pidió el dueño.
- **El documento**: la sección Imágenes es una galería de miniaturas, de a tandas; tocar una la abre
  a pantalla completa (`ProcessedImageViewerScreen`) con pellizco para acercar, deslizando o con las
  flechas para pasar de una a otra y Escape para volver. «Quitar de Procesado» está en la pantalla
  completa, con Suprimir sobre la miniatura enfocada y como acción del lector de pantalla, siempre
  con «Deshacer».
- **Los censos**: `processed_images` en los conteos que son compuerta de la migración, en «nunca se
  achica» y en las referencias rotas de la unión; la unión suma las de la copia cuya forma llegó,
  sin repetir la forma ni el archivo de la fuente, después de las de acá; el resultado lo cuenta
  (`processedImagesAdded`) y la vista previa lo cuenta en los archivos nuevos. Una forma con
  archivo que espera en la papelera del contenido acá —la copia del original o una imagen— ya no
  vuelve con la unión, igual que un texto soltado.
- **Para la decisión 87 (cambio de regla en la unión):** `rendition_merge.dart` marca como «soltado
  acá» (`dropped_here`) cualquier forma de la copia cuyo `rendition_id` espera en la papelera del
  contenido de esta bóveda, no solo un texto. Hoy las únicas formas con archivo que la papelera
  guarda con su id son la copia del original y las imágenes de un procesado: así lo que la persona
  quitó acá no vuelve con la unión. Vale también para la copia del original del 1b.
- **Con el conmutador «El original» del paso 2**: en «De la fuente» van las secciones enteras, el
  original —con el número que sigue a ellas— y al final la grilla de imágenes, que no tiene número
  (se recorre con Tab). «Va a quedar» muestra las dos cosas: el original con su peso y las imágenes
  con lo que ocupan, y abajo el total suma lo que ocupan las imágenes.

Verificación:

- `flutter analyze`: 19.
- Pruebas nuevas: el plan de la galería y la elección, 12; lo que ofrece cada fuente, 11; la galería
  en la base, 8; el caso de uso y el repositorio con imágenes —crear, «Todas», vista previa,
  copias que no llegan, deshacer, volver a triar, quitar con «Deshacer», la papelera del contenido,
  la papelera del documento y el borrado de verdad, soltar el archivo de la fuente, el filtro—, 17;
  el modelo de la hoja, 7; la grilla de la hoja, 8; la galería y la pantalla completa, 6; la unión
  y la copia de la bóveda, 4; la Bandeja, 1; la migración 46→47, 4.
- Ajustadas a lo nuevo: la hoja recorre las secciones sin Imágenes en una página sin fotos, y una
  foto sin letras que falló o terminó sin texto ya se puede triar.
- Suite entera: 11.132 pasan. Cuatro fallaron solo con la suite entera en marcha —tres de tiempos
  (el banco del modelo, partir en otro hilo, los candidatos de vocabulario) y una lectura de una
  copia vieja— y pasan corridas solas.
- Rebasado sobre la decisión J y los pasos 4 y 5: pasan 3.458 de procesado, Bandeja, cuadernos,
  tarjetas, unión de bóvedas, base, papelera, Biblioteca y lectura. Las tarjetas no salen de una
  imagen, y su prueba lo dice.
- Rebasado sobre el paso 2, segunda tanda (el conmutador «El original»): pasan 2.655 de procesado,
  Bandeja, cuadernos, unión, base, papelera y Biblioteca —una de la copia entrante falló solo con
  todo en marcha y pasa sola—, con una prueba más de la hoja: una página guardada ofrece su
  original y sus fotos, el número del original sigue a las secciones enteras, la grilla va al final
  y «Va a quedar» y «Listo» llevan las dos.
- 40 mutaciones: 38 muertas. Las dos que sobrevivían eran equivalentes —«ya tiene esa imagen» y
  «es la misma imagen en la unión» se comprobaban dos veces, por la forma y por el archivo de la
  fuente, y como el id de la forma sale de los dos es la misma comprobación—: se sacó lo repetido.
  Otras dos se mataron sumando lo que faltaba probar: una forma que apunta al archivo de la fuente
  no lo ofrece dos veces, y reemplazar sin ninguna elegida no pide nada.
- Sin probar en el emulador ni en el teléfono: la grilla y la galería con fotos de verdad
  decodificándose (en las pruebas los archivos no son imágenes y se ve el ícono), el pellizco del
  zoom, y una página guardada de verdad con su «Contenido» bajado.

### Paso 8: la fuente de consulta (decisión K)

Hecho sobre los pasos 1b, 2 (las dos tandas), 3, 4, 5 y la decisión J, ya en main; lo que depende
del paso 6 queda señalado al final.

- **Un solo criterio**: `isConsultationSource` (`processed/domain/services/consultation_source.dart`).
  Una fuente es todo lo que no es una nota propia —documento, libro, página, publicación, imagen,
  audio, video, referencia—; un documento procesado no llega al detalle (tiene su pantalla). Lo
  leen el detalle, el panel de la fuente y su hoja «Más».
- **Lo que sale del detalle de una fuente** (una nota propia no cambia):
  - de la tarjeta de estudiar, «Extraer resumen», «Extraer síntesis» y «Extraer palabras clave»
    (`StudyDocumentCard.studiedRows` en `false`). Quedan los tres botones que marcan el original,
    la leyenda, el avance y «Extraer» con el texto, la transcripción y las fotos; sin ninguno de
    los dos, ni el título «Extraer». El lector en voz alta sigue ofreciendo lo estudiado;
  - el mosaico «Resumir»: el panel de una fuente queda en Leer · Copiar · Más. Con él se fueron
    `SourcePanel.onSummarize`, la llave de la tarjeta a la que llevaba y `showStudyLayer`, que solo
    servían a eso;
  - de «Más», «Organizar con IA», «Buscar fechas con IA» y «Borrar archivo, quedarme con el
    texto». Este último no aplicaba a ninguna nota, así que salió entero: la acción, su
    `canKeepOnlyText` y `trashOriginalFile` (el repositorio sigue sabiendo soltar el archivo, para
    la unión de bóvedas y la papelera). «Borrar el texto, quedarme con el libro» queda: el dueño no
    lo marcó;
  - la línea «La IA organizó esto»: lo que la IA hizo en la fuente no se borra, solo deja de verse;
  - el Mapa (`LocalGraphPanel`), las Tarjetas de repaso (`FlashcardSection`) y, en la barra, la nota
    derivada ✨ y el quiz.
- **La línea que lleva a estudiarlo** (`SourceStudyLine`), donde estaba el Mapa:
  - con documento procesado —vivo o en la papelera—, «Se estudia en Procesado: …» con
    «Estudiarlo en Procesado»;
  - sin él, «Para estudiarlo, triálo», con el botón que abre la hoja «¿Qué va a Procesado?» por el
    camino de «Volver a triar» (`retriageAction`, paso 4), que tría también lo que todavía espera en
    la Bandeja, con su «Deshacer». En la Bandeja dice «Triar»; ya triada o descartada, «Volver a
    triar». Sin texto, el botón espera apagado con su motivo (`InboxActions`), y se prende solo. Un
    solo camino: no hay un triar del detalle aparte del de «Volver a triar»;
  - una referencia sin texto no dice nada: no hay qué estudiar (decisión E).
- **El documento procesado se estudia ahí**, con las piezas de siempre sobre el documento (es un
  elemento de la bóveda, decisión A), sin copias:
  - debajo de sus secciones, su Mapa (`LocalGraphPanel`) y sus Tarjetas (`FlashcardSection` con
    `processed`), en `ProcessedStudyTools`. En la papelera no se ven —el elemento de la papelera no
    se sirve—: se lee y se restaura;
  - **«De la fuente»**: en la sección de tarjetas, plegado, con cuántas son, las que ya tenía la
    fuente. Son las mismas filas —no se mueven ni se copian—, siguen en Repasar con su historial,
    su «Ver en la fuente» lleva al pasaje de la fuente, y se editan, se rechazan y se borran como
    las demás. Sin ninguna, no ocupa lugar;
  - arriba, la línea «La IA organizó esto» del documento (`ProcessedAiLine`), cuando hay algo que
    contar;
  - en la barra, el ✨ de la nota derivada, el quiz y «Más» (`ProcessedMoreMenu`) con «Organizar
    con IA» y «Buscar fechas con IA» sobre el documento: los mismos puntos de entrada de la cola
    (`organizeNowWithAi`, `findDatesNowWithAi`) con su id. Que la cola trabaje su texto procesado
    es del paso 6;
  - **«Borrar la copia del original, quedarme con el texto»** (`DropOriginalCopy`): va por el
    mismo camino del 1b para quitar el original al volver a triar (`ProcessSourceUseCase` con
    `OriginalEdit(remove)`): la copia va a la papelera del contenido —se recupera de ahí, y el
    archivo se borra recién al vencer—, y el aviso trae «Deshacer» (el comprobante del procesado).
    Nunca toca el archivo de la fuente. No pregunta antes, como soltar un archivo en la fuente.
  - **Que el documento no quede mudo.** Sin sección Texto, su texto propio es el de la fuente que
    es el de la copia (decisión I): soltarla lo dejaba sin qué estudiar, y sin el texto sobre el que
    están su resumen, su síntesis y sus palabras clave. La opción promete «quedarme con el texto»,
    así que lo cumple sin preguntar: en el mismo guardado, el texto de la fuente entra como su
    sección Texto. Es el mismo texto con las mismas posiciones, así que lo estudiado en el
    documento sigue en su lugar; «Deshacer» deshace las dos cosas. Avisar y ofrecer guardarlo
    sería una pregunta cuya única respuesta sensata es «sí». Si la fuente no tiene texto, solo se
    suelta la copia.
  - No se ofrece sin copia, ni con la fuente en la papelera o borrada: procesar se arma contra la
    fuente viva, y sin ella la copia es lo único que queda de su original.
  - **La tarjeta de estudiar del documento** (`ProcessedStudySlot`) quedó conectada a
    `processedStudyTextProvider` del 1b —su sección Texto o la copia—, con la clave del procesado:
    Resumir · Sintetizar · Palabras clave sobre lo procesado y, en «Extraer», el resumen, la
    síntesis y las palabras clave para leer, copiar y escuchar. Salió el proveedor provisorio que
    devolvía `null`: queda un solo `processedStudyTextProvider`, el de `processed_providers.dart`.
  - **La barrita sobre la copia del original** (la vista del paso 2, `ProcessedOriginalScreen`): la
    copia es de solo lectura (`isReadOnlyStudyKey`, sobre la clave `procesado-original:<id>`). Lo
    marcado ahí es lo elegido del procesado, en las posiciones del texto de la fuente: no hay una
    forma de texto donde caiga un resaltado, una nota, una tarjeta o un hecho de la línea de tiempo,
    y redirigirlos a la fuente rompería que nada de lo que se hace sobre la copia cae en ella. Así
    que se quitan, no se redirigen: la barrita queda con Copiar, Escuchar y «Extraer como nota», que
    va a las notas del documento (decisión J). `HighlightToolbar` aprendió a no dibujar los colores
    ni «Subrayar» sin sus callbacks; lo deciden en un solo lugar `documentHighlightToolbar` (PDF y
    página) y `buildHighlightMenu` (lector y texto extraído).
- **De qué texto sale lo que se estudia**: el texto de las tarjetas del paso 5
  (`readProcessedCardText`), uno solo para todo lo que se estudia con IA de un documento procesado.
  - **Las tarjetas con IA** de la sección salen de ahí, sin pasaje: el procesado no tiene una forma
    de texto donde caer, y la de la fuente es de otro elemento. La sección lo lee solo si quien la
    muestra dice que es un procesado (`processed`); si no se puede leer, lo dice y no cae a la
    fuente.
  - **El quiz** también, y cada respuesta se ancla **en la fuente**, en el pasaje que el procesado
    copió de ella (`ProcessedCardText.sourceAnchorOf`): «Ver en la fuente» lleva a la Biblioteca,
    como un fragmento. Lo escrito o editado a mano no está en la fuente y no se cita —la pregunta se
    descarta, por la misma regla de siempre: ninguna opción sin pasaje real—. La respuesta correcta
    guarda su propio elemento (`QuizQuestionResult.correctSourceItemId`), y los distractores salen
    de otros elementos que no sean esa fuente.
  - **La nota derivada** de un solo documento procesado va por lo que el paso 5 armó para los
    cuadernos (`_citableProcessed`): lo primero copiado tal cual, citado en la fuente.

**Lo que falta, del paso 6:** el Mapa y la cola de la IA sobre procesados. Hoy el grafo local de un
procesado no tiene vínculos, y la Biblioteca filtra los procesados de los vecinos que dibuja;
«Organizar con IA» y «Buscar fechas con IA» del documento ya piden por su id. Además,
`processedStudyTextProvider` es un `FutureProvider`: no se rehace solo cuando cambian las páginas;
«Borrar la copia» lo invalida.

Verificación:

- `flutter analyze`: 19.
- Pruebas nuevas: soltar la copia, con la base real (5); la línea del detalle (8); lo que sale del
  detalle en seis tipos de fuente y lo que queda en una nota (7); el documento que se estudia —Mapa,
  tarjetas, «De la fuente», la barra, la línea de la IA, la papelera, la tarjeta de estudiar y la
  copia— (13); las tarjetas del procesado y «De la fuente» (5); el quiz del procesado (2); la nota
  derivada de un procesado (2); la barrita sobre la copia (2); la tarjeta de estudiar de una fuente
  (2); el panel de una fuente y de una nota (2). Las del panel, el detalle, la lectura en voz alta,
  la línea de la IA y la tarjeta se ajustaron a lo que salió.
- Con la tarjeta de estudiar arriba del documento, la prueba de la letra al doble en un teléfono
  encontró tres desbordes de piezas de siempre, que ahora se parten en vez de desbordar: la leyenda
  de la tarjeta de estudiar, el título de las Tarjetas de repaso y el vacío del grafo local.
- La suite entera, antes de rebasar sobre los pasos 2 (segunda tanda), 4, 5 y J: 11.105 pasan y 46 se
  saltean; las 16 que fallaron en esa corrida pasan después —las 15 de la línea «La IA organizó
  esto», que ahora mira el detalle de una nota, y «Medir GPU y CPU», que depende del tiempo con la
  máquina cargada—. Después de rebasar: pasan 4.335 de procesado, tarjetas, notas, visores,
  organizar, Biblioteca, estudiar, Bandeja, IA que organiza, diseño, lectura y línea de tiempo, más
  las pruebas que se sumaron después.
- Mutaciones: 60 en la primera tanda, 57 muertas. De las tres que sobrevivieron, una era de un
  código que se fue al unificar con el texto de tarjetas del paso 5; otra —que una fuente descartada
  dijera «Triar»— se mató probando los dos estados, y la tercera era equivalente —el documento en la
  papelera ya no se sirve, así que la regla aparte sobraba— y se sacó la regla. Después de rebasar,
  29 sobre lo nuevo y lo que cambió (el quiz y las tarjetas sobre el texto de tarjetas, la nota
  derivada de un procesado, la barrita de solo lectura, la línea y el documento): todas muertas.

**Paso 6 (hecho): organizar lo procesado.** Sin subir el esquema: todo sale de las tablas de hoy,
colgado del documento procesado (decisión F).

- **La IA organiza lo procesado, no las fuentes.**
  - La cola (`AiOrganizeBacklog`) toma solo notas: las de la persona y los documentos procesados,
    que son notas. Una fuente ya no entra ni nueva, ni de la biblioteca que ya existía, ni pedida a
    mano: `_organize` y `_findDates` la saltan. Se quitó `itemProcessed`, el aviso de la cola de
    procesamiento al terminar una fuente. La revisión con otro modelo no organiza: corrige lo que la
    IA ya hizo, y sigue igual.
  - **El punto para encolar un procesado** es `AiOrganizeQueue.enqueueProcessedForOrganizing(id)`.
    Lo llama un solo lugar, `TriageIntoProcessed` —triar en la Bandeja, pasar sin modificar y
    «Volver a triar»—, cada vez que el triado dejó el documento distinto: no con «Sin cambios», ni si
    falló y se deshizo. Le llega como `organize`, un parámetro del caso de uso; en la app es
    `organizeTriagedProvider`, que lee la cola recién al triar, y en las pruebas un registro
    (`LibraryHarness.triagedForOrganizing`), así ninguna pantalla arranca una cola de verdad. Lo
    organiza en el acto, en una pasada nueva que no repite lo que ya estaba.
  - **Deshacer el triado no lo saca de la cola.** Un documento que nació con el triado se borra al
    deshacer, y la cola salta lo que ya no existe sin abrir una pasada (lo fija una prueba); uno que
    ya existía vuelve a como estaba, y organizarlo otra vez no repite nada. Sin llamarlo, un
    procesado nuevo igual se organiza solo —la cola lo ve en la base cuando lleva 15 segundos
    quieto— y uno que cambió mucho también, como una nota; la llamada es lo que hace que volver a
    triar con algo chico, como un fragmento con una fecha, no espere.
  - **Lee solo lo elegido** (`OrganizeTextReader`): las partes del procesado, armadas en un solo
    lugar (`joinProcessedParts`): las páginas del texto pegadas, lo demás separado por un renglón en
    blanco. El mismo texto lo leen los pasos, la revisión, la huella que dice si cambió, los
    vectores (`noteTextOf`) y el comienzo de un candidato o de una entrada de nota mapa, que lee
    solo las primeras partes de un libro. Las tarjetas, no: salen de «el texto que se estudia»
    (`readProcessedCardText`, decisión I), como las de la cobertura.
  - **Vínculos entre procesados**: el selector de candidatos deja a cada lado con lo suyo, por SQL
    (`isProcessedSql`). Un procesado se vincula solo con procesados; lo de la Biblioteca, entre sí.
  - **Las fechas citan su lugar**: lo que la IA encuentra en una parte copiada tal cual se guarda en
    el procesado con la cita en la forma de la fuente (`citeInSource`, con `sourceOffsetOf`); un
    tramo que cruza dos páginas pegadas y seguidas en el original también. En una parte editada o
    escrita por la persona queda con su frase y sin posición. `DatedEventRepository` acepta esa cita
    porque la forma es de la fuente del procesado. «Abrir en el documento» abre el original ahí
    (`TimelineEvent.quoteItemId`). Las fechas son solo de lo procesado: de una nota de la persona
    no se buscan, porque no se verían.
  - **Las notas mapa** reúnen lo procesado de cada tema: es su material, como lo era una fuente.
- **Las cuatro pantallas leen solo lo procesado**, en SQL:
  - `LibraryQuery.scope` (`LibraryScope.processed`): los mismos filtros de la Biblioteca sobre los
    documentos procesados; el texto se busca en sus partes y el tipo es el de su fuente. Lo usan el
    Mapa, la Línea, el grafo local, el Explorador («el material» de una rama), los selectores
    («Documento», «Un documento», vincular desde el Mapa, «✨ Sugerir vínculos») y la bibliografía
    de una rama, que cita las fuentes de lo procesado.
  - **El Atlas cuenta cada procesado por cuánto se trabajó** (`ProcessedDepth`): solo el texto, con
    resumen o síntesis, con fragmentos o con notas propias. Es la cobertura nueva —las cuatro barras
    de siempre—, y el vacío «muchas fuentes sin nota viva» pasa a «muchos documentos y ninguno con
    notas». Así se arregló de raíz el -1: un procesado ya no es «elemento sin escalón».
  - **El Mapa**: los ítems, los vínculos, el esquema, los elementos de un tema, las contradicciones
    y el tablero, con `mapItemSql`. La tarjeta de madurez de las notas pasa a «Cuánto trabajaste lo
    procesado», con la misma escalera y los mismos colores que el Atlas. «Ver en el Mapa» se ofrece
    solo si lo vinculado está en el Mapa.
  - **El grafo local**: `watchNeighborhood(processedOnly: true)`, solo vínculos entre procesados.
    Es también el Mapa del documento procesado (paso 8): dibuja sus vecinos procesados, que se
    piden con `LibraryScope.processed` —lo que el paso 8 dejó anotado como pendiente—.
  - **La Línea de tiempo**: las fechas de los procesados y los hechos que la persona escribe a mano
    en una nota suya, como «Hechos sueltos», que no salen de ninguna fuente. Un hecho marcado en el
    texto de una fuente va a su documento procesado. El repositorio lee el corpus que pide la
    consulta (`LibraryQuery.scope`): la Línea pide `processed`, y el calendario de la Biblioteca
    —que reusa esa lectura para «Fecha del hecho»— sigue leyendo sus fuentes y sus notas.
- **Empiezan de cero**: sin nada procesado, el Atlas y el Mapa muestran `FillsOnTriage` —que se
  llenan al triar, con «Ir a la Bandeja»—, y la Línea vacía ofrece la Bandeja y «Agregar un hecho».
- **Los accesos desde la fuente**: «Ver en la línea de tiempo» abre la de su procesado. El id del
  procesado sale de la fuente (`processedDocumentIdFor`), así que se pregunta por él sin traer el
  documento.
  - Con el paso 8 (decisión K), una fuente es de consulta: su Mapa, «Organizar con IA», «Buscar
    fechas con IA» y la línea de la IA están en el documento procesado, y piden con su id. Este paso
    había hecho que, desde la fuente, trabajaran sobre su procesado o dijeran que faltaba triarla;
    con el paso 8 ese código no lo alcanza nadie y se sacó, con su tarjeta, sus avisos y sus pruebas.
    El grafo local dibuja el de un documento procesado; de cualquier otro elemento, nada. Por eso
    el detalle de una nota propia ya no lo pone: no tiene Mapa, y sus vínculos están en «Vínculos».
- **Abrir un procesado** desde esas pantallas pasa por un solo punto, `openOrganizedItem`, que va a
  `RoutePaths.itemDetail`: con el paso 2 en main, esa ruta redirige a la pantalla del documento
  procesado.
- Lo que las fuentes ya tenían —temas, vínculos, fechas— no se borra: sigue en su detalle.
- Las pruebas escriben un documento procesado en un solo lugar, `insertProcessedRows`
  (`test/support/processed_rows.dart`); `insertProcessedDocument` es un atajo encima, con un mismo
  texto en cada sección elegida.
- Pasa la suite entera: 11.248 pruebas.
- 45 mutaciones, todas muertas. Nueve sobrevivieron la primera vez: siete se mataron con lo que
  faltaba probar —la cita de una fecha en la fuente, la huella de lo elegido, cruzar partes que no
  van pegadas o no son seguidas, cada lado de los vínculos con lo suyo, el tope del grafo local—, y
  dos eran código que nunca corría y se sacó. Otras cuatro se fueron con lo que el paso 8 dejó sin
  uso.
- Sin probar en el emulador ni en el teléfono.

### Paso 9 (hecho): el cierre

- La decisión 87 en `docs/arquitectura.md`, con el cambio de regla de `dropped_here` en la unión
  de bóvedas (paso 7), y F41 en «Construido».
- `CONTEXTO_DEL_PROYECTO.md` y la GUÍA al día. En la GUÍA quedaba que el mosaico «Resumir» estaba
  en el panel de una fuente: ahora dice que queda solo en una nota propia.
- Suite entera sobre `87e147ee`: **11.333 pasan, 0 fallas, 46 omitidas**. `flutter analyze`: 19.
- En una primera corrida de la suite, `processed_document_screen_test` se colgó en su primera
  prueba («Ver el original en la Biblioteca» abre la fuente): no terminó en cinco minutos, y ni
  siquiera saltó el límite de 240 s, así que el proceso quedó trabado entero. No se repitió: el
  archivo solo pasa (35 de 35), con carga alta en paralelo pasa, y la segunda corrida de la suite
  entera pasó completa. Si vuelve a pasar, mirar ahí primero.
- Sin probar en el emulador ni en el teléfono: la APK se instala si el dueño la pide.
