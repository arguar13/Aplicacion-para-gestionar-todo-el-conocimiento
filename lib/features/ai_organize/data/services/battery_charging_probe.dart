import 'package:battery_plus/battery_plus.dart';
import 'package:sinapsis/features/ai_organize/domain/services/charging_probe.dart';

/// Si el dispositivo está enchufado, según `battery_plus`.
///
/// Enchufado es cargando, con la batería llena, o enchufado sin cargar —el
/// límite de carga de muchos teléfonos—: en los tres la energía viene de la
/// pared. «No se sabe» (`BatteryState.unknown`) depende de dónde: en una
/// computadora de escritorio, que no tiene batería, es justamente eso, y está
/// enchufada; en un teléfono no se supone nada ([unknownMeansPlugged]).
///
/// Si el sistema no contesta —el complemento no existe en esa plataforma, o
/// falla—, también «no se sabe», como en `DiskSpacePlusFreeSpaceProbe`.
class BatteryChargingProbe implements ChargingProbe {
  BatteryChargingProbe({required this.unknownMeansPlugged, Battery? battery})
    : _battery = battery ?? Battery();

  /// Qué es «no se sabe»: enchufado en escritorio, no en un teléfono.
  final bool unknownMeansPlugged;
  final Battery _battery;

  @override
  Future<bool> isCharging() async {
    try {
      return _isPlugged(await _battery.batteryState);
    } on Exception {
      // `MissingPluginException` o `PlatformException`: ver arriba.
      return _isPlugged(BatteryState.unknown);
    }
  }

  @override
  Stream<bool> watchCharging() => _battery.onBatteryStateChanged
      .map(_isPlugged)
      .handleError(
        // Mismo criterio que `isCharging`: sin el complemento, el stream
        // falla al escucharlo, y eso es «no se sabe», no un error de la cola.
        (Object _) {},
        test: (error) => error is Exception,
      )
      .distinct();

  bool _isPlugged(BatteryState state) => switch (state) {
    BatteryState.charging ||
    BatteryState.full ||
    BatteryState.connectedNotCharging => true,
    BatteryState.discharging => false,
    BatteryState.unknown => unknownMeansPlugged,
  };
}
