# F31 — Repasar sin depender de Anki, y una sesión que se disfruta

> **Estado: aprobado** (2026-10-08), en el chat («aprobado»), con todas las recomendadas: **A**
> SM-2 con pasos de aprendizaje, **B** 20 nuevas y 200 repasos por día, **C** las dos direcciones,
> los huecos y «escribí la respuesta», **D** traer mazos de Anki, **E** un aviso diario opcional.
> Pedido del usuario, mirando
> la pantalla de repaso en su teléfono: *"a la sesión de flashcards hazla más interactiva y que los
> botones tengan formas iguales y el texto se vea bien; haz que tenga todo lo necesario para no
> depender de las apps de Anki, aunque también mantenga las funciones de exportar y compartir con
> Anki, y que sea elegante, interactivo y atractivo"*.
>
> **Ya resuelto, sin plan** (era un defecto): los cuatro botones de calificar medían distinto y el
> texto se partía letra por letra (`615cb23`); ahora miden lo mismo y dicen cuándo vuelve la
> tarjeta con cada respuesta.

## Lo que hay hoy (relevado en el código)

| Qué | Cómo está |
|---|---|
| **Repasar** | Una cola global de lo que vence hoy: una tarjeta a la vez, cuatro botones, y nada más. |
| **Calendario de repaso** | SM-2 (el de las primeras versiones de Anki). «De nuevo» devuelve la tarjeta **para mañana**, no para dentro de unos minutos. |
| **Cuántas por día** | Sin límite: con 114 tarjetas pendientes, las 114 de una vez. |
| **Qué estudiar** | Todo junto. No se puede elegir «solo Roma», «solo este cuaderno» o «solo lo que vence hoy de esta etiqueta». |
| **Durante el repaso** | No se puede editar la tarjeta, ni pausarla, ni deshacer una respuesta que se tocó mal. |
| **Mirar y ordenar las tarjetas** | Solo desde el detalle de cada elemento, de a una fuente por vez. No hay un lugar para ver todas, buscar, filtrar, pausar o borrar varias. |
| **Formas de tarjeta** | Pregunta y respuesta, y opción múltiple. No hay «las dos direcciones», ni huecos para completar, ni «escribí la respuesta». |
| **Estadísticas** | Ya hay racha, insignias, calendario de actividad, retención semanal y las tarjetas más difíciles. Falta el pronóstico de lo que viene y cuántas están nuevas, aprendiéndose o maduras. |
| **Anki** | Se exporta (`.apkg`, TSV, CSV). No se puede **traer** un mazo de Anki a Sinapsis. |

## Qué se construye

Pensado en cuatro tandas, de lo que más pesa al día a día a lo más fino. Cada una se puede usar
sola, y se prueba en tu teléfono antes de pasar a la siguiente.

1. **La sesión.**
   - La tarjeta **se da vuelta** con una animación; un gesto la califica (deslizar a la derecha
     «Bien», a la izquierda «De nuevo», hacia arriba «Fácil»; los botones siguen) y vibra al tocar.
   - Una **barra de avance** de la sesión, y al terminar una **pantalla de resumen** —cuántas,
     cuánto tardaste, cuántas acertaste, la racha— en lugar de «No hay nada para repasar».
   - **Deshacer** la última respuesta.
   - Desde la propia tarjeta: **editarla**, **pausarla** («suspender»), **posponerla hasta mañana**
     y **borrarla**, sin salir del repaso.
   - Atajos de teclado en la compu: espacio para dar vuelta, 1 a 4 para calificar, Z para deshacer.
2. **Qué estudiar y cuánto.**
   - Una pantalla de entrada a Repasar que muestra **cuántas hay nuevas, cuántas se están
     aprendiendo y cuántas vencen**, y deja elegir **qué estudiar**: todo, un tema, una etiqueta,
     un cuaderno o un elemento.
   - **Límites por día**: tarjetas nuevas (20 por defecto) y repasos (200), cambiables.
   - **Pasos de aprendizaje**: una tarjeta nueva, o una que olvidaste, **vuelve en 1 minuto y
     después en 10** dentro de la misma sesión, antes de pasar a repasarse en días. Es lo que hace
     que Anki funcione de verdad, y hoy falta.
