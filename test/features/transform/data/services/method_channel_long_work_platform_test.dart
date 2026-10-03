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
                      '${args['done']}/${args['total']}'
                      '${args['detail'] == null ? '' : ' ${args['detail']}'} '
                      '${args['types']}',
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
    await platform.show(
      const LongWorkNotice(
        owner: LongWorkOwner.sampleLibrary,
        done: 7,
        total: 80,
      ),
    );
    await platform.stop();

    expect(calls, [
      'working processing 1/4 [data_sync]',
      'working organizing 3/120 [data_sync]',
      'working sample_library 7/80 [data_sync]',
      'idle',
    ]);
  });

  test('si Android no puede, el trabajo sigue: no lanza', () async {
    fail = true;

    await platform.show(
      const LongWorkNotice(owner: LongWorkOwner.aiOrganize, done: 0, total: 0),
    );

    expect(calls, ['working organizing 0/0 [data_sync]']);
  });

  test('una descarga dice qué modelo se baja, y una transcripción, que es '
      'procesar medios', () async {
    await platform.show(
      const LongWorkNotice(
        owner: LongWorkOwner.modelDownload,
        done: 470,
        total: 1000,
        detail: LongWorkDetail.languageModel,
      ),
    );
    await platform.show(
      const LongWorkNotice(
        owner: LongWorkOwner.processing,
        done: 1,
        total: 4,
        kinds: {LongWorkKind.mediaProcessing, LongWorkKind.dataSync},
      ),
    );
    await platform.show(
      const LongWorkNotice(
        owner: LongWorkOwner.audioDownload,
        done: 0,
        total: 0,
      ),
    );

    expect(calls, [
      'working model_download 470/1000 language_model [data_sync]',
      'working processing 1/4 [media_processing, data_sync]',
      'working audio_download 0/0 [data_sync]',
    ]);
  });

  test('cuando Android corta el servicio, se entera quien escucha', () async {
    final stops = <void>[];
    final subscription = platform.stoppedBySystem.listen(stops.add);

    await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .handlePlatformMessage(
          channel.name,
          channel.codec.encodeMethodCall(
            const MethodCall('timedOut', {'type': 'data_sync'}),
          ),
          (_) {},
        );
    await subscription.cancel();

    expect(stops, hasLength(1));
  });
}
