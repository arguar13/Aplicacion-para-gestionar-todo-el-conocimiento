# F15 — Biblioteca académica (metadatos, citas, bibliografía, BibTeX y RIS)

> **Estado: aprobado y construido** (2026-09-21 / 2026-09-24). Aprobado en el chat, tal como está escrito, con las catorce decisiones D1 a D14 y los objetivos de medición propuestos. Lo construido, lo que se midió y lo que no hace, en la Decisión 48 de `../arquitectura.md`. Lo que salió distinto de lo planeado: el nombre de una persona terminó en cuatro columnas y no en las tres de D2 (se sumó `name_suffix`); los commits 5, 10, 11, 12 y 15 salieron partidos en más de uno; y **el objetivo propuesto de importar 5.000 entradas en 20 s NO se cumple**: medir mostró que el costo real es el del escritor único por entrada, no el de las transacciones, y el objetivo subió a la cifra real con margen (90 s).

Cuarta fase del encargo F12–F17. Cambia el esquema (v21 → v22), **de forma aditiva**: nada se
borra ni se reescribe. Restricción inalienable intacta: F15 no toca el texto de ninguna fuente ni
un chunk, no usa modelos de lenguaje —todo es determinista— y no agrega dependencias. Al cierre,
`verifyChunkInvariant` en verde sobre la bóveda entera.

**Al final de F15 se puede:** guardar los datos bibliográficos de una fuente (con autores como
entidad que se fusiona y se renombra como cualquier valor del vocabulario), copiar su cita en APA 7,
MLA 9, Chicago (notas y autor-fecha) e IEEE, armar la bibliografía de un espacio, de una rama del
Atlas, de una nota o de una selección, llevarla al pie de una nota exportada, e importar y exportar
BibTeX y RIS sin duplicar al reimportar.

## Lo que ya existe (F15 lo reemplaza, no parte de cero)

- `lib/features/citations/`: `CitationStyle` con APA, MLA y Chicago; `formatCitation`, que arma una
  cita en texto plano con lo único que hay —`authorName` tal cual, el año de `publishedAt` o «s.f.»,
  el título y el dominio de la URL—; `formatBibtex`, una entrada `@online`/`@misc` por fuente;
  `CitationSection` en el detalle (elegir estilo y copiar) y `BibtexExporter`. Dice de sí mismo que es
  una «simplificación deliberada»: no separa apellido y nombre y excluyó IEEE «hasta que alguien lo
  pida». Alguien lo pidió.
- `source` guarda `originUrl`, `authorName`, `authorUrl`, `publishedAt`, `capturedAt` y el archivo
  original. Nada de editorial, DOI, volumen ni autores estructurados.

## Dónde el encargo choca con el código real (a confirmar al aprobar)

1. **«Extender `source` con los campos» sale caro y frágil.** Cada campo versionado de `source` está
   enumerado en al menos seis lugares (`EntryField`, `MergeField`, `entry_merge_applier`,
   `set_union_merge`, `KnowledgeEntryWriter`, `knowledge_row_mapping`): quince columnas serían quince
   campos de linaje con su regla de conflicto. Propongo una tabla 1:1 `source_reference` y una de
   autores `source_contributor`, que en el linaje de F11 cuentan como **un solo campo**
   (`reference`): si dos dispositivos la editan, gana la más nueva entera y el conflicto se muestra
   con la cita ya armada, no con un JSON. El resultado para el usuario es el mismo que pide el encargo.
2. **Una referencia puede no tener texto** (un libro que solo se cita). Hoy toda fuente nace de una
   captura con texto. Eso es compatible: el invariante de chunking cuenta las fuentes sin texto
   aparte —«ni pasan ni fallan»— y F7 las ignora porque no tienen `dedupHash`. Hace falta un
   `SourceKind.reference`; el compilador marcará cada `switch` exhaustivo que lo necesite.
3. **El motor de F7 no sirve como está para «idempotente por DOI/ISBN».** Compara el hash y el simhash
   del TEXTO, y una referencia no tiene texto; además `selectCandidates` carga todas las huellas de la
   bóveda en cada consulta, lo que sería cuadrático en una importación de miles. Lo que sí se reusa de
   F7 es la fusión de duplicados y la pantalla de posibles duplicados, para las coincidencias difusas.
   La identidad por DOI/ISBN/URL es nueva: índices y normalización.
