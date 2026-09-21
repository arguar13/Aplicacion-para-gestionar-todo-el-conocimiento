# Cifras de rendimiento

Aquí quedan versionadas las mediciones de la bóveda sintética de 10.000
elementos y ~300.000 chunks (ver las decisiones 43 y 45 en
`../arquitectura.md`), una carpeta por equipo y fecha:

    docs/benchmarks/<equipo>/<aaaa-mm-dd>/
        latest_report.md            los 13 escenarios, con el objetivo y lo medido
        latest_footprint.txt        cuánto pesa el texto en disco
        latest_merge_report.md      la fusión de una variante y de una copia entera
        latest_migration_report.md  migrar v17 a v20 y compactar después
        latest_timeline_report.md   la línea de tiempo: armado y arrastre sostenido
        timeline_drag.json          los cuadros del arrastre, uno por uno
        latest_cold_start_report.md abrir la app con 10.000 elementos
        latest_backup_report.md     armar y abrir la copia
        latest_backup_saf_report.md guardar la copia y elegirla con los selectores
                                    del sistema (solo con -SaveToFolder)
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
