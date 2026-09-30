# F22 — Fidelidad del texto: transcribir y extraer sin cambiar nada

> **Estado: aprobado** (2026-09-30), en el chat, "totalmente": las decisiones A, B, C y D como se
> recomendaron. Nace del uso real de la
> versión release en el teléfono (Xiaomi 23090RA98G, HyperOS), el día después de cerrar F21:
>
> 1. Un audio de 3 minutos tardó mucho en transcribirse.
> 2. Una alabanza salió transcrita con un texto que no tiene nada que ver ("es tu maquillaje, es
>    tu maquillaje…" decenas de veces, "no sé si la verdad es verdad…" otras tantas).
> 3. En un libro PDF, mantener apretado sobre la página para copiar un fragmento no copia nada: el
>    visor entero se pone gris.
>
> Y un pedido general: **toda transcripción o extracción —audio, video, libros, lo que sea— tiene
> que ser fiel al original: no cambiar, no borrar, no alterar nada.**

## Lo que se puede prometer y lo que no

- **La app no va a alterar nada a propósito.** Hoy sí lo hace en varios lugares (ver abajo): une
  palabras cortadas por guion, borra los saltos de línea de los libros, agrega barras invertidas,
  guarda traducciones en vez del original. Todo eso se corrige.
- **Los motores de reconocimiento —voz y OCR— se equivocan a veces**, y ninguno es perfecto con
  música cantada. Lo que sí se puede garantizar es que la app **detecte y corrija los errores
  groseros del motor** (los bucles de repetición y el texto inventado sobre silencio), que no se
  pierdan palabras en los cortes, y que la precisión se **mida con cifras** —contra transcripciones
  hechas por personas— y no se suponga.

## Qué pasa de verdad (medido, no supuesto)

Todo reproducido en la PC con el mismo motor y la misma versión que usa la app (sherpa-onnx 1.13.8,
Whisper small int8, 4 hilos, español fijo, tramos de 29 s). Dos audios de prueba: una alabanza
cantada con música ("La Bondad de Dios", 5 min) y 10 minutos de una charla TEDx en español con
subtítulos hechos por personas, contra los que se cuenta cada palabra.

### 1. El texto inventado de la alabanza: un bucle de Whisper, sin protección

Whisper, cuando se confunde —música, canto, un tramo raro—, puede entrar en un **bucle**: repite
la misma frase hasta agotar el límite del tramo. En la alabanza de prueba pasó en un tramo: "oh, oh,
oh…" **90 veces**. Es exactamente lo que se ve en tus capturas. La app no tiene ninguna defensa:
guarda lo que salga.

- *Evidencia:* índice de repetición (compresión del texto, el mismo criterio que usa Whisper
  original) de **9,4** en ese tramo; un texto normal da entre 1 y 2.
- *Y además es lo que lo hace lento:* ese tramo tardó **24,8 s**; los demás, **3 a 7 s**. Un audio
  con música puede caer en varios bucles, y cada uno cuesta cinco veces más.
- *La corrección probada:* volver a transcribir el tramo que entró en bucle, partido en dos mitades.
  En la prueba, las dos mitades salieron limpias ("de la bondad de Dios." y la pausa musical).

### 2. El corte fijo cada 29 segundos pierde y deforma palabras

Hoy el audio se corta cada 29 s exactos, caiga donde caiga: en medio de una palabra, de una frase.
Probé cortes más cortos y cortes en la pausa más cercana:

| Cómo se corta el audio | Diferencia con los subtítulos humanos | Palabras perdidas | Bucles en la alabanza |
|---|---|---|---|
| Cada 29 s exactos (hoy) | 16,2 % | 79 | sí (índice 9,4) |
| Cada 14,5 s exactos | 16,4 % | 78 | no |
| **Hasta 14,5 s, en la pausa más cercana** | **15,2 %** | **67** | **no** |

Parte de esa diferencia no son errores: los subtítulos de TED están editados, no son literales
("Y durante esta ponencia" contra lo dicho: "A lo largo de esta ponencia"). Lo que importa es la
comparación entre filas: cortar en pausas pierde **15 % menos palabras** y no entra en bucles.

### 3. Por qué no cambiar de motor

Probé tres motores más, con los mismos audios:

- **Parakeet v3 (NVIDIA)**: en la charla, igual de preciso que Whisper (17,6 %) y **4 veces más
  rápido**. Pero con canto es mucho peor: se saltea versos enteros y mete portugués ("Eu cantarei",
  "Tão fiel"). Además pesa 670 MB más para descargar.
- **Qwen3-ASR**: con la alabanza **tradujo la letra al inglés** y entró en un bucle peor que
  Whisper. Descartado.
- **Un detector de voz (Silero)** para transcribir solo donde hay voz: descartó **186 de los 299
  segundos** de la alabanza, porque al canto con música no lo considera voz. Para fidelidad es
  inaceptable: se perderían versos enteros.

Whisper small sigue siendo el mejor con canto y empata en habla. La corrección es protegerlo, no
reemplazarlo.

### 4. El idioma

Whisper está fijado en español. Si lo dejo detectar el idioma solo, confunde el español con
**gallego** y escribe sin acentos ("por que tantos seres humanos" en vez de "por qué"). Pero con el
español fijo, un audio en inglés sale **traducido** o deformado, no transcrito. Ver la decisión B.

### 5. La lentitud

En la PC, Whisper small tarda **0,2 veces la duración** en la alabanza, una vez sin bucles, y
**0,48 veces** en habla densa. No tengo la cifra de tu teléfono: el día anterior no estaba
conectado para medir. Es lo primero que se mide, con el motor solo, sin tocar la app, probando
2, 4, 6 y 8 hilos, porque en tu procesador (2 núcleos grandes y 6 chicos) más hilos no siempre
es más rápido. Con eso se fija la configuración, y se decide si hace falta la decisión D.

### 6. El PDF gris: un defecto de la biblioteca del visor, no del libro

`pdfrx` 2.6.1, el visor de PDF, pasó a usar una copia propia de los componentes de Material
(`material_ui`), con sus propias traducciones. La app no las carga. Al mantener apretado, el visor
selecciona el texto y arma el menú "Copiar / Seleccionar todo"; el menú pide las traducciones, no
las encuentra y **se rompe**. En la versión release, Flutter reemplaza lo que se rompió por un
recuadro gris que ocupa todo el visor. El triángulo tenue que se ve en tu captura es el tirador de
la selección, debajo del gris: la selección sí funcionaba.

- *Evidencia:* `pdfrx/lib/src/widgets/pdf_viewer.dart:9` importa `material_ui`; el menú por
  defecto (`:3610-3639`) usa el `AdaptiveTextSelectionToolbar` de `material_ui`, que en Android
  llama a `MaterialLocalizations.of(context)` (`material_ui-1.2.0/.../adaptive_text_selection_toolbar.dart:216`);
  la app solo registra las traducciones de Flutter (`flutter_localizations`), que son de otro tipo.
- *Corrección de raíz:* darle al visor las traducciones y el tema que espera, en el borde del visor.

### 7. Dónde la app altera el texto hoy (inventario completo)

Revisé el camino de cada tipo de fuente, desde el archivo original hasta el texto que se guarda.
La base guarda lo que le entregan sin tocarlo, y la fragmentación reconstruye el texto exacto:
**lo que altera está en cada lector**.

**Libros PDF**
- Une palabras cortadas por guion al final de línea: "teórico-⏎práctico" pasa a "teóricopráctico",
  y "1990-⏎1995" a "19901995".
- Convierte cada salto de línea en espacio: se pierde la forma de poemas, listas, tablas, índices y
  títulos. Una página entera queda como un solo párrafo.
- Colapsa espacios: se pierden las columnas alineadas.

**PDF escaneados**
- Solo reconoce una página si no tiene **ninguna** letra. Una página escaneada con un número de
  página o una marca de agua como texto real **nunca se reconoce**, y su contenido se pierde.
- Si el reconocimiento de una página falla, se guarda como página vacía **y reconocida**: no se
  reintenta nunca y no avisa.

**Audio y video del teléfono**
- Bucles, cortes a mitad de palabra e idioma: puntos 1, 2 y 4.
- Todo queda en una sola línea, sin pausas ni marcas de tiempo (ver la decisión C).

**YouTube**
- Baja una sola pista de subtítulos y prefiere la española. Un video hablado en inglés que tenga
  subtítulos en español guarda **la traducción**, no lo que se dijo.

**Word (DOCX)**
- Ignora los controles de contenido, en los que suelen estar las portadas, los índices y secciones
  enteras de las plantillas. También ignora los encabezados, pies de página, notas al pie y
  comentarios.
- Cambia la numeración real de Word ("1.", "a)", "3.2.1") por guiones.
- Pierde símbolos y guiones irrompibles ("e‑mail" pasa a "email").
- Duplica el texto de los cuadros de texto.
- Borra un "****" literal ("Clave: ****" pasa a "Clave: ").
- Pierde las tablas dentro de tablas.

**EPUB**
- Vuelca como texto el título interno de cada capítulo y el CSS o JavaScript que tenga dentro.
- Agrega barras invertidas: "[1]" pasa a "\[1\]", "1. Intro" a "1\. Intro".
- Pega los superíndices: "10⁶" pasa a "106".
- Se saltea los capítulos marcados como no lineales, que suelen ser notas y apéndices.

**Páginas web y redes sociales**
- Lee toda página como UTF-8: una página en Latin-1 pierde las tildes ("a�o").
- Una página con menos de 250 caracteres de artículo **se descarta entera**.
- Agrega las mismas barras invertidas que en EPUB.
- Deja sin traducir entidades HTML como "&#233;" o "&nbsp;".

**Texto plano**
- Un .txt en Latin-1 o UTF-16 sale con caracteres rotos.

**Al mostrarlo**
- Todo el texto extraído se dibuja como Markdown: un "var_uno_dos" del OCR se ve en cursiva y sin
  guiones bajos. Lo guardado está bien; lo que se ve, no.
- El botón "Quitar marcas de tiempo" aparece en cualquier texto con una línea que empiece como
  "[12:30]", incluidos PDF y Word, y además de quitar las marcas **junta todos los párrafos**.

*Solo escritorio:* Tesseract en Windows devuelve el texto mal decodificado ("canción" pasa a
"canciÃ³n").

## El principio que se adopta

**Lo que se guarda es el original, carácter por carácter.** Estructura (párrafos, saltos de línea,
títulos, listas) incluida. Lo que necesita otra forma —la búsqueda que tiene que encontrar
"explicaciones" aunque en el libro diga "ex-⏎plicaciones", el chat, las tarjetas— la **deriva** del
original sin tocarlo. Cada lector tiene pruebas con archivos reales que comparan lo guardado contra
lo esperado **carácter por carácter**.

## Decisiones para vos

- **A. El motor de transcripción.**
  - **Recomendado:** seguir con Whisper small —el mejor con canto, sin descargar nada nuevo—
    y agregarle las protecciones medidas: cortes en pausas, detección y corrección de bucles, y
    no transcribir el silencio puro (ahí es donde Whisper inventa frases como "Subtítulos
    realizados por la comunidad de Amara.org").
  - *Alternativa:* Parakeet para el habla (4 veces más rápido) y Whisper para la música. Es más
    complejo, suma 670 MB de descarga y hay que decidir qué es música, así que solo lo propondría
    si tu teléfono resulta lento con las protecciones puestas (decisión D).
- **B. El idioma de los audios.**
  - **Recomendado:** español por defecto, y un selector "Idioma del audio" en el detalle del
    elemento, junto a "Volver a transcribir", para el audio que no sea en español.
  - *Alternativa:* un ajuste general, igual para todos los audios.
- **C. Marcas de tiempo en las transcripciones de audio y video del teléfono.**
  - **Recomendado:** una línea por tramo con su minuto, "[3:15] …", igual que las de YouTube.
    Permite ubicar una frase en el audio, y la búsqueda y las citas ya las entienden. No cambian
    ni una palabra de lo dicho, y el botón "Quitar marcas de tiempo" las saca si no las querés.
  - *Alternativa:* texto corrido, como hoy.
- **D. La velocidad.** Se mide primero en tu teléfono (te pido conectarlo 15 minutos). Si con las
  protecciones una hora de audio tarda más de una hora, te traigo las cifras y la opción A
  alternativa para que decidas vos. No la agrego sin tu aprobación.

Lo que ya está en tu bóveda —la alabanza de la captura, por ejemplo— no cambia solo. Se agrega
**"Volver a extraer el texto"** en el detalle de cada elemento. Tus subrayados se vuelven a ubicar
en el texto nuevo por su contenido. Si alguno ya no aparece igual, se conserva con su texto
copiado y un aviso, no se borra.

## Secuencia de commits (cada uno compila, pasa el analizador y la suite completa por sí solo)

1. `fix(viewer)`: copiar texto del PDF. El visor recibe las traducciones y el tema de
   `material_ui`, y el menú sale en español y en modo oscuro. Incluye una prueba de regresión que
   construye el menú.
2. `fix(transform)`: tramos de hasta 14,5 s, cortados en la pausa más cercana. Lo que ya estaba a
   medio transcribir con los tramos viejos se retoma desde cero, sin mezclar los dos cortes.
3. `fix(transform)`: protección contra bucles. Se detectan por el índice de repetición y por
   frases repetidas, y el tramo se vuelve a transcribir en mitades, hasta dos veces. Si aun así
   repite, se guarda la parte que no se repite y una marca visible "[fragmento no reconocido
   m:ss–m:ss]": un hueco honesto, no texto inventado.
4. `fix(transform)`: el silencio puro no se transcribe. Se decide por la energía de la señal, no
   por un detector de voz: el canto nunca se descarta.
5. `perf(transform)`: hilos y configuración medidos en tu teléfono, con las cifras en
   `docs/benchmarks/`.
6. `feat(transform)`: idioma del audio (decisión B) y marcas de tiempo por tramo (decisión C).
7. `fix(transform)`: PDF fiel. Los saltos de línea y los guiones quedan como en el libro, y la
   búsqueda sigue encontrando las palabras cortadas, porque el índice recibe la versión unida.
8. `fix(transform)`: PDF escaneados. Una página se reconoce si casi no tiene texto y es sobre todo
   imagen. Un reconocimiento fallido queda como fallido y se reintenta, no como página vacía.
9. `fix(transform)`: Word fiel. Controles de contenido, encabezados, pies, notas, numeración real,
   símbolos, cuadros de texto sin duplicar, "****" y tablas anidadas.
10. `fix(transform)`: EPUB fiel. Sin título interno ni CSS ni JavaScript volcados, sin barras
    invertidas, superíndices marcados, y los capítulos no lineales al final en vez de perdidos.
11. `fix(transform)`: web y redes fieles. Se respeta la codificación que declara la página, se
    traducen todas las entidades HTML, no se agregan barras invertidas, y un artículo corto se
    guarda igual en vez de descartarse.
12. `fix(transform)`: texto plano con su codificación (UTF-16 con BOM, Latin-1 o Windows-1252), y
    Tesseract en UTF-8 en escritorio.
13. `fix(transform)`: YouTube guarda los subtítulos en el idioma en que se habla, no una
    traducción.
14. `fix(library)`: el texto extraído se muestra tal cual. Markdown solo en lo que de verdad es
    Markdown (notas, y la estructura de Word, EPUB y web). "Quitar marcas de tiempo" solo aparece en
    transcripciones y conserva las líneas.
15. `feat(library)`: "Volver a extraer el texto" por elemento, con los subrayados reubicados.
16. `test(transform)`: banco de fidelidad. Archivos reales de cada tipo con su texto esperado
    carácter por carácter, más la medición de audio contra transcripciones humanas en el
    dispositivo.
17. `docs(arquitectura)`: Decisión 55 y cierre de F22. Versión release instalada en tu teléfono y
    limpieza del disco de todo lo que generé y ya no sirve.

## Cómo se verifica

Mismo ritmo de siempre por commit:

1. Formato, analizador y tests del área.
2. Suite completa en la copia aislada.
3. Commit, árbol limpio y push.

Pruebas nuevas:

- **Audio:** con un reconocedor falso, un tramo en bucle se vuelve a transcribir en mitades, un
  bucle que no se corrige deja la marca de hueco, el silencio no llega al motor y los cortes caen
  en la pausa.
- **Visor:** el menú de copiar se construye sin error dentro de la app.
- **Cada lector:** el texto guardado es idéntico al esperado, archivo por archivo.
- **Búsqueda:** una palabra cortada por guion en un PDF se encuentra.
- **Subrayados:** sobreviven a "Volver a extraer el texto".

En tu teléfono, con la versión release:

- **Audio:** la misma alabanza y un audio hablado de al menos 10 minutos, con el tiempo que tardan
  y el texto que dan, antes y después.
- **PDF:** mantener apretado, copiar un párrafo y pegarlo en otra app.

## Criterios de cierre

- [ ] Mantener apretado en un PDF selecciona el texto, y "Copiar" lo copia.
- [ ] Ningún bucle de repetición llega al texto guardado: la alabanza de prueba sale sin
      repeticiones inventadas.
- [ ] Los cortes del audio caen en pausas; pierden menos palabras que hoy, medido contra
      subtítulos humanos.
- [ ] La velocidad en tu teléfono está medida, con cifras antes y después.
- [ ] Ningún lector une, borra, escapa, traduce ni reordena texto: cada uno con su prueba carácter
      por carácter.
- [ ] Lo que ya estaba en la bóveda se puede volver a extraer sin perder subrayados.
- [ ] Suite completa verde antes de cada commit. Disco limpio al terminar.
