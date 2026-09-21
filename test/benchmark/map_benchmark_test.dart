import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'map_benchmark.dart';
import 'synthetic_vault.dart';
import 'vault_benchmark.dart';

/// Se corre a propósito y no con toda la suite: necesita la bóveda sintética de
/// 10.000 elementos, que se arma —la primera vez— en unos minutos.
///
///     flutter test test/benchmark/map_benchmark_test.dart \
///       --dart-define=BENCH=true --timeout none
///
/// Los escenarios están en `map_benchmark.dart`.
const _runBenchmark = bool.fromEnvironment('BENCH');

void main() {
  group(
    'benchmark del mapa de conocimiento',
    skip: _runBenchmark ? false : 'se corre con --dart-define=BENCH=true',
    () => registerMapBenchmark(
      BenchmarkEnvironment(
        open: openBenchmarkVault,
        log: stdout.writeln,
        save: (name, content) => File(
          '.dart_tool/sinapsis_benchmark/$name',
        ).writeAsStringSync(content),
        targetDivisor: kDesktopFactor,
        description: const String.fromEnvironment(
          'BENCH_DEVICE_INFO',
          defaultValue: 'escritorio',
        ),
      ),
    ),
  );
}
