import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/features/creations/podcast/domain/podcast.dart';
import 'package:sinapsis/features/creations/podcast/domain/podcast_json.dart';
import 'package:sinapsis/features/creations/podcast/domain/podcast_options.dart';

/// F47, paso 6: el JSON del podcast —lo que contesta la IA, leído con
/// tolerancia, y lo que se guarda—.
void main() {
  group('lo que contesta la IA', () {
    test('la forma pedida', () {
      final draft = PodcastJson.readDraft({
        'title': 'El mar abierto',
        'segments': [
          {'speaker': 'A', 'kind': 'link', 'text': '¿Qué pasó?'},
          {
            'speaker': 'B',
            'kind': 'data',
            'text': 'El mar se abrió.',
            'quotes': [
              {'source': 'Éxodo', 'quote': 'El mar se abre ante ellos'},
            ],
            'pause': 'long',
          },
        ],
      });

      expect(draft.title, 'El mar abierto');
      expect(draft.segments, hasLength(2));
      expect(draft.segments.first.kind, PodcastSegmentKind.link);
      final second = draft.segments.last;
      expect(second.speaker, 'B');
      expect(second.kind, PodcastSegmentKind.data);
      expect(second.longPause, isTrue);
      expect(second.quotes.single.quote, 'El mar se abre ante ellos');
      expect(second.quotes.single.source, 'Éxodo');
    });

    test('en español, con la cita como texto y la fuente en el tramo', () {
      final draft = PodcastJson.readDraft({
        'título': 'Episodio',
        'guion': [
          {
            'voz': 'Anfitriona',
            'tipo': 'dato',
            'texto': 'Cruzaron en seco.',
            'fuente': 'Éxodo',
            'citas': ['cruzan en seco', 'el mar se abre ante ellos'],
          },
          'Un tramo suelto, sin nada más.',
          {'voz': 'B', 'texto': '   '},
          42,
        ],
      });

      expect(draft.title, 'Episodio');
      expect(draft.segments, hasLength(2));
      final first = draft.segments.first;
      expect(first.speaker, 'Anfitriona');
      expect(first.kind, PodcastSegmentKind.data);
      expect([for (final q in first.quotes) q.source], ['Éxodo', 'Éxodo']);
      expect(draft.segments.last.text, 'Un tramo suelto, sin nada más.');
    });

    test('la lista sola, o un nivel de más', () {
      expect(
        PodcastJson.readDraft([
          {'speaker': 'A', 'text': 'Hola.'},
        ]).segments,
        hasLength(1),
      );
      expect(
        PodcastJson.readDraft({
          'script': {
            'segments': [
              {'speaker': 'A', 'text': 'Hola.'},
            ],
          },
        }).segments,
        hasLength(1),
      );
      expect(PodcastJson.readDraft('nada').segments, isEmpty);
      expect(PodcastJson.readDraft(null).segments, isEmpty);
    });
  });

  group('lo guardado', () {
    const podcast = Podcast(
      title: 'El mar abierto',
      format: PodcastFormat.conversation,
      length: PodcastLength.short,
      requestedWords: 450,
      targetWords: 300,
      segments: [
        PodcastSegment(
          speaker: PodcastSpeaker.a,
          text: '¿Qué pasó en el mar?',
          kind: PodcastSegmentKind.link,
          pauseAfter: kPodcastTurnPause,
        ),
        PodcastSegment(
          speaker: PodcastSpeaker.b,
          text: 'Se abrió y cruzaron.',
          kind: PodcastSegmentKind.data,
          citations: [
            PodcastCitation(
              quote: 'El mar se abre ante ellos',
              documentId: 'p-exodo',
              documentTitle: 'Éxodo',
            ),
          ],
        ),
      ],
      discarded: [
        PodcastDiscard(
          reason: PodcastDiscardReason.numberNotInMaterial,
          text: 'Eran 600.000.',
        ),
      ],
    );

    test('ida y vuelta, igual', () {
      expect(PodcastJson.decode(PodcastJson.encodeString(podcast)), podcast);
      expect(PodcastJson.decode(PodcastJson.encode(podcast)), podcast);
    });

    test('sabe cuánto dura: las palabras y los silencios', () {
      expect(podcast.words, 9);
      expect(
        podcast.estimatedDuration,
        Duration(milliseconds: (9 * 60000 / kPodcastWordsPerMinute).round()) +
            kPodcastTurnPause,
      );
      expect(podcast.shortenedByMaterial, isTrue);
      expect(podcast.speakers, [PodcastSpeaker.a, PodcastSpeaker.b]);
      expect(podcast.citations.single.documentId, 'p-exodo');
    });

    test('lo que no es un podcast con tramos da null; lo que no se entiende '
        'de un tramo se ignora', () {
      expect(PodcastJson.decode('no es JSON'), isNull);
      expect(PodcastJson.decode(const {'segments': <Object>[]}), isNull);
      final read = PodcastJson.decode(
        jsonEncode({
          'segments': [
            {
              'speaker': '?',
              'kind': '?',
              'text': 'Algo.',
              'citations': [
                {'quote': 3},
                {'quote': 'una cita'},
              ],
            },
            {'text': ''},
          ],
          'discarded': [
            {'reason': 'otra', 'text': 'x'},
          ],
        }),
      )!;
      expect(read.segments.single.speaker, PodcastSpeaker.a);
      expect(read.segments.single.kind, PodcastSegmentKind.data);
      expect(read.segments.single.citations.single.quote, 'una cita');
      expect(read.discarded, isEmpty);
      expect(read.format, PodcastFormat.conversation);
      expect(read.length, PodcastLength.medium);
    });
  });
}
