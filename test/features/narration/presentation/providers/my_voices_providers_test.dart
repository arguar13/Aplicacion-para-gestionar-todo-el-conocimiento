import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sinapsis/core/design/theme_mode_notifier.dart'
    show sharedPreferencesProvider;
import 'package:sinapsis/features/narration/data/voices/eleven_labs_voice_cloud.dart';
import 'package:sinapsis/features/narration/domain/voices/mine/kokoro_blend.dart';
import 'package:sinapsis/features/narration/domain/voices/mine/my_voice.dart';
import 'package:sinapsis/features/narration/domain/voices/offline_voice_catalog.dart';
import 'package:sinapsis/features/narration/domain/voices/voice_profile.dart';
import 'package:sinapsis/features/narration/domain/voices/voice_traits.dart';
import 'package:sinapsis/features/narration/presentation/providers/my_voices_providers.dart';
import 'package:sinapsis/features/narration/presentation/providers/offline_voice_providers.dart';
import 'package:sinapsis/features/narration/presentation/voices/voice_texts.dart';
import 'package:sinapsis/l10n/generated/app_localizations_es.dart';

import '../../../../support/my_voices_harness.dart';

final _blend = KokoroBlend(
  locale: 'es',
  timbre: const [BlendPart(28, 0.6), BlendPart(3, 0.4)],
  prosody: const [BlendPart(28, 1)],
);

/// [count] voces creadas en el teléfono, de la más vieja a la más nueva.
List<MyVoice> _created(int count) => [
  for (var i = 0; i < count; i++)
    MyVoice(
      id: 'v${i.toString().padLeft(2, '0')}',
      name: 'V$i',
      origin: VoiceOrigin.created,
      home: MyVoiceHome.phone,
      locale: 'es',
      createdAt: DateTime.utc(2026).add(Duration(minutes: i)),
      blend: _blend,
    ),
];

void main() {
  final es = AppLocalizationsEs();

  Future<ProviderContainer> container(
    List<MyVoice> voices, {
    bool kokoro = true,
  }) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final created = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        elevenLabsKeyStoreProvider.overrideWithValue(
          ElevenLabsKeyStore(storage: FakeSecureStorage()),
        ),
        myVoicesProvider.overrideWith((ref) => Stream.value(voices)),
        installedVoicePackagesProvider.overrideWith(
          (ref) => Stream.value({if (kokoro) OfflineVoiceCatalog.kokoro.id}),
        ),
      ],
    );
    addTearDown(created.dispose);
    created
      ..listen(myVoicesProvider, (_, _) {})
      ..listen(installedVoicePackagesProvider, (_, _) {});
    await Future<void>.delayed(Duration.zero);
    return created;
  }

  test('las creadas leen con Kokoro y si caben en el voices.bin', () async {
    final voices = _created(kokoroSpeakerSlots + 1);
    final ready = (await container(voices)).read(readyMyVoiceNamesProvider);
    expect(ready, hasLength(kokoroSpeakerSlots));
    expect(ready, contains(voices.first.narrationVoice.name));
    expect(ready, isNot(contains(voices.last.narrationVoice.name)));
  });

  test('sin Kokoro, ninguna creada lee', () async {
    final ready = (await container(
      _created(2),
      kokoro: false,
    )).read(readyMyVoiceNamesProvider);
    expect(ready, isEmpty);
  });

  test('la tarjeta de la que no cabe lo dice, y la que espera a Kokoro '
      'también', () {
    final profiles = myVoiceProfiles(_created(kokoroSpeakerSlots + 1));
    expect(
      myVoiceOriginLine(profiles.last, es, ready: false),
      contains(es.f47P4NoRoomToRead),
    );
    expect(
      myVoiceOriginLine(profiles.first, es, ready: false),
      contains(es.f47P4NeedsKokoro),
    );
    expect(
      myVoiceOriginLine(profiles.first, es, ready: true),
      isNot(contains(es.f47P4NeedsKokoro)),
    );
  });
}
