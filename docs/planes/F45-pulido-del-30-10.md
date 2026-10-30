# F45 — Pulido del 30/10: avisos, triar, la Biblioteca solo con el original, Procesado y el diseño

> **Estado: APROBADO** (2026-10-30, «Aprobado» en el chat), con las decisiones A a E como están;
> la B, la recomendada, **elegida por el dueño** el 30/10: «Al elegir «Texto extraído» en el
> triaje, la IA de turno lo ordena (columnas, encabezados, cortes y títulos)».
>
> Pedido del dueño, el 30/10, con diez capturas: *"Ahora vamos con una serie de mejoras"* —once,
> con la de la Infografía y la Presentación—. Se construye en paralelo con F44 (el Mapa), en
> pantallas distintas:
>
> - **ola 1**: F44 pasos 1 a 3 y F45 pasos 2 a 4;
> - **ola 2**: F44 pasos 4 y 5 y F45 paso 5;
> - **ola 3**: F45 paso 1, los avisos. Va solo al final porque toca los 179 avisos de toda la app.
>
> **Segunda tanda del 30/10 (mejoras 12 a 16): APROBADA** (2026-10-30, «Aprobado» en el chat, con las decisiones F a H como están). Pedido del dueño con siete
> capturas: *"También quería agregar una mejora…"*. Entra como el paso 7, en la ola 2, después de
> integrar los pasos 3 y 4: toca las mismas pantallas de Procesado y de la Biblioteca.
>
> **Tercera tanda del 30/10 (mejoras 17 a 19): APROBADA** (2026-10-30, con la decisión I como está). Pedido del dueño con dos capturas
> más y las notas en el texto. Entra como los pasos 7c (en la ola 2) y 8 (en la ola 3, sobre el
> lector y el original ya unificados).

## Las once mejoras

### 1. Los avisos de abajo: ordenados, con su ✕ siempre y por encima de todo (1.ª captura)

**Lo que pasa hoy.** «Procesado actualizado: Historia de Heródoto…» con «Ver» al lado del texto,
y «Deshacer» y la ✕ en un renglón aparte, con aire sin sentido. El aviso común (`AppSnackBar`,
F43 M1) admite **un** botón; los que necesitan dos meten el segundo adentro del texto, y Material
los acomoda como puede. Además, el **lector flotante** (el botón redondo de «Leer en voz alta»,
F25) va por encima de toda la app y tapa la ✕.

**Qué se hace.**

- Un solo aviso para toda la app, con **el texto a la izquierda** (hasta tres renglones), **uno
  o dos botones** alineados a la derecha («Ver», «Deshacer») y **la ✕ siempre**, en todos los
  avisos (también los cortos: decisión A).
- Si no entra en un renglón, los botones bajan **juntos**, alineados a la derecha, con la ✕
  arriba a la derecha, como una tarjeta: nunca un hueco en el medio.
- **El lector flotante se corre para arriba** mientras hay un aviso, como un botón flotante de
  Android: el aviso se ve entero y nada tapa la ✕.
- Se pasan **los 179 avisos** de la app al aviso común. El censo de avisos que ya existe
  (`snack_bar_census_test`) exige que ninguno quede afuera.

### 2. «¿Qué va a Procesado?»: el original primero, las imágenes plegadas y el texto al final (2.ª)

- **Orden nuevo:** **El original** → **Imágenes** → **Texto extraído**.
- **Imágenes, plegada**: una fila compacta —«Imágenes · 40 · 4,1 MB · 0 elegidas ▸»— que se
  despliega con la flecha y recién ahí muestra la grilla con «Todas» y «Ninguna».
- **Texto extraído, con la IA de turno** (ver la decisión B): al prenderlo, dice qué IA lo va a
  hacer («Lo extrae Gemini» o «Gemma, en el teléfono») y, al tocar «Listo», la IA arma el texto
  en segundo plano, con el aviso de la cola de siempre.

### 3. La vista previa de una imagen: «Ampliar» en el medio, como el PDF (3.ª)

El botón de las flechitas, hoy en la esquina, pasa **al centro** de la imagen con la píldora de
«Leer como libro» del PDF (el mismo componente, no una copia), con el texto **«Ampliar»**.

### 4. Fuera «Leer» (y su pantalla) en la Biblioteca (4.ª)