4. **La extracción automática hoy escribe sin preguntar**: `DocumentTransformer`, `WebArticleTransformer`
   y el de YouTube ponen título y `authorName` al capturar, y «lo que diga el documento gana sobre el
   nombre del archivo». Eso es procedencia (principio 2) y se queda. Lo NUEVO —autores estructurados,
   editorial, DOI, volumen— va por sugerencia a confirmar, con la infraestructura de F4
   (`SuggestionKind.metadata`). Un detalle a corregir: al adjuntar un PDF a una referencia importada,
   el transformador no puede pisarle el título y los autores que ya se confirmaron.
5. **Autores como vocabulario.** El vocabulario ya tiene categorías, valores, alias, fusión con
   deshacer (F8) y candidatos a fusionar por nombre normalizado: «García Márquez» y «Garcia Marquez» son
   exactamente el problema «Roma»/«roma». Pero un valor no tiene orden ni rol (autor, traductor,
   editor), y la fusión de valores hoy solo re-apunta asignaciones, alias e hijos de la jerarquía: hay que
   enseñarle a re-apuntar también las obras, y a deshacerlo.
6. **«Fragmento citado en una nota»**: hoy un `QuoteBlock` es solo texto, sin referencia a nada. Lo que
   sí existe es la relación `extractedFrom` con el rango de caracteres (la nota atómica) y los
   resaltados, y cada chunk sabe su página (`pageNumber`) o su minuto (`startMs`). Entonces «citado» =
   extraído o resaltado, y la página o el minuto se leen del chunk que contiene el rango.
7. **Exportar una nota con bibliografía**: `Exporter.export(item)` no recibe nada más que el elemento.
   Se le agrega un parámetro opcional con el apéndice. Markdown y DOCX ya se escriben a mano (`archive` +
   `xml`), así que las cursivas de una bibliografía son posibles sin dependencias.
8. **El portapapeles de Flutter es solo texto plano.** Una cita copiada pierde las cursivas. Para pegar
   con formato se ofrecen Markdown y `.docx`; un portapapeles enriquecido pediría una dependencia y no
   se hace.
9. **La bóveda sintética no tiene metadatos bibliográficos.** Se le agrega una capa aparte (un generador
   con su propia semilla, aplicado al final) para no mover nada de lo ya medido.

## Decisiones que necesito que confirmes (mi recomendación va primero)

- **D1 Autores = valores de una categoría de sistema «Autor»** (tipo nuevo `person`, sembrada por la
  migración como «Tema»), más una tabla `source_contributor` con el ORDEN y el ROL. Así renombrar, alias,
  fusionar con deshacer, candidatos a fusionar, «obras de este autor» y los filtros funcionan sin código
  paralelo. *Alternativa:* una tabla `author` propia, que copia todo eso.
  La asignación `item_property_values` del autor se mantiene **espejada** por el escritor (para que los
  conteos, «sin uso», el Explorador y la línea de tiempo funcionen sin tocarlos); la fuente de verdad de
  quién es autor, en qué orden y con qué rol es `source_contributor`.
- **D2 El nombre** se guarda como `name_family`, `name_given` y `is_institution` (tres columnas de
  `property_values`, con el precedente de las fechas y los números); la etiqueta canónica es
  «Apellido, Nombre» y es lo que el vocabulario compara. **No adivino nombres**: BibTeX y RIS traen el
  formato (`Apellido, Nombre` es fiable; `Nombre Apellido` sigue el algoritmo de BibTeX), y `authorName`
  —un canal de YouTube, una cuenta— se queda como texto literal hasta que alguien lo estructura.
  Dos personas con el mismo nombre se distinguen con un calificador en la etiqueta («García, Juan
  (historiador)»); la unicidad por categoría del vocabulario no se cambia.
- **D3 Los datos bibliográficos** viven en `source_reference` (1:1 con la fuente) y **aparte de
  `KnowledgeItem`**: las listas no cargan nada nuevo y el detalle pide la referencia por su clave.
  Campos: tipo, título del contenedor, editorial, lugar, edición, volumen, número, páginas, ISBN, ISSN,
  DOI, fecha de consulta, **clave de cita** (la que trae un `.bib`, para que exportar de vuelta conserve
  las claves que alguien ya usa en su texto) y la precisión de la fecha. El año NO se duplica: se reusa
  `Source.publishedAt` con su precisión (año, mes, día o «sin fecha»). La fecha de consulta de una fuente
  web es, por defecto, la de captura.
- **D4 Tipos y roles**: los ocho pedidos —libro, capítulo, artículo, tesis, fuente primaria, documental,
  sitio web, publicación en red— más «otro» (plantilla genérica con huecos marcados). Roles: autor,
  traductor, y dos que el encargo no nombra pero hacen falta —editor (un capítulo se cita «En A. B.
  (Ed.)») y director (un documental)—. Por defecto, sin tocar nada: página web = sitio web,
  YouTube y video = documental, publicación en red = publicación en red; un documento suelto no tiene
  tipo y su cita marca el hueco. Un `@inproceedings` de un `.bib` entra como artículo con el contenedor
  del congreso, y el informe de importación lo dice.
