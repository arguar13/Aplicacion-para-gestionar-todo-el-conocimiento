import 'dart:convert';
import 'dart:io';

import 'package:integration_test/integration_test_driver.dart';

/// El lado de la PC de las pruebas de integración que corren en un dispositivo
/// (`integration_test/`): recibe lo que la prueba dejó en `reportData` —los
/// informes del benchmark— y lo guarda como archivos.
///
/// Hace falta porque `flutter test integration_test` compila en modo debug, y
/// un benchmark en debug mide un Dart de 5 a 10 veces más lento que el de la
/// app de verdad. Con `flutter drive --profile` el código va compilado como
/// el de producción, y este es el driver que ese comando pide:
///
///     flutter drive --profile --flavor staging -d <dispositivo> \
///       --driver=test_driver/integration_test.dart \
///       --target=integration_test/vault_benchmark_test.dart
///
/// Los archivos van a la carpeta de la variable de entorno `BENCH_OUT`, o a
/// `docs/benchmarks/raw` si no está. `tool/bench_android.ps1` arma el comando
/// entero y elige una carpeta con el nombre del dispositivo.
///
/// Un texto se guarda tal cual, con el nombre que trae; cualquier otra cosa
/// —las cifras de cuadros de una pantalla, por ejemplo— se guarda como JSON, en
/// un archivo con el nombre de su clave y la extensión `.json`.
///
/// `writeResponseOnFailure: true` (F18, 18.1): `integrationDriver` por
/// defecto NUNCA llama a `responseDataCallback` si alguna prueba del archivo
/// falló —ni siquiera los informes de las pruebas que sí pasaron—. Un
/// benchmark que verifica un umbral (F18, D3) tiene que fallar PRECISAMENTE
/// cuando el umbral no se cumple, y ese es el caso en el que más hace falta
/// el informe guardado, no menos.
Future<void> main() => integrationDriver(
  writeResponseOnFailure: true,
  responseDataCallback: (data) async {
    if (data == null) return;
    final out = Directory(
      Platform.environment['BENCH_OUT'] ?? 'docs/benchmarks/raw',
    )..createSync(recursive: true);
    for (final MapEntry(:key, :value) in data.entries) {
      if (value is String) {
        File('${out.path}/$key').writeAsStringSync(value);
      } else {
        File(
          '${out.path}/$key.json',
        ).writeAsStringSync(const JsonEncoder.withIndent('  ').convert(value));
      }
    }
    stdout.writeln('Informes guardados en ${out.absolute.path}');
  },
);
