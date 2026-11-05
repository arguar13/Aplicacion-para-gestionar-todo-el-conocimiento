import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/features/narration/domain/entities/narration_voice.dart';
import 'package:sinapsis/features/narration/domain/voices/mine/kokoro_blend.dart';
import 'package:sinapsis/features/narration/domain/voices/mine/my_voice.dart';
import 'package:sinapsis/features/narration/domain/voices/mine/recording_check.dart';
import 'package:sinapsis/features/narration/domain/voices/offline_voice_catalog.dart';
import 'package:sinapsis/features/narration/domain/voices/voice_filter.dart';
import 'package:sinapsis/features/narration/domain/voices/voice_profile.dart';
import 'package:sinapsis/features/narration/domain/voices/voice_traits.dart';

final _blend = KokoroBlend(
  locale: 'es',
  timbre: const [BlendPart(28, 0.6), BlendPart(3, 0.4)],
  prosody: const [BlendPart(28, 1)],
  pace: 0.97,
);

final _created = MyVoice(
  id: 'v1',
  name: 'Clara',
  origin: VoiceOrigin.created,
  home: MyVoiceHome.phone,
  locale: 'es',
  createdAt: DateTime.utc(2026, 10, 31, 12),
  gender: VoiceGender.female,
  timbre: VoiceTimbre.clear,
  styles: const {VoiceStyle.calm},
  description: 'mujer serena',
  blend: _blend,
  faceSeed: 2,
);

final _cloned = MyVoice(
  id: 'v2',
  name: 'Papá',
  origin: VoiceOrigin.cloned,
  home: MyVoiceHome.elevenLabs,
  locale: 'es-AR',
  createdAt: DateTime.utc(2026, 10, 31, 13),
  cloudVoiceId: 'abc123',
  consent: VoiceConsent(
    kind: VoiceConsentKind.permission,
    personName: 'Jorge Pérez',
    grantedAt: DateTime.utc(2026, 10, 31, 12, 59),
  ),
  recording: const MyVoiceRecording(
    file: 'grabacion.wav',
    report: RecordingReport(
      total: Duration(seconds: 95),
      voiced: Duration(seconds: 80),
      noiseDb: -70,
      voiceDb: -18,
      clippedRatio: 0,
    ),
    uploaded: false,
  ),
  sampleFile: 'muestra.mp3',
);

