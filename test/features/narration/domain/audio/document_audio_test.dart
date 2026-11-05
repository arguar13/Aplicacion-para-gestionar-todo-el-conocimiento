import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/features/creations/podcast/domain/podcast_audio.dart';
import 'package:sinapsis/features/narration/domain/audio/document_audio.dart';
import 'package:sinapsis/features/narration/domain/audio/speech_audio.dart';
import 'package:sinapsis/features/narration/domain/entities/narration_voice.dart';
import 'package:sinapsis/features/narration/domain/read_aloud/readable_document.dart';

const _es =
    'La república romana cayó cuando César cruzó el río con sus legiones, '
    'y el senado no pudo hacer nada para detenerlo en aquellos días.';
const _en =
    'The Roman republic fell when Caesar crossed the river with his '
    'legions, and the senate could do nothing to stop him in those days.';

ReadableSegment _seg(String key, int start, String spoken) => ReadableSegment(
  sourceKey: key,
  start: start,
  end: start + spoken.length,
  spoken: spoken,
);

const _daniela = NarrationVoice(
  name: 'piper-es_AR-daniela-high',
  locale: 'es-AR',
  engine: NarrationEngine.offline,
);
const _lessac = NarrationVoice(
  name: 'piper-en_US-lessac-medium',
  locale: 'en-US',
  engine: NarrationEngine.offline,
);