La pantalla de lectura del texto extraído («Ninguna nota extraída», «Seleccioná un fragmento…»)
deja de abrirse desde la Biblioteca. Leer, marcar y sacar notas del texto se hace en Procesado. La
pantalla **no se borra**: la sigue usando Procesado.

### 5. El texto en árabe de un video en español (5.ª): la causa de raíz

**Lo que se sabe.** El texto de Procesado es una copia del de la Biblioteca, y el de un video sale
de dos caminos:

- de los subtítulos de YouTube;
- si no hay en qué confiar, de la transcripción del audio en el teléfono.

F22 ya había cerrado un caso así: un video en español con subtítulos subidos en árabe. Desde
entonces nunca se baja una pista en un idioma que no sea el que se habla. Que vuelva a pasar quiere
decir que hay **otro** camino que lo deja entrar, por ejemplo:

- un video **doblado con IA**, cuyo audio «de siempre» YouTube marca en árabe;
- el idioma del título adivinado mal;
- la transcripción del teléfono sin el idioma fijado;
- o una captura anterior a F22.

**Qué se hace.**

1. **Diagnóstico con el video real**: se lee del teléfono solo ese elemento (su enlace y de qué
   pista salió; nada más de la base) y se repite la bajada en la PC. Con la causa a la vista se
   arregla donde está.
2. **Una red de seguridad, pase lo que pase**: antes de guardar un texto de un video, se compara
   su escritura y su idioma con el idioma que se habla. Si no coinciden —árabe en un video en
   español—, **no se guarda**: se transcribe el audio en el teléfono con el idioma fijado, y el
   aviso lo dice.
3. **Arreglar lo ya guardado**: la Bandeja y Procesado ofrecen «Volver a extraer» en los videos
   cuyo texto no está en su idioma, y se puede pedir para todos de una vez.
4. **Nunca un texto inventado**: el texto de un video sale de los subtítulos o del audio, nunca de
   una IA que lo escriba. Si la decisión B hace que una IA ordene el texto, cada palabra se
   comprueba contra lo transcripto (ver B).

### 6. Fuera «Escuchar» de la sección «Texto» de Procesado (6.ª)

Sale el botón de la cabecera de la tarjeta «Texto». **Escuchar sigue** en el lector flotante de
abajo, que lee lo que está en pantalla: es la misma función en un solo lugar.

### 7. Una página web en Procesado, como en el teléfono; y la barra de Resumen y Síntesis (7.ª)

- **Vista móvil**: la página se muestra con el ancho del teléfono (la vista de un navegador móvil,
  sin el menú lateral ni las columnas de escritorio de Wikipedia), no achicada.
- **La barra de arriba, rehecha**:
  - hoy son tres botones grandes («Resumen · Sin hacer», «Síntesis…», «Palabras clave…») y una
    leyenda repetida debajo;
  - pasan a **una sola fila de tres fichas compactas**, del mismo alto, cada una con su color, su
    estado («Hecho», «Sin hacer», «Haciendo…») y un toque para crearla o verla;
  - la leyenda de colores se integra en las mismas fichas (el punto de color es la leyenda);
  - en 360 dp con la letra al doble pasan a dos renglones sin cortarse.

### 8 y 9. La Biblioteca, solo con el original (8.ª y 9.ª)

En el detalle de **cualquier** documento de la Biblioteca salen:

- la fila **Leer · Copiar · Más** (9.ª);
- la tarjeta **«Estudiar el documento»** con Resumir, Sintetizar, Palabras clave, Descargar y
  «Extraer texto» (8.ª).

Se queda **«Se estudia en Procesado… Estudiarlo en Procesado»**, que es la puerta a lo trabajado.

**Lo que había en «Más» no se pierde; cambia de lugar:**

| Antes, en «Más» | Ahora |
|---|---|
| Organizar con IA, buscar fechas | ya eran de Procesado (F41, decisión K) |
| Volver a extraer, quitar marcas de tiempo | en Procesado, sobre su texto |
| Soltar el texto de un libro | en Procesado |
| Pantalla completa | el «Ampliar» del centro de la vista previa (punto 3) |

### 10. La tarjeta de triar de la Bandeja y su barra (10.ª)

- **La barra de arriba**:
  - el ↶ de deshacer se confunde con «volver»; pasa a **«Deshacer» con el ícono de historial**
    (reloj con flecha) y su texto al costado en pantallas anchas;
  - «1 pendiente» queda como una ficha.
