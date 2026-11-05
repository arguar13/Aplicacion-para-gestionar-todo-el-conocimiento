import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/features/creations/podcast/presentation/providers/podcast_voices.dart';
import 'package:sinapsis/features/narration/domain/voices/mine/kokoro_blend.dart';
import 'package:sinapsis/features/narration/domain/voices/mine/my_voice.dart';
import 'package:sinapsis/features/narration/domain/voices/voice_traits.dart';
import 'package:sinapsis/features/narration/presentation/providers/my_voices_providers.dart';

import '../../../../support/my_voices_harness.dart';

final _cloned = MyVoice(
  id: 'v1',
  name: 'Papá',
  origin: VoiceOrigin.cloned,
  home: MyVoiceHome.elevenLabs,
  locale: 'es-AR',
  createdAt: DateTime.utc(2026, 10, 31),
  cloudVoiceId: 'eleven-1',
  consent: VoiceConsent(
    kind: VoiceConsentKind.permission,
    personName: 'Jorge',
    grantedAt: DateTime.utc(2026, 10, 31),
  ),
);

final _created = MyVoice(
  id: 'v2',
  name: 'Serena',
  origin: VoiceOrigin.created,
  home: MyVoiceHome.phone,
  locale: 'es',
  createdAt: DateTime.utc(2026, 10, 31),
  blend: KokoroBlend(
    locale: 'es',
    timbre: const [BlendPart(28, 0.5), BlendPart(3, 0.5)],
    prosody: const [BlendPart(28, 1)],
  ),
);

/// F47, paso 4, con el paso 6b: las voces propias se ofrecen para el podcast
/// con su id de la biblioteca (`mia:<id>`) —también la de la nube, que
/// cobra y se aprueba antes de generar—, listas si pueden leer ya.
void main() {
  Future<List<PodcastVoiceOption>> optionsFor({
    required bool cloud,
    String language = 'es',
  }) async {
    final harness = await MyVoicesHarness.create(
      cloudEnabled: cloud,
      cloudKey: cloud ? 'k' : null,
      kokoro: true,
    );
    addTearDown(harness.dispose);
    await harness.store.save(_cloned);
    await harness.store.save(_created);
    final container = ProviderContainer(overrides: harness.overrides);
    addTearDown(container.dispose);
    container
      ..listen(myVoicesProvider, (_, _) {})
      ..listen(podcastVoiceOptionsProvider(language), (_, _) {});
    await container.read(myVoicesProvider.future);
    return container.read(podcastVoiceOptionsProvider(language).future);
  }

  PodcastVoiceOption? option(List<PodcastVoiceOption> all, MyVoice voice) =>
      all.where((o) => o.id == voice.narrationVoice.name).firstOrNull;

  test('las dos propias se ofrecen con su id, su nombre y su origen, y '
      'listas', () async {
    final all = await optionsFor(cloud: true);
    final cloned = option(all, _cloned)!;
    expect(cloned.name, 'Papá');
    expect(cloned.origin, VoiceOrigin.cloned);
    expect(cloned.locale, 'es-AR');
    expect(cloned.ready, isTrue);
    final created = option(all, _created)!;
    expect(created.origin, VoiceOrigin.created);
    expect(created.ready, isTrue);
  });

  test('con la nube apagada, la de la nube se ofrece pero no está lista: '
      'va después de las que generan ya', () async {
    final all = await optionsFor(cloud: false);
    final cloned = option(all, _cloned)!;
    expect(cloned.ready, isFalse);
    expect(
      all.indexOf(cloned),
      greaterThan(all.indexOf(option(all, _created)!)),
    );
  });

  test('en otro idioma no aparecen', () async {
    final all = await optionsFor(cloud: true, language: 'en');
    expect(option(all, _cloned), isNull);
    expect(option(all, _created), isNull);
  });
}
