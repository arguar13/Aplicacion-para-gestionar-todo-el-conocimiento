# F27 — La IA organiza sola, y todo se puede corregir

> **Estado: propuesto** (2026-10-02), esperando "aprobado" en el chat. Pedido del usuario: *"que las
> tarjetas, las relaciones o vínculos o grafos, además de hacerse manualmente, se hagan con IA
> automáticamente, así me ahorro mucho trabajo, de manera inteligente y automática, pero que si veo
> un error me deje después borrar o editar esa relación"*, y *"al atlas y demás cosas, que además
> de manual la app automáticamente lo haga con IA"*.

## Lo que hay hoy (relevado en el código)

La IA corre en el teléfono: el modelo de chat (Gemma, ~3,7 GB) y el de relaciones (~300 MB). Los
dos se bajan una vez. Hoy, cuando un elemento termina de procesarse, la app hace esto:

| Qué | Qué hace la IA hoy | Qué tiene que hacer el usuario |
|---|---|---|
| **Vínculos entre elementos** | los **propone** solo para fuentes, no para notas | aceptarlos uno por uno en la Bandeja. Si no, quedan olvidados: el detalle no los muestra. Una vez aceptados **no se pueden deshacer ni editar** (solo borrar) |
| **Tarjetas de repaso** | nada solo; con el botón ✨ propone hasta 5 | tildarlas una por una. Después **no se pueden editar** (el código existe, la pantalla no) |
| **Quiz de opción múltiple** | nada solo; con el botón de la barra | revisar cada pregunta |
| **Temas, etiquetas, propiedades** | las **propone** | aceptarlas en la Bandeja o en la revisión en lote |
| **Datos de la referencia** (autor, año…) | los lee del archivo, sin IA | aceptarlos |
| **Espacio, madurez, tipo de nota** | nada | todo a mano |
| **Atlas** | nada: se calcula solo con los temas y las notas | armar el árbol de temas, escribir las notas vivas y las notas mapa |
| **Duplicados** | los detecta sin IA | fusionar o descartar |

Además:

- La biblioteca que ya existe no pasa nunca por la IA.
- Ajustes no tiene ningún control de esto.
- Varias decisiones registradas dicen **"nunca se guarda nada sin que la persona lo revise"**: la 21
  para las tarjetas, la 38 para los vínculos y la 53 para el quiz. Esto las cambia a propósito, y
  quedará escrito como una decisión nueva.

## La idea: aplica sola, pero todo a la vista y reversible

La IA trabaja en segundo plano y **aplica sola** lo que encuentra. Cada cosa que hace queda
**marcada como suya**, con el motivo, y se puede **editar, borrar o deshacer**, de a una o todo
junto. Lo que borres como error queda recordado, para que no lo vuelva a proponer.

1. **Vínculos.** Para cada elemento nuevo —también las notas, al guardarlas—, busca con qué otros
   de la biblioteca se relaciona y crea el vínculo: relacionado, continúa, contradice, cita o
   resume, con una frase de por qué. En el detalle, cada vínculo de la IA lleva una marca ✨.
   Tocarlo deja:
   - **cambiar el tipo**;
   - **editar la frase**;
   - **borrarlo**;
   - "**no era**": lo borra y la IA no lo vuelve a proponer.

   Los grafos, el Mapa y el Atlas se arman solos con esos vínculos.
2. **Tarjetas.** Cada elemento nuevo trae sus tarjetas de repaso hechas, ancladas a la frase del
   texto de donde salen, y entran solas a tu repaso. Cuántas depende del largo del texto (decisión
   D). Las tarjetas, las de la IA y las tuyas, ahora **se pueden editar**, además de borrar.
3. **Temas, etiquetas y propiedades.** Se asignan solas, con la marca ✨. Un toque las quita.
4. **Espacio.** Si tenés espacios, la IA pone cada elemento nuevo en el que corresponde.
5. **Datos de la referencia.** Completa solos los campos vacíos: nunca pisa lo que escribiste.
6. **Atlas.** Lo que hoy es trabajo a mano:
   - **El árbol de temas.** Un tema nuevo se ubica solo debajo de su tema padre ("Roma" debajo de
     "Historia antigua").
   - **Notas mapa.** Un tema que junta material suficiente recibe su nota mapa: el índice del tema,
     con los enlaces a lo que hay. Va marcada como de la IA, igual que hoy los derivados.
   - **Madurez.** La IA **sugiere** subir la madurez de una nota cuando crece, sin cambiarla sola:
     es tu juicio.
