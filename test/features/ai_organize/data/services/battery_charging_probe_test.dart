import 'package:battery_plus/battery_plus.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:sinapsis/features/ai_organize/data/services/battery_charging_probe.dart';

class _MockBattery extends Mock implements Battery {}

void main() {
  late _MockBattery battery;

  setUp(() => battery = _MockBattery());

  BatteryChargingProbe probe({bool desktop = false}) =>
      BatteryChargingProbe(unknownMeansPlugged: desktop, battery: battery);

  test('enchufado es cargando, llena o enchufada sin cargar', () async {
    for (final (state, plugged) in [
      (BatteryState.charging, true),
      (BatteryState.full, true),
      (BatteryState.connectedNotCharging, true),
      (BatteryState.discharging, false),
    ]) {
      when(() => battery.batteryState).thenAnswer((_) async => state);
      expect(await probe().isCharging(), plugged, reason: '$state');
    }
  });

  test('«no se sabe» es enchufado solo en escritorio', () async {
    when(
      () => battery.batteryState,
    ).thenAnswer((_) async => BatteryState.unknown);

    expect(await probe().isCharging(), isFalse);
    expect(await probe(desktop: true).isCharging(), isTrue);
  });

  test('sin el complemento, es «no se sabe»', () async {
    when(
      () => battery.batteryState,
    ).thenThrow(MissingPluginException('sin batería'));

    expect(await probe().isCharging(), isFalse);
  });

  test('avisa al enchufar y desenchufar, sin repetir', () async {
    when(() => battery.onBatteryStateChanged).thenAnswer(
      (_) => Stream.fromIterable([
        BatteryState.discharging,
        BatteryState.charging,
        BatteryState.full,
        BatteryState.discharging,
      ]),
    );

    expect(await probe().watchCharging().toList(), [false, true, false]);
  });
}
