# F21 — Procesamiento confiable y rápido

> **Estado: cerrado** (2026-09-29) en diecinueve commits —ver la decisión 54 en
> `docs/arquitectura.md` y el cierre al final—. **Aprobado** (2026-09-29), en el chat, con la decisión A en una variante propia del
> usuario (ver abajo), B y C como se recomendaron, y la escala subida a libros de cientos de
> páginas y videos de hasta 3-4 horas. Nace de un reporte del uso real en el teléfono (Xiaomi
> 23090RA98G, HyperOS): un short de YouTube de 2 minutos, una página web y un libro quedan
> "Procesando" para siempre; lo que se guarda después queda "En espera" detrás; borrar lo trabado
> no destraba nada.

## Escala objetivo

Libros de cientos de páginas (escaneados incluidos) y videos o audios de **hasta 3-4 horas**, de
YouTube o del propio teléfono. A esa escala no alcanza con que sea rápido:

- **Nada carga el archivo entero en memoria.** Hoy la captura lee cada archivo completo a
  `Uint8List` y rechaza lo que pasa de 500 MB (`CapturedFile.maxBytes`) —un video de 3 horas
  grabado con el teléfono pesa varios GB—; el documento se abre desde bytes; el audio se decodifica
  entero; el audio de YouTube se junta en memoria. Todo pasa a trabajar desde el disco, por partes.
- **Lo largo se retoma donde quedó.** Una transcripción de 4 horas o el reconocimiento de 500
  páginas escaneadas guardan su avance por tramo o por página: si se interrumpen, siguen desde ahí,
  no desde cero.
- **Avance visible** en la tarjeta y en el detalle, con barra.
- **Lo que viene después también escala:** fragmentar e indexar el texto de un libro de cientos de
  páginas, y calcular los vectores del motor de relaciones de miles de fragmentos, se miden; lo
  pesado va al carril largo, por partes y retomable.

## Qué pasa de verdad (medido, no supuesto)

Diagnóstico hecho sobre la app en vivo en el teléfono —registros, y el estado interno de la cola
leído de la memoria del proceso por el servicio de depuración de Dart— más un cronometraje de cada
etapa en la PC. Siete causas, cada una con su evidencia:

1. **Lo interrumpido nunca se retoma.** `enqueuePending` (al abrir la Biblioteca) solo vuelve a
   encolar lo que está `pending`. Si la app se cierra, Android la congela o el sistema la mata
   mientras un elemento está `processing`, ese elemento queda "Procesando" para siempre.
   *Evidencia:* con la app recién abierta, la cola procesó los 4 elementos "En espera" y quedó
   **vacía y en reposo** (`_queue` vacía, `_current = null`, `_isDraining = false`), y "El Santo
   Rosario" —marcado `processing` de una sesión anterior— **nunca entró**. HyperOS congela las
   apps en segundo plano de forma agresiva, y salir de la app para compartir algo desde YouTube es
   exactamente el uso normal.
2. **Ningún tiempo límite en YouTube, y ninguno por elemento.** `YoutubeExplodeClient` usa el
   cliente HTTP propio del paquete, **sin límite de tiempo**; una conexión que muere (el teléfono
   se durmió, cambió de wifi a datos) deja la espera colgada para siempre. La cola es una fila
   única sin vigilante: un elemento colgado frena a todos los que vienen detrás.
3. **Borrar no cancela nada.** Mandar a la papelera un elemento que se está procesando no corta
   su procesamiento: la cola sigue esperándolo. Por eso borrar el video no destrabó la cola.
4. **El guardado final pisa lo que hiciste mientras procesaba.** `ProcessItemUseCase` guarda la
   "foto" del elemento tomada al empezar: una etiqueta, un tema o un título que cambiaste mientras
   tanto se pierde (la papelera sí se respeta: `upsert` no toca `deletedAt`).
5. **La cola se pierde si se reconstruye.** `processingQueueProvider` observa (`ref.watch`) una
   cadena de ~20 providers; si cualquiera se reconstruye —por ejemplo, al cambiar el modelo de
   chat elegido— la cola se descarta con todo lo que tenía, y nada la vuelve a llenar hasta el
   próximo arranque.
