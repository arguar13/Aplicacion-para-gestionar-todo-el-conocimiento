import 'dart:io';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';

import '../test/benchmark/synthetic_vault.dart';
import '../test/benchmark/vault_benchmark.dart';

/// El benchmark de la bóveda sintética, para correr EN el dispositivo: los
/// mismos escenarios que en escritorio, pero exigiendo el objetivo del encargo
/// tal cual —FTS < 300 ms, detalle < 200 ms, grafo local < 500 ms— porque acá
/// el teléfono es el teléfono.
///
///     flutter test integration_test/vault_benchmark_test.dart -d <dispositivo>
///
/// La primera vez arma la bóveda de 10.000 elementos y ~300.000 chunks en el
/// directorio temporal del dispositivo, y necesita unos 1,2 GB libres. Lo que
/// se mide sale por el log.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group(
    'benchmark de la bóveda sintética, en el dispositivo',
    () => registerVaultBenchmark(
      BenchmarkEnvironment(
        open: () async {
          final temporary = await getTemporaryDirectory();
          return openBenchmarkVault(
            directory: Directory('${temporary.path}/sinapsis_benchmark'),
          );
        },
        log: debugPrint,
        save: (name, content) {},
      ),
    ),
  );
}
