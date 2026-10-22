# F37 — Todo lo que guardás, en un tema (y en varios, si querés)

> **Estado: aprobado, por construir** (2026-10-22). Aprobado en el chat: *"apruebo todos los
> planes"* —con las decisiones A–E tal como están—. Va después de terminar F36.
>
> Pedido: *"si es la primera vez que agrego un elemento que al elegir el elemento que quiero
> agregar o guardar en la biblioteca que me obligue a crear un tema así se guarde en ese tema
> creado y que los demás elementos que yo agregue se agreguen por defecto a ese tema si es que yo
> no creo otro tema, sino que me deje elegir el tema y a su vez me siga apareciendo la opción de
> crear un tema nuevo … así los elementos siempre están en un tema creado (que también permita que
> se guarden en varios temas si yo selecciono varios temas)"*.

## Lo que hay hoy (relevado en el código)

| Qué | Cómo está |
|---|---|
| **Un tema por elemento, como mucho** | El tema es una columna (`knowledge_entries.space_id`): un elemento está en uno o en ninguno. La tabla lo dice a propósito: «es una carpeta, no una marca». |
| **Al guardar** | El formulario de captura tiene el campo «Tema» (`SpaceField`), **optativo**. Arranca con el tema por el que está filtrada la Biblioteca, si hay uno. |
| **Otras entradas** | Compartir desde otra app guarda sin preguntar nada, y sin tema. El editor de notas tiene su chip de tema, también optativo. Las notas derivadas no ponen tema. |
| **La IA** | «Elegir el tema» (F27) le pone uno a lo nuevo **que no tiene**, entre los que ya armaste, solo con certeza alta. Nunca crea uno. |
| **Dónde se usa el tema** | En 54 archivos: el filtro de la Biblioteca, el tablero por tema, la tabla, el Atlas («Temas»), el Mapa, la línea de tiempo, los cuadernos, el repaso por tema, la bibliografía, la exportación, los duplicados, la unión de bóvedas y su historial por campo. |

## Qué se construye

### 1. Varios temas por elemento

- Un elemento puede estar en **uno o en varios temas**. Aparece en cada uno: en el filtro de la
  Biblioteca, en cada columna del tablero, en cada rama «Temas» del Atlas y en el Mapa.
- Por dentro, el tema deja de ser una columna y pasa a una tabla propia elemento–tema, como ya
  pasa con los valores de las propiedades. La migración copia el tema de cada elemento: nada se
  pierde ni cambia de lugar.

### 2. Al guardar algo

- **La primera vez**, si todavía no tenés ningún tema, el formulario te pide crear uno antes de
  guardar. Es una tarjeta amable arriba del botón: *«Primero, un tema para empezar a ordenar»*,
  con un campo para el nombre. «Guardar» se habilita cuando hay un tema.
- **Las siguientes**, el campo «Temas» ya viene lleno con **los temas que usaste la última vez**.
  Si no cambiás nada, lo nuevo va ahí.
- **Elegir es fácil**: tocás el campo y se abre una hoja con tus temas para marcar uno o varios,
  un buscador, y siempre arriba **«Crear tema nuevo»**. Lo que creás ahí queda marcado.
- Los temas elegidos se ven como chips en el formulario y se sacan con su ✕. Nunca queda vacío:
  sacar el último no se puede, y lo dice.

### 3. Las demás entradas

- **Compartir desde otra app**: va a tus temas de la última vez, y un aviso dice *«Guardado en
  Historia · Cambiar»*. Si todavía no tenés ningún tema, abre el formulario para crearlo.
- **Una nota nueva** del editor arranca con los temas de la última vez, en su chip.
- **Una nota derivada** (resumen, preguntas…) va a los temas del elemento del que sale.
- **En el detalle** de un elemento, el chip de tema pasa a «Temas», con la misma hoja.

### 4. Lo que ya tenías sin tema

- No se toca solo. En la Biblioteca aparece una tarjeta *«12 elementos sin tema · Ordenarlos»*.
  Te lleva a la lista de esos elementos, donde los podés marcar y elegirles temas de a varios.
  Cuando no queda ninguno, la tarjeta desaparece, y también la columna «Sin tema» del tablero.

### 5. La IA

- «Elegir el tema» (F27) sigue para lo que haya quedado sin tema, como hoy. A lo nuevo, que ya
  entra con tema, no le agrega otro.

## Decisiones para que confirmes al aprobar

- **A.** Varios temas por elemento, **en una tabla propia**, en vez de un tema principal más
  otros aparte. Es más trabajo ahora, pero ningún lado tiene que saber cuál es el «principal».
- **B.** El tema por defecto son **los que usaste la última vez**, de a varios si fueron varios, y
  se recuerda en el teléfono.
- **C.** Lo que ya tenías sin tema **no se mueve solo**: lo ordenás desde la tarjeta cuando
  quieras. La otra opción es meterlo todo en un tema «General» al actualizar.
- **D.** Para la unión de bóvedas, **los temas de un elemento cuentan como un solo dato**: gana el
  último cambio, como hoy con el tema único. Así, un tema que sacaste en un dispositivo no vuelve
  desde el otro.
- **E.** Compartir desde otra app **no pregunta**: va a los temas de la última vez, con
  «Cambiar» en el aviso.

## Pasos (cada uno, su commit y su push)

1. **Dónde se guarda**:
   - la tabla elemento–tema, con la migración a v41 que copia el tema de hoy;
   - el repositorio: los temas de un elemento, ponerlos y sacarlos;
   - el historial por campo, la unión de bóvedas, la papelera y la fusión de duplicados (que
     junta los temas de los dos).
   - Pruebas y mutación.
2. **Leer con varios temas**: el filtro y las vistas de la Biblioteca, el Atlas, el Mapa, la
   línea de tiempo, los cuadernos, el repaso por tema, la bibliografía y la exportación. Pruebas.
3. **La hoja de temas**: marcar varios, buscar y «Crear tema nuevo»; el campo «Temas» en el
   formulario, con la tarjeta de la primera vez y los temas de la última vez. Pruebas de widget y
   mutación.
4. **Las demás entradas**: compartir, el editor de notas, las derivadas y el detalle. Pruebas.
5. **Lo que no tiene tema**: la tarjeta y la lista para ordenarlo. Pruebas.
6. **Cierre**:
   - GUIA_DE_USO, la decisión en `docs/arquitectura.md`, CONTEXTO y el «Avance» de este plan;
   - suite entera y `verify_commit`.
   - APK al teléfono solo si la pedís.

## Avance

Todavía nada: empieza al cerrar F36.
