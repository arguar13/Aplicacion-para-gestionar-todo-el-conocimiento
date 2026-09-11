import 'dart:io' as io;

import 'package:flutter/foundation.dart' show kIsWeb;

/// Resuelve la URL base para hablar con un backend corriendo en la propia
/// máquina de desarrollo (el mock server de `json-server`, por ejemplo).
/// Solo la usa el flavor `dev`; `staging`/`prod` apuntan a hosts reales
/// fijos en `EnvConfig`.
///
/// El emulador de Android corre en su propia VM: ahí `localhost` apunta al
/// emulador mismo, no a la máquina host, por eso usa el alias especial
/// `10.0.2.2`. iOS (simulador), Web y desktop sí comparten red con el host,
/// así que `localhost` les sirve directo.
///
/// `kIsWeb` se comprueba antes que nada: `dart:io`/`Platform` no está
/// disponible en Web y `Platform.isAndroid` lanza ahí si se llega a
/// evaluar.
String resolveLocalBaseUrl({int port = 3000}) {
  if (kIsWeb) return 'http://localhost:$port';
  if (io.Platform.isAndroid) return 'http://10.0.2.2:$port';
  return 'http://localhost:$port';
}