3. **Mirar y ordenar todas las tarjetas.**
   - Una pantalla **«Mis tarjetas»**: lista de todas, búsqueda, filtros (nuevas, aprendiendo,
     vencen, pausadas, de un tema o una etiqueta), y acciones sobre varias a la vez: pausar,
     reiniciar, mover, borrar.
   - **Estadísticas completas**: lo que ya hay, más el **pronóstico de los próximos 30 días**, el
     reparto entre nuevas, jóvenes y maduras, y cuántos botones de cada tipo usaste.
4. **Más formas de tarjeta, y puente con Anki.**
   - **Las dos direcciones** (pregunta → respuesta y respuesta → pregunta, como dos tarjetas).
   - **Huecos para completar** (`El {{c1::Imperio romano}} cayó en 476`), que la IA también sabe
     hacer.
   - **«Escribí la respuesta»**, que compara con la correcta y te dice si coincidió.
   - **Traer un mazo de Anki**: abrís un `.apkg` y sus tarjetas, con su calendario, entran a
     Sinapsis. Exportar y compartir con Anki siguen igual, y se prueban de ida y vuelta.

## Decisiones que necesito que confirmes

- **A. El calendario de repaso.**
  - *(Recomendado)* **Quedarse con SM-2 y sumarle los pasos de aprendizaje.** Es lo que ya entiende
    el resto de la app y lo que exporta a Anki sin perder nada.
  - Alternativa: pasar a **FSRS**, el calendario nuevo de Anki, que retiene mejor con menos
    repasos. Cambia cómo se guarda cada tarjeta y no se puede dar marcha atrás sin perder el
    historial; conviene sumarlo después, como una opción aparte, cuando ya haya historial para
    ajustarlo.
- **B. Cuántas por día.**
  - *(Recomendado)* **20 nuevas y 200 repasos por día**, cambiables en Ajustes y por mazo.
  - Alternativa: sin límite, como hoy.
- **C. Las formas nuevas de tarjeta.**
  - *(Recomendado)* **Las dos direcciones, huecos para completar y «escribí la respuesta»**,
    todas.
  - Alternativa: solo las dos direcciones y los huecos.
- **D. Traer mazos de Anki.**
  - *(Recomendado)* **Sí**, con su calendario. Si dejás de usar Anki, no perdés lo que estudiaste.
  - Alternativa: solo exportar, como hoy.
- **E. Aviso para repasar.**
  - *(Recomendado)* **Una notificación diaria a la hora que elijas**, con cuántas tarjetas tenés.
    Apagada hasta que la prendas.
  - Alternativa: sin aviso.

## Lo que cambia por dentro

- **La base de datos** (v39): cada tarjeta guarda en qué paso de aprendizaje está, si está pausada
  o pospuesta, y de qué dirección es; los límites y la forma de cada tarjeta se guardan con ella.
  Todo lo nuevo viaja en la fusión de bóvedas y en la exportación.
- **El calendario no se rompe**: lo que hoy está programado sigue igual; los pasos de aprendizaje
  solo afectan a lo nuevo y a lo que se olvide de ahora en adelante.

## Orden de trabajo

1. La sesión: vuelta de tarjeta, gestos, avance, resumen, deshacer, editar y pausar desde la
   tarjeta, atajos.
2. Qué estudiar y cuánto: la entrada a Repasar, los mazos, los límites y los pasos de aprendizaje
   (esquema v39).
3. «Mis tarjetas» y las estadísticas completas.
4. Las formas nuevas, traer mazos de Anki, y el aviso diario.
5. En cada tanda: pruebas, la guía de uso, la decisión de arquitectura, y prueba en tu teléfono
   contigo.
