import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/features/creations/domain/entities/creation_material.dart';
import 'package:sinapsis/features/creations/podcast/domain/podcast.dart';
import 'package:sinapsis/features/creations/podcast/domain/podcast_check.dart';
import 'package:sinapsis/features/creations/podcast/domain/podcast_options.dart';

/// F47, paso 6: el guion se comprueba contra el material que leyó la IA —solo
/// con lo del material, con la cita de cada dato—. Lo que no se sostiene se
/// quita, con su porqué.
void main() {
  const exodo = CreationMaterialReading(
    documentId: 'p-exodo',
    title: 'Éxodo',
    text:
        '## Éxodo\n\nMoisés guía al pueblo fuera de Egipto. El mar se abre '
        'ante ellos y cruzan en seco. Caminan 40 años por el desierto, y en '
        'el año 1.200 antes de Cristo llegan al monte Sinaí.',
  );
  const genesis = CreationMaterialReading(
    documentId: 'p-genesis',
    title: 'Génesis',
    text:
        '## Génesis\n\nEn el principio Dios creó los cielos y la tierra. '
        'José es vendido por sus hermanos y llega a Egipto.',
  );

  PodcastChecker checker({
    PodcastFormat format = PodcastFormat.conversation,
    List<CreationMaterialReading> readings = const [exodo, genesis],
  }) => PodcastChecker(readings, format: format);

  PodcastDraftSegment data(
    String text, {
    String speaker = 'A',
    List<PodcastDraftQuote> quotes = const [],
    bool longPause = false,
  }) => PodcastDraftSegment(
    speaker: speaker,
    text: text,
    kind: PodcastSegmentKind.data,
    quotes: quotes,
    longPause: longPause,
  );

  group('las citas', () {
    test('una cita que está entera en el material se queda, con el documento '
        'donde está', () {
      final check = checker().check([
        data(
          'Cuenta que el mar se abrió y el pueblo pasó.',
          quotes: const [PodcastDraftQuote('El mar se abre ante ellos')],
        ),
      ]);

      expect(check.discarded, isEmpty);
      final citation = check.segments.single.citations.single;
      expect(citation.documentId, 'p-exodo');
      expect(citation.documentTitle, 'Éxodo');
      expect(citation.quote, 'El mar se abre ante ellos');
    });

    test('se compara sin mayúsculas, tildes ni signos, y con comillas '
        'alrededor', () {
      final check = checker().check([
        data(
          'José termina en Egipto.',
          quotes: const [
            PodcastDraftQuote('«jose es vendido, por sus HERMANOS»'),
          ],
        ),
      ]);

      expect(check.segments.single.citations.single.documentId, 'p-genesis');
    });

    test('un tramo de datos sin ninguna cita se quita', () {
      final check = checker().check([
        data('Moisés era un gran líder y todos lo seguían felices.'),
      ]);

      expect(check.segments, isEmpty);
      expect(check.discarded.single.reason, PodcastDiscardReason.noCitation);
      expect(
        check.discarded.single.text,
        'Moisés era un gran líder y todos lo seguían felices.',
      );
    });

    test('un tramo cuya cita no está en el material se quita', () {
      final check = checker().check([
        data(
          'Moisés habló con el Faraón doce veces.',
          quotes: const [
            PodcastDraftQuote('Moisés habló con el Faraón doce veces seguidas'),
          ],
        ),
      ]);

      expect(check.segments, isEmpty);
      expect(
        check.discarded.single.reason,
        PodcastDiscardReason.quoteNotInMaterial,
      );
    });

    test('una cita que empieza con el material y sigue inventada no '
        'cuenta: se pide entera', () {
      final check = checker().check([
        data(
          'El mar se abrió.',
          quotes: const [
            PodcastDraftQuote(
              'El mar se abre ante ellos y los egipcios aplauden',
            ),
          ],
        ),
      ]);

      expect(check.segments, isEmpty);
      expect(
        check.discarded.single.reason,
        PodcastDiscardReason.quoteNotInMaterial,
      );
    });

    test('con una elipsis, cada pedazo tiene que estar, en orden', () {
      final ok = checker().check([
        data(
          'Del mar al Sinaí.',
          quotes: const [
            PodcastDraftQuote('El mar se abre … llegan al monte Sinaí'),
          ],
        ),
      ]);
      expect(ok.segments, hasLength(1));

      final backwards = checker().check([
        data(
          'Del Sinaí al mar.',
          quotes: const [
            PodcastDraftQuote('llegan al monte Sinaí ... El mar se abre'),
          ],
        ),
      ]);
      expect(backwards.segments, isEmpty);
    });

    test('una cita de menos de cuatro palabras no prueba nada', () {
      final check = checker().check([
        data('Hablamos del mar.', quotes: const [PodcastDraftQuote('El mar')]),
      ]);

      expect(check.segments, isEmpty);
      expect(
        check.discarded.single.reason,
        PodcastDiscardReason.quoteNotInMaterial,
      );
    });

    test(
      'las citas que no están se sueltan aunque el tramo tenga una buena',
      () {
        final check = checker().check([
          data(
            'El mar se abrió y cruzaron.',
            quotes: const [
              PodcastDraftQuote('El mar se abre ante ellos'),
              PodcastDraftQuote('y los carros del Faraón se hunden'),
            ],
          ),
        ]);

        expect(check.segments.single.citations, hasLength(1));
      },
    );

    test('si la IA nombra el documento, se busca primero en él', () {
      const twin = CreationMaterialReading(
        documentId: 'p-copia',
        title: 'Copia',
        text: 'El mar se abre ante ellos y cruzan en seco.',
      );
      final check = checker(readings: const [exodo, twin]).check([
        data(
          'El mar se abrió.',
          quotes: const [
            PodcastDraftQuote('El mar se abre ante ellos', source: 'copia'),
          ],
        ),
      ]);

      expect(check.segments.single.citations.single.documentId, 'p-copia');
    });
  });

  group('las cifras', () {
    test('una cifra que no está en el material quita el tramo', () {
      final check = checker().check([
        data(
          'Caminaron 50 años por el desierto.',
          quotes: const [PodcastDraftQuote('Caminan 40 años por el desierto')],
        ),
      ]);

      expect(check.segments, isEmpty);
      expect(
        check.discarded.single.reason,
        PodcastDiscardReason.numberNotInMaterial,
      );
    });

    test('la misma cifra escrita con otro separador es la misma', () {
      final check = checker().check([
        data(
          'Llegan al Sinaí en el 1200 antes de Cristo, después de 40 años.',
          quotes: const [PodcastDraftQuote('llegan al monte Sinaí')],
        ),
      ]);

      expect(check.discarded, isEmpty);
      expect(podcastNumbersIn('1.200, 1,200 y 1200'), {'1200'});
      expect(podcastNumbersIn('en 1492.'), {'1492'});
    });
  });

  group('los enlaces', () {
    test('un saludo o una pregunta corta no necesitan cita', () {
      final check = checker().check([
        const PodcastDraftSegment(
          speaker: 'A',
          text: '¿Y qué pasó cuando llegaron al mar?',
          kind: PodcastSegmentKind.link,
        ),
      ]);

      expect(check.discarded, isEmpty);
      expect(check.segments.single.kind, PodcastSegmentKind.link);
      expect(check.segments.single.citations, isEmpty);
    });

    test('un enlace largo ya dice algo: sin cita, se quita', () {
      final long = List.filled(kPodcastMaxLinkWords + 1, 'palabra').join(' ');
      final check = checker().check([
        PodcastDraftSegment(
          speaker: 'A',
          text: long,
          kind: PodcastSegmentKind.link,
        ),
      ]);

      expect(check.segments, isEmpty);
      expect(check.discarded.single.reason, PodcastDiscardReason.noCitation);
    });

    test('un enlace con una cifra se trata como dato', () {
      final check = checker().check([
        const PodcastDraftSegment(
          speaker: 'A',
          text: 'Bienvenidos a este episodio de 8 minutos.',
          kind: PodcastSegmentKind.link,
        ),
      ]);

      expect(check.segments, isEmpty);
    });

    test('sin decir qué es, un tramo es un dato', () {
      final check = checker().check([
        const PodcastDraftSegment(speaker: 'A', text: 'Hola a todos.'),
      ]);

      expect(check.segments, isEmpty);
      expect(check.discarded.single.reason, PodcastDiscardReason.noCitation);
    });
  });

  group('quién habla', () {
    test('en la conversación, cada tramo es de la A o de la B', () {
      final check = checker().check([
        const PodcastDraftSegment(
          speaker: 'Anfitriona',
          text: '¿Qué pasa en el mar?',
          kind: PodcastSegmentKind.link,
        ),
        data(
          'Se abre, y cruzan.',
          speaker: 'invitado',
          quotes: const [PodcastDraftQuote('El mar se abre ante ellos')],
        ),
        const PodcastDraftSegment(
          speaker: 'Lucía',
          text: '¿Y después?',
          kind: PodcastSegmentKind.link,
        ),
        const PodcastDraftSegment(
          speaker: 'Tomás',
          text: 'Siguen caminando.',
          kind: PodcastSegmentKind.link,
        ),
      ]);

      expect(
        [for (final s in check.segments) s.speaker],
        [
          PodcastSpeaker.a,
          PodcastSpeaker.b,
          PodcastSpeaker.a,
          PodcastSpeaker.b,
        ],
      );
      expect(check.speakers, {PodcastSpeaker.a, PodcastSpeaker.b});
    });

    test('en los formatos de una voz, todo lo dice la A', () {
      final check = checker(format: PodcastFormat.lesson).check([
        const PodcastDraftSegment(
          speaker: 'B',
          text: '¿Qué pasó en el mar?',
          kind: PodcastSegmentKind.link,
        ),
      ]);

      expect(check.segments.single.speaker, PodcastSpeaker.a);
    });
  });

  group('los silencios', () {
    test('un respiro con la misma voz, una pausa al cambiar, la larga si se '
        'pidió y nada después del último', () {
      final check = checker().check([
        const PodcastDraftSegment(
          speaker: 'A',
          text: '¿Qué pasó?',
          kind: PodcastSegmentKind.link,
        ),
        const PodcastDraftSegment(
          speaker: 'A',
          text: '¿Lo sabés?',
          kind: PodcastSegmentKind.link,
          longPause: true,
        ),
        const PodcastDraftSegment(
          speaker: 'B',
          text: 'Te cuento.',
          kind: PodcastSegmentKind.link,
        ),
        const PodcastDraftSegment(
          speaker: 'A',
          text: 'Dale.',
          kind: PodcastSegmentKind.link,
        ),
      ]);

      expect(
        [for (final s in check.segments) s.pauseAfter],
        [kPodcastBreath, kPodcastLongPause, kPodcastTurnPause, Duration.zero],
      );
      expect(kPodcastBreath, lessThan(kPodcastTurnPause));
      expect(kPodcastTurnPause, lessThan(kPodcastLongPause));
    });

    test('al unir las vueltas, el último de cada una recibe la pausa que le '
        'toca', () {
      const a = PodcastSegment(
        speaker: PodcastSpeaker.a,
        text: 'Uno.',
        kind: PodcastSegmentKind.link,
      );
      const b = PodcastSegment(
        speaker: PodcastSpeaker.b,
        text: 'Dos.',
        kind: PodcastSegmentKind.link,
      );
      const longA = PodcastSegment(
        speaker: PodcastSpeaker.a,
        text: 'Tres.',
        kind: PodcastSegmentKind.link,
        pauseAfter: kPodcastLongPause,
      );

      final joined = joinPodcastRounds([
        [a],
        [b, longA],
        [a],
      ]);

      // La pausa larga que pidió el último de una vuelta se respeta; el
      // último de todo no espera nada.
      expect(
        [for (final s in joined) s.pauseAfter],
        [
          kPodcastTurnPause,
          kPodcastTurnPause,
          kPodcastLongPause,
          Duration.zero,
        ],
      );
    });
  });

  test('cuenta las palabras de lo que quedó', () {
    final check = checker().check([
      data(
        'El mar se abre ante todos.',
        quotes: const [PodcastDraftQuote('El mar se abre ante ellos')],
      ),
      data('Inventado del todo.'),
    ]);

    expect(check.words, 6);
    expect(countPodcastWords('  uno\ndos\t tres  '), 3);
  });
}
