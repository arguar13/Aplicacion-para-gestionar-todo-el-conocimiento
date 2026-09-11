/// Paths y nombres de ruta centralizados. Cada feature nuevo añade sus
/// constantes aquí (o expone su propio archivo `xxx_route_paths.dart` que
/// este archivo re-exporta) para que las URLs web queden en un solo lugar.
abstract final class RoutePaths {
  static const splash = '/splash';
  static const login = '/login';
  static const dashboard = '/dashboard';
}

abstract final class RouteNames {
  static const splash = 'splash';
  static const login = 'login';
  static const dashboard = 'dashboard';
}