- **D5 Referencia sin texto = `SourceKind.reference`**, en estado «triado» (importar una bibliografía es
  una decisión deliberada; 300 entradas no inundan la Bandeja). Al adjuntarle un PDF pasa a `document`
  y sigue el camino de siempre —texto, chunks—, sin pisar lo confirmado.
- **D6 Los estilos son formateadores puros y desacoplados**, en un registro (como `ExporterRegistry`):
  agregar un estilo es una clase y una línea de registro. Devuelven **corridas** —texto plano, cursiva,
  hueco— y no un `String`, así el mismo resultado sale como texto, Markdown y `.docx` con cursivas y
  sangría francesa. Cinco variantes: APA 7, MLA 9, Chicago notas-bibliografía (nota completa, nota
  corta y entrada de bibliografía), Chicago autor-fecha e IEEE. Los términos («y», «Ed.», «pp.», «s. f.»,
  «En», «Consultado el») son datos puros en español e inglés, no ARB: los usa el dominio, sin contexto.
- **D7 Datos faltantes = hueco visible**, en lugar de inventar u omitir: `[falta: año]` resaltado en
  pantalla y literal en Markdown y `.docx`. Un año desconocido NO es «sin fecha»: hay un interruptor
  explícito «sin fecha» (→ «s. f.»/«n.d.»). Es un cambio respecto de hoy, donde un año ausente se
  escribía «s.f.» en silencio.
- **D8 El idioma de la cita** es el de la app por defecto, con un selector en la hoja de cita y en la
  bibliografía: una referencia en inglés en un trabajo en español se cita con los términos del trabajo.
- **D9 Identidad al importar**: DOI (normalizado) → ISBN-13 (10 y 13 se unifican, con dígito de control)
  → URL canónica → y solo entonces una coincidencia difusa (título + año + primer autor) que **propone,
  nunca fusiona sola** y va a la pantalla de duplicados de F7. Una entrada que coincide se **vincula**
  con la fuente que ya existe —si tenías el PDF de ese artículo, se le completan los metadatos, no se
  crea otra—. Reimportar completa lo vacío, **no pisa lo que el usuario tocó**, e informa las
  diferencias; un interruptor «priorizar el archivo» lo invierte.
- **D10 Qué es «realmente citado» por una nota**: las fuentes a las que llega por `extractedFrom`, por
  `cites` y por un `[[ ]]` que apunta a una fuente. `relatedTo` es una relación, no una cita.
- **D11 Bibliografía de un conjunto**: orden del estilo —alfabético por apellido sin acentos (a igual
  autor y año, sufijos a, b, c en APA y Chicago autor-fecha), IEEE numerada por el orden en que se
  muestra—. Se lee con una consulta liviana (una fila por fuente, sin texto) y no con `LibraryRepository.list`.
- **D12 Extracción como sugerencia**: una sola sugerencia `metadata` por fuente con todo lo hallado —Info
  y XMP del PDF; `<meta>` de la página (`citation_*`, `DC.*`, `og:` y JSON-LD); canal y fecha de
  YouTube—, que se ve pre-cargada y marcada en el formulario y en la Bandeja, y se confirma o se
  descarta. Nunca se escribe sin mirar. Las fuentes que ya existen no se recorren de golpe (10.000
  sugerencias inundarían la Bandeja): se generan al capturar y al abrir el formulario.
- **D13 Dónde aparece**: el detalle (tarjeta «Referencia» con el formulario y la cita); la selección de la
  Biblioteca; el menú de una rama del Atlas; el menú de un espacio; el menú de una nota; «Importar
  referencias» en el menú de la Biblioteca; el estilo y el idioma predeterminados en Ajustes.
- **D14 Importar adjuntos**: un PDF se vincula por el nombre que trae el campo `file`/`L1`, entre los
  archivos que se eligen **junto con** el `.bib`; en escritorio también junto al archivo. En Android el
  selector entrega copias, así que no hay una carpeta que recorrer: solo lo elegido. Las rutas
  absolutas del archivo original no se guardan.

## Secuencia de commits (cada uno compila y analiza solo)

1. `feat(reference)`: dominio puro —tipos y roles, `PersonName` con el algoritmo de nombres de BibTeX
   (apellido y nombre, «von», «Jr.», instituciones), normalización y validación de DOI, ISBN (con dígito
   de control) e ISSN, y la fecha con su precisión—. Sin base de datos.
