# F38 — Resaltar a mano con colores, y descargar el documento resaltado en su formato

> **Estado: APROBADO** (2026-10-22, *«F38 aprobado»* en el chat). Va después de F37.
>
> Pedido: *"que dentro del documento tenga opciones para pintar o subrayar manualmente lo que yo
> quiera en el documento original, o para destacar una parte y que me deje elegir el color, y que
> sea elegante e interactivo y que me deje copiar, escuchar dictado de voz de lo que seleccione y
> demás opciones, y que a su vez me deje descargar el documento de resumen (original con
> resaltado) o el documento de síntesis (original con resaltado) o documento con palabras claves
> resaltadas, según lo que seleccione, pero que me lo deje descargar en el mismo formato que ya
> está el documento"*.

> **Ampliado** (2026-10-22), a pedido: que valga para todo documento de texto, en el formato que
> sea —incluso EPUB— y también para las **páginas web**, descargadas en su formato original: el HTML
> que la app archivó al guardarlas.

## Lo que hay hoy (relevado en el código)

| Qué | Cómo está |
|---|---|
| **Subrayar** | En «Texto extraído» se selecciona y el menú ofrece Copiar, Leer en voz alta, Resaltar (con nota), Extraer como nota y Hacer tarjeta. **Un solo color**, y no se puede subrayar con una línea. En el lector de Word, EPUB y texto (embebido y «Leer como libro») el menú solo tiene Copiar y Leer en voz alta. |
| **PDF** | Se selecciona arrastrando sobre el PDF real (`pdf_drag_selection.dart`), con Copiar. No se resalta ahí. |
| **Lo estudiado (F36)** | Resumen verde, síntesis celeste y palabras clave rosa, pintados sobre el texto, y en el paso 5 sobre las letras del PDF. |
| **Para escribir archivos** | `pdfium_dart` —la misma biblioteca que ya muestra los PDF— trae lo necesario para **agregarle resaltados de verdad a un PDF** (anotaciones) sin tocar su texto. `archive` y `xml`, que ya están en el proyecto, permiten tocar un Word o un EPUB por dentro. |

## Qué se construye

### 1. Resaltar y subrayar a mano, con color

- Al seleccionar un fragmento **en cualquier lugar del documento** —el PDF real, el lector de Word,
  EPUB y texto, la página web archivada y «Texto extraído»— aparece una barrita elegante sobre la
  selección:
  - **una fila de colores** para resaltar, como en Word;
  - **Subrayar**, con una línea del color elegido;
  - **Copiar**, **Escuchar** (lee en voz alta lo seleccionado), **Nota**, **Extraer como nota** y
    **Hacer tarjeta**.
- Tocar algo ya resaltado abre su ficha chica: cambiarle el color, pasarlo a subrayado, escribirle
  una nota o borrarlo.
- Lo que resaltás a mano y lo de F36 conviven. El resaltador va **encima de las oraciones** y
  **debajo de las palabras clave**, y lo que se lee en voz alta, por encima de todo.
- Tus resaltados de siempre quedan como están, con el color de hoy.

### 2. Descargar el documento resaltado, en su formato

- En la tarjeta «Estudiar el documento» (F36), un botón **Descargar** ofrece:
  - **con el resumen resaltado**;
  - **con la síntesis resaltada**;
  - **con las palabras clave resaltadas**;
  - **con mis resaltados**.
  - Se pueden combinar: por ejemplo, el resumen y además tus resaltados.
- Sale **en el mismo formato que el original**, con el nombre del original más lo elegido (por
  ejemplo, *«Historia — resumen.pdf»*):
  - **PDF**: el mismo PDF con resaltados de verdad, de los que cualquier lector de PDF muestra y
    deja borrar. El texto sigue siendo seleccionable, porque no es una foto de las páginas.
  - **Word (.docx)**: el mismo documento, con el resaltado de Word en esas partes.
  - **EPUB**: el mismo libro, con esas partes coloreadas.
  - **Página web**: la página archivada (.html), con esas partes resaltadas, que se abre en
    cualquier navegador sin conexión.
  - **Texto (.txt) y Markdown**: ver la decisión C.
- Se guarda donde elijas, con el selector de archivos del sistema, o se comparte.

## Decisiones para que confirmes

- **A.** Los colores del resaltador a mano son **amarillo claro, naranja, violeta y turquesa**,
  más el subrayado. Son distintos del verde, el celeste y el rosa de F36, para no confundir
  «lo marqué yo» con «lo marcó la IA». El amarillo fuerte sigue siendo solo de lo que se lee en
  voz alta.
- **B.** El PDF descargado lleva **anotaciones de resaltado** (las del estándar), no una copia
  dibujada de las páginas.
- **C.** Un texto suelto (.txt) **no tiene cómo guardar un color**. Propongo descargarlo como **el
  mismo texto en .docx**, con los resaltados de Word. La otra opción es un .txt con lo resaltado
  entre marcas, como «⟦así⟧». Un Markdown sale en Markdown, con `==resaltado==`.
