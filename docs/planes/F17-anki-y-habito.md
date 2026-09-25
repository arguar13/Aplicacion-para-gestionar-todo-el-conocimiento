# F17 — Anki y hábito

> **Estado: aprobado y construido** (2026-09-25). Aprobado en el chat, tal como está escrito.
> Planificado con el masterprompt completo del encargo F12–F17 que el usuario pegó en el chat el
> 2026-09-24. Lo construido, lo que se midió y lo que no hace, en la Decisión 50 de
> `../arquitectura.md`. Lo que salió distinto de lo planeado: el commit 6 (prueba real en Anki y
> AnkiDroid) queda BLOQUEADO, sin cerrar —ni Anki de escritorio ni AnkiDroid están instalados en
> esta máquina—; los commits 7, 9 y 10 se partieron en sub-commits (7a/b/c, 9a/b, 10a/b) porque el
> trabajo real resultó más grande que uno solo, mismo criterio que ya usaron F9 a F16.

Sexta y última fase del encargo F12–F17. No cambia el texto de ninguna fuente ni un chunk. Al
cierre, `verifyChunkInvariant` en verde sobre la bóveda entera.

**Al final de F17 se puede:** exportar las tarjetas a un `.apkg` que se abre limpio en Anki y en
AnkiDroid, organizado en subdecks por la jerarquía de Temas del Atlas, con la procedencia de cada
tarjeta en el reverso, reexportando solo lo nuevo desde la última vez, con un TSV como camino
alternativo; y ver una racha diaria e insignias que premian destilar y consolidar —nunca
capturar—, con el historial de repasos que `review_log` ya guarda desde F11 y hoy no muestra en
ningún lado, todo apagable de un interruptor.

## Lo que ya existe (F17 completa, no crea de cero)

- **`AnkiPackageBuilder`** (`lib/features/export/data/services/anki_package_builder.dart`) ya arma
  un `.apkg` real: SQLite legacy (schema 11, el que cualquier Anki entiende al importar), un mazo
  fijo «Sinapsis», un modelo con dos campos (`Front`/`Back`) y una plantilla, `guid = card.id`.
  Mapea el SM-2 propio a los campos de Anki: tarjeta nueva si `repetitions == 0`; si no, tarjeta de
  repaso con `due` en días desde la creación de la colección, `ivl = intervalDays`, `factor =
  easeFactor × 1000` —el mapeo ya es fiel, no encontré un campo que se esté aproximando—.
  **Lo que NO hace hoy**, confirmado por su ausencia total en el archivo y en su test: no hay
  subdecks (todo va al mismo mazo), el reverso es solo la respuesta (sin fuente, sin fecha, sin
  cita), no hay exportación incremental (siempre exporta `getAll()` completo) y no hay TSV/CSV.
- **El sistema de tarjetas** (`lib/features/flashcards/`): `Flashcard` (con `sourceChunkId`,
  `sourceCharStart`, `sourceCharEnd` cuando la generó una extracción con match textual real —
  `locateQuote`—), `Sm2Scheduler.scheduleNext` (puro), `FlashcardRepository.review()` (una
  transacción: recalcula, actualiza la tarjeta e inserta una fila en `review_log`), y
  `ReviewScreen` (repasa de a una, sin contador de sesión ni racha).
- **`review_log`** ya guarda cada repaso desde F11 (`flashcardId`, `reviewedAt`, `grade`, `quality`,
  intervalo y facilidad antes/después) y **no tiene ninguna pantalla**: es la materia prima entera
  del historial de repasos de 17.2, ya esperando.
- **Nada de racha, hábito ni notificaciones existe.** Grepeé `streak|habit|racha` en todo `lib/`:
  cero resultados. Es la pieza genuinamente nueva de esta fase.