2. `feat(db)`: esquema v22 aditivo —`source_reference`, `source_contributor`, columnas de persona en
   `property_values`, `PropertyValueType.person`, la categoría de sistema «Autor», índices por DOI e
   ISBN y un trigger que solo deja poner personas como autores—. Migración con respaldo previo y
   conteos como compuerta; `drift_schema_v22.json` y su prueba.
3. `feat(reference)`: el escritor único graba la referencia (campo de linaje `reference`), espeja los
   autores en `item_property_values`, `SourceKind.reference`, y la lectura liviana por ids y por conjuntos.
   Los censos de lectura y de escritura cubren las tablas nuevas.
4. `feat(vault)`: la fusión de bóvedas y las copias traen la referencia y sus autores, con su conflicto
   legible y el restaurar de F11.
5. `feat(vocabulary)`: los autores como vocabulario —alta y edición con apellido y nombre, alias,
   fusión que re-apunta las obras con su deshacer, candidatos a fusionar por variantes de nombre y
   «obras de este autor»—.
6. `feat(citations)`: el motor de estilos —interfaz, registro, corridas con huecos, términos es/en— y
   APA 7 para los ocho tipos. Pruebas con los ejemplos de la propia guía.
7. `feat(citations)`: MLA 9 e IEEE.
8. `feat(citations)`: Chicago, notas y autor-fecha.
9. `feat(citations)`: la bibliografía de un conjunto —orden, sufijos, numeración IEEE, salida en texto,
   Markdown y `.docx`— y de dónde salen los conjuntos: espacio, rama del Atlas con subtemas, nota, selección.
10. `feat(reference)`: el formulario en el detalle (lo mínimo visible, el resto plegado y según el tipo) y
    la sección de cita renovada —referencia, cita en el texto, nota; estilo e idioma; copiar—, con la cita
    de un fragmento (nota atómica y resaltado) con su página o su minuto.
11. `feat(reference)`: la extracción como sugerencia —PDF, `<meta>`, YouTube— y su confirmación en el
    formulario y en la Bandeja; el transformador de documentos deja de pisar lo confirmado.
12. `feat(export)`: la bibliografía al pie de una nota exportada a Markdown, PDF o `.docx`, y las
    entradas de «Bibliografía» desde la Biblioteca, el Atlas, el espacio y la nota.
13. `feat(import)`: BibTeX —analizador estricto (macros `@string`, llaves y comillas, acentos LaTeX,
    nombres) y exportador con claves únicas— con prueba de ida y vuelta.
14. `feat(import)`: RIS, con las mismas garantías.
15. `feat(import)`: importar y exportar desde la app —identidad por DOI/ISBN/URL, idempotencia, informe
    de creadas, actualizadas y saltadas con su motivo, vínculo de PDF y duplicados difusos a la pantalla de F7—.
16. `test(bench)`: la bóveda con referencias (capa aparte, semilla propia) y los escenarios de abajo, en
    el emulador; cifras versionadas.
17. `docs(arquitectura)`: Decisión 48; este plan pasa a «construido».

Si la medición del 16 pide un arreglo, va en un commit `perf(...)` antes del 17, como en F13 y F14; y si
una cifra obliga a rediseñar algo, lo reporto antes de hacerlo.

## Medición (Android = el emulador, rotulado; PC enchufada; real, cuando haya teléfono)

El encargo no fija objetivos para F15. Propongo estos, para que los apruebes o los cambies:

| Escenario | Objetivo propuesto |
|---|---|
| Abrir el detalle con su referencia y su cita | < 200 ms (el de siempre) |
| Buscar una referencia por DOI o ISBN | < 10 ms, con plan de consulta que use el índice |
| Bibliografía APA de la rama mayor del Atlas (unas 4.900 fuentes): leer, formatear y ordenar | < 3 s |
| Esa misma bibliografía como `.docx` | < 4 s |
| Importar un `.bib` de 5.000 entradas (analizar, identificar y escribir) | < 90 s |
| Reimportarlo sin cambios (todo «ya estaba») | < 30 s |
| Exportar 10.000 referencias a BibTeX y a RIS | < 5 s cada uno |
| Candidatos a fusionar entre 2.000 autores con variantes de escritura | < 1 s |

