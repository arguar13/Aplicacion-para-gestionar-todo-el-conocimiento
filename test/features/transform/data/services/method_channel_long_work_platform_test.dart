import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/features/transform/data/services/method_channel_long_work_platform.dart';
import 'package:sinapsis/features/transform/domain/services/long_work_keeper.dart';

import '../../../../support/silent_logger.dart';

/// El servicio en primer plano de Android (F21), contra un canal simulado: le
/// llega de quién es el trabajo (F27), y si Android no puede, nada se corta.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
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
                : '${call.method} ${args['kind']} '
                      '${args['done']}/${args['total']}',
          );
          if (fail) throw PlatformException(code: 'no');
          return null;
        });
  });

  tearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null),
  );

  final platform = MethodChannelLongWorkPlatform(logger: const SilentLogger());

  test('dice de quién es el trabajo, cuánto va, y cuándo apagar', () async {
    await platform.show(
      const LongWorkNotice(owner: LongWorkOwner.processing, done: 1, total: 4),
    );
    await platform.show(
      const LongWorkNotice(
        owner: LongWorkOwner.aiOrganize,
        done: 3,
        total: 120,
      ),
    );
    await platform.stop();

    expect(calls, [
      'working processing 1/4',
      'working organizing 3/120',
      'idle',
    ]);
  });

  test('si Android no puede, el trabajo sigue: no lanza', () async {
    fail = true;

    await platform.show(
      const LongWorkNotice(owner: LongWorkOwner.aiOrganize, done: 0, total: 0),
    );

    expect(calls, ['working organizing 0/0']);
  });
}