- **La jerarquía de Temas (F13)** ya resuelve «de un elemento a su cadena de temas»: `Tema` es una
  categoría del vocabulario con `parent_id`/`depth` en `property_values`, y `atlas_builder.dart` ya
  tiene el precedente exacto de recorrer ese árbol y armar rutas con nombre —el molde para los
  subdecks `Sinapsis::Historia::Roma::República`—. Un elemento puede tener VARIOS temas asignados a
  la vez, o ninguno: el encargo no dice qué hacer en esos casos (ver D1).
- **La procedencia ya es resoluble** con `FragmentLocatorResolver.locate` (dominio puro, sin
  `WidgetRef`, corre bien desde un caso de uso) + `citationSourceOf`. `citeFragment` —que arma la
  cita completa— SÍ depende de `WidgetRef`: no se puede llamar tal cual desde `AnkiPackageBuilder`
  (que hoy es puro y corre incluso sin bindings). Hay que resolver la cita ANTES de llamar al
  builder, en el caso de uso, no adentro de él.
- **Ningún exportador del proyecto tiene «incremental» ni TSV/CSV.** Grepeé `lastExportedAt|
  incremental` en todo `lib/`: los únicos resultados son de la compactación de SQLite, ajenos a
  esto. `ExportFormat` es un enum cerrado de cinco valores (markdown, texto plano, PDF, BibTeX,
  `.docx`); agregar TSV es sumar un sexto valor y un exportador, sin precedente que copiar más allá
  del patrón general de `Exporter`.
- **No hay ninguna dependencia de notificaciones** en `pubspec.yaml` (ni `flutter_local_
  notifications` ni parecida). Si F17 necesitara una notificación real del sistema operativo, es una
  dependencia nueva a aprobar aparte, mismo criterio que `disk_space_plus` en F12.

## Dónde el encargo choca con el código real (a confirmar al aprobar)

1. **Una tarjeta puede no tener tema, o tener varios.** El encargo pide mazo por tema pero no dice
   qué hacer en esos dos casos (D1).
2. **El checksum de duplicados de Anki se calcula sobre el campo `Front`, no sobre el `guid`.** El
   criterio de cierre 17.3 pide «reimportar actualiza en vez de duplicar, verificado a mano en Anki
   real» — es EXACTAMENTE lo que hace falta probar, porque no puedo saber desde acá si un `Front`
   editado después de exportar sigue reconociéndose como la misma nota al reimportar. Si no lo hace,
   lo reporto antes de intentar un arreglo raro (como forzar que el checksum no cambie, que sería
   falsear un dato).
3. **No hay dónde guardar «cuándo se exportó por última vez».** Hace falta un campo nuevo (D4), y
   con él, esquema nuevo otra vez (v23 si F16 no lo subió antes, si no v24).
4. **«Sin notificaciones culposas» no exige notificaciones del sistema operativo.** El encargo pide
   tono sobrio, no un canal específico: se puede cumplir con un aviso dentro de la app (D3), sin
   sumar una dependencia.
5. **«Una contradicción resuelta» y «un tema completo de punta a punta»** (dos de las insignias que
   el encargo nombra como ejemplo) no tienen un estado explícito en el código hoy: `RelationKind.
   contradicts` es solo un vínculo, sin un campo «resuelta». Hace falta definir un criterio medible
   para cada una (D7).

## Decisiones que necesito que confirmes (mi recomendación va primero)

- **D1 Una tarjeta sin tema va a un subdeck `Sinapsis::Sin tema`**; una con varios temas se exporta
  UNA sola vez, en el subdeck de su primer tema asignado (por orden de asignación) — nunca
  duplicada en cada subdeck. *Motivo:* duplicar inflaría «cien tarjetas repasadas» (una insignia de
  17.2) contando la misma tarjeta real varias veces.
- **D2 El subdeck usa el nombre tal cual del valor del vocabulario**, separado por `::` —el
  separador estándar de Anki—, en el mismo texto que el usuario ve en el Atlas: `Sinapsis::Historia::
  Roma::República`.
