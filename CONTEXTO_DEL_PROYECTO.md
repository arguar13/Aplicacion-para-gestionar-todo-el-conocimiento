# Sinapsis — contexto completo del proyecto

Este documento es para quien empieza de cero, sin ningún recuerdo de sesiones anteriores
(una persona o una sesión nueva de Claude Code). Leyéndolo entero entendés qué es la app, cómo
está hecha, cómo se trabaja en este repositorio, qué reglas puso el dueño y en qué estado quedó
todo. Fecha del estado descrito: **2026-10-09** (`origin/main` = `8bce1cd`).

Documentos hermanos, de más general a más fino:

| Archivo | Para qué |
|---|---|
| `README.md` | Presentación del producto (el problema, qué acepta, qué reemplaza). Su sección «Estado» quedó vieja: no la tomes como el estado real. |
| `GUIA_DE_USO.md` | Manual de usuario, paso a paso, de **cada** función. Es la fuente de «qué hace la app hoy». |
| `docs/arquitectura.md` | Principios y **73 decisiones técnicas numeradas** (el porqué de cada cosa, con cifras medidas). Es la historia técnica real. |
| `docs/planes/F13…F31-*.md` | Los planes grandes que el dueño aprobó (F13 en adelante). |
| `lib/features/README.md` | Convención de capas de cada módulo. |
| `CONTEXTO_DEL_PROYECTO.md` | Este: la puerta de entrada. |

---

## 1. Qué es Sinapsis

Un **gestor de conocimiento personal** para guardar, entender y repasar todo lo que uno lee,
mira y escucha, sin perder nunca de dónde salió. **Funciona enteramente en el dispositivo**: sin
cuenta, sin servidor, sin suscripción, y con la IA corriendo localmente.

Recibe cualquier cosa y la convierte en **texto buscable con su procedencia**:

| Entra | Sale |
|---|---|
| Video o short de YouTube | Transcripción con marcas de tiempo, título, canal y enlace (sin clave de API) |
| Audio, nota de voz, podcast, reel | Transcripción con Whisper local |
| Foto o captura | Texto por OCR (ML Kit en Android, Tesseract en Windows y web) |
| Artículo o página web | Artículo limpio + copia de la página tal como estaba |
| Publicación de X, Bluesky, Mastodon | Texto, autor y enlaces |
| PDF, EPUB, DOCX, TXT, MD | Texto con estructura; el archivo original queda guardado |
| Apunte propio (notas de bloques) | Texto, igual que todo lo demás |

Sobre eso la app permite: **organizar** (etiquetas, temas jerárquicos, espacios, cuadernos,
propiedades tipadas, vínculos entre elementos), **explorar** (Biblioteca, Explorador, Atlas, Mapa,
grafo, línea de tiempo), **preguntarle a la bóveda** (chat con RAG local), **escuchar** (lector en
voz alta con el texto resaltado), **citar** (biblioteca académica, BibTeX/RIS) y **repasar**
(tarjetas con repetición espaciada, cuestionarios, hábito), además de **exportar** (Markdown, PDF,
HTML, NotebookLM, Anki).

Cuatro principios (detalle en `docs/arquitectura.md`, sección «Principios»): todo ocurre en el
dispositivo; la procedencia no se pierde nunca; nada de formatos cerrados (SQLite + archivos
sueltos + Markdown); degradar antes que fallar.

**Vocabulario del dominio.** *Bóveda* = la base de datos y los archivos del usuario, protegida con
una clave. *Elemento* (item) = lo guardado: una *fuente* (lo que vino de afuera) o una *nota*
(lo que escribió). *Forma* (rendition) = una representación de un elemento (el texto principal, la
transcripción, el archivo original). *Bandeja* = lo recién entrado, a revisar. *Contenido* = los
archivos que trae una página (documentos, imágenes, audios). *Tema* = el vocabulario controlado
jerárquico. *Cuaderno* = un subconjunto con nombre, fijo o por consulta.

## 2. Tecnología

