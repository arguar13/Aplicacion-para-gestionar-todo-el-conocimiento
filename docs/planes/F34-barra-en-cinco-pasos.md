# F34 — La barra del celular en cinco pasos, en el orden en que se usan

> **Estado: en construcción** (2026-10-22). Pedido directo, con el criterio ya dado por el dueño;
> se construye sin esperar aprobación y se documenta acá cada paso.
>
> Pedido: *"agrupes todos los iconos de la barra inferior de izquierda a derecha según su orden de
> uso … cronológico (por ejemplo primero voy a usar la biblioteca, debe aparecer a la izquierda,
> pegado lo que sigue al paso siguiente y así), … que todos aparezcan en la barra sin estar
> ocultos en tres puntitos, que sean cinco grupos … si una sección tiene varios iconos, que
> aparezca una interfaz nueva con una lista vertical interactiva que agrupe lo de un mismo paso,
> que el último icono de la derecha sea el de ajustes, no quites ninguna función"*.

## Lo que hay hoy (relevado en el código)

| Qué | Cómo está |
|---|---|
| **Destinos** | Nueve ramas en `app_router.dart`: Biblioteca, Bandeja, Atlas, Explorador, Mapa, Chat (no en la web), Cuadernos, Repasar y Ajustes (`lib/app/navigation/nav_destinations.dart`). |
| **Celular (< 600 dp)** | `NavigationBar` con cinco fijos —Biblioteca, Bandeja, Atlas, Mapa, Repasar— y un «Más» (`more_horiz`) que abre una hoja con Explorador, Chat, Cuadernos y Ajustes (F13, D1). |
| **Escritorio (≥ 600 dp)** | `NavigationRail` con los nueve, sin «Más». |
| **Insignias** | Bandeja (pendientes) y Repasar (tarjetas para hoy). |

## Qué se construye

La barra pasa a tener **cinco botones, fijos, que son los pasos del trabajo de izquierda a
derecha**. Sin «Más»: todo está en algún paso.

| # | Paso | Qué tiene | Al tocarlo |
|---|---|---|---|
| 1 | **Biblioteca** | Biblioteca | la abre (guardar se hace desde acá) |
| 2 | **Organizar** | Bandeja → Atlas → Explorador → Mapa | la lista del paso |
| 3 | **Preguntar** | Chat → Cuadernos | la lista del paso |
| 4 | **Repasar** | Repasar | lo abre |
| 5 | **Ajustes** | Ajustes | los abre |

- **Por qué estos cinco.** La guía cuenta la app como *guardar → organizar → conectar → preguntar →
  repasar*. Con Ajustes fijo a la derecha quedan cuatro lugares para cinco verbos: se juntan
  *organizar* y *conectar* (la Bandeja ordena lo que entró; el Atlas, el Explorador y el Mapa lo
  recorren y lo conectan) y quedan a un toque los dos que se usan todos los días —Biblioteca y
  Repasar—, con su insignia a la vista.
- **La lista del paso.** Un paso con más de un destino abre una hoja con la lista vertical, en el
  mismo orden de uso: título del paso, y por cada destino su ícono (con su insignia), su nombre y
  una línea que dice para qué sirve. El que está abierto se ve marcado. Tocar uno lo abre; tocar el
  que ya está abierto vuelve a su pantalla inicial, como en la barra.
- **Las insignias.** La de la Bandeja va también en «Organizar», para que los pendientes se vean
  sin abrir la lista.
- **En la web** no hay chat (decisión 6): «Preguntar» queda solo con Cuadernos y se muestra como
  Cuadernos, directo, sin lista. La regla es general: un paso de un solo destino es ese destino.
- **El riel de escritorio** sigue mostrando los nueve —sobra ancho—, en el mismo orden de uso.
- **Nada se pierde**: las nueve ramas, sus rutas y su estado (`StatefulShellRoute.indexedStack`)
  quedan como están; cambia solo cómo se llega desde el celular.

## Pasos

1. **La barra en cinco pasos** (`nav_destinations.dart`, `adaptive_scaffold.dart`, textos en es/en,
   pruebas de `adaptive_scaffold_test.dart` reescritas para la barra nueva, mutación).
2. **Documentación**: GUIA_DE_USO.md («Cómo te movés por la app» y cada «Cómo llegar»), decisión 76
   en `docs/arquitectura.md`, CONTEXTO, este plan; suite entera; APK al teléfono si se pide.

## Avance

(se completa con cada paso)