- **La tarjeta, ordenada por lo que se hace**:
  1. **La decisión** en una fila fija abajo, a lo ancho: **Descartar** (con borde) · **Triar**
     (relleno, la principal), del mismo alto y alineados.
  2. **Lo demás**, en un renglón de botones con ícono —«Pasar todo», «Extraer nota» y
     «Vincular»—; en angosto, en un menú «⋯».
  3. «Se encontraron datos de la referencia» como un aviso compacto dentro de la tarjeta, con
     «Usar» y la ✕.
  4. «Ver completo» al pie del texto, como un enlace.
  5. Los atajos de teclado solo en la computadora, en una línea gris.
- En 360 dp con la letra al doble, claro y oscuro, con el lector de pantalla.

### 11. La Infografía y la Presentación, más versátiles

Hoy (F43): 16 plantillas y 12 diseños de diapositiva; 18 estilos y 10 composiciones de infografía.

- **Presentación**:
  - **+12 plantillas** (Editorial, Suizo, Bauhaus, Pizarra, Revista, Académica, Minimal oscuro,
    Acuarela, Neón, Corporativa, Retro, Manuscrito);
  - **+8 diseños de diapositiva** (cita a toda página, línea de tiempo, comparación en dos
    columnas, número grande, cuadrícula de imágenes, proceso en pasos, mapa de conceptos, cierre
    con preguntas);
  - **personalizar**: la paleta (de la plantilla o una propia con un color de base), la pareja de
    letras, la densidad y el fondo (liso, degradado o con textura);
  - cambiar de plantilla en el visor, sin volver a llamar a la IA.
- **Infografía**:
  - **+12 estilos**;
  - **+6 composiciones** (línea de tiempo vertical, comparación, embudo, ciclo, mapa de temas,
    estadísticas en mosaico);
  - **+4 gráficos** (anillos, barras horizontales, pictograma y escala);
  - el mismo «personalizar» de colores, letras y fondo.
- Todo cabe en el teléfono, se exporta a PNG y PDF como hoy y respeta claro y oscuro.

## Segunda tanda del 30/10: las mejoras 12 a 16

### 12. Un solo lector para el texto, el resumen y la síntesis (1.ª, 2.ª y 3.ª capturas)

- **Hoy:**
  - en Procesado, la tarjeta «Texto · 6 páginas» se despliega ahí mismo, con su paginador, el texto
    crudo (con los enlaces de Wikipedia a la vista: `[concilio ecuménico](https://…)`) y el botón
    flotante del lector;
  - el resumen y la síntesis de Repasar se abren en otro lector, el de «Lo creado»
    (`ExtractViewer`): la barra con 🎧, el tamaño de letra y ⋮, «Ver 1 fuente», el título
    grande, el texto como papel y su propio reproductor.
- **Cambio:**
  - tocar «Texto» en Procesado abre **exactamente ese mismo lector**, con lo mismo arriba y en el
    mismo orden, rotulado «Texto · N páginas» en vez de «Resumen · N oraciones»;
  - el texto se muestra **limpio**: los enlaces quedan como palabras, sin la dirección, y las
    imágenes no se ven como `![](…)` (punto de partida, la mejora 2 del triaje);
  - cada sección de un procesado se abre igual, sea «Texto», «Resumen» o «Síntesis»;
  - **un solo dictado de voz**: el de 🎧 del lector, el mismo en los tres, y sin el botón
    flotante en esas pantallas;
  - **el original no cambia**: sigue con su lector flotante y sus marcas (mejora 16).
- No crea nada en «Lo creado»: es una vista del texto procesado, que se puede editar y marcar como
  hoy.

### 13. El desplazamiento del lector, que baja de golpe (3.ª)

- **Hoy:** en el resumen, un arrastre corto con impulso baja muchísimo de una vez.
- **La causa probable:** ese lector usa `ReadingScrollPhysics`, que multiplica por 1,5 el impulso
  al soltar. Se hizo para pasar hojas de un PDF o de un libro (F25), no para leer un texto de
  corrido.
- **Cambio:**
  - se confirma la causa con una prueba que mide cuánto recorre un mismo gesto;
  - el texto de corrido vuelve a la física de la plataforma;
  - el impulso extra queda solo donde se pasan hojas;
  - si además el texto salta porque la lista calcula mal el alto de un bloque largo, se arregla
    también, sin parches.