- **Flutter / Dart** (SDK ≥ 3.8). **Android primero**; Windows y web también andan; iOS pospuesto a
  propósito.
- **Riverpod** (estado), **go_router** (navegación), **freezed** (entidades), **drift** sobre
  **SQLite con FTS5** (base local; **esquema v39**), **dio** (red), `l10n` con `.arb` en español e
  inglés (`lib/l10n/app_es.arb`, `app_en.arb`).
- **IA local:** `flutter_gemma` con **Gemma 4 E4B** para chat, resúmenes, tarjetas, huecos,
  clasificación; embeddings en el dispositivo para relaciones y duplicados; **Whisper small**
  multilingüe vía **sherpa-onnx** para transcribir. Los modelos **no vienen con la app**: se bajan
  aparte, una vez, con permiso explícito (en Android los baja el gestor de descargas del sistema, así
  que siguen aunque se cierre la app).
- Tres *flavors*: `dev`, `staging`, `prod` (puntos de entrada `lib/main_dev.dart`, etc.). El que se
  usa a diario es **dev**: paquete Android `app.sinapsis.dev`, versión `0.1.0-dev`.
- Clave de la bóveda: PBKDF2 en el almacén seguro; se pide **una vez por encendido del teléfono**
  (decisión 63).

## 3. Cómo está organizado el código

Ruta del repositorio: `C:\dev - aplicaciones creadas\Aplicacion para gestionar todo el conocimiento`.
Rama única: `main` (remoto `origin`, GitHub).

```
lib/
  main*.dart, bootstrap.dart   Puntos de entrada por flavor
  app/                         app.dart, router/ (app_router.dart, route_paths.dart), navegación,
                               enchufes globales (aviso diario, reanudar descargas, errores)
  core/                        database/ (app_database.dart, tablas, migraciones), domain/,
                               design/, gemma/, audio/, network/, storage/, telemetry/, util/
  features/<nombre>/           un módulo por función, cada uno con data/ domain/ presentation/
  l10n/                        .arb y generados
test/                          espejo de lib/ (+ support/ con arneses; ~7.800 pruebas)
tool/                          scripts de trabajo (ver sección 6)
drift_schemas/                 un schema_vN.dart por versión del esquema
docs/                          arquitectura.md, planes/, benchmarks/
android/ ios/ windows/ web/    plataformas
```

**Regla de capas** (`lib/features/README.md`): `presentation → domain ← data`. `domain` no importa
nada de `data` ni de `presentation`. Los repositorios devuelven `Either<Failure, T>` (fpdart). Un
caso de uso = una acción de negocio.

Módulos principales de `lib/features/`: `capture` (entrada), `library` (Biblioteca y repositorio
central), `viewer`, `reading`, `notes`/`blocks` (notas de bloques), `transform` (transformadores:
YouTube, web, PDF, audio…), `organize`/`vocabulary`/`atlas`/`map`/`graph`/`relations` (organización
y exploración), `explorer`, `notebooks`, `inbox`, `suggestions`, `duplicates`, `timeline`,
`chat`, `narration` (voz alta), `citations`, `flashcards` (repaso), `habit` (racha, insignias),
`anki_import`, `export`, `study_reminder`, `ai_organize` (la IA que organiza sola), `keep_working`
(trabajo con la app cerrada), `content_trash`, `trash`, `vault` (clave, copia, fusión),
`settings`, `health`, `dev_seed` (biblioteca de ejemplo).

## 4. Historia: qué se construyó, en orden

Las primeras ocho fases armaron la base (captura, transformaciones, documentos, organización,
grafo, chat con RAG, flashcards SM-2, exportar, OCR/Whisper, web, Windows). Desde ahí el trabajo
se numera **F1…F31**, cada una con su decisión en `docs/arquitectura.md` (y plan en `docs/planes/`
desde F13):

- **F1–F11** — un solo modelo de datos Fuente/Nota, vocabulario controlado, Bandeja de entrada,
  clasificación asistida, motor de relaciones con embeddings, grafo local, deduplicación, higiene,
  consolidación, unificación, **durabilidad** (papelera, versión por campo, restauración que fusiona).