- **D.** Un PDF **escaneado** (fotos de páginas) no tiene letras donde resaltar. Ahí el PDF
  descargado lleva el resaltado como un recuadro de color en el lugar aproximado de la línea.

## Pasos (cada uno, su commit y su push)

1. **Prueba técnica del PDF**: agregarle un resaltado a un PDF de prueba con `pdfium_dart` y
   leerlo de vuelta. Es lo único con riesgo; si no anduviera, te lo cuento antes de seguir.
2. **Dónde se guarda**: el color y el estilo de cada resaltado (esquema nuevo, después del de F37),
   con la migración, la unión de bóvedas y la papelera. Pruebas y mutación.
3. **La barrita y la ficha** en «Texto extraído» y en el lector de Word, EPUB y texto. Pruebas de
   widget y mutación.
4. **Resaltar sobre el PDF real y la página web**, con la misma barrita, usando la ubicación de
   las letras y de las marcas de F36. Pruebas.
5. **Descargar**: PDF, Word, EPUB, página web, texto y Markdown, cada uno con su prueba sobre un
   archivo real chico. Mutación.
6. **Cierre**:
   - GUIA_DE_USO, la decisión en `docs/arquitectura.md`, CONTEXTO y el «Avance» de este plan;
   - suite entera y `verify_commit`.
   - APK al teléfono solo si la pedís.

## Avance

### Paso 1 (hecho): la prueba técnica del PDF salió bien

- `PdfMarkWriter` (`lib/features/export/data/marked/`) le agrega a un PDF resaltados y subrayados
  de verdad: las anotaciones `Highlight` y `Underline` del estándar.
  - Cada una lleva su color, un cuadrilátero por renglón, la nota (si tiene) y la marca de
    imprimir.
  - Lleva también su **apariencia**, el dibujo ya armado. Desde PDF 2.0 es obligatoria, y sin ella
    un lector que no sabe armarla no muestra el resaltado. La genera el propio PDFium, con el modo
    de mezcla que deja ver las letras debajo.
- Se guarda **agregando al final** del archivo: lo que había queda byte por byte, así que es el
  mismo PDF, con su firma si tenía, más los resaltados. El texto se sigue extrayendo igual.
- Lo que no era obvio:
  - `pdfrx_engine` no envuelve las anotaciones, así que se llama a PDFium directo (`pdfium_dart`,
    que ya venía con `pdfrx_engine` en la misma versión, ahora declarado).
  - Tiene que ser **en el hilo de PDFium de `pdfrx`** (`PdfrxEntryFunctions.compute`). Ahí `pdfrx`
    registró sus funciones para buscar fuentes, y PDFium las llama al armar la apariencia. Desde
    el hilo principal, el proceso se cae.
  - Una página que no existe se rechaza antes de mandar el trabajo a ese hilo, porque desde ahí los
    errores vuelven envueltos.
- Pruebas (`pdf_mark_writer_test.dart`, 9, sobre un PDF real chico):
  - se lee de vuelta tipo, renglones, nota, apariencia y marca de imprimir;
  - al pintar la página, el lugar resaltado toma el color exacto y el resto sigue blanco, y el
    subrayado es una línea, no un fondo;
  - varios renglones, varias páginas, el original byte por byte, el texto intacto y una página que
    no existe.
- Mutación: 11/11.

### Paso 2 (hecho): dónde se guarda el color y el estilo

- Los colores (`HighlightColor`: amarillo claro, naranja, violeta, turquesa) y los estilos
  (`HighlightStyle`: fondo o subrayado) están en `lib/core/domain/entities/`. Los usan la app y lo
  que se descarga: el escritor de PDF del paso 1 dejó su propio tipo y usa este.
- **Esquema v42**: `highlights` gana `color` (vacío = el color de siempre) y `style` (por defecto,
  fondo). Es aditiva, así que todo subrayado de antes queda igual. Los conteos de todo son
  compuerta.
- `OrganizeRepository` crea con color y estilo, y suma `updateHighlightLook` para cambiarlos sin
  tocar la nota ni el tramo.
- **Papelera**: el JSON de los subrayados soltados guarda las dos cosas. Lo soltado antes vuelve con
  el color de siempre y de fondo.
- **Unión de bóvedas**: las dos columnas viajan. Como la nota, un resaltado que ya está en las dos
  no se pisa: entra solo el que falta.
- Pruebas: la migración 41→42 (`migration_v42_test.dart`), el repositorio, la papelera (ida y
  vuelta, y lo soltado antes) y la unión.
- Mutación: 13/13. La que sobrevivió al principio —cambiar uno que ya no existe daba un fallo
  genérico en vez de decir que se borró— la mata ahora una prueba que mira el mensaje.
- El tono de cada color, en los dos temas y en lo que se descarga, está en `HighlightPalette`
  (`lib/core/design/`). Sin color, el de siempre.


### Paso 3 (hecho): la barrita y la ficha, en «Texto extraído» y en el lector

