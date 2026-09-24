# Cifras de rendimiento

Aquí quedan versionadas las mediciones de la bóveda sintética de 10.000
elementos y ~300.000 chunks (ver las decisiones 43, 45 y 46 en
`../arquitectura.md`), una carpeta por equipo y fecha —con un sufijo cuando una
misma fecha tiene dos corridas de fases distintas, como `2026-09-21-f13`—:

    docs/benchmarks/<equipo>/<aaaa-mm-dd>/
        latest_report.md            los escenarios, con el objetivo y lo medido
        latest_footprint.txt        cuánto pesa el texto en disco
        latest_hierarchy_report.md  F13: la consulta transitiva, CTE contra cierre
        latest_atlas_report.md      F13: abrir el Atlas con 2.000 temas
        latest_merge_report.md      la fusión de una variante y de una copia entera
        latest_migration_report.md  migrar v17 al esquema actual y compactar después
        latest_migration_v20_report.md
                                    migrar v20 a v21, el último salto (F13)
        latest_timeline_report.md   la línea de tiempo: armado y arrastre sostenido
        timeline_drag.json          los cuadros del arrastre, uno por uno
        latest_map_report.md        F14: el mapa —leer, armar, comunidades, recalcular,
                                    acomodar cada nivel, el motor entero—
        latest_map_screens_report.md
                                    F14: el mapa en pantalla: abrir cada vista y los
                                    cuadros de los gestos sostenidos
        map_*.json                  los cuadros de cada gesto, uno por uno
        latest_cold_start_report.md abrir la app con 10.000 elementos
        latest_backup_report.md     armar y abrir la copia
        latest_backup_saf_report.md guardar la copia y elegirla con los selectores
                                    del sistema (solo con -SaveToFolder)
        latest_reference_report.md  F15: la bóveda con referencias —detalle, búsqueda
                                    por DOI/ISBN, bibliografía de una rama, importar y
                                    exportar en lote, candidatos entre autores—
        dispositivo.md              el equipo exacto y cómo estaba al empezar

`<equipo>` es `<fabricante>-<modelo>-android<versión>` para un teléfono,
`emulador-<modelo>-android<versión>` para un emulador y
`escritorio-<sistema>-<procesador>` para una PC. Una cifra sin el equipo que la
produjo no dice nada: por eso cada informe empieza con él, y `dispositivo.md`
guarda lo que el equipo declara (modelo, Android, procesador, memoria, espacio
libre, temperatura).

## Un emulador no es un teléfono

Un emulador usa la CPU y el disco de la PC que lo aloja: sus TIEMPOS son
optimistas y no valen como los de un teléfono de gama media. Lo que sí vale es
la MEMORIA —el sistema mata la app en cuanto se pasa del límite— y que el
código, el arnés y las dependencias nativas corren en Android. Con ellos se
encontró lo que ninguna cifra de escritorio mostraba: ver la decisión 45. El
guion reconoce un emulador y lo rotula en la carpeta y en `dispositivo.md`.

Y la PC tiene que estar ENCHUFADA: a batería el sistema le baja la frecuencia al
procesador y al disco, y la misma medición sale de 3 a 5 veces peor (armar la
copia: 45–68 s enchufada, más de 220 s a batería). El guion avisa si la PC va a
batería y anota en `dispositivo.md` cómo estaba. Aun enchufada, dos corridas
iguales pueden diferir hasta un 50 %: una diferencia de esa escala no es una
regresión. Las corridas a batería y la primera, anterior al arreglo de la
búsqueda, están aparte (`<fecha>-a-bateria`, `<fecha>-antes-del-arreglo-…`)
para que se vea la diferencia.

## La bóveda sintética v5 (F13)

El generador (`test/benchmark/synthetic_vault.dart`) armó hasta F12 un «Tema»
plano de 600 valores. Desde F13 —versión 5— lo arma jerárquico y de 2.000 valores
con 10.000 elementos, una quinta parte y no un 6 %: hasta cinco niveles, con unas
pocas ramas enormes (la mayor tiene 303 valores y el 49 % de los elementos) y una
hoja para comparar. Las otras diez categorías no cambian. Las figuras de F12 y las
de F13 no son de la misma bóveda: la búsqueda y el detalle salieron parecidos, pero
el vocabulario, la línea de tiempo y la salud leen ahora más valores.

