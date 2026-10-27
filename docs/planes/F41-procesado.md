# F41 — «Procesado»: todo lo que ya pasó por la Bandeja, como una Biblioteca

> **Estado: PROPUESTO** (2026-10-27). Se aprueba escribiendo «aprobado» en el chat.
>
> Pedido del dueño, con una captura de «Organizar»: *"En la pestaña Organizar, vamos a crear otra
> interfaz, debajo de la Bandeja y arriba de la Línea de tiempo, que sea igual a la Biblioteca pero
> donde vaya todo lo procesado o tirado"*.
>
> Respuestas del dueño a las dos preguntas previas:
> - Lo resuelto **sigue también en la Biblioteca**: «Procesado» no esconde nada, junta.
> - El nombre es **«Procesado»**.

## Lo que hay hoy

- La **Bandeja** muestra de a una las fuentes que ya tienen texto. Cada una se resuelve con
  **«Triado»**, **«Descartar»**, **«Extraer nota»** o **«Vincular a nota viva»**. Las dos últimas,
  y «Revisar sugerencias», también la dejan triada (`InboxStatus.triaged`). Descartar la deja
  `discarded`. Nada se borra.
- Lo resuelto **sigue en la Biblioteca**, mezclado con todo. Solo se encuentra con **Filtros →
  «Bandeja» → Triado / Descartado**. El detalle de cada fuente dice «Triado el 3 oct» y ofrece
  «Volver a la Bandeja».
- **Cuándo se resolvió** ya se sabe: sale de la versión por campo de `state` (F11, F28), sin
  columna nueva.
- La Biblioteca tiene **un solo estado de filtros para toda la app** (`libraryQueryNotifierProvider`).

## Qué se construye

### 1. Un destino nuevo en «Organizar», entre Bandeja y Línea de tiempo

**Bandeja · Procesado · Línea de tiempo · Atlas · Mapa · Cuadernos**, con su ícono y la línea que
dice para qué sirve: *«Lo que ya revisaste en la Bandeja: triado y descartado»*.
- Es una rama nueva del shell, sumada **al final** del enum y del router para no correr índices,
  como el Atlas, los Cuadernos y la Línea de tiempo.
- Va también en el riel de escritorio.

### 2. La misma Biblioteca, no una copia

«Procesado» es **la pantalla de la Biblioteca** en otro espacio. Tiene lo mismo:
- la lista y las filas;
- el buscador;
- los filtros;
- la selección múltiple y sus acciones;
- las vistas guardadas;
- los mismos gestos.

Todo lo que se mejore en una mejora en las dos. Lo que cambia:
- **Su base:** solo lo triado y lo descartado. Arriba van tres chips: **Todo · Triado ·
  Descartado**. El filtro «Bandeja» de los Filtros sobra ahí y no se muestra.
- **Su propio estado de filtros.** El estado de la Biblioteca pasa a ser uno por espacio
  (`LibrarySpace.all` / `LibrarySpace.processed`). Buscar o filtrar en una no toca la otra, y cada
  una recuerda lo suyo al volver.
- **Su orden por defecto:** lo **resuelto más recientemente** arriba. Es un orden nuevo,
  «Cuándo se revisó», que sale de la misma fecha del chip del detalle. Los demás órdenes siguen
  disponibles.
- **Cada fila dice cómo y cuándo se resolvió:** «Triado · 3 oct» o «Descartado · ayer».
  - Va como chip discreto, con un color por estado, que lo descartado se lea apagado sin
    perder contraste.
  - Si se extrajo una nota o se vinculó a una nota viva, se dice eso.
- **«Volver a la Bandeja»** está en el menú de cada fila y en la selección múltiple, con
  «Deshacer». Es la misma acción que ya está en el detalle.
- **Vacío:** *«Todavía no revisaste nada en la Bandeja»*, con un botón a la Bandeja.

### 3. La Biblioteca no cambia

Sigue mostrando todo, como respondiste, y su filtro «Bandeja» sigue igual.

## Decisiones (se pueden cambiar mientras no se llegue a su paso)

- **A. Una pantalla, dos espacios.** No se duplica `LibraryScreen`: recibe su espacio. Copiarla
  haría que las dos se separaran con cada arreglo.
- **B. Lo descartado se ve atenuado**, no escondido. Con el chip «Triado» queda fuera.
- **C. Sin insignia de cuenta** en «Procesado». La de la Bandeja dice lo que falta hacer, y
  esto ya está hecho. La decisión 81 sacó las insignias que no piden acción.
- **D. Las notas propias no entran.** Nunca pasan por la Bandeja, así que no tienen «procesado».

## Pasos (cada uno, su commit y su push)

1. **El espacio en el dominio:**
   - `LibrarySpace` y el estado de filtros uno por espacio;
   - la base de «Procesado» en el repositorio;
   - el orden «Cuándo se revisó».

   Todo puro y probado aparte, con el censo de órdenes y la persistencia de la consulta.
2. **La pantalla y el destino:**
   - la rama del shell;
   - «Organizar» con Procesado debajo de la Bandeja;
   - la Biblioteca en el espacio «Procesado» con los chips, la fila con cómo y cuándo, y el vacío;
   - el riel.
3. **Las acciones:** «Volver a la Bandeja» por fila y en lote, con «Deshacer». Las acciones de la
   selección múltiple que ya existen, revisadas en el espacio nuevo.
4. **Cierre:**
   - la GUÍA, la decisión en `docs/arquitectura.md`, CONTEXTO y el «Avance»;
   - la suite entera y `verify_commit`;
   - la APK al teléfono si la pedís.

## Avance

(Vacío hasta aprobarlo.)
