/// Paths y nombres de ruta centralizados. Cada feature nuevo añade sus
/// constantes aquí (o expone su propio archivo `xxx_route_paths.dart` que
/// este archivo re-exporta) para que las URLs web queden en un solo lugar.
abstract final class RoutePaths {
  static const splash = '/splash';

  /// Las dos caras de la bóveda. Son rutas distintas y no una sola pantalla
  /// con dos modos porque responden a situaciones distintas: crear la bóveda
  /// pasa una vez en la vida del dispositivo, abrirla pasa en cada arranque.
  static const vaultCreate = '/vault/create';
  static const vaultUnlock = '/vault/unlock';

  /// La biblioteca: la pantalla principal con todo lo guardado.
  static const library = '/library';

  /// El detalle de un elemento. Se arma con [itemDetail] para no escribir la
  /// interpolación a mano en cada sitio que navega hasta acá.
  static const itemDetailPattern = '$library/:id';

  static String itemDetail(String id) => '$library/$id';

  /// Guardar algo nuevo.
  static const capture = '/capture';

  /// El modelo de transcripción: si está descargado, y descargarlo.
  static const transcriptionModel = '/transcription-model';

  /// Copia de seguridad de la bóveda completa: exportar e importar.
  static const vaultBackup = '/vault-backup';

  /// La bóveda como un grafo de vínculos.
  static const graph = '/graph';
}

abstract final class RouteNames {
  static const splash = 'splash';
  static const vaultCreate = 'vault-create';
  static const vaultUnlock = 'vault-unlock';
  static const library = 'library';
  static const itemDetail = 'item-detail';
  static const capture = 'capture';
  static const transcriptionModel = 'transcription-model';
  static const vaultBackup = 'vault-backup';
  static const graph = 'graph';
}