- **F12–F17** — cierre de deuda; jerarquía temática y **Atlas**; **Mapa** de conocimiento; biblioteca
  académica (citas, BibTeX/RIS); **Cuadernos**; exportar completo a Anki y **hábito** (racha, insignias).
- **F18–F20** — Mapa medido antes de rediseñar; **modo lote** transaccional; **quizzes** con
  distractores reales (nunca inventados).
- **F21–F24** — procesamiento confiable (nada queda «Procesando» para siempre; lo largo va por partes
  y retomable); **fidelidad del texto** (lo guardado es el original, carácter por carácter); el texto
  sigue al audio palabra por palabra; el audio de cada video.
- **F25–F29** — lector flotante en voz alta; panel de la fuente; **la IA que organiza sola** (vínculos,
  tarjetas, temas, con «Lo que hizo la IA» y deshacer); «nada se pierde» (Bandeja, Mapa con vínculos
  y un solo «tema»); **el trabajo sigue con la app cerrada**.
- **F30** — chat rápido (respuesta a medida que se escribe, modelo liberado de la RAM), Repasar con
  IA, Cuadernos con IA, Bandeja de texto + papelera del contenido, «Bajar todo» de páginas.
- **F31** — **Repasar sin depender de Anki** (la más reciente, decisiones 69–73): SM-2 con **pasos de
  aprendizaje** (1 y 10 min), **día de estudio de 4:00 a 4:00**, límites **20 nuevas / 200 repasos**
  por día (globales, no por mazo), cola de estudio con alcance (todo, tema, etiqueta, cuaderno,
  elemento), deshacer/pausar/posponer; sesión interactiva (vuelta animada, gestos, vibración,
  resumen, atajos de teclado); **«Mis tarjetas»** (lista paginada, filtros, acciones en lote) y
  **estadísticas** (pronóstico a 30 días, reparto, botones usados); formas nuevas de tarjeta
  (**dos direcciones, huecos `{{c1::…}}`, «escribí la respuesta»**, huecos con IA); **importar `.apkg`
  de Anki** sin duplicar (la procedencia es un UUID v5 del guid de la nota); **aviso diario**
  nativo opcional; sección «Repasar» en Ajustes.

## 5. Estado actual (2026-10-09)

- `origin/main` = `8bce1cd`. Árbol limpio. **Suite: 7.845 pruebas pasan, 0 fallas, 77 omitidas**
  (las omitidas son de siempre). **Analizador: 19 avisos** — es la línea base de
  `tool/verify_commit.ps1` y **no puede crecer**.
- F31 está completa en código y documentación. Se instaló en el teléfono del dueño (Xiaomi Redmi
  Note 13 Pro+, serial `HI5LQ84PFAPVOJWK`) como **instalación nueva**: el dueño había desinstalado la
  app antes (le enlentecía todo), así que su bóveda y sus modelos anteriores se borraron (Android
  elimina los datos al desinstalar). Hay que bajar los modelos de nuevo desde Ajustes.
- Dos commits intermedios (`38e4b7d`, `2d891e2`) tienen 20 avisos en vez de 19 (un import
  desordenado que arregla `d96779d`); ya están publicados y no se reescribió la historia.

**Pendiente — solo se puede medir con el teléfono** (nunca se midió):
chat (tiempo hasta la primera palabra, palabras por segundo, GPU o CPU, RAM antes y después; en
Ajustes → modelo → «Cómo anda en este teléfono» y «Medir GPU y CPU»); recalibrar con Gemma real el
60 % del ancla tolerante de las citas y los umbrales de parecido de los cuadernos (0,45 y 0,6); la
cola de IA con las 80 muestras; HyperOS (MIUI) con la app cerrada; que el aviso diario suene y abra
Repasar; importar un `.apkg` real de Anki (exportado con «Compatibilidad con versiones antiguas»:
el formato nuevo `anki21b` va en zstd y **no se lee**, la app da un error claro).

