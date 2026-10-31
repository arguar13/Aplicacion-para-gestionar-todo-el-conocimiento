import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:sinapsis/features/help/presentation/help_document.dart';

/// La guía de uso, empaquetada con la app desde la raíz del proyecto (ver
/// `assets:` en `pubspec.yaml`): la misma que se escribe con cada cambio, sin
/// una copia aparte que se quede vieja.
const kUserGuideAsset = 'GUIA_DE_USO.md';

/// Lo nuevo de cada etapa, empaquetado igual que la guía.
const kWhatsNewAsset = 'NOVEDADES.md';

/// De dónde se leen los textos de la Ayuda (F47, paso 7): lo empaquetado con
/// la app. Las pruebas lo cambian por uno que lee los archivos del disco.
final helpAssetBundleProvider = Provider<AssetBundle>((ref) => rootBundle);

/// La guía de uso, ya partida en capítulos. Se lee una vez y queda: la guía
/// no cambia mientras la app está abierta.
final userGuideProvider = FutureProvider<HelpDocument>(
  (ref) => _load(ref, kUserGuideAsset),
);

/// Las novedades, ya partidas en etapas.
final whatsNewProvider = FutureProvider<HelpDocument>(
  (ref) => _load(ref, kWhatsNewAsset),
);

/// Sin la caché del paquete: el texto ya queda en el documento, y la guía
/// entera no tiene por qué estar dos veces en la memoria.
Future<HelpDocument> _load(Ref ref, String asset) async => HelpDocument.parse(
  await ref.watch(helpAssetBundleProvider).loadString(asset, cache: false),
);

/// El nombre, la versión y la compilación de la app que está corriendo,
/// como los ve el sistema (F47, paso 7): en Android, la versión lleva el
/// sufijo del sabor —«0.1.0-dev»—, igual que en Ajustes › Apps.
@immutable
class AppVersion {
  const AppVersion({
    required this.name,
    required this.version,
    required this.build,
  });

  final String name;
  final String version;
  final String build;
}

/// La versión de la app, de `package_info_plus`.
final appVersionProvider = FutureProvider<AppVersion>((ref) async {
  final info = await PackageInfo.fromPlatform();
  return AppVersion(
    name: info.appName,
    version: info.version,
    build: info.buildNumber,
  );
});
