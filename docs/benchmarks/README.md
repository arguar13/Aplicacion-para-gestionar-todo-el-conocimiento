# Cifras de rendimiento

Aquí quedan versionadas las mediciones de la bóveda sintética de 10.000
elementos y ~300.000 chunks (ver la decisión 43 en `../arquitectura.md`), una
carpeta por dispositivo y fecha:

    docs/benchmarks/<fabricante>-<modelo>-android<versión>/<aaaa-mm-dd>/
        latest_report.md       los escenarios, con el objetivo y lo medido
        latest_footprint.txt   cuánto pesa el texto en disco
        dispositivo.md         el teléfono exacto y cómo estaba al empezar

Una cifra sin el dispositivo que la produjo no dice nada: por eso cada informe
empieza con el equipo, y `dispositivo.md` guarda lo que el teléfono declara
(modelo, Android, procesador, memoria, espacio libre, temperatura).

## Cómo se mide en un teléfono

Se mide en modo **profile**, que es el código de la app de verdad. Con
`flutter test integration_test` el código va en debug y el Dart sale de 5 a 10
veces más lento: las cifras engañarían.

1. Conectar el teléfono por USB con la depuración activada, desbloqueado y
   cargando. Con menos de 4 GB libres el guion se corta.
2. Empujar las bóvedas grandes, una vez: `tool/bench_android.ps1 -PushVaults`.
3. Correr: `tool/bench_android.ps1` (y `-Target vault_merge_benchmark_test`
   para los demás escenarios).

El guion usa el flavor `staging` (`app.sinapsis.staging`): para Android es otra
app, con sus datos propios, y no toca los de ninguna otra instalación de
Sinapsis del teléfono. El benchmark, además, nunca abre la base de la app:
trabaja con copias de la bóveda sintética en su directorio temporal.

## Cómo se mide en escritorio

    flutter test test/benchmark/vault_benchmark_test.dart \
      --dart-define=BENCH=true --timeout none

Corre los mismos escenarios contra un umbral menor (el objetivo dividido por
`kDesktopFactor`). Ese factor es una estimación de cuánto más rápida es la PC
que un teléfono de gama media, no una medición; se reemplaza por el cociente
medido entre las dos máquinas cuando haya cifras de un teléfono real.
