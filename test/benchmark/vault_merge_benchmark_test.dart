import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'synthetic_vault.dart';
import 'vault_merge_benchmark.dart';

/// La fusión a escala en escritorio; la medición está en
/// `vault_merge_benchmark.dart`, compartida con la de dispositivo
/// (`integration_test/vault_merge_benchmark_test.dart`).
///
///     flutter test test/benchmark/vault_merge_benchmark_test.dart \
///       --dart-define=BENCH=true --timeout none
const _runBenchmark = bool.fromEnvironment('BENCH');

void main() {
  group(
    'benchmark de la fusión a escala',
    skip: _runBenchmark ? false : 'se corre con --dart-define=BENCH=true',
    () => registerVaultMergeBenchmark(
      MergeBenchmarkEnvironment(
        vaultFile: () async {
          final base = await openBenchmarkVault();
          final profile = base.vault.profile;
          await base.db.close();
          return (file: benchmarkVaultFile(profile: profile), profile: profile);
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