- **La barrita** (`HighlightToolbar`, `lib/core/design/`): sobre la selección, una fila con los
  cuatro colores (resaltan de fondo, sin preguntar nada), **Subrayar** (línea del último color
  elegido, o el primero) y debajo Copiar, Escuchar, Nota, Extraer como nota y Hacer tarjeta.
  Compartir, Seleccionar todo y Buscar en la Web quedan detrás de «Más opciones», para no perder
  lo de siempre. No depende de un texto seleccionable: recibe dónde está la selección en la
  pantalla (`TextSelectionToolbarAnchors`) y un callback por botón —el que no tiene, no se
  dibuja—, para que la usen también el PDF real y la página web (paso 4).
- **La ficha** (`showHighlightCard`): al tocar algo ya resaltado, desde abajo: cambiarle el color,
  pasarlo de fondo a subrayado o al revés (se ve al instante), escribirle la nota o quitarlo.
- **Un lugar para lo que comparten** (`organize/presentation/hand_highlighting.dart`): resaltar,
  resaltar con nota, extraer como nota, hacer tarjeta y abrir la ficha, que antes vivían dentro de
  `HighlightableText`, ahora los usan también el lector de Word, EPUB y texto (en «Leer como
  libro» y embebido).
- **Los mismos resaltados en los dos lados.** El lector ya sabía de qué texto es lo que muestra
  (`StudyText`, de F36), pero no de qué elemento: ahora lo lleva (`itemId`), y con eso guarda los
  resaltados, extrae notas y hace tarjetas **en posiciones del texto extraído**, aunque cada página
  sea un tramo de él. Sin ese texto —un adjunto— no hay dónde guardar nada, y queda el menú de
  siempre.
- **Pintado**: cada resaltado con su color y su estilo; los de antes, con el color de siempre. De
  abajo hacia arriba: las oraciones de lo estudiado, lo que subrayó la persona, las palabras clave y
  lo que suena en voz alta. La línea de un subrayado se oscurece en el tema claro
  (`HighlightPalette.line`): con el tono de resaltador, clarísimo, casi no se veía.
- Eligiendo palabras clave, un toque es para elegirlas y no abre la ficha.
- Pruebas: la barrita sola (10), la ficha sola (8), el pintado (7 en `buildSpans`, 3 de la línea),
  `HighlightableText` (31, de las que 24 son nuevas) y el lector (15), más una de punta a punta en el
  detalle. Mutación: 26/26.

### Paso 5 (hecho): descargar el documento marcado, en su formato

- **Botón «Descargar»** en la tarjeta «Estudiar el documento». Abre una hoja con cuatro opciones
  que se combinan:
  - con el resumen;
  - con la síntesis;
  - con las palabras clave;
  - con mis resaltados.
- Las opciones sin datos aparecen deshabilitadas y dicen por qué. La hoja arranca con lo que ya se
  ve resaltado.
- El nombre sale como «Historia — resumen y mis resaltados.pdf».
- Se guarda con el selector del sistema. **Compartir no está**: la app no tiene cómo pasarle un
  archivo a otra app, y no se agregó una dependencia para eso. En Android, el selector ya deja
  elegir Drive y otras apps.
- El botón solo aparece si el original es de un formato que se sabe marcar. El formato se
  reconoce por los bytes, no por el nombre.
- **Las capas**, de abajo hacia arriba: el resumen, la síntesis, mis resaltados (el más reciente
  arriba) y las palabras clave. Es la misma regla de F36, ahora en
  `study_layers.dart`, que usan la pantalla y la descarga.
- **Cada formato** (`lib/features/export/data/marked/`, con un adaptador por formato en
  `marked_document_writers.dart`):
  - **PDF**: anotaciones de verdad sobre las letras de cada página. En una página escaneada va
    un recuadro en el lugar aproximado del renglón (decisión D).
  - **Word**: el sombreado del color exacto en los runs, o el subrayado. La nota va como
    comentario de Word. Lo demás del archivo queda byte por byte.
  - **Texto suelto**: sale como Word con el mismo texto (decisión C).
  - **Markdown**: `==así==` y `<u>así</u>`, sin romper su sintaxis.
  - **EPUB**: un `<mark>` del color en su capítulo, recorriendo los capítulos igual que el
    extractor. `mimetype` queda primero y sin comprimir.
  - **Página web archivada**: un `<mark>` del color, y la nota en el `title`.
- **Dónde cae cada tramo** (`mark_locator.dart`): se busca por las letras y los números, no por
  la posición. El texto extraído de un Word, un EPUB o una página es Markdown armado a partir del
  archivo y no coincide con él. Un tramo que no se encuentra se saltea.
- Mutación: 36/38 (Word, texto y Markdown: uno equivalente y uno de código que nunca se
  ejecutaba, que se borró), unos 54 en EPUB y página web con 3 equivalentes, 28/28 en la hoja y
  el caso de uso, y 10/10 en los adaptadores.