### 14. Lo que se crea, con IA o a mano, en un solo lugar (4.ª y 5.ª)

- **Hoy hay cuatro lugares para crear algo del mismo documento:**
  - arriba, ✨ (nota derivada) y el ícono del cuestionario, cada uno con su ruedita mientras
    trabaja;
  - en ⋮, «Organizar con IA» y «Buscar fechas con IA»;
  - abajo, en «Tarjetas de repaso», la ruedita de la IA y el «+» a mano.
- **Cambio, un botón «Crear» arriba (✨)** que abre una hoja con dos grupos:
  - **Con IA**: Organizar (temas, vínculos y tarjetas), Tarjetas de repaso, Cuestionario, Nota
    derivada y Buscar fechas;
  - **A mano**: Tarjeta, Nota y Vínculo;
  - cada fila dice qué hace y, si está trabajando, cómo va («Leyendo la parte 1 de 2…»), con
    «Cancelar»;
  - mientras algo trabaja, el ✨ de arriba lleva un anillo de progreso, en vez de dos ruedas
    sueltas;
  - ⋮ queda solo con lo que no crea nada («Borrar la copia del original»);
  - la sección «Tarjetas de repaso» de abajo queda para ver y repasar: su «+» y su ruedita se
    mudan a la hoja.
- Igual en el documento de la Biblioteca, si conserva alguno de esos botones después de la mejora
  8.

### 15. Las marcas del original, adentro del original (6.ª)

- **Hoy:** en la tarjeta del original de Procesado, arriba de la vista previa, están «Resumen ·
  Sin hacer», «Síntesis · Sin hacer», «Palabras clave · Sin hacer» y la leyenda de colores.
- **Cambio:**
  - en el detalle queda solo la vista previa con «Ver la página» (o «Ver el documento»);
  - la barra de las marcas va **adentro**, al abrirlo a pantalla completa, donde se marca;
  - en la vista previa, un renglón chico dice qué tiene marcado («Resumen · Palabras clave»).

### 16. El original, idéntico en Procesado y en la Biblioteca (7.ª)

- **Hoy:**
  - el original de Procesado abre con su barra (`OriginalStudyBar`) y el lector flotante con
    «Leer: Todo · Resumen · Síntesis · Palabras clave»;
  - el de la Biblioteca abre con otra barra (`StudyBar`) y otro arreglo.
- **Cambio, una sola pantalla de original para los dos:**
  - la misma barra de arriba, ya rehecha (la de la mejora 7: tres fichas compactas con su color y
    su estado);
  - el mismo lector flotante, con las mismas opciones;
  - el mismo visor (PDF, página o lector).
- **Cada uno marca lo suyo, como hoy:**
  - el de la Biblioteca, sobre la fuente;
  - el de Procesado, sobre su copia;
  - nada de uno pinta al otro, y de la Biblioteca nada se borra.
- En los dos se puede tener el resumen, la síntesis y las palabras clave del original. Lo que
  sale de la Biblioteca con la mejora 8 es la tarjeta «Estudiar el documento» del **detalle**: sus
  botones viven ahora adentro del original.

## Tercera tanda del 30/10: las mejoras 17 a 19

### 17. «49 elementos sin tema», en su lugar (1.ª captura)

- **Hoy:** una tarjeta grande arriba de la lista de la Biblioteca, con el texto que explica y
  «Ordenarlos». Empuja la lista hacia abajo cada vez que se abre la Biblioteca.
- **Cambio:**
  - pasa a ser **una ficha más del panel de estado** de arriba (el de la Bandeja, lo procesado y
    los vínculos), con su ícono de carpeta tachada y el número: «49 sin tema». Un toque abre la
    lista para ordenarlos, como hoy;
  - desplegado, el panel la explica en una línea («Elegiles uno o varios temas: así se encuentran,
    y aparecen en el Mapa y el Atlas») con «Ordenarlos»;
  - en **Organizar**, que es donde se ordena, la misma cuenta como una tarea más, con «Ordenarlos»;
  - en el Mapa ya están, en la burbuja «Sin tema» (F44).
- Sin nada sin tema, la ficha no se muestra.

### 18. «Volver a triar» y «Volver a la Bandeja», a la vista y ordenados (2.ª)

- **Hoy:** debajo del título de una fuente, «Triado el 10 oct» y dos enlaces sueltos («Volver a
  la Bandeja» y «Volver a triar»), en dos renglones desparejos. Se pierden.
