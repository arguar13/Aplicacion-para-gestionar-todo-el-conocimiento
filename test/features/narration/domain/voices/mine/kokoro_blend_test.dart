import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/features/narration/domain/voices/mine/kokoro_blend.dart';
import 'package:sinapsis/features/narration/domain/voices/offline_voice_catalog.dart';
import 'package:sinapsis/features/narration/domain/voices/voice_traits.dart';

/// Las voces de Kokoro del catálogo, por su `sid`.
final _kokoro = {
  for (final voice in OfflineVoiceCatalog.voices)
    if (voice.package == OfflineVoiceCatalog.kokoro) voice.speakerId: voice,
};

double _weightOf(List<BlendPart> parts, bool Function(OfflineVoice) test) =>
    parts
        .where((part) => test(_kokoro[part.speakerId]!))
        .fold(0, (sum, part) => sum + part.weight);

double _total(List<BlendPart> parts) =>
    parts.fold(0, (sum, part) => sum + part.weight);

void main() {
  group('KokoroBlend', () {
    test('normaliza cada mitad para que sume 1 y junta la misma voz', () {
      final blend = KokoroBlend(
        locale: 'es',
        timbre: const [BlendPart(28, 2), BlendPart(3, 1), BlendPart(28, 1)],
        prosody: const [BlendPart(29, 5)],
      );
      expect(blend.timbre, const [BlendPart(28, 0.75), BlendPart(3, 0.25)]);
      expect(blend.prosody, const [BlendPart(29, 1)]);
    });

    test('una mezcla sin voces, o en un idioma que Kokoro no dice, falla', () {
      expect(
        () => KokoroBlend(
          locale: 'es',
          timbre: const [],
          prosody: const [BlendPart(28, 1)],
        ),
        throwsArgumentError,
      );
      expect(
        () => KokoroBlend(
          locale: 'ja',
          timbre: const [BlendPart(28, 1)],
          prosody: const [BlendPart(28, 1)],
        ),
        throwsArgumentError,
      );
    });

    test('vuelve igual de su JSON, y uno roto no es una mezcla', () {
      final blend = KokoroBlend(
        locale: 'en-GB',
        timbre: const [BlendPart(21, 0.6), BlendPart(2, 0.4)],
        prosody: const [BlendPart(21, 1)],
        pace: 0.94,
      );
      expect(KokoroBlend.fromJson(blend.toJson()), blend);
      expect(KokoroBlend.fromJson({'locale': 'es'}), isNull);
      expect(KokoroBlend.fromJson({...blend.toJson(), 'locale': 'xx'}), isNull);
      expect(KokoroBlend.fromJson({...blend.toJson(), 'pace': 0}), isNull);
    });

    test('pronuncia como las voces del catálogo de su idioma', () {
      final blend = KokoroBlend(
        locale: 'es',
        timbre: const [BlendPart(28, 1)],
        prosody: const [BlendPart(28, 1)],
      );
      expect(blend.phonemes, const KokoroPhonemes.espeak('es'));
    });

    test('el resumen promedia las dos mitades, de la que más pesa a la que '
        'menos', () {
      final blend = KokoroBlend(
        locale: 'es',
        timbre: const [BlendPart(28, 0.5), BlendPart(3, 0.5)],
        prosody: const [BlendPart(28, 1)],
      );
      expect(blend.summary, const [BlendPart(28, 0.75), BlendPart(3, 0.25)]);
    });
  });

  group('proposeBlend', () {
    test('nunca es una voz del catálogo: al menos dos voces en el timbre y '
        'ninguna por encima del 80 %', () {
      for (final locale in OfflineVoiceCatalog.kokoroLocales) {
        for (final gender in [null, ...VoiceGender.values]) {
          for (final timbre in [null, ...VoiceTimbre.values]) {
            for (final age in [null, ...VoiceAge.values]) {
              for (var variant = 0; variant < 3; variant++) {
                final blend = proposeBlend(
                  VoiceDesign(
                    locale: locale,
                    gender: gender,
                    timbre: timbre,
                    age: age,
                    variant: variant,
                  ),
                );
                final reason = '$locale $gender $timbre $age $variant';
                expect(
                  blend.timbre.length,
                  greaterThanOrEqualTo(2),
                  reason: reason,
                );
                for (final part in blend.timbre) {
                  expect(
                    part.weight,
                    lessThanOrEqualTo(maxTimbreShare + 1e-9),
                    reason: reason,
                  );
                }
                expect(_total(blend.timbre), closeTo(1, 1e-9), reason: reason);
                expect(_total(blend.prosody), closeTo(1, 1e-9), reason: reason);
              }
            }
          }
        }
      }
    });

    test('la forma de hablar sale de voces nativas del idioma, del género '
        'pedido primero', () {
      final woman = proposeBlend(
        const VoiceDesign(
          locale: 'es',
          gender: VoiceGender.female,
          style: VoiceStyle.expressive,
        ),
      );
      // Dora es la única mujer nativa de Kokoro en español: lleva la prosodia.
      expect(woman.prosody.first, const BlendPart(28, 0.8));
      expect(
        _weightOf(woman.prosody, (voice) => voice.locale == 'es'),
        closeTo(1, 1e-9),
      );
      final english = proposeBlend(const VoiceDesign(locale: 'en-GB'));
      expect(
        _weightOf(english.prosody, (voice) => voice.locale == 'en-GB'),
        closeTo(1, 1e-9),
      );
    });

    test('el género da el timbre', () {
      final man = proposeBlend(
        const VoiceDesign(locale: 'es', gender: VoiceGender.male),
      );
      expect(
        _weightOf(man.timbre, (voice) => voice.gender == VoiceGender.male),
        closeTo(1, 1e-9),
      );
      final unset = proposeBlend(const VoiceDesign(locale: 'es'));
      expect(
        _weightOf(unset.timbre, (voice) => voice.gender == VoiceGender.female),
        closeTo(0.5, 1e-9),
      );
    });

    test('«grave» corre un cuarto del timbre de una mujer a voces de hombre, '
        'y «brillante» el de un hombre a voces de mujer', () {
      final deep = proposeBlend(
        const VoiceDesign(
          locale: 'es',
          gender: VoiceGender.female,
          timbre: VoiceTimbre.deep,
        ),
      );
      expect(
        _weightOf(deep.timbre, (voice) => voice.gender == VoiceGender.male),
        closeTo(0.25, 1e-9),
      );
      final bright = proposeBlend(
        const VoiceDesign(
          locale: 'es',
          gender: VoiceGender.male,
          timbre: VoiceTimbre.bright,
        ),
      );
      expect(
        _weightOf(bright.timbre, (voice) => voice.gender == VoiceGender.female),
        closeTo(0.25, 1e-9),
      );
    });

    test('«joven» y «mayor» corren una décima y cambian el ritmo', () {
      final senior = proposeBlend(
        const VoiceDesign(
          locale: 'es',
          gender: VoiceGender.female,
          age: VoiceAge.senior,
        ),
      );
      expect(
        _weightOf(senior.timbre, (voice) => voice.gender == VoiceGender.male),
        closeTo(0.1, 1e-9),
      );
      expect(senior.pace, closeTo(0.94, 1e-9));
      final young = proposeBlend(
        const VoiceDesign(
          locale: 'es',
          gender: VoiceGender.male,
          age: VoiceAge.young,
        ),
      );
      expect(
        _weightOf(young.timbre, (voice) => voice.gender == VoiceGender.female),
        closeTo(0.1, 1e-9),
      );
      expect(young.pace, closeTo(1.03, 1e-9));
    });

    test('«aterciopelado» reparte el timbre en tres voces y «claro» lo '
        'concentra en una, al 80 %', () {
      final velvety = proposeBlend(
        const VoiceDesign(
          locale: 'es',
          gender: VoiceGender.female,
          timbre: VoiceTimbre.velvety,
        ),
      );
      expect(velvety.timbre, hasLength(3));
      final clear = proposeBlend(
        const VoiceDesign(
          locale: 'es',
          gender: VoiceGender.female,
          timbre: VoiceTimbre.clear,
        ),
      );
      expect(clear.timbre.first.weight, closeTo(maxTimbreShare, 1e-9));
    });

    test('«sereno» reparte la prosodia entre las nativas y baja el ritmo; '
        '«enérgico» la concentra y lo sube', () {
      final calm = proposeBlend(
        const VoiceDesign(locale: 'es', style: VoiceStyle.calm),
      );
      expect(calm.prosody, hasLength(3));
      for (final part in calm.prosody) {
        expect(part.weight, closeTo(1 / 3, 1e-9));
      }
      expect(calm.pace, closeTo(0.94, 1e-9));
      final energetic = proposeBlend(
        const VoiceDesign(locale: 'es', style: VoiceStyle.energetic),
      );
      expect(energetic.prosody.first.weight, closeTo(0.8, 1e-9));
      expect(energetic.pace, closeTo(1.06, 1e-9));
    });

    test('el ritmo elegido multiplica el del estilo', () {
      final blend = proposeBlend(
        const VoiceDesign(locale: 'es', style: VoiceStyle.calm, pace: 1.2),
      );
      expect(blend.pace, closeTo(1.2 * 0.94, 1e-3));
    });

    test('«Otra variante» cambia las voces de la mezcla, y la misma '
        'variante da la misma', () {
      const design = VoiceDesign(locale: 'en-US', gender: VoiceGender.female);
      final first = proposeBlend(design);
      expect(proposeBlend(design), first);
      expect(proposeBlend(design.copyWith(variant: 1)), isNot(first));
    });
  });

  group('capTimbre', () {
    test('una sola voz se completa con otra del mismo género, al 80 %', () {
      final capped = capTimbre(const [BlendPart(28, 1)]);
      expect(capped.first, const BlendPart(28, maxTimbreShare));
      expect(capped, hasLength(2));
      expect(capped.last.weight, closeTo(1 - maxTimbreShare, 1e-9));
      expect(_kokoro[capped.last.speakerId]!.gender, VoiceGender.female);
    });

    test('lo que pasa del 80 % va a la otra de la mezcla', () {
      final capped = capTimbre(const [BlendPart(3, 0.9), BlendPart(2, 0.1)]);
      expect(capped, hasLength(2));
      expect(capped.first.weight, closeTo(maxTimbreShare, 1e-9));
      expect(capped.last, isA<BlendPart>());
      expect(capped.last.speakerId, 2);
      expect(capped.last.weight, closeTo(0.2, 1e-9));
    });

    test('una mezcla que ya cumple queda igual, normalizada', () {
      expect(capTimbre(const [BlendPart(3, 2), BlendPart(2, 2)]), const [
        BlendPart(3, 0.5),
        BlendPart(2, 0.5),
      ]);
    });
  });
}
