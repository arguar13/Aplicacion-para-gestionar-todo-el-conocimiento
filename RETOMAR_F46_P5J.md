# Retomar F46, paso 5j (pausa del 7/11)

Rama `worktree-agent-a0649bc38173a89bb`, sobre main `f0136493`. Antes de entregar: **deshacer
el commit wip** (`git reset --soft HEAD~1`, y después `git restore --staged .` si hace falta),
**borrar este archivo y la carpeta `retomar_f46_p5j/`**, y commitear 2a y la guía como se dice
abajo.

## Hecho y commiteado

- `9383e2e7` **fix(diseño) — 1b**, los paneles en el navegador de la raíz. COMPLETO:
  `lib/core/design/widgets/app_bottom_sheet.dart` (`showAppBottomSheet` +
  `AppBottomSheetFrame`: raíz, `isScrollControlled`, `useSafeArea`, manija, sin animación con
  «quitar animaciones», teclado, borde seguro de abajo, `maxHeightFactor`, `ownSurface`, captura
  del `ProviderScope` de quien abre con `UncontrolledProviderScope`). **Las 82 llamadas a
  `showModalBottomSheet` de `lib/` están migradas; no falta ninguna** (las otras dos apariciones
  eran comentarios, ya corregidos). Censo: `test/core/design/bottom_sheet_census_test.dart`.
  Pruebas: `test/core/design/widgets/app_bottom_sheet_test.dart` (14), 5 nuevas en
  `test/app/navigation/adaptive_scaffold_test.dart` (shell real: barra y riel tapados, «atrás»,
  teclado en «Con IA») y 1 en `read_aloud_overlay_test.dart` (el reproductor con un panel en la
  raíz). Esas dos carpetas: 104 pruebas, pasan. Analizador: 19.
  **Falta de 1b**: mutaciones (no se hicieron) y la suite completa.
- `0ef913a1` **fix(bandeja) — 5b**, la vista previa saltea la ficha. COMPLETO:
  `lib/core/util/markdown_lead.dart` (`markdownLeadStart`), usado en
  `RenderedMarkdown.excerpt`. Pruebas en `test/core/util/markdown_lead_test.dart` (18) y
  `markdown_display_test.dart`; fixture `test/fixtures/web/wikipedia_imperio_romano_inicio.md`.
  **Mutaciones: 27 de 27 muertas** (`retomar_f46_p5j/mut_5b.json`). Analizador: 19 (con los dos
  avisos de la prueba ya corregidos antes de commitear).

## A medio hacer (en el wip)

**2a, «Leer» en las notas de bloques — el código está terminado, falta verificar y commitear:**

- `lib/features/reading/domain/extractable_text.dart`: `readableBlocksOf`, `hasReadingText`,
  typedef `ReadableBlocks`. Listo.
- `lib/features/blocks/presentation/widgets/block_view.dart`: `baseStyle`, `playingColor`,
  `readAloudParts`, `_BlockStyle`. Listo.
- `lib/features/blocks/presentation/widgets/note_links.dart` (nuevo): `openNoteLink`, sacado de
  `_BlocksRendition._openLink` del detalle. Listo.
- `lib/features/library/presentation/screens/item_detail_screen.dart`: usa `readAloudParts` y
  `openNoteLink`; se sacó el import de `library_query.dart` que quedó sin uso. Listo.
- `lib/features/reading/presentation/screens/reading_screen.dart`: `_NoteText` (BlockView de solo
  lectura, sin barra de extraer ni cuenta), `_readableProvider` con las notas. Listo.
- `lib/features/library/presentation/widgets/source_panel.dart`: «Leer» con `hasReadingText`;
  ayuda `f46P5jReadNote` en una nota. Listo.
- `.arb`: **agregada** `f46P5jReadNote` (es «Leer la nota», en «Read the note»), **quitada**
  `sourcePanelReadNeedsSource` (de los dos). `flutter gen-l10n` ya corrido (los generados no se
  commitean: correr `flutter gen-l10n` al retomar si no están).
- Pruebas: `test/features/reading/domain/extractable_text_test.dart` (nuevo),
  `test/features/blocks/presentation/widgets/block_view_test.dart` (nuevo, 4, pasan),
  `reading_screen_test.dart` (grupo «una nota de bloques»), `reading_read_aloud_test.dart` (1),
  `source_panel_test.dart` (2 nuevas, 1 cambiada). Tanda `test/features/blocks`,
  `test/features/reading`, `source_panel_test`, `test/features/library/presentation/screens`:
  todo pasa salvo las 2 de block_view que ya se arreglaron (pasan solas).