- **D3 El aviso de racha es dentro de la app** (un banner al abrir, o el mismo tipo de insignia que
  ya usa `dueFlashcardCountProvider` en el ícono de repaso), **no una notificación del sistema
  operativo.** Si en algún momento se quiere una notificación real, es una dependencia nueva
  (`flutter_local_notifications` o similar) que pido aprobar aparte, con el mismo criterio que
  `disk_space_plus`.
- **D4 «Incremental» es un campo `last_exported_at` nullable en `Flashcard`**, puesto al terminar
  una exportación exitosa; «exportar todo» queda como opción explícita aparte (un interruptor en el
  diálogo de exportar), para no atrapar a nadie que de verdad necesite reexportar todo —por ejemplo,
  al cambiar de dispositivo Anki—.
- **D5 El checksum de Anki es un riesgo a VERIFICAR, no a evitar.** El criterio de cierre 17.3 ya
  pide probarlo a mano; si el comportamiento real de Anki no cumple «actualiza, no duplica» para una
  tarjeta cuyo `Front` cambió, lo reporto con lo que encuentre, en vez de intentar un parche que
  falsee un dato para que Anki «no note» el cambio.
- **D6 La racha cuenta un día si CUALQUIERA** de estas acciones ocurrió, no una combinación: triar
  en la Bandeja (aceptar o descartar algo, no solo abrirla), extraer una nota atómica, editar una
  nota viva (cualquier campo con versión), repasar al menos una flashcard, o resolver algo en
  Vocabulario (fusionar, renombrar, mover en la jerarquía). Capturar una fuente nueva NO cuenta —tal
  como pide el encargo—. Con 1 o 2 días de gracia por semana (el encargo lo deja abierto): propongo
  2, para que una semana ocupada de verdad no corte una racha larga sin necesidad.
- **D7 Las insignias del encargo, con un criterio medible cada una**: primera nota `mature`; diez
  notas vivas; **una contradicción resuelta** = una relación `contradicts` que deja de existir entre
  las dos notas (se borra, o una de las dos se edita y dedujo la tensión) —a definir con más
  precisión al construirlo, si el criterio no alcanza a distinguir «se resolvió» de «se borró por
  otro motivo», lo reporto antes de escribirlo mal—; **un tema completo de punta a punta** = todas
  las fuentes de esa rama del Atlas (contando descendientes, D del 13.1) tienen al menos una nota
  viva `mature` que las cita; cien tarjetas repasadas (de `review_log`, repasos distintos, no
  tarjetas distintas); un mes de consolidación semanal = actividad significativa en cada una de las
  semanas del mes.
- **D8 El historial de repasos es una pantalla nueva sobre `review_log`**: curva de retención
  (proporción de `good`/`easy` por semana), tarjetas difíciles (mayor proporción de `again`),
  constancia (un calendario simple de actividad, como el de una racha de GitHub pero sin comparar
  con nadie).
- **D9 Un solo interruptor en Ajustes apaga TODO 17.2** —racha, insignias, historial— de una vez;
  encenderlo de nuevo no reconstruye lo que pasó mientras estuvo apagado (no hay «racha perdida que
  recuperar»: el apagado es honesto, no un pausado que sigue contando por atrás).

## Secuencia de commits (cada uno compila y analiza solo)

Bloque A — Anki (17.1)

1. `feat(export)`: esquema —`last_exported_at` en `Flashcard` (D4), aditivo—, con respaldo previo y
   compuerta de conteo. (Número de versión: v23 si F16 no se hizo antes, si no v24.)
2. `feat(export)`: subdecks por jerarquía —función pura que arma el `path` de Anki desde el `itemId`
   (recorre ancestros con el mismo patrón de `atlas_builder.dart`), con las reglas de D1/D2—.
3. `feat(export)`: procedencia en el reverso —el caso de uso resuelve la cita con
   `FragmentLocatorResolver`/`citationSourceOf` ANTES de llamar al builder, que solo recibe texto ya
   armado—.
4. `feat(export)`: exportación incremental (D4) —filtra por `last_exported_at`, con «exportar todo»
   como opción aparte—.
