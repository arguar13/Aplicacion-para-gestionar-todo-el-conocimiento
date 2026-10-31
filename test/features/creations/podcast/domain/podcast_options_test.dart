import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/features/creations/podcast/domain/podcast_options.dart';

/// F47, paso 6: lo elegido en la hoja del podcast —el formato, la duración y
/// las voces—, guardado como dato estable.
void main() {
  group('el formato', () {
    test('la conversación tiene dos voces; los demás, una', () {
      expect(PodcastFormat.conversation.speakerCount, 2);
      expect(PodcastFormat.conversation.speakers, [
        PodcastSpeaker.a,
        PodcastSpeaker.b,
      ]);
      for (final format in [
        PodcastFormat.brief,
        PodcastFormat.lesson,
        PodcastFormat.story,
      ]) {
        expect(format.speakerCount, 1, reason: format.name);
        expect(format.speakers, [PodcastSpeaker.a]);
      }
    });

    test('se lee de las opciones; lo que no se entiende es Conversación', () {
      expect(PodcastFormat.of(const {'format': 'story'}), PodcastFormat.story);
      expect(
        PodcastFormat.of(const {'format': 'otro'}),
        PodcastFormat.conversation,
      );
      expect(PodcastFormat.of(const {}), PodcastFormat.conversation);
    });
  });

  group('la duración', () {
    test('Corto ~3 min, Medio ~8 y Largo ~15, medidos en palabras', () {
      expect(PodcastLength.short.minutes, 3);
      expect(PodcastLength.medium.minutes, 8);
      expect(PodcastLength.long.minutes, 15);
      expect(PodcastLength.short.targetWords, 3 * kPodcastWordsPerMinute);
      expect(PodcastLength.long.targetWords, 15 * kPodcastWordsPerMinute);
      expect(kPodcastWordsPerMinute, 150);
    });

    test('se lee de las opciones; lo que no se entiende es Medio', () {
      expect(PodcastLength.of(const {'length': 'long'}), PodcastLength.long);
      expect(PodcastLength.of(const {'length': 9}), PodcastLength.medium);
    });
  });

  group('las voces', () {
    test('una por persona que habla, en orden: dos en la conversación', () {
      final options = {
        'voices': [
          {'speaker': 'b', 'voiceId': 'device:es-ES:jorge'},
          {'speaker': 'a', 'voiceId': 'device:es-AR:sofia'},
        ],
      };

      expect(PodcastCast.of(options, PodcastFormat.conversation), const [
        PodcastVoiceChoice(
          speaker: PodcastSpeaker.a,
          voiceId: 'device:es-AR:sofia',
        ),
        PodcastVoiceChoice(
          speaker: PodcastSpeaker.b,
          voiceId: 'device:es-ES:jorge',
        ),
      ]);
      // La segunda voz de una conversación que pasó a Breve no cuenta.
      expect(PodcastCast.of(options, PodcastFormat.brief), const [
        PodcastVoiceChoice(
          speaker: PodcastSpeaker.a,
          voiceId: 'device:es-AR:sofia',
        ),
      ]);
    });

    test('sin elegir, la del teléfono; lo que no se entiende se ignora', () {
      final cast = PodcastCast.of(const {
        'voices': [
          'basura',
          {'speaker': 'z', 'voiceId': 'x'},
          {'speaker': 'a', 'voiceId': '  '},
        ],
      }, PodcastFormat.conversation);

      expect(cast, const [
        PodcastVoiceChoice(speaker: PodcastSpeaker.a),
        PodcastVoiceChoice(speaker: PodcastSpeaker.b),
      ]);
    });

    test('se guarda como dato: quién habla y el id de su voz', () {
      const cast = [
        PodcastVoiceChoice(
          speaker: PodcastSpeaker.a,
          voiceId: 'device:es-AR:x',
        ),
        PodcastVoiceChoice(speaker: PodcastSpeaker.b),
      ];

      final saved = PodcastCast.toOptions(cast);
      expect(saved, [
        {'speaker': 'a', 'voiceId': 'device:es-AR:x'},
        {'speaker': 'b', 'voiceId': null},
      ]);
      expect(
        PodcastCast.of({'voices': saved}, PodcastFormat.conversation),
        cast,
      );
    });

    group('se ajustan a las voces que hay', () {
      const sofia = 'device:es-AR:sofia';
      const jorge = 'device:es-ES:jorge';

      test('la conversación recibe dos voces distintas', () {
        final fitted = PodcastCast.fit(
          const [
            PodcastVoiceChoice(speaker: PodcastSpeaker.a),
            PodcastVoiceChoice(speaker: PodcastSpeaker.b),
          ],
          available: const [sofia, jorge],
        );

        expect([for (final c in fitted) c.voiceId], [sofia, jorge]);
      });

      test('a quien le falta, la que no usa la otra persona', () {
        final fitted = PodcastCast.fit(
          const [
            PodcastVoiceChoice(speaker: PodcastSpeaker.a),
            PodcastVoiceChoice(speaker: PodcastSpeaker.b, voiceId: sofia),
          ],
          available: const [sofia, jorge],
        );

        expect([for (final c in fitted) c.voiceId], [jorge, sofia]);
      });

      test('con una sola voz en el idioma, las dos la comparten', () {
        final fitted = PodcastCast.fit(
          const [
            PodcastVoiceChoice(speaker: PodcastSpeaker.a),
            PodcastVoiceChoice(speaker: PodcastSpeaker.b),
          ],
          available: const [sofia],
        );

        expect([for (final c in fitted) c.voiceId], [sofia, sofia]);
      });

      test('una del teléfono que ya no está —otro idioma, desinstalada— se '
          'suelta y se reemplaza', () {
        final fitted = PodcastCast.fit(
          const [
            PodcastVoiceChoice(
              speaker: PodcastSpeaker.a,
              voiceId: 'device:en-US:sam',
            ),
          ],
          available: const [sofia],
        );

        expect(fitted.single.voiceId, sofia);
      });

      test('una de la biblioteca de voces se deja como está', () {
        final fitted = PodcastCast.fit(
          const [
            PodcastVoiceChoice(
              speaker: PodcastSpeaker.a,
              voiceId: 'piper:ar-1',
            ),
            PodcastVoiceChoice(speaker: PodcastSpeaker.b),
          ],
          available: const [sofia],
        );

        expect([for (final c in fitted) c.voiceId], ['piper:ar-1', sofia]);
      });

      test('sin ninguna en el idioma, la del teléfono', () {
        final fitted = PodcastCast.fit(const [
          PodcastVoiceChoice(speaker: PodcastSpeaker.a, voiceId: sofia),
        ], available: const []);

        expect(fitted.single.voiceId, isNull);
      });
    });

    test('el id de una voz del teléfono dice su acento y su nombre', () {
      final id = PodcastVoiceId.device(
        locale: 'es-AR',
        name: 'es-ar-x-esd-local',
      );

      expect(id, 'device:es-AR:es-ar-x-esd-local');
      expect(PodcastVoiceId.parseDevice(id), (
        locale: 'es-AR',
        name: 'es-ar-x-esd-local',
      ));
      expect(PodcastVoiceId.parseDevice('piper:es-AR'), isNull);
      expect(PodcastVoiceId.parseDevice('device:'), isNull);
    });
  });
}
