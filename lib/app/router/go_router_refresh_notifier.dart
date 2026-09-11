import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Puente entre Riverpod y `GoRouter.refreshListenable` (que espera un
/// `Listenable` de Flutter, no un `Provider`). Cada cambio en cualquiera de
/// los providers observados hace que el router vuelva a evaluar `redirect`
/// sin necesidad de reconstruir el `GoRouter` completo (eso perdería el
/// stack de navegación).
///
/// Toma una lista y no un único provider porque `redirect` puede depender de
/// más de una cosa a la vez —el estado de la bóveda, y si hay algo
/// compartido esperando revisión— y las dos tienen que poder disparar una
/// reevaluación por separado.
class GoRouterRefreshNotifier extends ChangeNotifier {
  GoRouterRefreshNotifier(
    Ref ref,
    List<ProviderListenable<Object?>> listenables,
  ) {
    for (final listenable in listenables) {
      ref.listen(listenable, (_, _) => notifyListeners());
    }
  }
}
