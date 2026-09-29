import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/features/transform/data/services/platform_long_work_keeper.dart';

import '../../../../support/silent_logger.dart';

/// El guardián del trabajo largo en Android (F21, decisión C), contra un
/// canal simulado. Con `testWidgets` por el reloj falso: el margen para
/// soltar se prueba sin esperarlo de verdad.
void main() {
  const channel = MethodChannel('app.sinapsis/long_work');
  late List<String> calls;
  var fail = false;

  setUp(() {
    calls = [];
    fail = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          final args = call.arguments as Map<Object?, Object?>?;
          calls.add(
            args == null
                ? call.method
                : '${call.method} ${args['done']}/${args['total']}',
          );
          if (fail) throw PlatformException(code: 'no');
          return null;
        });
  });

  tearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null),
  );

  /// Suelta a los 15 segundos, el valor de la app.
  PlatformLongWorkKeeper keeper() =>
      PlatformLongWorkKeeper(logger: const SilentLogger());

  testWidgets('solo avisa lo que cambia: otro porcentaje, no cada página', (
    tester,
  ) async {
    keeper()
      ..working(done: 1, total: 400)
      ..working(done: 2, total: 400)
      ..working(done: 3, total: 400)
      ..working(done: 4, total: 400);
    await tester.pump();

    expect(calls, ['working 1/400', 'working 4/400']);
  });

  testWidgets('soltar espera un momento: si en ese momento empieza otro '
      'trabajo largo, el servicio sigue', (tester) async {
    final k = keeper()..working(done: 10, total: 10);
    await tester.pump();

    k.idle();
    await tester.pump(const Duration(seconds: 5));
    k.working(done: 0, total: 50);
    await tester.pump(const Duration(seconds: 30));

    expect(calls, ['working 10/10', 'working 0/50']);
  });

  testWidgets('pasado el momento, se suelta una sola vez', (tester) async {
    final k = keeper()..working(done: 0, total: 0);
    await tester.pump();

    k
      ..idle()
      ..idle();
    await tester.pump(const Duration(seconds: 16));

    expect(calls, ['working 0/0', 'idle']);
  });

  testWidgets('sin trabajo previo, soltar no le habla a Android', (
    tester,
  ) async {
    keeper().idle();
    await tester.pump(const Duration(seconds: 16));

    expect(calls, isEmpty);
  });

  testWidgets('si Android no puede, el trabajo sigue: no lanza', (
    tester,
  ) async {
    fail = true;

    keeper().working(done: 1, total: 2);
    await tester.pump();

    expect(calls, ['working 1/2']);
  });
}