**Limitaciones conocidas y a propósito:** sin FSRS (SM-2 por ahora); no se importan medios ni
historial de Anki; no existe «tiempo estudiado» (el historial no guarda duración); borrar tarjetas
no pasa por la papelera (la papelera es de elementos); opción múltiple no se edita; las imágenes de
una página están dos veces (copia archivada + «Contenido»), decisión del dueño de dejarlo así; en la
web no se importa de Anki.

## 6. Cómo se trabaja en este repositorio

**Herramientas de `tool/`:**

- `tool/verify_commit.ps1 -Rev <hash>` — compila y analiza **ese commit** en aislamiento (no corre
  pruebas) y exige no pasar la línea base de avisos. Correrlo desde PowerShell, no desde Git Bash,
  y **mirar su resultado antes de hacer `git push`** (en una cadena no frena).
- `tool/run_suite.ps1 -Log <nombre>` — corre la suite completa sobre una **copia** en `%TEMP%`
  (30–45 min); el registro termina con `EXIT <código>`.
- `tool/arb_union.py` — junta los `.arb` cuando chocan en un cherry-pick:
  `python tool/arb_union.py lib/l10n/app_es.arb lib/l10n/app_en.arb`.
- `tool/arb_agregar.py <arb> <bloques.txt>` — agrega claves **como texto** antes del `}` final.

**Comandos habituales:**

```
dart run build_runner build --delete-conflicting-outputs   # freezed/drift
flutter gen-l10n                                            # textos
git checkout -- windows/                                    # build_runner lo reescribe sin querer
flutter analyze                                             # mirar el número: base 19
flutter test <archivo> --timeout 60s                        # de a pocos archivos
```

**Trampas que ya costaron caro:**

- `dart format` sobre carpetas enteras reformatea archivos ajenos: formatear **solo lo propio**.
- Los `.arb` se editan **solo insertando líneas** antes del `}` final; nunca cargar y volcar el JSON.
- Heredocs de bash con comillas complejas fallan: escribir el script con la herramienta de archivos.
- Las pruebas de memoria fallan bajo carga: si una falla sola y pasa una por una, es de carga.
- `git commit` sin pathspec commitea el índice tal cual, no el árbol de trabajo.
- Una columna nueva en `flashcards`/`flashcard_options` hay que revisarla en tres censos (fusión,
  `repoint_item_references_v18`, la tabla misma). El censo de lecturas de `item`
  (`test/core/database/read_census_test.dart`) exige decidir qué pasa con la papelera.
- `drift_dev schema generate` reescribe todos los `schema_vN.dart`: restaurar los viejos con git.
- Un `Zone.root.run` o un futuro sacado de la zona del test **cuelga** los tests de widgets; dentro
  de una transacción de la biblioteca, la búsqueda de duplicados se lanza al confirmar
  (`_afterCommit`). En `testWidgets`, `watchAll().first` sobre un stream de la base se cuelga.
- Un `flutter_tester` huérfano deja `build/native_assets/.../sqlite3.dll` tomado y el siguiente
  `flutter test` falla sin mensaje de prueba. Cerrar los procesos propios.
- Git Bash convierte `/data/...` en rutas de Windows: usar `MSYS_NO_PATHCONV=1` con `adb`.

**Integrar el trabajo de agentes** (el método usual): cada agente trabaja en su propio *worktree*
(`isolation: "worktree"`, rama `worktree-agent-<id>`, carpeta `.claude/worktrees/`). Se integra con
`git cherry-pick $(git rev-list --reverse <base>..<rama>)`; después `build_runner` + `gen-l10n` +
`git checkout -- windows/`; `flutter analyze` (≤ 19); `verify_commit` **por hash** de cada commit;
suite completa; push; borrar la copia con `git worktree remove -f -f` y `git branch -D`. Si un
agente corrige algo dentro de un commit intermedio, va en **ese** commit
(`git cherry-pick -n` + `git checkout <fix> -- <archivos>` + `git commit -C`). Si un agente se corta
por límite de uso, `SendMessage` al mismo agente lo reanuda (si no dejó commits, su copia
desaparece y hay que relanzar). **Todos los agentes con Sonnet 5.5** (`model: "sonnet"` explícito).

