import 'package:flutter/services.dart';
import 'package:sinapsis/features/keep_working/domain/services/background_settings.dart';

/// [BackgroundSettings] en Android, por el canal
/// `app.sinapsis/background_settings` (ver `BackgroundSettingsChannel`):
/// las pantallas de Xiaomi primero, y si no están, las de Android.
class MethodChannelBackgroundSettings implements BackgroundSettings {
  const MethodChannelBackgroundSettings({
    MethodChannel channel = const MethodChannel(
      'app.sinapsis/background_settings',
    ),
  }) : _channel = channel;

  final MethodChannel _channel;

  @override
  Future<BackgroundSettingsStatus> status() async {
    final status = await _channel.invokeMapMethod<String, Object?>('status');
    return BackgroundSettingsStatus(
      isXiaomi: status?['xiaomi'] == true,
      // Una app con el uso en segundo plano restringido no está "sin
      // restricciones" aunque Android no la optimice.
      batteryUnrestricted:
          status?['batteryUnrestricted'] == true &&
          status?['backgroundRestricted'] != true,
    );
  }

  @override
  Future<BackgroundSettingsScreen?> openAutostart() => _open('openAutostart');

  @override
  Future<BackgroundSettingsScreen?> openBattery() => _open('openBattery');

  Future<BackgroundSettingsScreen?> _open(String method) async =>
      switch (await _channel.invokeMethod<String>(method)) {
        'autostart' => BackgroundSettingsScreen.autostart,
        'battery' => BackgroundSettingsScreen.battery,
        'app_details' => BackgroundSettingsScreen.appDetails,
        'battery_list' => BackgroundSettingsScreen.batteryList,
        _ => null,
      };
}
