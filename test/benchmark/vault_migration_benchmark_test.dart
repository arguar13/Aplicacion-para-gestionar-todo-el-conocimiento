import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'vault_migration_benchmark.dart';

/// La migración a escala en escritorio; la medición está en
/// `vault_migration_benchmark.dart`, compartida con la de dispositivo
/// (`integration_test/vault_migration_benchmark_test.dart`).
///
/// Necesita la bóveda de un esquema anterior en
/// `.dart_tool/sinapsis_benchmark/vault_s17_g4_10000.sqlite` (la que dejó el
/// benchmark de F10); sin ella se salta.
///
///     flutter test test/benchmark/vault_migration_benchmark_test.dart \
///       --dart-define=BENCH=true --timeout none
const _runBenchmark = bool.fromEnvironment('BENCH');

void main() {
  group(
    'benchmark de la migración a escala',
    skip: _runBenchmark ? false : 'se corre con --dart-define=BENCH=true',
    () => registerVaultMigrationBenchmark(
      MigrationBenchmarkEnvironment(
        oldVaultFile: () async {
          final file = File(
            '.dart_tool/sinapsis_benchmark/vault_s17_g4_10000.sqlite',
          );
          return file.existsSync() ? file : null;
        },
        log: stdout.writeln,
        save: (name, content) {
          Directory(
            '.dart_tool/sinapsis_benchmark',
          ).createSync(recursive: true);
          File(
            '.dart_tool/sinapsis_benchmark/$name',
          ).writeAsStringSync(content);
        },
        description: const String.fromEnvironment(
          'BENCH_DEVICE_INFO',
          defaultValue: 'escritorio',
        ),
      ),
    ),
  );
}
