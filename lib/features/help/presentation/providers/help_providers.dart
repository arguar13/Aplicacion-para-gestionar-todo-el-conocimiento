import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/features/help/presentation/help_document.dart';

/// La guía de uso, empaquetada con la app desde la raíz del proyecto (ver
/// `assets:` en `pubspec.yaml`): la misma que se escribe con cada cambio, sin
/// una copia aparte que se quede vieja.
const kUserGuideAsset = 'GUIA_DE_USO.md';

/// De dónde se leen los textos de la Ayuda (F47, paso 7): lo empaquetado con
/// la app. Las pruebas lo cambian por uno que lee los archivos del disco.
final helpAssetBundleProvider = Provider<AssetBundle>((ref) => rootBundle);

/// La guía de uso, ya partida en capítulos. Se lee una vez y queda: la guía
/// no cambia mientras la app está abierta.
final userGuideProvider = FutureProvider<HelpDocument>(
  (ref) => _load(ref, kUserGuideAsset),
);

/// Sin la caché del paquete: el texto ya queda en el documento, y la guía
/// entera no tiene por qué estar dos veces en la memoria.
Future<HelpDocument> _load(Ref ref, String asset) async => HelpDocument.parse(
  await ref.watch(helpAssetBundleProvider).loadString(asset, cache: false),
);