5. `feat(export)`: exportador TSV/CSV —`ExportFormat` gana un valor, exportador nuevo, separador y
   codificación explícitos—.
6. `docs(export)`: prueba real en Anki y AnkiDroid —reimportar actualiza en vez de duplicar (D5),
   subdecks, procedencia, TSV—, con lo que encuentre documentado en `docs/benchmarks/` o similar,
   igual que F12 documentó el dispositivo Android real.

Bloque B — hábito (17.2)

7. `feat(habit)`: cálculo de racha —servicio puro sobre lo que ya existe (`field_versions`,
   `review_log`, aceptar una sugerencia en `suggestions`) según D6, sin tabla nueva si alcanza con
   lo que ya hay; si no alcanza, una tabla mínima de eventos, reportado antes de agregarla—.
8. `feat(habit)`: indicador de racha en la app (D3), con los días de gracia.
9. `feat(habit)`: insignias —servicio puro con los criterios de D7—, con su pantalla.
10. `feat(habit)`: historial de repasos (D8), pantalla nueva sobre `review_log`.
11. `feat(habit)`: el interruptor único de Ajustes (D9).
12. `docs(arquitectura)`: Decisión 50, este plan pasa a «construido» — con esto se cierra también el
    encargo F12–F17 entero.

Si el paso 6 encuentra algo que Anki no admite de forma fiel, se documenta y se deja el TSV del
paso 5 como camino, nunca un `.apkg` a medias — tal como pide el encargo.

## Medición (Android = el emulador, rotulado; PC enchufada; real, cuando haya teléfono; Anki, en un
Anki de verdad)

El encargo no fija cifras para F17, salvo la prueba real de importación en Anki (17.3, no es una
cifra, es un sí/no verificado a mano). Propongo estos objetivos de rendimiento propios, para que los
apruebes o los cambies:

| Escenario | Objetivo propuesto |
|---|---|
| Exportar 1.000 tarjetas nuevas a `.apkg` | < 5 s |
| Reexportar de forma incremental, sin tarjetas nuevas | < 1 s |
| Calcular la racha y las insignias al abrir la app | < 100 ms |
| Abrir el historial de repasos con 10.000 filas en `review_log` | < 300 ms |

## Criterios de cierre (17.3, del encargo)

- [ ] Un `.apkg` exportado importa limpio en AnkiDroid y en Anki de escritorio.
- [ ] Reimportar actualiza en vez de duplicar (GUID estable), verificado a mano en Anki real.
- [ ] La procedencia viaja en la tarjeta.
- [ ] La racha no cuenta capturas.
- [ ] La gamificación es desactivable por completo.
- [ ] Invariante de chunking verde sobre la bóveda entera.

## Lo que no hará (dicho de antemano)

- **No sincroniza en vivo con Anki** (ni AnkiConnect ni ninguna API en vivo): entra y sale por
  archivo, como BibTeX y RIS en F15.
- **No compara ni compite con otros usuarios**, ni publica nada: todo local, dicho explícito en el
  encargo.
- **Los subdecks no migran solos** si la jerarquía de Temas cambia después de exportar: la próxima
  exportación refleja la jerarquía ACTUAL: los mazos viejos que ya se crearon en Anki no se
  renombran ni se mueven desde acá.
- **No manda notificaciones del sistema operativo** salvo que se apruebe una dependencia nueva
  aparte (D3).
- **No inventa una insignia por volumen puro** (ni «100 fuentes capturadas» ni parecidas): todas
  están ligadas a destilar, consolidar o repasar, nunca a capturar.

## Opcional, pero me ayudaría mucho

Un Anki o AnkiDroid instalado para la prueba del paso 6 —es un criterio de cierre explícito del
encargo (17.3) y no se puede verificar sin la app real—. Si no está disponible, F17 avanza hasta el
paso 5 y NO se declara cerrada, mismo criterio que el Android real de F12.
