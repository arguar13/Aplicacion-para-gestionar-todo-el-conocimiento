# F28 — Nada se pierde: la Bandeja, el Mapa y un solo «tema»

> **Estado: aprobado** (2026-10-03), en el chat («Aprobado todos los planes»), con las recomendadas:
> **A** —«Tema» es lo que elegís al guardar, y el Mapa y el Atlas se arman también con tus temas;
> lo que hoy llaman «Tema» pasa a «Etiquetas»— y **B** —lo procesado se reencuentra en la
> Biblioteca: sección «Bandeja» en Filtros y chip en el detalle—. Pedido del usuario: *"cuando
> pongo «Triado» en las tarjetas o cuando agrego las relaciones con otros documentos luego no
> aparece nada en grafos ni en mapa conceptual, y es como que no pasa nada. Además en la pestaña de
> tarjetas arriba dice «33 pendientes» pero no me deja ver qué queda pendiente cuando hago click ahí
> […] después de procesar es como que un agujero negro se traga todo lo procesado porque no lo
> vuelvo a ver más"*.

## Lo que hay hoy (relevado en el código)

| Qué hacés | Qué pasa de verdad | Lo que ves |
|---|---|---|
| **«Triado»** en la Bandeja | Cambia un estado interno del elemento y nada más | La tarjeta desaparece. Ninguna otra pantalla muestra ni filtra ese estado: lo triado sigue en la Biblioteca **sin ninguna marca** |
| Tocar **«33 pendientes»** | Nada: es texto sin acción | La Bandeja muestra **una sola tarjeta por vez**, sin lista de lo que falta |
| **«Vincular a nota viva»** | Saca la fuente de la Bandeja **antes** de elegir; si cancelás o no hay ninguna nota viva, igual sale | Desaparece sin vincularse, y **«Deshacer» no la recupera** |
| **«Revisar sugerencias»** | Ídem: la saca antes de revisar | Sin aviso ni deshacer |
| **Deshacer** | Solo la última acción, y solo mientras la pantalla esté abierta | — |
| **Vincular dos documentos** | La relación se guarda bien | Se ve en el detalle de los dos —abajo de todo— y **en ningún otro lado** |
| **El Mapa** | Dibuja **etiquetas**, no documentos: un documento sin etiquetas y sus vínculos quedan afuera | Con la biblioteca de ejemplo —sin etiquetas— dice **«Todavía no hay temas»** aunque hayas vinculado cosas |
| **«Tema»** | Nombra **dos cosas distintas**: lo que elegís al guardar (y filtrás en la Biblioteca) y el «Tema» del Mapa y el Atlas, que en el detalle se llama «Etiquetas» | Poner un tema al guardar **no aparece en el Mapa** |

## Qué se construye

1. **La Bandeja no se traga nada.**
   - Tocar **«33 pendientes»** abre la **lista de la cola**: todo lo que espera, con su tipo y su
     fecha; tocar uno lo lleva arriba del mazo.
   - Cada acción deja **un aviso con «Ver» y «Deshacer»**: «Triado: El Imperio romano · Ver ·
     Deshacer». «Ver» abre el elemento.
   - **«Vincular a nota viva» y «Revisar sugerencias» solo trían si se completó la acción.** Si
     cancelás, o no hay notas vivas, la fuente queda en la Bandeja. Si no hay ninguna nota viva, el
     selector ofrece **crear una** con lo que estás vinculando.
   - **Deshacer de varios pasos**, que sobrevive si salís de la pantalla.
   - La primera vez, una tarjeta corta que explica qué es triar y adónde va lo procesado.
2. **Lo que pasó por la Bandeja se reencuentra** (decisión B).
3. **El Mapa muestra lo que hacés.**
   - Una vista **«Vínculos»**: los documentos y sus relaciones, tengan o no tema. Vincular dos
     cosas se ve ahí en el acto.
   - Cuando faltan temas, el Mapa **no queda vacío**: dice cuántos elementos están sin tema y ofrece
     **«Organizar con IA»**.
   - El vínculo que creás avisa «Vinculado · Ver en el Mapa».
   - En el detalle, el grafo de vínculos sube y queda **a la vista**, arriba de las tarjetas.
4. **Un solo «tema»** (decisión A).

## Decisiones que necesito que confirmes

- **A. Qué es un «tema».**
  - *(Recomendado)* **«Tema» es lo que elegís al guardar**, lo que filtrás y lo que ves en el Mapa y
    en el Atlas: el Mapa y el Atlas se arman **también con tus temas**, así que poner un tema al
    guardar ya lo ubica. Lo que hoy el Mapa y el Atlas llaman «Tema» pasa a llamarse
    **«Etiquetas»** en toda la app, como ya se llama en el detalle; el Mapa deja elegir entre «Temas»
    y «Etiquetas».
  - Alternativa: lo que elegís al guardar pasa a llamarse **«Carpeta»**, y «Tema» queda para las
    etiquetas que arman el Mapa y el Atlas.
- **B. Dónde se reencuentra lo procesado.**
  - *(Recomendado)* **En la Biblioteca**: en Filtros, una sección **«Bandeja»** —Por revisar,
    Triado, Descartado— y en el detalle de cada elemento un chip **«Triado el 3 oct»** con
    «Volver a la Bandeja». Sin pantallas nuevas.
  - Alternativa: una pantalla aparte, **«Historial de la Bandeja»**, con lo triado y lo descartado
    por día.

## Orden de trabajo

1. Las acciones de la Bandeja: no triar lo cancelado, avisos con «Ver» y «Deshacer», deshacer de
   varios pasos, crear una nota viva desde el selector.
2. La lista de la cola desde «N pendientes», y la tarjeta que explica el triaje.
3. Lo procesado reencontrable (decisión B).
4. El Mapa: la vista «Vínculos», sin vacíos mudos, y el grafo del detalle más arriba.
5. Un solo «tema» (decisión A): textos, Mapa y Atlas.
6. Pruebas, la guía de uso, y prueba en tu teléfono con la biblioteca de ejemplo.
