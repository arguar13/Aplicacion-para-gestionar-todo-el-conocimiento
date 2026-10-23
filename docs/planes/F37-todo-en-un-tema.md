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

### Pasos 1 y 2 (hechos, en un solo commit)

Van juntos porque sacar la columna `item.space_id` rompe a la vez todo lo que la escribía y todo lo
que la leía: no hay un estado intermedio que compile.

- **Esquema v41** (`item_spaces.dart`): la tabla elemento–tema, con clave `(item_id, space_id)`,
  borrado en cascada con el elemento y con el tema, e índice por tema. La migración:
  - copia el tema de cada elemento; uno que apuntaba a un tema que ya no existe queda sin tema;
  - reconstruye `item` sin la columna;
  - comprueba que el índice de texto `item_search` siga con las mismas filas y que sus triggers
    sigan andando.
  - Prueba: `migration_v41_test.dart`, con los conteos de todo lo demás como compuerta.
- **`KnowledgeEntryWriter`**:
  - `setSpaces`, `addSpaces`, `removeSpaces` y `spacesOf`;
  - el conjunto es un solo campo con su versión (`EntryField.spaces`): un cambio es una versión, y
    el mismo conjunto en otro orden no es cambio;
  - `setFieldFromText` lee el JSON de un conflicto, y también el tema solo que guardaba uno de antes.
- **Unión de bóvedas** (decisión D): `ItemSpacesMergePlanner` compara los dos conjuntos ya
  traducidos al identificador de acá (`SpaceMerge.localIdSql`) y decide con `StampRows`, como
  cualquier campo. Si gana la copia, su conjunto reemplaza entero al de acá. Un elemento nuevo llega
  en todos sus temas. Un conflicto muestra los nombres de los temas de cada lado.
- **Fusión de duplicados**: el que queda suma los temas del descartado.
- **IA**:
  - «Elegir el tema» solo actúa sobre lo que no tiene ninguno;
  - deshacer la pasada saca solo el tema que puso;
  - corregir o sacar ese tema no toca los que puso la persona;
  - deshacer una revisión que lo sacó lo devuelve, junto a los que la persona haya sumado.
- **Lectura**:
  - Biblioteca: filtro, tarjeta, tabla y tablero. En el tablero, el elemento va en la columna de
    cada tema, y arrastrarlo lo saca de la columna de donde salió y conserva los otros.
  - Atlas, Mapa y cuadernos: un elemento cuenta en cada uno de sus temas, y `item_spaces` está
    entre lo que avisa cambios.
  - La línea de tiempo, el repaso por tema y la bibliografía pasan por el mismo filtro de la
    Biblioteca.
- Pruebas: suite entera 8.559 (78 omitidas), con las nuevas de cada pieza. Mutación: 19/19.
  - Dos mutantes vivieron en la primera vuelta y mostraron huecos en las pruebas:
    - un conflicto sobre un tema que en cada bóveda tiene otro identificador;
    - el mismo conjunto en el orden en que no lo devuelve la base.
  - Las dos pruebas se reforzaron y los mataron.
- Al pasar a varios temas, deshacer una revisión que sacó el tema de la IA lo devuelve, aunque la
  persona haya sumado otro después. Antes no lo devolvía, porque con un tema solo, sumar otro era
  reemplazar el de la IA.

### Paso 3 (hecho)

- **La hoja de temas** (`spaces_picker_sheet.dart`):
  - se marcan uno o varios;
  - desde 8 temas, un buscador;
  - «Crear tema nuevo» lo crea con lo escrito y lo deja marcado, sin cerrar la hoja; si el nombre
    ya existe (sin contar mayúsculas ni tildes), marca ese.
  - Con `requireOne`, «Listo» no se toca sin ninguno y lo dice.
- **El campo «Temas»** (`spaces_field.dart`): chips con su ✕ y la hoja al tocarlo. Hay una versión
  compacta para el editor de notas. En la captura tiene que quedar al menos uno: sacar el último
  avisa, y sin ninguno «Guardar» está apagado.
- **La primera vez** (`first_space_card.dart`): sin ningún tema, la captura muestra la tarjeta para
  crear el primero, y queda elegido.
- **Los temas de la última vez** (`last_spaces.dart`, decisión B):
  - se guardan en el teléfono (SharedPreferences, `last_space_ids`), no en la bóveda;
  - los escribe cada captura que se guarda bien y cada nota nueva;
  - algo guardado sin temas no los borra.
  - Al abrir la captura, de esos quedan solo los que todavía existen.
- **Qué gana al abrir la captura**: si la Biblioteca está parada en un tema, ese. Si no, los de la
  última vez. Se decidió así porque abrir la captura desde un tema dice dónde va lo nuevo.
- **El editor de notas, adelantado del paso 4**:
  - una nota nueva elige sus temas con el campo compacto;
  - arranca en los que le pasa la captura;
  - no exige ninguno.
  - Primero, el editor ponía los de la última vez por su cuenta. La mutación mostró que así podía
    traer de vuelta un tema borrado. Ahora los decide solo la captura, que ya filtra los que existen.