**Guía** (`GUIA_DE_USO.md`): ya escrita, en el wip — las hojas tapan la barra («Cómo te movés»),
«Leer» en el panel del elemento, la sección nueva «Leer una nota de bloques» y la vista previa de
la Bandeja. Revisarla una vez y commitearla sola como `docs(guía): …`.

## Falta por completo

1. `flutter analyze` con 2a: tiene que dar **19** (la última pasada daba 23: los 4 avisos ya
   están corregidos, falta confirmarlo).
2. Mutaciones de 2a: `python tool/mutar.py retomar_f46_p5j/mut_2a.json` (21; que mueran todas).
3. Mutaciones de 1b (escribir el JSON): el censo (cada patrón), `useRootNavigator`, el relleno del
   teclado y `removeViewInsets`, el `SafeArea` de abajo y `ownSurface`, `maxHeightFactor`, la
   captura del contenedor (`scoped`), `disableAnimations`, `showDragHandle`. Pruebas:
   `app_bottom_sheet_test.dart`, `bottom_sheet_census_test.dart`, `adaptive_scaffold_test.dart`.
4. Commit de 2a con `retomar_f46_p5j/msg_2a.txt` (rutas explícitas de la lista de arriba + los
   dos `.arb`).
5. Commit `docs(guía)`.
6. **Suite completa** sobre una copia (no en el worktree: tarda horas con la máquina cargada, y
   no se puede tocar nada mientras): `robocopy` del worktree a una carpeta del scratchpad (sin
   `.git`, `build`, `.dart_tool`), `flutter pub get`, `build_runner`, `gen-l10n`, y
   `timeout 14400 flutter test --concurrency=2`. Si algo de 1b falla, arreglarlo y reescribir la
   historia local (commits sin push) para que cada commit pase solo.
7. Avance del paso 5j en `docs/planes/F46-indice.md` (al final, como el de 5h; el archivo está en
   LF en el repo), en un `docs(planes)` aparte.
8. Informe al coordinador: commits, cuáles son de documentación, analizador por commit, suite,
   mutaciones (5b: 27/27), claves `.arb` (+`f46P5jReadNote`, −`sourcePanelReadNeedsSource`), y lo
   del emulador.

## Para mirar en el emulador (para el informe)

Cualquier hoja abierta desde una pestaña (la lista de Organizar/Estudiar, «Nuevo cuaderno», los
filtros de la Línea de tiempo y el Mapa, la velocidad del reproductor, el «⋮» del lector): tapa la
barra y la oscurece, la barra no responde, «atrás» y el gesto predictivo la cierran primero; con
el teclado («Con IA», el buscador de temas, la nota del resaltado) sube con él; abajo no queda
debajo de la barra de gestos; con el reproductor sonando, se hace a un lado y vuelve encima de la
barra al cerrarla; en la tablet, tapa el riel. «Leer» de una nota de bloques; vacía, apagado. La
tarjeta de «República romana» y la de Platón en la Bandeja, desde el primer párrafo.

## Trampas

- El shell del agente rechaza `cd … && sed/grep` con variables o `$( )`: usar comandos simples,
  PowerShell para listas de archivos (`$files = git diff --name-only …; dart format @files`).
- La copia de trabajo es CRLF (`core.autocrlf=true`); los scripts propios leen/escriben en bytes
  y respetan el final de línea. `sed -i` deja LF: da igual, git normaliza.
- No correr el analizador y las pruebas a la vez. `tool/run_suite.ps1` usa
  `%TEMP%\sinapsis-suite`, que puede pisarse con el otro agente: usar una carpeta propia.
- Al matar procesos, mirar el `CommandLine`: hay pruebas del otro agente
  (`agent-abe338714d818a2ea`) corriendo; esas no se tocan.
- Decisión de 2a, para el informe: la nota se lee **de solo lectura** (sin extraer, resaltar ni
  tarjetas) porque las posiciones de una nota se corren al editarla. Un salto con posiciones
  (cita del chat a una nota, que vienen en coordenadas del JSON) abre el lector arriba, sin bajar
  al bloque: queda como mejora posible.
