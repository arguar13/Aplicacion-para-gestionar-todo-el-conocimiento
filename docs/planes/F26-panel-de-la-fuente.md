# F26 — El panel de la fuente: los botones ordenados

> **Estado: aprobado** (2026-10-02), en el chat, con las recomendadas: **A** —cuatro mosaicos,
> Leer, Resumir, Copiar y Más— y **B** —el reproductor del audio dentro del panel—. Pedido del usuario: *"entre
> el video, o audio o documento y el texto transcripto hay una serie de botones que están
> desalineados y ubicados como aleatoriamente: ordénalos en un panel muy elegante, interactivo y
> atractivo"*.

## Lo que hay hoy (relevado en el código)

Entre la vista previa y el texto aparecen hasta **ocho controles sueltos**, cada uno con su propio
lugar y su propio estilo:

| Qué | Cómo se ve hoy | Cuándo |
|---|---|---|
| Reproductor del audio (YouTube, video, TikTok) | una tarjeta aparte de 220 px; la de YouTube con otro radio | video, YouTube con el audio bajado |
| "Descargando el audio… 42 %" / "No se pudo… Reintentar" | texto y barra a la izquierda, botón sin ícono | YouTube |
| "Borrar archivo, quedarme con el texto" | botón de texto **solo, a la derecha** | audio, video, YouTube, TikTok |
| "Volver a extraer el texto" | botón de texto, en una fila **a la derecha** | casi todo, salvo TikTok, web y notas |
| "Quitar marcas de tiempo" | ídem | transcripciones con marcas |
| "Leer para destilar", "Resumir con IA", "Copiar todo" | ídem | siempre |
| "Extrayendo el texto de nuevo…" / error con "Reintentar" | otra fila, a la izquierda | al volver a extraer |

**Por qué se ve desordenado:**

- Hay cinco tipos de botón distintos.
- Unas filas van alineadas a la derecha y otras a la izquierda.
- Con cinco botones en un teléfono la fila pasa a dos renglones, y el segundo queda torcido y pegado
  al primero.
- La separación con la vista previa es a veces 4 px, a veces 12 y a veces nada.
- En los PDF y libros las acciones quedan **escondidas** dentro de "Texto extraído" plegado.
- Si un elemento tiene más de un texto, la fila se repite.

## Qué se construye

**Un solo panel**, una tarjeta con el mismo lenguaje que la vista previa: el mismo radio de 16, el
mismo borde suave y 12 px de aire arriba. Va siempre en el mismo lugar —debajo de la vista previa y
arriba del texto—, una sola vez por elemento.

```
┌──────────────────────────────────────────────┐
│          vista previa: video / PDF / …       │
└──────────────────────────────────────────────┘
┌──────────────────────────────────────────────┐
│  🎧 Audio del video                 1×       │  ← solo si hay audio (decisión B)
│  ────────●──────────────  02:13 / 41:05      │
│            ⟲10     ▶     10⟳                 │
│  ─────────────────────────────────────────── │
│  ⬇ Descargando el audio… 42 %  ▰▰▰▱▱▱▱       │  ← solo mientras pasa algo
│  ─────────────────────────────────────────── │
│   ( 📖 )      ( ✨ )      ( ⧉ )      ( ⋯ )    │
│    Leer      Resumir     Copiar      Más      │
└──────────────────────────────────────────────┘
          texto transcripto…
```

1. **Las acciones como mosaicos iguales:**
   - Cada uno es un ícono dentro de un círculo de color suave, con su nombre debajo, todos del mismo
     ancho y repartidos parejo.
   - Al tocarlos responden con la onda de Material y una vibración corta. Mientras trabajan
     —"Resumir"— el ícono gira.
   - Nunca pasan a dos renglones ni quedan torcidos.
2. **"Más" abre una hoja** con lo que se usa de vez en cuando:
   - Volver a extraer el texto, con el idioma.
   - Quitar marcas de tiempo.
   - Borrar el archivo y quedarme con el texto.

   Cada opción va con su ícono y una línea que explica qué hace, y solo aparecen las que aplican a
   ese elemento.
3. **El estado, dentro del panel:**
   - Lo que está pasando ocupa una franja propia, con ícono, texto, barra y, si falló, un único botón
     "Reintentar" del mismo estilo en todos los casos.
   - Esa franja aparece y desaparece con una animación suave, y no se ve cuando no pasa nada.
   - Casos: bajando el audio, volviendo a extraer, transcribiendo, falta el modelo.
4. **En PDF y libros** las acciones quedan a la vista, fuera de "Texto extraído" plegado.
5. Las notas de bloques usan el mismo panel: Leer · Resumir · Copiar · Editar.

## Decisiones que necesito que confirmes

- **A. Cuántas acciones a la vista.**
  - *(Recomendado)* **Cuatro mosaicos**: Leer, Resumir, Copiar y Más. Lo de vez en cuando va en
    "Más". Queda limpio en cualquier teléfono.
  - Alternativa: **todas a la vista**, en una grilla de mosaicos de 3 por fila (hasta 2 filas), sin
    "Más".
- **B. El reproductor del audio** (YouTube, videos, TikTok).
  - *(Recomendado)* **Dentro del panel**, como su parte de arriba: el audio y sus acciones en una
    sola tarjeta.
  - Alternativa: **queda aparte**, encima del panel, solo emparejado en tamaño y radio.

## Orden de trabajo

1. El panel con los mosaicos y la hoja "Más", y el estado dentro del panel.
2. El reproductor según la decisión B; los documentos con las acciones a la vista.
3. Pruebas en pantallas de teléfono (360 y 412 px de ancho) para cada tipo de fuente, y la prueba
   en el teléfono al final, junto con lo demás.