"El elemento con más relaciones" y «una nota con enlaces» son dos escenarios
distintos: con la primera nota que se escribió con enlaces se medía, según el
sorteo, una de las que más relaciones reciben —salió una con 1.235—. Ahora «una
nota con enlaces» es la de las relaciones de un elemento típico, y el peor caso
tiene su propio escenario.

## Cómo se mide en un dispositivo Android

Se mide en modo **profile**, que es el código de la app de verdad. Con
`flutter test integration_test` el código va en debug y el Dart sale de 5 a 10
veces más lento: las cifras engañarían.

1. Un teléfono con la depuración USB activada, desbloqueado y cargando, o un
   emulador arrancado. Con menos de 4 GB libres el guion se corta.
2. `tool/bench_android.ps1` corre los 13 escenarios. Para los demás:

       tool/bench_android.ps1 -Target vault_merge_benchmark_test
       tool/bench_android.ps1 -Target cold_start_benchmark_test
       tool/bench_android.ps1 -Target timeline_benchmark_test
       tool/bench_android.ps1 -Target vault_backup_benchmark_test
       tool/bench_android.ps1 -Target vault_migration_benchmark_test -PushVaults
       tool/bench_android.ps1 -Target vault_migration_benchmark_test -PushVaults `
         -OldVault vault_s20_g4_10000.sqlite -Label f13

   `-OldVault` elige de qué esquema se parte —el de v17, de 909 MB, es el
   predeterminado, y el de v20 mide solo el último salto— y deja el informe con
   el esquema en el nombre. `-Label` suma un sufijo a la carpeta de las cifras
   para que dos corridas del mismo día no se pisen.

   Cada escenario arma la bóveda sintética en el directorio temporal de la app
   —unos 30 s en un emulador, más en un teléfono—, salvo la migración, que
   parte de una bóveda de un esquema anterior que el generador ya no sabe armar:
   esa se empuja con `-PushVaults`.
3. Guardar la copia con el selector de carpetas de Android y volver a elegirla
   con el de archivos exige a alguien que los maneje. En una terminal:

       tool/bench_android.ps1 -Target vault_backup_benchmark_test -SaveToFolder

   y en otra, para que el guion haga lo que haría una persona:

       tool/bench_android_pick_folder.ps1 -PickFile sinapsis-backup-bench.zip

El guion usa el flavor `staging` (`app.sinapsis.staging`): para Android es otra
app, con sus datos propios, y no toca los de ninguna otra instalación de
Sinapsis del dispositivo. El benchmark, además, nunca abre la base de la app:
trabaja con copias de la bóveda sintética en su directorio temporal.

Tres cosas del arnés que costaron un rato y conviene saber:

- `flutter drive` DESINSTALA la app al terminar, y con ella se va lo empujado:
  hay que empujar antes de cada corrida (`-PushVaults` lo hace).
- Lo que `adb push` deja en la carpeta de la app queda a nombre de `shell` con
  permiso 660: la app ve la carpeta pero no puede abrir los archivos
  («Permission denied»). El guion les abre los permisos.
- `--no-dds` hace falta para medir cuadros: sin él, `watchPerformance` intenta
  conectarse a un puerto de la PC que en el dispositivo no existe.

## El mapa de conocimiento (F14)

`test/benchmark/map_benchmark.dart` tiene los escenarios de lo que el mapa lee y
calcula —armar el grafo de temas, detectar comunidades en frío y tras un cambio,
acomodar cada nivel, el motor entero con su isolate—. Los corre el escritorio
(`map_benchmark_test.dart`, con `--dart-define=BENCH=true`) y el dispositivo
(`integration_test/map_benchmark_test.dart`). Sus tiempos son de referencia: el
encargo no fija un objetivo para ellos.

La misma prueba de dispositivo abre la PANTALLA y mide cuánto tarda cada vista en
verse y cuántos cuadros se pierden con un gesto sostenido —arrastre y dos dedos—,
en el esquema y en cada nivel del grafo, y con el mapa recalculándose de fondo.
Ese es el criterio de cierre de F14: interacción fluida con 2.000 temas, con el
percentil 90 de armado y de raster por debajo del presupuesto de un cuadro
(16,6 ms) y menos del 5 % de cuadros fuera de él.

    tool/bench_android.ps1 -Target map_benchmark_test -Label f14

No hace falta `-PushVaults`: la bóveda se arma en el dispositivo en unos segundos.
En escritorio, las pantallas se miden con

    flutter drive --profile -d windows --driver=test_driver/integration_test.dart `
      --target=integration_test/map_benchmark_test.dart