void main() {
  test('vuelve igual de su ficha, con la mezcla y el consentimiento', () {
    final created = MyVoice.fromJson(_created.toJson())!;
    expect(created.toJson(), _created.toJson());
    expect(created.blend, _blend);
    final cloned = MyVoice.fromJson(_cloned.toJson())!;
    expect(cloned.toJson(), _cloned.toJson());
    expect(cloned.consent, _cloned.consent);
    expect(cloned.consent!.personName, 'Jorge Pérez');
    expect(cloned.recording!.report.voiced, const Duration(seconds: 80));
  });

  test('una ficha a la que le falta lo que la hace leer no es una voz', () {
    final created = _created.toJson();
    expect(MyVoice.fromJson({...created, 'blend': null}), isNull);
    final cloned = _cloned.toJson();
    expect(MyVoice.fromJson({...cloned, 'cloudVoiceId': null}), isNull);
    // Una clonada sin consentimiento no se lee nunca.
    expect(MyVoice.fromJson({...cloned, 'consent': null}), isNull);
    expect(
      MyVoice.fromJson({
        ...cloned,
        'consent': {
          ...?(cloned['consent'] as Map<String, Object?>?),
          'personName': ' ',
        },
      }),
      isNull,
    );
    expect(MyVoice.fromJson({...created, 'origin': 'offline'}), isNull);
    expect(MyVoice.fromJson('no es una ficha'), isNull);
  });

  test('lee con el motor de donde vive', () {
    expect(
      _created.narrationVoice,
      const NarrationVoice(
        name: 'mia:v1',
        locale: 'es',
        engine: NarrationEngine.offline,
      ),
    );
    expect(_cloned.narrationVoice.engine, NarrationEngine.cloud);
    expect(isMyVoice(_cloned.narrationVoice), isTrue);
    expect(myVoiceIdOf(_cloned.narrationVoice), 'v2');
    expect(
      isMyVoice(const NarrationVoice(name: 'es-ar-x-local', locale: 'es-AR')),
      isFalse,
    );
  });

  test('la cara sale del id y de la cara elegida', () {
    expect(_created.faceKey, 'v1#2');
    expect(_cloned.faceKey, 'v2');
  });

  test('en la biblioteca, con sus rasgos, dónde vive y si va por la nube', () {
    final [created, cloned] = myVoiceProfiles([_created, _cloned]);
    expect(created.id, 'mia:v1');
    expect(created.origin, VoiceOrigin.created);
    expect(created.gender, VoiceGender.female);
    expect(created.timbre, VoiceTimbre.clear);
    expect(created.styles, {VoiceStyle.calm});
    expect(created.inCloud, isFalse);
    expect(created.faceKey, 'v1#2');
    expect(cloned.inCloud, isTrue);
    expect(cloned.needsInternet, isTrue);
    expect(cloned.locale, 'es-AR');
    expect(
      voiceProfileOf(_cloned.narrationVoice, mine: [_created, _cloned])!.mine,
      _cloned,
    );
    // Una propia que ya no está no tiene tarjeta.
    expect(voiceProfileOf(_cloned.narrationVoice), isNull);
  });

  test('una voz creada lee como un hablante más del catálogo de Kokoro, '
      'con su id propio', () {
    final voice = OfflineVoice.blend(
      id: 'v1',
      speakerId: 3,
      name: 'Clara',
      locale: 'es',
      kokoroPhonemes: _blend.phonemes,
      pace: 0.97,
    );
    expect(voice.id, '${myVoicePrefix}v1');
    expect(voice.isBlend, isTrue);
    expect(voice.package, OfflineVoiceCatalog.kokoro);
    expect(OfflineVoiceCatalog.voices.every((v) => !v.isBlend), isTrue);
  });

  test('Filtrar ofrece los rasgos que eligió quien creó la voz, y Mías las '
      'muestra', () {
    final all = [
      ...myVoiceProfiles([_created, _cloned]),
      ...offlineVoiceProfiles(OfflineVoiceCatalog.voices),
    ];
    final options = VoiceFilterOptions.of(all, const VoiceFilter());
    expect(options.timbres, [VoiceTimbre.clear]);
    expect(options.styles, [VoiceStyle.calm]);
    final calm = voicesIn(
      all,
      tab: VoiceLibraryTab.all,
      filter: const VoiceFilter().toggleStyle(VoiceStyle.calm),
      favorites: const {},
    );
    expect([for (final v in calm) v.id], ['mia:v1']);
    final mine = voicesIn(
      all,
      tab: VoiceLibraryTab.mine,
      filter: const VoiceFilter(),
      favorites: const {},
    );
    expect([for (final v in mine) v.id], ['mia:v1', 'mia:v2']);
  });

  group('blendSlots', () {
    MyVoice created(String id, DateTime at) => MyVoice(
      id: id,
      name: id,
      origin: VoiceOrigin.created,
      home: MyVoiceHome.phone,
      locale: 'es',
      createdAt: at,
      blend: _blend,
    );

    test('por antigüedad, y por id si nacieron a la vez; las de la nube no '
        'ocupan lugar', () {
      final slots = blendSlots([
        created('c', DateTime.utc(2026, 3)),
        _cloned,
        created('b', DateTime.utc(2026)),
        created('a', DateTime.utc(2026, 3)),
      ]);
      expect(slots, {'b': 0, 'a': 1, 'c': 2});
    });

    test('las que no caben quedan sin lugar, y su tarjeta lo dice', () {
      final voices = [
        for (var i = 0; i <= kokoroSpeakerSlots; i++)
          created(
            'v${i.toString().padLeft(2, '0')}',
            DateTime.utc(2026, 1, i + 1),
          ),
      ];
      final slots = blendSlots(voices);
      expect(slots, hasLength(kokoroSpeakerSlots));
      expect(slots.containsKey(voices.last.id), isFalse);
      final profiles = myVoiceProfiles(voices);
      expect(profiles.last.noRoom, isTrue);
      expect(profiles.first.noRoom, isFalse);
    });
  });
}
