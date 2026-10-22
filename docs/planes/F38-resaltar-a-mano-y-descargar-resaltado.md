# F38 — Resaltar a mano con colores, y descargar el documento resaltado en su formato

> **Estado: para confirmar** (2026-10-22). Llegó junto con *"apruebo todos los planes"*, pero ese
> mensaje fue antes de que este plan existiera: confirmalo con *«aprobado»* cuando lo leas. Va
> después de F36 y F37, así que no frena nada.
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

Todavía nada: espera tu «aprobado», y va después de F36 y F37.