**Dos bóvedas de temas, y no es un descuido.** El generador de la bóveda sintética
asigna los temas de cada elemento al azar, sin relación entre unos y otros. Sirve
para las búsquedas y las lecturas, pero su grafo de temas es una maraña sin
estructura: 2.164 temas y 94.506 uniones en UNA sola comunidad, y un panorama de un
solo nodo. Eso mide el peor coste de armar el grafo y nada más: no dice cuántas
comunidades salen, cuánto se mueven tras un cambio ni cómo se ve el panorama. Por eso
el benchmark mide también con `structuredTopicInput`
(`test/benchmark/structured_topics.dart`): conserva el árbol de temas de la bóveda y
reparte los elementos por áreas —una rama de primer nivel, elegida con más
probabilidad cuanto más grande—, con puentes entre ellas y vínculos que en su mayoría
unen elementos de la misma área. De ahí salen 49 comunidades y un panorama que se
puede dibujar. Que las áreas sean las ramas de primer nivel es una decisión del
generador, y es también lo que la jerarquía favorece al agrupar: estos datos NO dicen
si el peso que la jerarquía suma a las uniones agrupa mejor o peor con los temas de
una bóveda real.

En pantalla, los temas son esos, y todo lo demás —el tablero, el esquema, los
elementos de un tema— sale de la base: `StructuredMapRepository` reemplaza solo la
lectura del grafo de temas. Cada línea de un informe dice cuál usó: «(base)» es la del
azar.

## La bóveda con referencias (F15)

`test/benchmark/reference_benchmark.dart` mide lo que agrega la biblioteca
académica: abrir el detalle de una fuente con su referencia y su cita, buscar
por DOI o por ISBN, la bibliografía APA de una rama grande del Atlas —como
texto y como `.docx`—, los candidatos a fusionar entre los autores del
vocabulario, importar un `.bib` de 5.000 entradas y reimportarlo sin cambios,
y exportar 10.000 referencias a BibTeX y a RIS. También deja constancia de la
memoria residente durante la importación.

Es una **capa aparte, con su propia semilla** (`_seedReferenceLayer`), no la
misma bóveda de 10.000 elementos de los demás escenarios: para tener 10.000
FUENTES con referencia hacen falta bastantes más de 10.000 elementos en
total —las fuentes son el 72 % de la bóveda sintética—, así que arma la suya
propia de 15.000. Se cachea igual que la de siempre
(`vault_s<esquema>_g<generador>_15000.sqlite`, más un archivo `.ok` propio
para la capa) y no toca nada de lo que el benchmark de siempre mide.

    flutter test test/benchmark/reference_benchmark_test.dart \
      --dart-define=BENCH=true --timeout none

    tool/bench_android.ps1 -Target reference_benchmark_test -Label f15

Que una consulta por DOI o por ISBN entre por su índice, y no por un
recorrido de la tabla, es un caso más de `query_plans_test.dart` —corre
siempre, no hace falta el `--dart-define`—: eso no necesita 10.000 filas para
comprobarse, solo el esquema.

## Cómo se mide en escritorio

    flutter test test/benchmark/vault_benchmark_test.dart \
      --dart-define=BENCH=true --timeout none

Corre los mismos escenarios contra un umbral menor (el objetivo dividido por
`kDesktopFactor`). Ese factor es una estimación de cuánto más rápida es la PC
que un teléfono de gama media, no una medición; se reemplaza por el cociente
medido entre las dos máquinas cuando haya cifras de un teléfono real —el
emulador no sirve para eso: comparte la CPU con la PC—. Con
`flutter drive -d windows --profile` se obtiene la referencia en modo profile,
que es la de `escritorio-windows-i5-10300h/`.

La migración y la compactación, la copia y la fusión a escala también tienen su
versión de escritorio (`test/benchmark/vault_*_benchmark_test.dart`, con
`--dart-define=BENCH=true`).
