# F24 — El audio de cada video, siempre a mano

> **Estado: propuesto** (2026-10-01), esperando aprobación en el chat ("aprobado"). Pedido del
> usuario: *"cuando se trate siempre de un audio, un short, TikTok o video, que siempre debajo de la
> vista previa del video aparezca un reproductor con el audio del video (el mismo reproductor que
> usa la app cuando se importa un audio de mi móvil), ese mismo reproductor usa para reproducir el
> audio que siempre descargarás cuando se trata de un video"*. Viene después de F23: con el audio a
> mano, el texto de esos videos también puede seguir al audio en amarillo.

## Lo que hay hoy (relevado en el código)

| Qué | Qué se guarda | Qué se ve en el detalle | ¿Texto? |
|---|---|---|---|
| **TikTok, reels de Instagram** | el **video entero** (MP4) | **el reproductor de la app**, con el video y su audio, ±10 s y velocidad | **no**: el audio no se transcribe |
| **Video o audio del teléfono** | el archivo | el reproductor de la app | sí, transcrito |
| **YouTube (también Shorts)** | **nada**: solo los subtítulos | una **miniatura** que abre la app de YouTube | sí: los subtítulos, o el audio transcrito si no hay |

El botón "Descargar el audio" de YouTube se quitó hoy a pedido (commit `2cbc9f7`): esto no lo
devuelve. El audio se baja solo, sin botón.

## Qué se construye

1. **YouTube: el audio se baja siempre, solo, después de dejar el video listo** —el video no
   espera—, directo a disco y retomable si se corta, y debajo de la miniatura aparece **el mismo
   reproductor** que el de un audio del teléfono: ±10 s, velocidad, mini reproductor flotante, y el
   texto que sigue al audio en amarillo (renglón por renglón con los subtítulos, que traen su
   momento; palabra por palabra si el texto salió de transcribir el audio). Un video sin subtítulos
   ya baja su audio para transcribirlo: **ese mismo archivo se conserva** en vez de borrarlo, así no
   se baja dos veces.
2. **TikTok y reels: su audio se transcribe**, como el de un video del teléfono. El reproductor ya
   está; lo que falta es el texto para que pueda seguir al audio, para buscar y para el chat.
3. Los videos de YouTube que ya están en la biblioteca: su audio se baja la próxima vez que se
   abren (o con "Volver a extraer el texto").

## Decisiones que necesito que confirmes

- **A. Calidad del audio de YouTube** (lo que ocupa en el teléfono):
  - *(Recomendado)* **La pista más liviana**, Opus de ~50 kbps: **~22 MB por hora** —un video de 10
    minutos, ~4 MB; uno de 4 horas, ~90 MB—. Opus a esa tasa se escucha bien para voz y aceptable
    para música.
  - Alternativa: **la de mejor calidad**, la que se bajaba con el botón, ~160 kbps: **~72 MB por
    hora** —4 horas, ~290 MB—.
- **B. TikTok, reels y videos del teléfono:**
  - *(Recomendado)* **No duplicar el reproductor**: el que se ve ya es el reproductor de la app, con
    el audio y los mismos controles. Se agrega la transcripción de TikTok y reels (punto 2).
  - Alternativa: además, un segundo reproductor solo de audio debajo del video, sobre el mismo
    archivo (los dos controlarían el mismo audio).

## Orden de trabajo

1. La pista de audio según la decisión A; bajarla sola después de procesar, en segundo plano y
   retomable; conservar la del video sin subtítulos.
2. El reproductor debajo de la miniatura de YouTube, con el mini reproductor y el texto que sigue
   al audio.
3. Transcribir el audio de TikTok y reels.
4. Pruebas, medición de espacio con videos reales, y prueba en tu teléfono al final (junto con
   F23).
