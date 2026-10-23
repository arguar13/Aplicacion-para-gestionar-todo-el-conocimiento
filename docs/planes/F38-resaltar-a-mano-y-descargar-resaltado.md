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