- **Cambio, una tarjeta propia, «Bandeja»**, del ancho de la pantalla:
  - arriba, el estado con su ícono: «✓ Triado el 10 oct» (o «En la Bandeja»);
  - debajo, **dos botones del mismo alto, uno al lado del otro**:
    - «Volver a triar», relleno, con su ícono de triar: es lo que más se usa;
    - «Volver a la Bandeja», con borde y el ícono de la Bandeja (no la flecha de deshacer, que se
      confunde con «volver»);
  - en 360 dp con la letra al doble, uno debajo del otro, a lo ancho;
  - en lo que todavía está en la Bandeja, un solo botón: «Triar ahora».

### 19. Notas en cualquier parte del texto, como en Adobe Reader o en Word

- **Dónde:**
  - en todos los originales, en la Biblioteca y en Procesado: PDF, libros (EPUB, Word, texto),
    páginas web y transcripciones;
  - en el texto extraído, el resumen y la síntesis (el lector único de la mejora 12).
- **Cómo se pone una:**
  - se elige un pedazo de texto (o se mantiene apretado un párrafo) y, en la barra que aparece,
    **«Nota»**;
  - se escribe en una tarjeta que se abre ahí mismo, con su color (los cinco de resaltar) y
    «Listo»; se guarda sola mientras se escribe.
- **Cómo se ve, siempre prolija:**
  - el pedazo elegido queda con un subrayado fino punteado del color de la nota;
  - en el margen, a la altura del párrafo, **un globito** con el color de la nota (y un número si
    hay varias en el mismo renglón), que no tapa el texto;
  - tocarlo despliega la nota en una tarjeta flotante con sombra suave, la fecha, «Editar»,
    «Cambiar color», «Copiar» y «Borrar» (con «Deshacer»);
  - en un PDF, el globito va sobre la página, al costado del renglón, como el ícono de nota de
    Adobe, y sigue a la página al acercar o alejar;
  - en una página web, el globito va al costado del párrafo, dentro de la página;
  - en angosto, el margen se corre: el globito queda al final del renglón, chico.
- **Para encontrarlas:**
  - un ícono «Notas (N)» en la barra del documento abre la lista de sus notas, en el orden del
    texto, con el pedazo citado; tocar una lleva a su lugar y la abre;
  - la búsqueda de la Biblioteca y el chat también las encuentran (son texto de la persona).
- **De quién es cada nota:**
  - la del original de la Biblioteca, de la fuente;
  - la del original de Procesado, de su copia: nada de uno aparece en el otro (decisión H);
  - de la Biblioteca nada se borra: las notas se agregan, nunca tocan el documento.
- **Si el texto cambia** (se vuelve a extraer), cada nota se reubica por el pedazo citado, como
  los resaltados; si ya no se encuentra, queda en la lista como «Sin lugar», nunca se pierde.
- **Al descargar marcado** (F38), las notas van como notas del PDF (las que se abren con un
  toque en cualquier lector) y, en el texto, como notas al pie.
- Se ve bien en claro y en oscuro, con «sin animaciones» (aparece sin deslizarse), con el lector
  de pantalla («Nota: …» al pasar por el párrafo) y en 360 dp con la letra al doble.

## Decisiones (se pueden cambiar mientras no se llegue a su paso)

- **A. La ✕ en todos los avisos**, también en los cortos («Copiado»). Pedido literal: «para que se
  pueda sacar siempre». Cambia la regla de F43 M1, que la ponía solo en los largos o con botón.
- **B. «Texto extraído» al triar: la IA de turno lo arma, con la extracción de siempre como
  base.** *(Elegida por el dueño el 30/10.)*
  - **Recomendada:**
    - la app sigue sacando el texto por su cuenta, como hoy, pero ya no se muestra en la
      Biblioteca; lo siguen usando por dentro la búsqueda, el chat y los vínculos;
    - al elegir «Texto extraído» al triar, la IA de turno lo **ordena**: une las columnas, saca
      encabezados y pies de página repetidos, arregla los cortes y marca los títulos;
    - cada palabra se comprueba contra la extracción: si la IA inventa, resume o traduce, se queda
      la extracción tal cual y el aviso lo dice.
  - *Alternativa:* que la IA lea el archivo desde cero (Gemini, OpenAI y Claude leen PDF e
    imágenes). No la recomiendo: cuesta mucho más con un libro, no anda con Gemma en el teléfono,
    y es justo lo que puede inventar o traducir (punto 5).
