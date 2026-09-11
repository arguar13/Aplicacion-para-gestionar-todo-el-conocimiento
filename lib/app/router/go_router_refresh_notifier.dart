import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Puente entre Riverpod y `GoRouter.refreshListenable` (que espera un
/// `Listenable` de Flutter, no un `Provider`). Cada cambio en el provider
/// observado hace que el router vuelva a evaluar `redirect` sin necesidad
/// de reconstruir el `GoRouter` completo (eso perdería el stack de
/// navegación).
class GoRouterRefreshNotifier extends ChangeNotifier {
  GoRouterRefreshNotifier(Ref ref, ProviderListenable<Object?> listenable) {
    ref.listen(listenable, (_, _) => notifyListeners());
  }
}