**Instalar en el teléfono** (solo cuando el dueño lo pide):

```
flutter build apk --flavor dev --release -t lib/main_dev.dart --target-platform android-arm64
adb -s <serial> push -Z build/app/outputs/flutter-apk/app-dev-release.apk /data/local/tmp/sinapsis.apk
sha256sum <local>   vs   adb -s <serial> shell sha256sum /data/local/tmp/sinapsis.apk   # deben coincidir
adb -s <serial> shell pm install -r /data/local/tmp/sinapsis.apk
adb -s <serial> shell rm -f /data/local/tmp/sinapsis.apk
```

El cable del teléfono es viejo e inestable: una copia corrupta del mismo tamaño ya hizo fallar una
instalación (de ahí el `sha256`). Si sale *offline*: `adb reconnect offline` / `adb kill-server`; el
dueño a veces debe desbloquear la pantalla o reactivar «Depuración USB (ajustes de seguridad)».
Instalar encima conserva datos y modelos **solo si la app ya estaba instalada** (verificar con
`firstInstallTime` en `dumpsys package app.sinapsis.dev`). La compilación en frío tarda ~6 min.

## 7. Reglas permanentes del dueño

1. **Hablarle siempre en español rioplatense**, incluidas las notas internas, las descripciones de
   comandos y las instrucciones a los agentes.
2. **Errores de raíz:** nada de parches temporales, `skip`, timeouts alargados, excepciones tragadas ni
   pruebas aflojadas. Ante una falla se corrige la causa real.
3. **Toda prueba clave se comprueba por mutación:** deshacer el arreglo, ver que la prueba falla, y
   **verificar que la mutación se aplicó de verdad** (una mutación mal armada ya dejó pasar pruebas
   sin probar nada).
4. **Cada avance se commitea y se sube** (`git push origin main`); mensajes de commit en español,
   con el pie `Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>`.
5. **Actualizar `GUIA_DE_USO.md`** con cada cambio visible para el usuario, y revisarla completa al
   cerrar una fase.
6. **Los planes grandes** van en `docs/planes/` y el dueño aprueba escribiendo «aprobado» en el chat.
   Las decisiones técnicas se numeran en `docs/arquitectura.md` (hoy llegan a la 73). Lo que el
   dueño debe leer va dentro del workspace con enlace relativo.
7. **Limpieza al terminar:** borrar compilaciones y temporales viejos (`build/` pesa ~4 GB), medir el
   espacio antes y después, apagar Gradle/emulador/pruebas propios (`./gradlew --stop` en `android/`).
   **No tocar los procesos de VS Code** (el servidor de Kotlin y su Gradle no son nuestros).
8. **Teléfono:** nunca instalar una versión nueva sin que el dueño lo pida o avise. Los agentes no
   usan el emulador ni el teléfono. Para probar en Android, si hace falta, el AVD `Pixel_9_Pro` del PC
   (cifras rotuladas «emulador»).
9. **No instalar software que no se pidió.**
10. Si algo es difícil de revertir o sale hacia afuera (push forzado, borrar, reescribir historia),
    **preguntar primero**.

## 8. Cómo arrancar una sesión nueva

1. Leé este documento y, de `GUIA_DE_USO.md`, el índice y la sección que toque el pedido.
2. `git status`, `git log --oneline -10`, `git worktree list` (¿quedaron copias de agentes?).
3. Si vas a cambiar código: leé la decisión correspondiente en `docs/arquitectura.md` (buscá
   `### <número>.`) y el plan de `docs/planes/`.
4. Antes de dar algo por hecho: `flutter analyze` (19), pruebas de lo que tocaste, `verify_commit`
   por hash, y la suite completa antes de cerrar una fase.
5. Si el dueño pide una función grande, escribí primero el plan en `docs/planes/` y esperá su
   «aprobado».
6. Al terminar: actualizar guía y decisión, commit, push, limpieza (regla 7).