- La hoja vieja de un solo tema (`space_picker_sheet.dart`) sigue en uso en la selección múltiple,
  el menú de la tarjeta y el detalle. Pasan a la hoja nueva en el paso 4, y entonces se borra.
- Pruebas:
  - suite entera 8.567 (78 omitidas);
  - la captura, con el grupo «los temas de lo que se guarda (F37)»;
  - `last_spaces_test.dart`.
- Mutación: 15/15 sobre el código final, en dos vueltas (13 de 14 en la primera; el que vivió ya no aplica).
  - En la primera sobrevivió «el editor no arranca en los de la última vez» y mostró el defecto de
    arriba.
  - Se corrigió, y la prueba nueva (una nota nueva no arranca en un tema borrado) mata los dos
    mutantes del editor.

### Paso 4 (hecho)

- **Compartir desde otra app**:
  - El plan partía de que lo compartido se guardaba sin preguntar. No es así: lo
    compartido abre el formulario de captura ya cargado, para revisar el tipo y los posibles
    duplicados antes de guardar (`SharedContentController`).
  - Con el paso 3, ese formulario ya trae los temas de la última vez, y sin ningún tema muestra la
    tarjeta del primero. Eso cumple la decisión E: compartir no suma ninguna pregunta.
  - No se pasó a guardar sin revisar ni se agregó el aviso «Guardado en X · Cambiar». Saltear la
    revisión cambiaría una decisión anterior (el comentario de `SharedContentController`) que el plan no discutió. Queda dicho por si se quiere.
- **Una nota derivada** de un elemento va a los temas de ese elemento
  (`GenerateDerivedNoteUseCase`). La de un cuaderno sigue como antes: el tema de la consulta, si la
  consulta es por tema.
  - Las notas que crea un `[[vínculo]]` y las notas mapa del Atlas no salen de un elemento, y no se
    tocaron.
- **El detalle**: el chip «Tema» pasó a «Temas» (`ItemSpacesEditor`), con los mismos chips y la
  misma hoja que el editor de notas.
  - Cada cambio se escribe al momento, como las etiquetas.
  - No exige ninguno: lo que ya estaba sin tema se ordena cuando la persona quiere (decisión C).
  - Se borró el `SpacePicker` viejo.
- **El menú de la tarjeta**: «Mover a tema» pasó a «Elegir temas». Abre la hoja con los suyos
  marcados, y «Listo» los guarda; el aviso nombra todos.
- Queda con la hoja vieja solo «Mover a tema» de la selección múltiple. Pasa al paso 5, junto con
  la lista para ordenar lo que no tiene tema, y ahí se borra `space_picker_sheet.dart`.
- Pruebas: las nuevas del detalle (grupo «temas (F37)»), las del menú y la de la derivada.
- Suite entera 8.573 (78 omitidas). Mutación: 5/5.

### Paso 5 (hecho)

- **El filtro «sin tema»**: `LibraryQuery.withoutSpaces`, con `NOT EXISTS` sobre `item_spaces`. Con
  un tema puesto no deja pasar nada. Queda afuera de las vistas guardadas, como `ids`, porque es la
  lista para ordenar y no un filtro de la Biblioteca.
- **Un contador vivo**: `LibraryRepository.watchCount`, para la tarjeta, sin traer la lista.
  - La lista y el contador de la Biblioteca ahora miran también `item_spaces`.
  - Borrar un tema avisa, porque drift propaga el borrado en cascada.
  - La prueba lo comprueba, y la mutación lo confirma.
- **La tarjeta** `UnsortedItemsCard`: «N elementos sin tema · Ordenarlos».
  - Solo aparece en la Biblioteca sin filtros y fuera del modo selección: con un filtro, el número
    no sería de lo que se mira.
  - Desaparece sola al ordenar lo último.
- **La lista** `UnsortedItemsScreen` (ruta `/unsorted`):
  - se marcan los que van juntos («Marcar todos»);
  - «Elegir temas para N» abre la hoja de siempre, que exige al menos uno;
  - los marcados reciben esos temas, salen de la lista, y un aviso los nombra.
  - Vacía, dice «Todo tiene tema».
  - Lo ordenado deja de estar marcado: si vuelve a la lista porque se borró su tema, vuelve sin
    marcar.
- **El tablero**: la columna «Sin clasificar» está solo mientras quede algo sin tema.
- **La selección múltiple**: «Mover a tema» pasó a «Elegir temas» con la hoja nueva.
  - La hoja arranca con los temas que tienen todos los elegidos.
  - Marcar uno se lo suma a todos; desmarcar uno de esos se lo saca a todos.
  - Los temas que tiene solo alguno no se tocan.
  - Lo hace `LibraryRepository.changeSpaces` (sumar y sacar en un solo cambio por elemento), que
    reemplaza al `addSpaces` del repositorio.
- Se borró la hoja vieja de un solo tema (`space_picker_sheet.dart`), con sus textos
  `detailSpaceChoose` y `libraryItemMoveToSpace`.
- Mutación: 11/11, en dos vueltas.
  - En la primera sobrevivió «lo ordenado sigue marcado»: el contador ya no lo contaba, porque sale
    de la lista.
  - La prueba nueva lo hace volver a la lista, borrando su tema, y mata el mutante.
- Suite entera 8.586 (78 omitidas).
