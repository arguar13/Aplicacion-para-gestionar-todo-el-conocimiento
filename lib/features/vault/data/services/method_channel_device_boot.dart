import 'package:flutter/services.dart';

/// El encendido de Android (ver `DeviceBoot`): su contador de arranques
/// (`Settings.Global.BOOT_COUNT`), que el sistema suma uno cada vez que el
/// teléfono arranca. No necesita ningún permiso. Ver `SinapsisEngine`, que
/// instala el canal.
///
/// `null` si el sistema no lleva la cuenta —antes de Android 7—. Si el canal
/// falla, el error sube: quien lo llama decide, y la bóveda decide pedir la
/// clave.
Future<String?> androidDeviceBoot({
  MethodChannel channel = const MethodChannel('app.sinapsis/device_boot'),
}) async => (await channel.invokeMethod<int>('bootCount'))?.toString();
