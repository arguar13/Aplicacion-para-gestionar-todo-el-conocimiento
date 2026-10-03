# F29 — Que siga trabajando con la app cerrada

> **Estado: aprobado** (2026-10-03), en el chat («Aprobado todos los planes»), con la recomendada:
> las descargas de los modelos con el gestor del sistema, el procesamiento y la IA siguen mientras
> Android no mate la app, y una ayuda para «Inicio automático» y «Sin restricciones». Pedido del
> usuario: *"haz que
> el contenido se siga descargando o procesando los documentos en segundo plano si minimizo la app o,
> si se puede, si la cierro"*.
>
> **Minimizar** ya se está arreglando aparte, sin plan: todo trabajo largo —procesar, la IA, bajar
> los modelos y el audio de YouTube— pasa a mantener viva la app con su notificación. Este plan es
> para **cerrarla** (deslizarla fuera de las recientes).

## Lo que pasa hoy al cerrar la app

Todo el trabajo corre **dentro de la app**: al cerrarla, Android destruye la app y con ella el trabajo
en curso. Al volver a abrirla, el procesamiento **se retoma solo** desde donde quedó (por tramos y por
páginas) y la IA también; las descargas de los modelos retoman desde donde iban al tocar
«Descargar».

## Qué permite Android, de verdad

- Android **sí** deja que un trabajo siga con la app cerrada, de dos formas: un **servicio que no se
  apaga al cerrar** la app, o **descargas que maneja el propio sistema**.
- **Límites que no se pueden saltear**: Android 15 y 16 cortan el trabajo en segundo plano a las
  **6 horas por día**; y en tu teléfono (Xiaomi, HyperOS) deslizar la app suele **matar todo** salvo
  que actives **«Inicio automático»** y pongas el ahorro de batería en **«Sin restricciones»** para
  Sinapsis. La app puede llevarte a esos ajustes, pero no activarlos sola.

## Decisión que necesito que confirmes

- **A. Hasta dónde llegar.**
  - *(Recomendado)* **Las descargas siguen con la app cerrada, y el procesamiento sigue mientras
    Android no la mate.**
    - Las **descargas de los modelos** pasan al **gestor de descargas del sistema**: siguen aunque
      cierres la app o reinicies el teléfono, y retoman solas.
    - El **procesamiento y la IA** siguen con la app cerrada en el mismo servicio de hoy, que deja de
      apagarse al cerrarla; si HyperOS lo mata igual, se retoman al abrirla, como ahora.
    - Una pantalla de ayuda, una sola vez, te lleva a activar «Inicio automático» y «Sin
      restricciones».
  - Alternativa: **todo en un proceso aparte** que procese aunque la app nunca se abra, con su
    propia copia de la base. Mucho más trabajo y riesgo, y en HyperOS tampoco garantiza nada sin esos
    dos ajustes.

## Orden de trabajo

1. Las descargas de los tres modelos con el gestor del sistema, retomables y con su notificación.
2. El servicio sigue al cerrar la app mientras haya trabajo; respeta el límite de 6 horas.
3. La ayuda para «Inicio automático» y «Sin restricciones».
4. Pruebas y prueba en tu teléfono: cerrar la app a mitad de una descarga y de una transcripción.