/// F47, paso 5: qué se genera para el audio de un documento, cómo se sabe si
/// el guardado sigue siendo el de ahora y cómo queda su ficha.
void main() {
  group('la voz de cada tramo', () {
    test('una sin conexión, una propia, una del teléfono y ninguna', () {
      expect(
        speechVoiceIdOf(_daniela, locale: 'es'),
        'offline:piper-es_AR-daniela-high',
      );
      expect(
        speechVoiceIdOf(
          const NarrationVoice(
            name: 'mia:v1',
            locale: 'es-AR',
            engine: NarrationEngine.cloud,
          ),
          locale: 'es',
        ),
        'mia:v1',
      );
      expect(
        speechVoiceIdOf(
          const NarrationVoice(name: 'mia:v2', locale: 'es-AR'),
          locale: 'es',
        ),
        'mia:v2',
      );
      expect(
        speechVoiceIdOf(
          const NarrationVoice(name: 'es-us-x-esd-local', locale: 'es_US'),
          locale: 'es',
        ),
        'device:es-US:es-us-x-esd-local',
      );
      expect(speechVoiceIdOf(null, locale: 'fr'), 'device:fr:');
    });
  });

  group('el plan', () {
    test('un tramo por pedazo con su voz; la pausa corta dentro de un texto, '
        'la larga al cambiar de texto y ninguna al final', () {
      final segments = [
        _seg('a', 0, 'Uno dos tres.'),
        _seg('a', 14, 'Cuatro cinco.'),
        _seg('b', 0, 'Seis siete.'),
      ];
      final plan = DocumentAudioPlan.of(segments, const [
        _daniela,
        _daniela,
        _lessac,
      ], fallbackLocale: 'es-AR');
      expect(plan.pieces, const [
        SpeechAudioPiece(
          text: 'Uno dos tres.',
          voiceId: 'offline:piper-es_AR-daniela-high',
          pauseAfter: kDocumentAudioPause,
        ),
        SpeechAudioPiece(
          text: 'Cuatro cinco.',
          voiceId: 'offline:piper-es_AR-daniela-high',
          pauseAfter: kDocumentAudioTextPause,
        ),
        SpeechAudioPiece(
          text: 'Seis siete.',
          voiceId: 'offline:piper-en_US-lessac-medium',
        ),
      ]);
      expect(plan.voices, const [_daniela, _daniela, _lessac]);
      expect(plan.isEmpty, isFalse);
    });

    test('sin voz elegida, la del teléfono del idioma del pedazo; sin idioma '
        'reconocido, la del idioma de respaldo', () {
      final plan = DocumentAudioPlan.of(
        [_seg('a', 0, _es), _seg('a', 200, _en), _seg('a', 400, '12 34')],
        const [null, null, null],
        fallbackLocale: 'it-IT',
      );
      expect(plan.pieces.map((p) => p.voiceId), [
        'device:es:',
        'device:en:',
        'device:it-IT:',
      ]);
    });

    test('un pedazo sin nada que decir no lleva tramo: empieza con el '
        'siguiente, y al final si no hay ninguno después', () {
      final segments = [
        _seg('a', 0, '  '),
        _seg('a', 3, 'Uno.'),
        _seg('a', 8, ' '),
        _seg('a', 10, 'Dos.'),
        _seg('a', 15, ''),
      ];
      final plan = DocumentAudioPlan.of(
        segments,
        List.filled(5, _daniela),
        fallbackLocale: 'es',
      );
      expect(plan.pieces.map((p) => p.text), ['Uno.', 'Dos.']);
      expect(plan.pieceOfSegment, [0, 0, 1, 1, 2]);
      const s5 = Duration(seconds: 5);
      const total = Duration(seconds: 9);
      expect(plan.segmentStarts(const [Duration.zero, s5], total), [
        Duration.zero,
        Duration.zero,
        s5,
        s5,
        total,
      ]);
      expect(
        DocumentAudioPlan.of(
          [_seg('a', 0, ' ')],
          const [null],
          fallbackLocale: 'es',
        ).isEmpty,
        isTrue,
      );
    });

    test(
      'la huella cambia con el texto, la voz o la pausa, y no sin ellos',
      () {
        final segments = [_seg('a', 0, 'Uno.'), _seg('a', 5, 'Dos.')];
        String of(List<ReadableSegment> s, List<NarrationVoice?> v) =>
            DocumentAudioPlan.of(s, v, fallbackLocale: 'es').fingerprint;
        final base = of(segments, const [_daniela, _daniela]);
        expect(of(segments, const [_daniela, _daniela]), base);
        expect(
          of(
            [_seg('a', 0, 'Uno.'), _seg('a', 5, 'Tres.')],
            const [_daniela, _daniela],
          ),
          isNot(base),
        );
        expect(of(segments, const [_daniela, _lessac]), isNot(base));
        // Otro texto entre los dos: la pausa larga.
        expect(
          of(
            [_seg('a', 0, 'Uno.'), _seg('b', 0, 'Dos.')],
            const [_daniela, _daniela],
          ),
          isNot(base),
        );
      },
    );

    test('la huella del podcast es la de siempre: los audios de antes siguen '
        'siendo suyos', () {
      const pieces = [
        SpeechAudioPiece(
          text: 'Hola.',
          voiceId: 'device:es:',
          pauseAfter: Duration(milliseconds: 300),
        ),
      ];
      final legacy = sha256
          .convert(
            utf8.encode(
              jsonEncode([
                for (final piece in pieces)
                  [piece.voiceId, piece.pauseAfter.inMilliseconds, piece.text],
              ]),
            ),
          )
          .toString()
          .substring(0, 32);
      expect(speechAudioFingerprint(pieces), legacy);
      expect(podcastAudioFingerprint(pieces), legacy);
    });
  });

  group('el estado', () {
    final segments = [_seg('a', 0, 'Uno.'), _seg('a', 5, 'Dos.')];
    final plan = DocumentAudioPlan.of(segments, const [
      _daniela,
      _daniela,
    ], fallbackLocale: 'es');
    DocumentAudio audio({String? fingerprint, int starts = 2}) => DocumentAudio(
      documentId: 'doc',
      title: 'Roma',
      fingerprint: fingerprint ?? plan.fingerprint,
      reference: 'originales/audio-documentos/x/audio.m4a',
      mimeType: 'audio/mp4',
      duration: const Duration(seconds: 3),
      starts: List.filled(starts, Duration.zero),
      voices: List.filled(starts, _daniela),
      createdAt: DateTime.utc(2026, 11, 5),
    );

    test('sin audio, ninguno; el de este texto, listo; otro, viejo', () {
      expect(
        documentAudioStatusOf(null, plan, segments),
        DocumentAudioStatus.none,
      );
      expect(
        documentAudioStatusOf(audio(), plan, segments),
        DocumentAudioStatus.ready,
      );
      expect(
        documentAudioStatusOf(audio(fingerprint: 'otra'), plan, segments),
        DocumentAudioStatus.stale,
      );
      // Lo mismo dicho, partido en otros pedazos: no se resaltaría bien.
      expect(
        documentAudioStatusOf(audio(starts: 3), plan, segments),
        DocumentAudioStatus.stale,
      );
    });
  });

  group('la ficha', () {
    final audio = DocumentAudio(
      documentId: 'processed:p1:text',
      title: 'Roma',
      fingerprint: 'f' * 32,
      reference: 'originales/audio-documentos/abc/audio-ffffffff.m4a',
      mimeType: 'audio/mp4',
      duration: const Duration(milliseconds: 12345),
      starts: const [
        Duration.zero,
        Duration(milliseconds: 1500),
        Duration(milliseconds: 6000),
      ],
      voices: const [_daniela, null, _lessac],
      createdAt: DateTime.utc(2026, 11, 5, 10, 30),
    );

    test('ida y vuelta por JSON, con su voz por pedazo', () {
      final back = DocumentAudio.fromJson(
        jsonDecode(jsonEncode(audio.toJson())),
      )!;
      expect(back.documentId, audio.documentId);
      expect(back.title, 'Roma');
      expect(back.fingerprint, audio.fingerprint);
      expect(back.reference, audio.reference);
      expect(back.mimeType, 'audio/mp4');
      expect(back.extension, 'm4a');
      expect(back.duration, audio.duration);
      expect(back.starts, audio.starts);
      expect(back.voices, const [_daniela, null, _lessac]);
      expect(back.createdAt, audio.createdAt);
      final recording = back.recordingAt('/disco/a.m4a');
      expect(recording.path, '/disco/a.m4a');
      expect(recording.starts, audio.starts);
      expect(recording.voiceAt(2), _lessac);
    });

    test('una ficha que no se entiende no es un audio', () {
      final json = audio.toJson();
      expect(DocumentAudio.fromJson(null), isNull);
      expect(DocumentAudio.fromJson('texto'), isNull);
      expect(DocumentAudio.fromJson({...json, 'version': 2}), isNull);
      expect(DocumentAudio.fromJson({...json}..remove('reference')), isNull);
      expect(DocumentAudio.fromJson({...json, 'durationMs': 'mucho'}), isNull);
      expect(
        DocumentAudio.fromJson({
          ...json,
          'voiceOf': [0],
        }),
        isNull,
      );
      expect(
        DocumentAudio.fromJson({
          ...json,
          'voices': [
            {'name': 'x', 'locale': 'es', 'engine': 'marciano'},
          ],
        }),
        isNull,
      );
      expect(DocumentAudio.fromJson({...json, 'createdAt': 'ayer'}), isNull);
      expect(
        DocumentAudio(
          documentId: 'd',
          title: 't',
          fingerprint: 'f',
          reference: 'r',
          mimeType: 'audio/wav',
          duration: Duration.zero,
          starts: const [],
          voices: const [],
          createdAt: DateTime.utc(2026),
        ).extension,
        'wav',
      );
    });
  });

  test('la clave de un documento es un nombre de carpeta estable, y el '
      'trabajo de la pieza común es «doc-» y esa clave', () {
    final key = documentAudioKeyOf('processed:p1/text');
    expect(key, matches(RegExp(r'^[0-9a-f]{24}$')));
    expect(documentAudioKeyOf('processed:p1/text'), key);
    expect(documentAudioKeyOf('processed:p2/text'), isNot(key));
    expect(documentAudioWorkKey('processed:p1/text'), 'doc-$key');
  });
}
