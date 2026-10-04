import 'package:sinapsis/features/keep_working/domain/services/background_settings.dart';

/// Los ajustes de segundo plano de un teléfono de mentira (F29): qué marca
/// es, cómo está la batería y qué pantalla se abre con cada botón.
class FakeBackgroundSettings implements BackgroundSettings {
  FakeBackgroundSettings({
    this.isXiaomi = false,
    this.batteryUnrestricted = false,
    this.autostartOpens = BackgroundSettingsScreen.autostart,
    this.batteryOpens = BackgroundSettingsScreen.battery,
  });

  bool isXiaomi;
  bool batteryUnrestricted;
  BackgroundSettingsScreen? autostartOpens;
  BackgroundSettingsScreen? batteryOpens;

  /// Lo que se abrió, en orden.
  final opened = <String>[];

  @override
  Future<BackgroundSettingsStatus> status() async => BackgroundSettingsStatus(
    isXiaomi: isXiaomi,
    batteryUnrestricted: batteryUnrestricted,
  );

  @override
  Future<BackgroundSettingsScreen?> openAutostart() async {
    opened.add('inicio automático');
    return autostartOpens;
  }

  @override
  Future<BackgroundSettingsScreen?> openBattery() async {
    opened.add('batería');
    return batteryOpens;
  }
}
