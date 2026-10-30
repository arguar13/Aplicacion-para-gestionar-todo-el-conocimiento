import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/audio/audio_focus.dart';
import 'package:sinapsis/core/audio/media_session.dart';
import 'package:sinapsis/core/audio/media_session_hub.dart';
import 'package:sinapsis/core/audio/method_channel_media_session.dart';
import 'package:sinapsis/core/audio/null_media_session.dart';

import '../../support/fake_media_session.dart';

const _reading = MediaSessionState(
  title: 'Un documento',
  subtitle: 'Leyendo con la voz del teléfono · 1,0×',
  position: Duration(seconds: 10),
  duration: Duration(minutes: 5),
  playing: true,
);

MediaSessionState _at(Duration position, {bool playing = true}) =>
    MediaSessionState(
      title: _reading.title,
      subtitle: _reading.subtitle,
      position: position,
      duration: _reading.duration,
      playing: playing,
    );

void main() {
  late FakeMediaSession platform;
  late MediaSessionHub hub;
  var now = Duration.zero;

  setUp(() {
    platform = FakeMediaSession();
    now = Duration.zero;
    hub = MediaSessionHub(platform, now: () => now);
    addTearDown(hub.dispose);
  });

  group('la tarjeta', () {
    test('muestra lo que tiene el foco, y se va cuando no hay nada', () {
      final source = FakeMediaSource(_reading);

      hub.follow(source);
      expect(platform.card, _reading);

      source.value = null;
      expect(platform.card, isNull);
      expect(platform.ended, 1);

      // Sin tarjeta, otro «nada» no vuelve a avisar.
      source.value = null;
      expect(platform.ended, 1);
    });

    test('sin nada que mostrar, no aparece', () {
      hub.follow(FakeMediaSource());

      expect(platform.shown, isEmpty);
      expect(platform.ended, 0);
    });

    test('pasa a lo que tome el foco, y sin nadie se va', () {
      final first = FakeMediaSource(_reading);
      const audio = MediaSessionState(title: 'Una clase', playing: true);
      final second = FakeMediaSource(audio);

      hub
        ..follow(first)
        ..follow(second);
      expect(platform.card, audio);

      // Lo de antes ya no la mueve.
      first.value = _at(const Duration(minutes: 3));
      expect(platform.card, audio);

      hub.follow(null);
      expect(platform.card, isNull);
    });

    test('mientras suena, no la vuelve a mandar con cada palabra: el '
        'teléfono adelanta la barra solo', () {
      final source = FakeMediaSource(_reading);
      hub.follow(source);

      now = const Duration(seconds: 3);
      source.value = _at(const Duration(seconds: 13));
      now = const Duration(seconds: 4);
      source.value = _at(const Duration(seconds: 15));

      expect(platform.shown, hasLength(1));
    });

    test('se corrige si la barra se apartó más de 2 s: un salto, o una voz '
        'más rápida que lo estimado', () {
      final source = FakeMediaSource(_reading);
      hub.follow(source);

      now = const Duration(seconds: 1);
      source.value = _at(const Duration(seconds: 21));

      expect(platform.shown, hasLength(2));
      expect(platform.card?.position, const Duration(seconds: 21));
    });

    test('en pausa, la barra no avanza sola', () {
      final source = FakeMediaSource(
        _at(const Duration(seconds: 10), playing: false),
      );
      hub.follow(source);

      now = const Duration(seconds: 30);
      source.value = _at(const Duration(seconds: 11), playing: false);
      expect(platform.shown, hasLength(1));

      source.value = _at(const Duration(seconds: 13), playing: false);
      expect(platform.shown, hasLength(2));
    });

    test('lo que se ve —pausa, título, voz, la cola— se manda enseguida', () {
      final source = FakeMediaSource(_reading);
      hub.follow(source);

      source
        ..value = _at(_reading.position, playing: false)
        ..value = const MediaSessionState(
          title: 'Otro',
          position: Duration(seconds: 10),
          duration: Duration(minutes: 5),
        );

      expect(platform.shown, hasLength(3));
      expect(platform.card?.title, 'Otro');
    });

    test('al dejar de usarse, se va', () {
      hub
        ..follow(FakeMediaSource(_reading))
        ..dispose();

      expect(platform.card, isNull);
    });
  });

  group('lo que se toca', () {
    test('le llega a lo que suena', () {
      final source = FakeMediaSource(_reading);
      hub.follow(source);

      platform
        ..tap(const MediaPause())
        ..tap(const MediaSkip(Duration(seconds: -10)))
        ..tap(const MediaNext())
        ..tap(const MediaOpen());

      expect(source.handled, [
        isA<MediaPause>(),
        isA<MediaSkip>().having(
          (c) => c.by,
          'by',
          -const Duration(seconds: 10),
        ),
        isA<MediaNext>(),
        isA<MediaOpen>(),
      ]);
    });

    test('sin nada en la tarjeta, no le llega a nadie', () {
      final source = FakeMediaSource(_reading);
      hub
        ..follow(source)
        ..follow(null);

      platform.tap(const MediaPlay());

      expect(source.handled, isEmpty);
    });
  });

  group('se porta bien con el teléfono', () {
    test('una llamada pausa, y al cortar sigue', () {
      final source = FakeMediaSource(_reading);
      hub.follow(source);

      platform.interrupt(const MediaInterruptionBegan(resumable: true));
      expect(source.handled, [isA<MediaPause>()]);
      expect(platform.card?.playing, isFalse);

      platform.interrupt(const MediaInterruptionEnded());
      expect(source.handled, [isA<MediaPause>(), isA<MediaPlay>()]);
    });

    test('lo que estaba en pausa sigue en pausa después de la llamada', () {
      final source = FakeMediaSource(_at(Duration.zero, playing: false));
      hub.follow(source);

      platform
        ..interrupt(const MediaInterruptionBegan(resumable: true))
        ..interrupt(const MediaInterruptionEnded());

      expect(source.handled, isEmpty);
    });

    test('otra app que se queda con el sonido pausa, y no vuelve sola', () {
      final source = FakeMediaSource(_reading);
      hub.follow(source);

      platform
        ..interrupt(const MediaInterruptionBegan(resumable: false))
        ..interrupt(const MediaInterruptionEnded());

      expect(source.handled, [isA<MediaPause>()]);
    });

    test('desconectar los auriculares pausa, y no vuelve sola', () {
      final source = FakeMediaSource(_reading);
      hub.follow(source);

      platform.interrupt(const MediaBecameNoisy());
      expect(source.handled, [isA<MediaPause>()]);

      platform.interrupt(const MediaInterruptionEnded());
      expect(source.handled, hasLength(1));
    });

    test('si la persona toca algo en el medio, manda ella', () {
      final source = FakeMediaSource(_reading);
      hub.follow(source);

      platform
        ..interrupt(const MediaInterruptionBegan(resumable: true))
        ..tap(const MediaPause())
        ..interrupt(const MediaInterruptionEnded());

      expect(source.handled, [isA<MediaPause>(), isA<MediaPause>()]);
    });
  });

  group('el provider', () {
    late ProviderContainer container;

    setUp(() {
      container = ProviderContainer(
        overrides: [
          mediaSessionPlatformProvider.overrideWithValue(platform),
          mediaSessionClockProvider.overrideWithValue(() => now),
        ],
      );
      addTearDown(container.dispose);
    });

    test('muestra lo registrado con el testigo que tiene el foco', () {
      container.read(mediaSessionHubProvider);
      final reader = FakeMediaSource(_reading);
      const audioOwner = #audio;
      final audio = FakeMediaSource(
        const MediaSessionState(title: 'Una clase', playing: true),
      );
      container.read(mediaSessionSourcesProvider.notifier)
        ..register(#lector, reader)
        ..register(audioOwner, audio);

      container.read(audioFocusProvider.notifier).claim(#lector);
      expect(platform.card, _reading);

      container.read(audioFocusProvider.notifier).claim(audioOwner);
      expect(platform.card?.title, 'Una clase');

      // Lo que suena y no tiene tarjeta la saca.
      container.read(audioFocusProvider.notifier).claim(#otro);
      expect(platform.card, isNull);
    });

    test('lo que se registra después de tomar el foco aparece igual, y al '
        'irse se lleva la tarjeta', () {
      container
        ..read(mediaSessionHubProvider)
        ..read(audioFocusProvider.notifier).claim(#lector);
      final reader = FakeMediaSource(_reading);
      final sources = container.read(mediaSessionSourcesProvider.notifier)
        ..register(#lector, reader);
      expect(platform.card, _reading);

      // Sacar otro con el mismo testigo no saca a este.
      sources.unregister(#lector, FakeMediaSource());
      expect(platform.card, _reading);

      sources.unregister(#lector, reader);
      expect(platform.card, isNull);
    });

    test('donde no hay tarjeta —la web, Windows— no hace nada', () {
      final none = ProviderContainer(
        overrides: [
          mediaSessionPlatformProvider.overrideWithValue(
            const NullMediaSession(),
          ),
        ],
      );
      addTearDown(none.dispose);

      none
        ..read(mediaSessionHubProvider)
        ..read(
          mediaSessionSourcesProvider.notifier,
        ).register(#lector, FakeMediaSource(_reading))
        ..read(audioFocusProvider.notifier).claim(#lector);

      expect(const NullMediaSession().isSupported, isFalse);
    });
  });

  group('el canal con Android', () {
    TestWidgetsFlutterBinding.ensureInitialized();
    const channel = MethodChannel('app.sinapsis/media_session');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

    tearDown(() => messenger.setMockMethodCallHandler(channel, null));

    test('manda lo que muestra la tarjeta', () async {
      final calls = <MethodCall>[];
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        return null;
      });
      final session = MethodChannelMediaSession();
      addTearDown(session.dispose);

      await session.update(
        const MediaSessionState(
          title: 'Un documento',
          subtitle: 'Leyendo',
          position: Duration(seconds: 3),
          duration: Duration(minutes: 1),
          playing: true,
          hasNext: true,
          requestsAudioFocus: false,
        ),
      );
      await session.end();

      expect(calls.map((c) => c.method), ['update', 'end']);
      expect(calls.first.arguments, {
        'title': 'Un documento',
        'subtitle': 'Leyendo',
        'positionMs': 3000,
        'durationMs': 60000,
        'playing': true,
        'hasNext': true,
        'focus': false,
        'artwork': null,
      });
    });

    test('sin nada del otro lado, deja de intentar y no falla', () async {
      final calls = <String>[];
      final session = MethodChannelMediaSession();
      addTearDown(session.dispose);

      await session.update(_reading);
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call.method);
        return null;
      });
      await session.end();

      expect(calls, isEmpty);
    });

    test('lo que llega de Android sale por sus canales', () async {
      final session = MethodChannelMediaSession();
      addTearDown(session.dispose);
      final commands = <MediaCommand>[];
      final interruptions = <MediaInterruption>[];
      session.commands.listen(commands.add);
      session.interruptions.listen(interruptions.add);
      const codec = StandardMethodCodec();

      Future<void> send(String method, Map<String, Object?> arguments) =>
          messenger.handlePlatformMessage(
            channel.name,
            codec.encodeMethodCall(MethodCall(method, arguments)),
            (_) {},
          );

      await send('command', {'name': 'seek', 'ms': 4200});
      await send('command', {'name': 'skip', 'ms': -10000});
      await send('interruption', {'kind': 'noisy'});
      await pumpEventQueue();

      expect(commands, [
        isA<MediaSeek>().having(
          (c) => c.to,
          'to',
          const Duration(milliseconds: 4200),
        ),
        isA<MediaSkip>().having(
          (c) => c.by,
          'by',
          const Duration(seconds: -10),
        ),
      ]);
      expect(interruptions, [isA<MediaBecameNoisy>()]);
    });

    test('lee cada cosa que se toca y cada interrupción', () {
      MediaCommand? command(String name, [int? ms]) =>
          MethodChannelMediaSession.commandFrom({'name': name, 'ms': ms});

      expect(command('play'), isA<MediaPlay>());
      expect(command('pause'), isA<MediaPause>());
      expect(command('next'), isA<MediaNext>());
      expect(command('stop'), isA<MediaStop>());
      expect(command('open'), isA<MediaOpen>());
      expect(command('skip'), isNull);
      expect(command('seek'), isNull);
      expect(command('otra'), isNull);

      MediaInterruption? interruption(String kind) =>
          MethodChannelMediaSession.interruptionFrom({'kind': kind});

      expect(
        interruption('began'),
        isA<MediaInterruptionBegan>().having((i) => i.resumable, 'r', isTrue),
      );
      expect(
        interruption('lost'),
        isA<MediaInterruptionBegan>().having((i) => i.resumable, 'r', isFalse),
      );
      expect(interruption('ended'), isA<MediaInterruptionEnded>());
      expect(interruption('otra'), isNull);
    });
  });
}
