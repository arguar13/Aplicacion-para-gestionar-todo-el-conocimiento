import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../test/benchmark/synthetic_vault.dart';

/// La carpeta donde el dispositivo guarda la bóveda sintética de 10.000
/// elementos, lista para `openBenchmarkVault`.
///
/// Si `tool/bench_android.ps1 -PushVaults` empujó la bóveda del esquema actual
/// —la base, su resumen y su marca— a la carpeta `files/bench` de la app, se
/// copia acá una sola vez y las corridas la reutilizan: es la MISMA bóveda que
/// la del escritorio, y ahorra armarla en el dispositivo, que son varios
/// minutos y 1,2 GB de escritura. Sin lo empujado, la primera corrida la arma.
///
/// No se lista la carpeta de lo empujado: la crea `adb`, con su dueño, y la app
/// puede leer sus archivos por nombre pero no listarla (`Permission denied`).
Future<Directory> deviceBenchmarkDirectory() async {
  final temporary = await getTemporaryDirectory();
  final directory = Directory('${temporary.path}/sinapsis_benchmark')
    ..createSync(recursive: true);

  // Lo empujado con `adb` solo existe en Android: en escritorio el plugin ni
  // implementa `getExternalStorageDirectory` y la bóveda se arma acá.
  if (!Platform.isAndroid) return directory;
  final external = await getExternalStorageDirectory();
  if (external == null) return directory;
  final pushed = '${external.path}/bench';

  // Los tres nombres de la bóveda de este esquema, con la marca al final: si la
  // copia se interrumpe, la bóveda a medias no pasa por completa.
  final base = p.withoutExtension(
    p.basename(benchmarkVaultFile(directory: directory).path),
  );
  for (final extension in ['.sqlite', '.json', '.ok']) {
    final source = File('$pushed/$base$extension');
    final target = File('${directory.path}/$base$extension');
    if (target.existsSync() || !source.existsSync()) continue;
    await source.copy(target.path);
  }
  return directory;
}
