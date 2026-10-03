import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/core/config/app_flavor.dart';
import 'package:sinapsis/core/config/env_config.dart';

/// La flavor con que arrancó la app (`main_dev.dart`, `main_staging.dart` o
/// `main_prod.dart`).
///
/// Un provider y no `EnvConfig.current` leído en cada pantalla: lo que solo
/// existe en desarrollo —la biblioteca de ejemplo— se decide acá, y una
/// prueba lo reemplaza para comprobar que en prod no aparece sin tocar el
/// estado global de `EnvConfig`.
final appFlavorProvider = Provider<AppFlavor>(
  (ref) => EnvConfig.current.flavor,
);
