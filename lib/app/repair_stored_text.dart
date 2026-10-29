import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/core/database/database_provider.dart';
import 'package:sinapsis/core/database/repairs/utf8_mojibake_repair.dart';
import 'package:sinapsis/core/design/theme_mode_notifier.dart';
import 'package:sinapsis/core/logging/logger_provider.dart';
import 'package:sinapsis/core/util/util_providers.dart';

/// En las preferencias: si ya se arreglaron los títulos guardados con las
/// letras rotas (F43, M7). No es un paso del esquema —la base no cambia de
/// forma, cambia el texto de algunas filas—, así que no va en una migración:
/// se hace una vez por instalación, al abrir la app, y se anota acá.
const utf8MojibakeRepairDoneKey = 'data_repair_utf8_mojibake_v1';

/// Al abrir la app, una sola vez: arregla los títulos que quedaron guardados
/// como «DeclaraciÃ³n» antes del arreglo de raíz (ver [Utf8MojibakeRepair]).
///
/// Se anota como hecho solo si terminó: si falla a mitad de camino, el error
/// llega a quien llama —en la app, a la telemetría por la zona de
/// `bootstrap`— y se vuelve a intentar al abrirla otra vez, sin riesgo,
/// porque lo ya arreglado no se vuelve a tocar.
///
/// [read] es el `read` de quien llama: el de la app (`WidgetRef`) o el de una
/// prueba (`ProviderContainer`).
Future<Utf8MojibakeRepairReport?> repairUtf8MojibakeOnce(
  T Function<T>(ProviderListenable<T> provider) read,
) async {
  final prefs = read(sharedPreferencesProvider);
  if (prefs.getBool(utf8MojibakeRepairDoneKey) ?? false) return null;

  final report = await Utf8MojibakeRepair(
    read(appDatabaseProvider),
    clock: read(clockProvider),
  ).run();
  if (report.total > 0) {
    read(appLoggerProvider).info(
      'Letras rotas arregladas (F43, M7) — títulos: ${report.titles}, '
      'subtítulos: ${report.subtitles}, autores: ${report.authors}, '
      'sugerencias: ${report.suggestions}.',
    );
  }
  await prefs.setBool(utf8MojibakeRepairDoneKey, true);
  return report;
}