**Revisado tras medir en escritorio (commit 16):** los dos objetivos de importar subieron con la cifra
real, no con una estimación. Con la transacción por lote (una sola confirmación para las 5.000 entradas
en vez de miles sueltas) crear tarda ~20 s y reimportar sin cambios ~6 s, YA en escritorio y sin dividir
por ningún factor: el escritor único mantiene el índice de texto completo, el versionado y las tablas
espejo por cada entrada, el mismo costo que paga cualquier guardado normal de la app. Bajarlo de verdad
—saltarse esos triggers durante una importación masiva y rearmar el índice al final, como hace el
generador sintético con datos propios— es un rediseño del escritor único sobre datos reales de un
usuario, con más riesgo de dejar el índice inconsistente si algo falla a mitad de camino: queda como
límite conocido para una fase futura, no para este commit. La bibliografía de la rama mayor también subió
un poco (2 s → 3 s): en escritorio ronda 700-870 ms, más cerca del objetivo que el resto de los
escenarios.

Además, la memoria residente máxima de la importación —medida: 41-81 MB en escritorio, 78 MB en el
emulador—, y que el analizador de un archivo muy grande tenga un tope (30 MB, ya en el código) y no se
lleve la app por delante.

**Medido en el emulador** (`Sinapsis_Bench`, 16 GB de disco —`Pixel_9_Pro` solo tiene 6 y no alcanza para
esta bóveda de 15.000 elementos—; cifras en
`docs/benchmarks/emulador-Google-sdk_gphone16k_x86_64-android17/2026-09-24-f15/`): los diez escenarios
pasan, todos con margen amplio. El emulador comparte la CPU de la PC (enchufada) y por eso sale más
rápido que el propio escritorio en el import —4,9 s crear, 2,2 s reimportar, frente a 19,9 s y 6,3 s en
escritorio—: son cifras optimistas, no las de un teléfono de gama media, y quedan rotuladas como tales.

## Criterios de cierre (15.4)

Los cinco del encargo, más lo que F15 promete:

- Metadatos bibliográficos completos y editables por fuente, con autores que se fusionan y renombran.
- Cita en los cuatro estilos —con las dos variantes de Chicago—, copiable en un toque, con los huecos
  marcados en lugar de inventados.
- Bibliografía de un espacio, de una rama del Atlas, de una nota y de una selección, ordenada por estilo.
- BibTeX y RIS entran y salen; reimportar no duplica; una entrada que no se entiende se reporta y se
  salta, nunca se guarda a medias; **exportar y volver a importar devuelve lo mismo** (prueba de ida y vuelta).
- Las cifras de arriba, medidas en el emulador.
- Invariante de chunking verde sobre la bóveda entera; los dos censos verdes y cubriendo lo nuevo.

## Lo que no hará (dicho de antemano)

- **No es un motor CSL.** Son cinco variantes escritas a mano y probadas contra los ejemplos de las guías
  de cada estilo; no cubren todos los tipos de obra ni todas las particularidades (archivos y
  colecciones de una fuente primaria, patentes, leyes). Lo que no entra en los ocho tipos sale con
  la plantilla genérica y sus huecos. En un `.bib`, `@patent` o `@software` se reportan y se saltan.
- **No mide en un teléfono real**: solo hay emulador, y sus tiempos son optimistas.
- **No convierte de golpe las fuentes que ya existen**: su `authorName` sigue siendo texto y las citas lo
  usan tal cual, con el tipo y el resto marcados como huecos, hasta que alguien completa la referencia.
- **No copia con cursivas** (el portapapeles es de texto plano): para eso están Markdown y `.docx`.
- **No arma citas dentro del cuerpo** de una nota exportada: solo la bibliografía al pie. Tampoco resuelve
  homónimos por su cuenta ni cita en más idiomas que español e inglés.
- **No sincroniza con Zotero**: entra y sale por archivos. Los campos de un `.bib` o un `.ris` que F15 no
  guarda (resumen, palabras clave, notas) se cuentan en el informe de importación; no se pierden en
  silencio.
- **No busca ni descarga el PDF de un DOI**: vincula lo que el archivo trae.
- **Los `.bib` y `.ris` son exportaciones de REFERENCIAS, no de fuentes**: la exportación de una fuente
  (Markdown, PDF, `.docx`, texto) sigue devolviendo su texto íntegro, sin apéndice.

## Opcional, pero me ayudaría mucho

Un `.bib` y un `.ris` **exportados de tu Zotero** (unas 30 entradas reales, con lo que tengas de libros,
capítulos, artículos, tesis y páginas), y cómo Zotero formatea esas mismas entradas en los cuatro estilos.
Serían el corpus de aceptación: importan sin que se salte ninguna, y la cita generada se compara contra la
de Zotero. Sin eso pruebo con las guías y con archivos de ejemplo que armo yo, que es más débil.
