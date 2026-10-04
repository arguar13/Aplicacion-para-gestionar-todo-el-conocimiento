import 'package:flutter/foundation.dart';

/// Lo que se sabe de los ajustes del sistema que deciden si Sinapsis puede
/// seguir trabajando con la app cerrada (F29).
@immutable
class BackgroundSettingsStatus {
  const BackgroundSettingsStatus({
    required this.isXiaomi,
    required this.batteryUnrestricted,
  });

  /// Xiaomi, Redmi o POCO (MIUI, HyperOS): ahí deslizar la app la cierra
  /// entera, salvo con "Inicio automático" y la batería "Sin restricciones".
  final bool isXiaomi;

  /// Si Android ya no le aplica ahorro de batería. "Inicio automático" no se
  /// puede leer: Xiaomi no lo publica.
  final bool batteryUnrestricted;
}

/// Qué pantalla de ajustes se abrió.
enum BackgroundSettingsScreen {
  /// "Inicio automático" de Xiaomi.
  autostart,

  /// El ahorro de batería de Sinapsis, de Xiaomi.
  battery,

  /// La ficha de la app en los ajustes de Android: de ahí, "Batería".
  appDetails,

  /// La lista de optimización de batería de Android.
  batteryList,
}

/// Los ajustes del sistema que deciden si el trabajo sigue con la app
/// cerrada (F29). Ninguna app puede cambiarlos sola: solo llevar a la persona
/// a la pantalla justa, la propia de su marca si la hay, y si no la de
/// Android.
abstract interface class BackgroundSettings {
  Future<BackgroundSettingsStatus> status();

  /// Abre "Inicio automático"; dice qué abrió, o `null` si no pudo abrir
  /// nada.
  Future<BackgroundSettingsScreen?> openAutostart();

  /// Abre el ahorro de batería de Sinapsis; dice qué abrió, o `null` si no
  /// pudo abrir nada.
  Future<BackgroundSettingsScreen?> openBattery();
}