6. **Trabajo inútil y en el lugar equivocado:**
   - *Página web:* para "archivar" la página de vaticannews la app hizo **335 descargas y bajó
     13,8 MB** (tipografías de armenio, canarés, malayalam, tamil; `.eot` y `.ttf` de cada una;
     134 respuestas 404) para un artículo de **1,5 KB**. En la PC: bajar la página 0,4 s, extraer
     el artículo 0,4 s, **archivar 11,5 s**, convertir a texto 0,05 s.
   - *YouTube:* además de la transcripción (unos KB, segundos para cualquier duración) se baja
     **el audio entero**, acumulado en una `List<int>` —8 bytes por cada byte de audio: un video
     de una hora son ~500 MB de memoria—, sin límite de tiempo y en el camino crítico: el video no
     queda "listo" hasta que termina. La app tenía 927 MB de memoria residente durante la prueba.
   - *Audio y video del teléfono:* Whisper "small" con un solo hilo (el valor por defecto de
     sherpa-onnx) y el audio entero cargado en memoria (una hora = 115 MB de WAV + 230 MB de
     muestras). Y si el modelo no está descargado, falla con un mensaje genérico ("No se pudo
     sacar el texto") y un "Reintentar" que va a fallar igual: el motivo real ("el modelo de
     transcripción todavía no está descargado") solo aparece en el registro. Es lo que le pasó a
     "Himno de Alabanza".
   - *PDF escaneado:* si ninguna página trae texto, se reconoce **cada página** automáticamente
     (render a 2,5x + codificación PNG en Dart puro, en el hilo principal + ML Kit). Un libro
     escaneado de cientos de páginas son decenas de minutos. (Lo mismo pasa con una captura de
     Cámara de dos fotos o más: se guarda como PDF de imágenes.)
7. **La app instalada es la de depuración**: el trabajo de Dart corre de 5 a 10 veces más lento
   que en la versión final. No es la causa de los cuelgues —durante la prueba la app estuvo al 0 %
   de CPU, esperando, no trabajando—, pero sí de parte de la lentitud. El hardware del teléfono no
   es el problema.

## Qué se arregla sin necesidad de decisión (es corrección de defectos)

- **Retomar lo interrumpido:** al abrir, lo que quedó `processing` vuelve a la cola. Con un tope
  de intentos: algo que hace caer la app tres veces seguidas no entra en un bucle infinito, queda
  "No se pudo extraer" con su motivo.
- **Tiempo límite en todo:** cada etapa de red con su límite (YouTube incluido) y un vigilante por
  elemento: tope fijo para las tareas cortas; para las largas (transcribir), corte si **deja de
  avanzar**, no por duración total. Lo cortado queda con su motivo y la cola sigue.
- **Borrar cancela:** si está en cola, sale; si se está procesando, se corta en el acto y la cola
  pasa al siguiente.
- **No pisar cambios:** al terminar se guarda solo lo que trajo el procesamiento (texto, título
  real, autor, archivo) sobre la versión **actual** del elemento; si está en la papelera, el
  resultado se descarta.
- **Dos carriles:** lo rápido (páginas, publicaciones, subtítulos de YouTube, texto de documentos,
  imágenes) por uno, lo largo (transcribir audio/video, reconocer páginas escaneadas, bajar audio)
  por otro. Un video de una hora nunca frena una página web.
- **La cola no se pierde:** sus dependencias se leen al usarlas, no se observan; y cada vez que la
  cola nace se resincroniza desde la base.
- **Archivado web liviano:** sin tipografías (no aportan nada para leer), sin recursos repetidos,
  con tope de cantidad y de tiempo total; el artículo queda listo aunque el archivado no termine.
  El trabajo pesado de HTML sale del hilo principal.
- **Motivo visible:** cuando algo falla, el detalle dice por qué. Si falta un modelo, el botón es
  "Descargar el modelo", y lo que esperaba ese modelo se retoma solo al terminar de descargarlo.
- **Versión final en el teléfono:** al cerrar, se instala la versión de lanzamiento (release), no
  la de depuración.

## Decisiones tomadas

- **A — elegida en una variante propia:** se extrae el texto que el documento ya trae (rápido, en
  el carril corto) **y** se reconocen las páginas escaneadas **siempre, automáticamente**, pero en
  segundo plano, en el carril largo, con barra de avance y retomable, sin impedir nunca abrir el
  libro. En el detalle de un documento lo principal es **el original** en su visor; el texto
  extraído no se muestra para leer —queda plegado— porque existe para la búsqueda, el chat, las
  tarjetas, el quiz y las citas, no para verlo.
- **B — recomendada:** el audio de YouTube solo se baja si lo pedís.
- **C — recomendada:** la transcripción larga sigue aunque salgas de la app, con notificación.
  Se extiende al otro trabajo largo, el reconocimiento de páginas escaneadas: el servicio en
  primer plano cubre el carril largo entero.

Texto original de las opciones, como se presentaron:

- **A. Documentos (PDF, EPUB, DOCX).** Pediste que no se les extraiga nada. Antes de hacerlo, lo
  que eso cuesta: el visor integrado sí deja leer, seleccionar y copiar, pero **la búsqueda, el
  chat con tu bóveda, las tarjetas, el quiz, "Leer para destilar" y las citas con número de página
  dejarían de ver el contenido de tus documentos** — todo eso lee el texto extraído, no el visor.
  Y en un PDF escaneado el visor no deja seleccionar nada (no tiene texto). Lo que de verdad
  tarda no es extraer el texto que el documento ya trae (segundos, incluso con cientos de
  páginas) sino el reconocimiento automático de páginas escaneadas.
  - **Recomendado:** seguir sacando el texto que el documento ya trae —rápido, en el carril
    corto, sin frenar nada—, y **nunca** reconocer páginas escaneadas solo: pasa a ser un botón
    por documento ("Reconocer el texto de las páginas escaneadas"), en el carril largo, con avance
    visible y cancelable. El documento se puede abrir y leer desde el primer segundo.
  - *Alternativa (lo que pediste literalmente):* no extraer nada; los documentos quedan listos al
    instante, sin búsqueda/chat/tarjetas/quiz/destilar sobre su contenido. Se puede sumar un botón
    "Extraer el texto" por documento para cuando sí lo quieras.
- **B. Audio de los videos de YouTube.**
  - **Recomendado:** no se baja más automáticamente. El video queda listo en segundos con su
    transcripción, dure lo que dure. En el detalle, un botón "Descargar el audio" que lo baja en el
    carril largo, directo a disco, con avance y cancelable.
  - *Alternativa:* seguir bajándolo solo, pero después de marcar el video como listo, en el carril
    largo y directo a disco.
- **C. Videos y audios del teléfono de media hora o una hora (transcripción en el dispositivo).**
  - **Recomendado:** usar todos los núcleos del procesador; transcribir por tramos leyendo del
    disco, sin cargar la hora entera en memoria; avance visible ("Transcribiendo… 40 %"); y un
    **servicio en primer plano de Android** (notificación "Sinapsis está transcribiendo…") para
    que HyperOS no la congele si salís de la app. Después de medir la velocidad real en tu
    teléfono, si "small" sigue siendo lento para una hora, te propongo sumar "base" como opción
    más rápida (con algo menos de precisión) — esa elección sería tuya, con las cifras delante.
  - *Alternativa:* lo mismo sin servicio en primer plano: más simple, pero la transcripción se
    pausa cada vez que salís de la app.

## Secuencia de commits (cada uno compila, pasa el analizador y la suite completa por sí solo)

1. `fix(transform)`: lo interrumpido se retoma al abrir; la cola se resincroniza desde la base al
   nacer y deja de observar sus dependencias.
2. `feat(database)`: esquema v31 — motivo del fallo, cantidad de intentos y avance guardado del
   procesamiento (respaldo previo, compuerta de conteo, y los tres censos de la fusión).
3. `fix(transform)`: tiempos límite en toda etapa de red (YouTube incluido) y vigilante por
   elemento; el motivo queda guardado. Tope de intentos para lo interrumpido.
4. `fix(transform)`: borrar cancela; el guardado final no pisa cambios hechos durante el
   procesamiento.
5. `refactor(transform)`: dos carriles, corto y largo, e informe de avance por elemento.
6. `feat(library)`: barra de avance en la tarjeta y en el detalle.
7. `perf(transform)`: archivado web liviano, y el HTML pesado fuera del hilo principal.
8. `perf(capture)`: capturar por ruta, copiando por partes —sin cargar el archivo en memoria— y
   sin el tope de 500 MB (el límite pasa a ser el espacio libre).
9. `perf(transform)`: YouTube listo con la transcripción; audio a pedido (decisión B), directo a
   disco, con avance y cancelable.
10. `feat(transform)`: documentos según la decisión A — abiertos desde el disco, texto por página,
    reconocimiento de escaneos en el carril largo fuera del hilo principal, retomable por página;
    el detalle muestra el original primero y el texto plegado.
11. `perf(transform)`: transcripción en el dispositivo por tramos desde disco, con todos los
    núcleos, avance, y retomable por tramo.
12. `feat(transform)`: servicio en primer plano en Android para el carril largo (decisión C).
13. `perf(relations)`: lo que viene después de procesar —fragmentos, índice, vectores— medido a
    escala de libro y de video de 4 horas; lo pesado, por partes en el carril largo.
14. `feat(library)`: motivo visible, "Descargar el modelo", y retomar lo que esperaba un modelo.
15. `docs(arquitectura)`: Decisión 54, cierre de F21. Instalación de la versión release.

## Cómo se verifica

Mismo ritmo de siempre: por commit, formato → analizador → tests del área → suite completa en la
copia aislada → commit → árbol limpio → push. Tests nuevos: lo `processing` se retoma al abrir y
el tope de intentos corta un bucle; un transformador que nunca responde no frena la cola (vence el
vigilante y el siguiente se procesa); borrar un elemento en curso lo corta y la cola sigue; una
etiqueta agregada durante el procesamiento sobrevive al guardado final; un elemento largo no
frena a uno corto; reconstruir las dependencias no vacía la cola.

En el teléfono, versión release, antes y después, con cifras en `docs/benchmarks/`: tiempo hasta
"listo" de un short de YouTube y de un video de 3-4 horas, de la página de vaticannews, de un PDF
de cientos de páginas con texto y de uno escaneado, y de un audio o video local de al menos una
hora (con la extrapolación a 4 horas explícita); memoria máxima durante cada uno; cerrar la app a
mitad de una transcripción y de un reconocimiento de escaneos y comprobar que siguen desde donde
quedaron; borrar a mitad y comprobar que la cola sigue.

## Criterios de cierre

- [x] Ningún elemento queda "Procesando" para siempre: lo interrumpido se retoma, lo colgado vence.
- [x] Nada frena la cola: ni un elemento colgado, ni uno largo, ni uno borrado.
- [~] Un video de YouTube de 3-4 horas queda listo en segundos (con subtítulos disponibles). El
      camino ya no baja el audio —solo título, autor y transcripción, con tope de tiempo—, pero no
      se midió con un video real de cuatro horas.
- [x] Un video local de varios GB se guarda sin cargarse en memoria, y su transcripción se retoma
      donde quedó si se interrumpe. Lo segundo, medido en el emulador; lo primero, probado con
      pruebas y no con un archivo de varios GB en el dispositivo.
- [x] Un libro de cientos de páginas se abre al instante; su texto y el reconocimiento de sus
      páginas escaneadas avanzan en segundo plano con barra, y se retoman donde quedaron.
- [x] La página de vaticannews queda lista en una fracción de lo que tarda hoy, medida: archivarla
      pasó de 11,5 s y 335 pedidos a 1,1 s y 60 (PC).
- [x] Todo fallo muestra su motivo real y, si falta un modelo, cómo conseguirlo.
- [x] Invariante de chunking verde; la suite completa verde antes de cada commit. Con dos salvedades
      dichas en su momento: el commit 10 salió con un aviso del analizador en una prueba,
      corregido en un commit aparte; y cuatro pruebas de tiempo o de memoria fallaron alguna vez
      con la máquina cargada y pasaron solas —la del visor de documentos se corrigió de raíz—.

## Cierre

Diecinueve commits (del 1 al 17, más dos correcciones de prueba). Lo que quedó distinto del plan:

- **El esquema v31 llegó más tarde y más chico.** El motivo, los intentos y el estado del
  procesamiento ya tenían columnas en `source`; v31 solo agrega el avance guardado
  (`processing_checkpoint`).
- **Un defecto que no estaba en el plan:** medido en el emulador, sherpa-onnx descartaba el último
  medio segundo de cada tramo de 30 s. Los tramos pasaron a 29 s.
- **Cifras del emulador, no del teléfono**: el teléfono del usuario se usa a diario y no se tocó.
  La prueba en dispositivo (`integration_test/processing_benchmark_test.dart`) queda lista para
  medirlo cuando se pueda.
- **El modelo "base"** no se sumó: la elección, con las cifras del teléfono delante.