7. **Duplicados.** Siguen como aviso: fusionar borra uno de los dos, y eso no lo hace sola.

**Dónde se ve lo que hizo:**

- **En cada elemento**, una línea: "La IA organizó esto: 4 vínculos, 6 tarjetas, 3 temas", con
  "Ver" y "Deshacer todo". Va dentro del panel de F26.
- **Una pantalla "Lo que hizo la IA"**, en orden de fecha y agrupada por elemento, con deshacer por
  cada cosa o por elemento. Arriba, **"Para revisar"**, con lo que la IA no aplicó porque no estaba
  segura (decisión B).
- **En Ajustes › IA**:
  - un interruptor por tipo (vínculos, tarjetas, temas, espacio, Atlas);
  - "pausar la IA";
  - el avance de la pasada por la biblioteca existente.

## Decisiones que necesito que confirmes

- **A. Qué aplica sola.**
  - *(Recomendado)* **Vínculos, tarjetas, temas/etiquetas/propiedades, espacio, datos vacíos de la
    referencia, el árbol de temas y las notas mapa.** La madurez solo se sugiere y los duplicados
    siguen como aviso.
  - Alternativa: **también la madurez**, que la IA sube sola cuando una nota crece.
- **B. Cuando la IA duda.**
  - *(Recomendado)* **Lo seguro se aplica solo y lo dudoso va a "Para revisar"**, con aceptar o
    descartar de un toque. Menos errores que corregir después.
  - Alternativa: **todo se aplica solo**; los errores se corrigen después.
- **C. La biblioteca que ya tenés.** El modelo de IA del teléfono tarda en cada elemento (lo mido
  en tu teléfono antes de cerrar; calculo de decenas de segundos a un par de minutos por elemento):
  una biblioteca grande lleva horas.
  - *(Recomendado)* **Una pasada en segundo plano solo con el teléfono cargando**, retomable, con el
    avance en Ajustes. No gasta batería ni entorpece mientras usás el teléfono.
  - Alternativa: **solo lo nuevo de ahora en adelante**; lo viejo, a pedido desde cada elemento o
    cada tema.
- **D. Cuántas tarjetas por elemento.**
  - *(Recomendado)* **Según el largo**: de 3 (un artículo corto) a 12 (un libro o un video largo),
    una cada tantas ideas.
  - Alternativa: **5 siempre**, como hoy con el botón.

## Lo que hace falta por dentro (para que sea confiable)

- **Saber qué hizo la IA.** Los vínculos, las tarjetas y las propiedades guardan quién los creó —vos
  o la IA—, la confianza y el motivo, con un registro de cada pasada para poder deshacerla entera.
  Es un cambio de esquema (v33 → v34), con su migración y los censos de la fusión de bóvedas.
- **Nada por duplicado.** No repite lo que ya existe, lo que descartaste ni lo que marcaste "no era".
- **Una cola de IA aparte** de la de procesamiento: el video queda listo en segundos como ahora, y la
  IA trabaja después, de a un elemento por vez. Se pausa y se retoma, y no corre si falta el modelo.
  Si falta, aparece un aviso que invita a bajarlo, una sola vez.
- **Los textos largos** (libros, videos de horas) se recorren por partes; la IA no ve el texto
  entero de una vez.

## Orden de trabajo

1. Procedencia y deshacer: esquema v34, migración, censos de la fusión; editar vínculos y tarjetas.
2. La cola de IA en segundo plano, con pausa, reintentos y la invitación a bajar el modelo.
3. Vínculos automáticos, también para notas, con la marca ✨ y "no era".
4. Tarjetas automáticas, según la decisión D.
5. Temas, espacio y datos de la referencia automáticos.
6. Atlas: el árbol de temas y las notas mapa.
7. "Lo que hizo la IA", "Para revisar", la línea en cada elemento y Ajustes › IA.
8. La pasada por la biblioteca existente (decisión C), con medición real en tu teléfono.
9. Pruebas: cada tipo con un modelo falso, deshacer, que no repita, migración con una bóveda grande
   y fusión de bóvedas. Prueba en tu teléfono al final.
