import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'synthetic_vault.dart';
import 'vault_benchmark.dart';

/// Se corre a propósito y no con toda la suite: arma —la primera vez— una
/// bóveda de 10.000 elementos y ~300.000 chunks.
///
///     flutter test test/benchmark/vault_benchmark_test.dart \
///       --dart-define=BENCH=true --timeout none
///
/// Los escenarios están en `vault_benchmark.dart`.
const _runBenchmark = bool.fromEnvironment('BENCH');

void main() {
  group(
    'benchmark de la bóveda sintética',
    skip: _runBenchmark ? false : 'se corre con --dart-define=BENCH=true',
    () => registerVaultBenchmark(
      BenchmarkEnvironment(
        open: openBenchmarkVault,
        log: stdout.writeln,
        save: (name, content) => File(
          '.dart_tool/sinapsis_benchmark/$name',
        ).writeAsStringSync(content),
        targetDivisor: kDesktopFactor,
      ),
    ),
  );
}
