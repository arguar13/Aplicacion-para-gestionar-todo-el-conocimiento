import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sinapsis/core/audio/lock_screen_title.dart';
import 'package:sinapsis/core/audio/media_session_hub.dart';
import 'package:sinapsis/core/audio/method_channel_media_session.dart';
import 'package:sinapsis/core/audio/null_media_session.dart';
import 'package:sinapsis/core/design/theme_mode_notifier.dart';

import '../../support/fake_media_session.dart';

/// El título de lo que suena en la pantalla de bloqueo (F47, paso 7a-bis):
/// la preferencia, de entrada apagada, y que llegue a Android al abrirse la
/// app y cada vez que cambia. Qué se oculta lo decide Android
/// (`LockScreenPrivacy.kt`).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late SharedPreferences prefs;
  late FakeMediaSession session;

  Future<ProviderContainer> open({
    Map<String, Object> stored = const {},
    bool supported = true,
  }) async {
    SharedPreferences.setMockInitialValues(stored);
    prefs = await SharedPreferences.getInstance();
    session = FakeMediaSession(isSupported: supported);
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        mediaSessionPlatformProvider.overrideWithValue(session),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  test('de entrada, apagado: no se ve en la pantalla de bloqueo', () async {
    final container = await open();
    expect(container.read(lockScreenTitleProvider), isFalse);
  });

  test('prenderlo queda guardado para la próxima vez que se abra la '
      'app', () async {
    final container = await open();
    await container.read(lockScreenTitleProvider.notifier).set(show: true);
    expect(container.read(lockScreenTitleProvider), isTrue);

    final reopened = ProviderContainer(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
    );
    addTearDown(reopened.dispose);
    expect(reopened.read(lockScreenTitleProvider), isTrue);
  });

  test('llega a Android al abrirse la app, antes de que suene nada, y cada '
      'vez que cambia', () async {
    final container = await open();
    container.read(lockScreenTitleSyncProvider);
    expect(session.lockScreenTitle, [false]);
    expect(session.shown, isEmpty);

    final notifier = container.read(lockScreenTitleProvider.notifier);
    await notifier.set(show: true);
    await pumpEventQueue();
    expect(session.lockScreenTitle, [false, true]);

    // Lo mismo otra vez no se manda de nuevo.
    await notifier.set(show: true);
    await notifier.set(show: false);
    await pumpEventQueue();
    expect(session.lockScreenTitle, [false, true, false]);
  });

  test('si estaba prendido, al abrirse la app llega prendido', () async {
    final container = await open(
      stored: {'media_session.show_title_on_lock_screen': true},
    );
    container.read(lockScreenTitleSyncProvider);
    expect(session.lockScreenTitle, [true]);
  });

  test('donde no hay tarjeta no se manda nada', () async {
    final container = await open(supported: false);
    container.read(lockScreenTitleSyncProvider);
    await container.read(lockScreenTitleProvider.notifier).set(show: true);
    await pumpEventQueue();
    expect(session.lockScreenTitle, isEmpty);
    await const NullMediaSession().showTitleOnLockScreen(show: true);
  });

  test('por el canal, como lo lee `MediaSessionChannel`', () async {
    const channel = MethodChannel('app.sinapsis/media_session');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final calls = <MethodCall>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    final platform = MethodChannelMediaSession();
    addTearDown(platform.dispose);

    await platform.showTitleOnLockScreen(show: true);
    await platform.showTitleOnLockScreen(show: false);

    expect(calls.map((c) => c.method), ['lockScreen', 'lockScreen']);
    expect(calls.map((c) => c.arguments), [
      {'showTitle': true},
      {'showTitle': false},
    ]);
  });

  group('censos del lado de Android', () {
    const kotlin = 'android/app/src/main/kotlin/app/sinapsis';
    String read(String path) => File(path).readAsStringSync();

    test('el canal entiende lo que manda Dart', () {
      final channel = read('$kotlin/MediaSessionChannel.kt');
      expect(channel, contains('"lockScreen" ->'));
      expect(channel, contains('call.argument<Boolean>("showTitle") == true'));
    });

    test('la tarjeta cierra los tres caminos con la misma regla', () {
      final service = read('$kotlin/MediaPlaybackService.kt');
      // La regla, en un solo lugar.
      expect(service, contains('LockScreenPrivacy.face('));
      // 1 y 3: la tarjeta y los metadatos pasan a lo genérico, y se entera
      // de la pantalla que se apaga, se prende y se desbloquea.
      for (final action in [
        'Intent.ACTION_SCREEN_OFF',
        'Intent.ACTION_SCREEN_ON',
        'Intent.ACTION_USER_PRESENT',
      ]) {
        expect(service, contains(action));
      }
      expect(service, contains('R.string.media_locked_title'));
      // 2: privada, con una versión pública genérica.
      expect(service, contains('LockScreenPrivacy.visibility('));
      expect(service, contains('setPublicVersion(buildNotification(generic('));
      // De entrada, oculto, hasta que Dart diga otra cosa.
      expect(
        service,
        contains('@Volatile private var showTitleOnLockScreen = false'),
      );
    });

    test('lo genérico está en castellano y en inglés', () {
      for (final values in ['values', 'values-en']) {
        expect(
          read('android/app/src/main/res/$values/media_strings.xml'),
          contains('<string name="media_locked_title">'),
          reason: values,
        );
      }
    });
  });
}