- **C. El lector flotante se corre arriba del aviso**, en lugar de esconderse: sigue a la vista y
  a un toque.
- **D. La web en Procesado se muestra con el ancho del teléfono** también en la computadora,
  dentro de su tarjeta.
- **E. Nada se borra de la Biblioteca** (la regla de siempre): sale lo que se **muestra**, no los
  datos. El texto extraído de cada fuente sigue guardado.

- **F. El texto de un procesado se abre en el lector de «Lo creado»**, como vista del texto (sin
  crear una fila en «Lo creado»). *Alternativa:* rehacer la tarjeta desplegable con el aspecto
  del lector; no la recomiendo, porque serían dos lectores que mantener iguales a mano.
- **G. Un solo «Crear» arriba, con «Con IA» y «A mano»**. *Alternativa:* dejar los botones donde
  están y solo alinearlos; no la recomiendo, porque seguirían siendo cuatro lugares.
- **H. Una sola pantalla de original para Procesado y la Biblioteca**, con lo de cada uno por su
  propia clave, como hoy. La barra es la de la mejora 7.
- **I. Las notas en una tabla propia, `text_notes`**, para todos los textos. Cada nota guarda a
  qué texto pertenece (el original de la Biblioteca, la copia de Procesado, el texto procesado o
  una creación), su lugar, el pedazo citado, la nota y el color. Así se ven y se comportan igual
  en todos lados. Un resaltado de antes que ya tenía su nota (F38) se muestra con el mismo
  globito, sin migrarlo. *Alternativa:* guardarlas como resaltados con un estilo «nota»; no la
  recomiendo, porque los resaltados solo existen sobre los originales, no sobre el resumen ni la
  síntesis.

## Pasos (cada uno, su commit y su push)

Una ola de cinco agentes en paralelo, cada uno en su rama, con su GUÍA, sus pruebas y sus
mutaciones; se integran en `main` de a uno, con su suite, su push y su verificación.

1. **Los avisos** (1, decisiones A y C): el aviso común con dos botones y la ✕, los 179 avisos
   pasados a él con su censo, y el lector flotante que se corre.
2. **Triar** (2 y 10, decisión B): la hoja «¿Qué va a Procesado?» con el orden nuevo, Imágenes
   plegada y Texto extraído con la IA comprobada palabra por palabra; la tarjeta y la barra de la
   Bandeja.
3. **La Biblioteca, solo el original** (3, 4, 8 y 9, decisión E): «Ampliar» en el medio, fuera
   «Leer», la fila de acciones y «Estudiar el documento», y lo de «Más» mudado a Procesado.
4. **Procesado** (5, 6 y 7): el diagnóstico del árabe con el video real, la red de seguridad del
   idioma, «Volver a extraer» para lo ya guardado, fuera «Escuchar», la web en vista móvil y la
   barra de Resumen y Síntesis.
5. **El diseño** (11): las plantillas, diseños, estilos, composiciones y gráficos nuevos, y
   «Personalizar» en la Presentación y la Infografía.
6. **El cierre**: la suite entera, la decisión 91 en arquitectura, la GUÍA y la APK al teléfono si
   la pedís.
7. **La segunda tanda** (12 a 16, decisiones F a H), en la ola 2, cuando estén los pasos 3 y 4. Lo
   hacen dos agentes:
   - **7a**: el lector único del texto y el desplazamiento (12 y 13);
   - **7b**: «Crear» en un solo lugar, las marcas adentro y el original idéntico (14, 15 y 16);
   - **7c**: «Sin tema» en el panel de estado y en Organizar, y la tarjeta «Bandeja» de una fuente
     (17 y 18).
8. **Las notas en el texto** (19, decisión I), en la ola 3, sobre el lector único y el original ya
   unificados: la tabla con su migración, poner y ver una nota en el lector, en el PDF, en los
   libros y en la web, la lista «Notas (N)», la búsqueda y el chat, reubicarlas y descargarlas.

## Lo que no entra (para que quede dicho)

- **Borrar el texto extraído que ya está guardado** en la Biblioteca: deja de mostrarse, no se
  borra (decisión E).
- **Traducir**: ningún texto extraído se traduce; siempre queda en el idioma de la fuente.

## Avance

(vacío: se llena con cada paso)
