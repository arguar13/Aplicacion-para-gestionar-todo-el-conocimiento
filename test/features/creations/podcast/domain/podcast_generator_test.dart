import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/features/creations/domain/entities/creation_material.dart';
import 'package:sinapsis/features/creations/domain/entities/creation_scope.dart';
import 'package:sinapsis/features/creations/domain/entities/study_creation.dart';
import 'package:sinapsis/features/creations/domain/entities/study_creation_kind.dart';
import 'package:sinapsis/features/creations/domain/services/creation_generator.dart';
import 'package:sinapsis/features/creations/domain/services/structured_writer.dart';
import 'package:sinapsis/features/creations/podcast/domain/podcast.dart';
import 'package:sinapsis/features/creations/podcast/domain/podcast_generator.dart';
import 'package:sinapsis/features/creations/podcast/domain/podcast_json.dart';
import 'package:sinapsis/features/creations/podcast/domain/podcast_options.dart';
import 'package:sinapsis/features/creations/podcast/domain/podcast_prompt.dart';
import 'package:sinapsis/features/transform/domain/entities/cancellation_signal.dart';

import '../../mind_map/support/fake_structured_writer.dart';

/// F47, paso 6: quien escribe el guion del podcast, con la orquestación de
/// verdad (de una vez, por partes, la corrección) y una IA de mentira que
/// devuelve guiones fijos —también cortos, de una sola voz o con citas
/// falsas—.
void main() {
  const generator = PodcastGenerator();

  CreationJob job({
    PodcastFormat format = PodcastFormat.conversation,
    PodcastLength length = PodcastLength.short,
    String? topic,
    CancellationSignal? signal,
  }) => CreationJob(
    creation: StudyCreation(
      id: 'c-1',
      kind: StudyCreationKind.podcast,
      scope: const CreationScope.document('p-exodo'),
      languageCode: 'es',
      status: CreationStatus.generating,
      createdAt: DateTime(2026, 10, 30),
      updatedAt: DateTime(2026, 10, 30),
      sourceIds: const ['p-exodo'],
      options: {
        'format': format.storageKey,
        'length': length.storageKey,
        'topic': ?topic,
      },
    ),
    cancellation: signal ?? CancellationSignal(),
  );

  const sentence = 'El mar se abre ante ellos y el pueblo cruza en seco.';

  /// Un material de [words] palabras, de un solo documento.
  CreationMaterial material({int words = 1200}) {
    final text = List.filled((words / 12).ceil(), sentence).join(' ');
    return CreationMaterial(
      mode: CreationMaterialMode.fullText,
      text: '## Éxodo\n\n$text',
      sources: [
        CreationMaterialSource(
          documentId: 'p-exodo',
          title: 'Éxodo',
          chars: text.length,
        ),
      ],
      sourceStarts: const [0],
    );
  }

  /// Un tramo de datos de 12 palabras con su cita, que está en el material.
  Map<String, Object?> data(String speaker) => {
    'speaker': speaker,
    'kind': 'data',
    'text': 'Cuenta que el mar se abre y el pueblo lo cruza tranquilo.',
    'quotes': [
      {'source': 'Éxodo', 'quote': 'el pueblo cruza en seco'},
    ],
  };

  /// Un guion de unas [words] palabras: tramos de datos de a 12, alternando
  /// la A y la B (o solo la A con [oneVoice]).
  String script(int words, {bool oneVoice = false, String title = 'El mar'}) =>
      jsonEncode({
        'title': title,
        'segments': [
          for (var i = 0; i < (words / 12).round(); i++)
            data(oneVoice || i.isEven ? 'A' : 'B'),
        ],
      });

  Future<Podcast> generate(
    FakeStructuredWriter writer, {
    CreationJob? on,
    CreationMaterial? from,
    void Function(double, CreationStep)? progress,
  }) async {
    final output = await generator.generate(
      on ?? job(),
      from ?? material(),
      writer,
      progress ?? (_, _) {},
    );
    expect(output.contentVersion, PodcastJson.contentVersion);
    return PodcastJson.decode(output.content)!;
  }

  group('de una vez', () {
    test('lo que contesta la IA, comprobado, con su título, sus voces y su '
        'duración en palabras', () async {
      final writer = FakeStructuredWriter((_, _) => script(450));

      final podcast = await generate(writer);

      expect(writer.calls, hasLength(1));
      expect(podcast.title, 'El mar');
      expect(podcast.format, PodcastFormat.conversation);
      expect(podcast.requestedWords, 450);
      expect(podcast.targetWords, 450);
      expect(podcast.words, inInclusiveRange(315, 630));
      expect(podcast.speakers, [PodcastSpeaker.a, PodcastSpeaker.b]);
      expect(podcast.discarded, isEmpty);
      expect(podcast.segments.first.citations.single.documentId, 'p-exodo');
      // Lo que se le pidió: el formato, las palabras, las citas y el idioma.
      final instruction = writer.calls.single.instruction;
      expect(instruction, contains('una conversación entre dos voces'));
      expect(instruction, contains('unas 450 palabras dichas'));
      expect(instruction, contains('entre 315 y 630'));
      expect(instruction, contains('copiadas TAL CUAL del material'));
      expect(instruction, contains('español'));
      expect(instruction, contains('"speaker": "B"'));
    });

    test(
      'lo que pidió la persona en «¿De qué trata?» va con la tarea',
      () async {
        final writer = FakeStructuredWriter((_, _) => script(450));

        await generate(writer, on: job(topic: 'el cruce del mar'));

        expect(
          writer.calls.single.instruction,
          contains('Lo que pidió la persona: «el cruce del mar»'),
        );
      },
    );

    test('un formato de una voz pide todo de la A', () async {
      final writer = FakeStructuredWriter(
        (_, _) => script(450, oneVoice: true),
      );

      final podcast = await generate(
        writer,
        on: job(format: PodcastFormat.lesson),
      );

      expect(podcast.speakers, [PodcastSpeaker.a]);
      expect(writer.calls.single.instruction, contains('una clase'));
      expect(
        writer.calls.single.instruction,
        isNot(contains('"speaker": "B"')),
      );
    });
  });

  group('la duración', () {
    test('una vuelta que se queda corta se devuelve para corregirla, con '
        'cuántas palabras le faltan', () async {
      final writer = FakeStructuredWriter(
        (_, index) => index == 0 ? script(120) : script(450),
      );

      final podcast = await generate(writer);

      expect(writer.calls, hasLength(2));
      expect(writer.calls.last.lead, contains('Quedó de 120 palabras dichas'));
      expect(writer.calls.last.lead, contains('entre 315 y 630'));
      expect(podcast.words, inInclusiveRange(315, 630));
    });

    test('una que se pasa, también', () async {
      final writer = FakeStructuredWriter(
        (_, index) => index == 0 ? script(900) : script(450),
      );

      await generate(writer);

      expect(writer.calls, hasLength(2));
      expect(writer.calls.last.lead, contains('Quedó de 900 palabras dichas'));
    });

    test('si tampoco corregida respeta la duración, no se guarda', () async {
      final writer = FakeStructuredWriter((_, _) => script(120));

      await expectLater(
        generate(writer),
        throwsA(isA<UnreadableStructuredReply>()),
      );
    });

    test('si el material no da para lo pedido, apunta a lo que da y lo '
        'anota', () async {
      // 122 palabras de material —120 y su título— dan para 183 de podcast,
      // no para 450.
      final writer = FakeStructuredWriter((_, _) => script(180));

      final podcast = await generate(writer, from: material(words: 120));

      expect(podcast.targetWords, 183);
      expect(podcast.requestedWords, 450);
      expect(podcast.shortenedByMaterial, isTrue);
      expect(writer.calls.single.instruction, contains('unas 183 palabras'));
    });

    test('las cuentas: lo que da el material y en cuántas vueltas', () {
      expect(podcastTargetWords(450, 1000), 450);
      expect(podcastTargetWords(450, 100), 150);
      expect(podcastTargetWords(450, 2), kPodcastMinWords);
      // Gemma: ~900 tokens por respuesta, unas 290 palabras por vuelta.
      final gemma = PodcastGenerator.replyTokensFor(2048);
      expect(gemma, 921);
      expect(podcastRoundsFor(PodcastLength.short.targetWords, gemma), 2);
      expect(podcastRoundsFor(PodcastLength.long.targetWords, gemma), 8);
      // Un modelo grande: un Largo entero en una vuelta.
      final big = PodcastGenerator.replyTokensFor(1000000);
      expect(big, PodcastGenerator.replyTokens);
      expect(podcastRoundsFor(PodcastLength.long.targetWords, big), 2);
      expect(podcastRoundsFor(PodcastLength.medium.targetWords, big), 1);
      expect(podcastRoundsFor(100000, 600), kPodcastMaxRounds);
      expect(podcastWordRange(300), (210, 420));
    });
  });

  group('la comprobación', () {
    test(
      'en la conversación, una sola voz se devuelve para corregirla',
      () async {
        final writer = FakeStructuredWriter(
          (_, index) => index == 0 ? script(450, oneVoice: true) : script(450),
        );

        final podcast = await generate(writer);

        expect(writer.calls, hasLength(2));
        expect(writer.calls.last.lead, contains('tienen que hablar las dos'));
        expect(podcast.speakers, hasLength(2));
      },
    );

    test('si siempre habla una sola, no se guarda', () async {
      final writer = FakeStructuredWriter(
        (_, _) => script(450, oneVoice: true),
      );

      await expectLater(
        generate(writer),
        throwsA(isA<UnreadableStructuredReply>()),
      );
    });

    test('los tramos sin cita o con citas falsas se quitan y quedan '
        'anotados, con su porqué', () async {
      final reply = jsonDecode(script(420)) as Map<String, Object?>;
      (reply['segments']! as List).insertAll(1, [
        {'speaker': 'B', 'kind': 'data', 'text': 'Eran millones de personas.'},
        {
          'speaker': 'A',
          'kind': 'data',
          'text': 'El Faraón se arrepintió enseguida.',
          'quotes': ['el Faraón se arrepintió enseguida de todo'],
        },
        {
          'speaker': 'B',
          'kind': 'data',
          'text': 'Cruzaron 600 mil personas.',
          'quotes': ['el pueblo cruza en seco'],
        },
      ]);
      final writer = FakeStructuredWriter((_, _) => jsonEncode(reply));

      final podcast = await generate(writer);

      expect(
        [for (final d in podcast.discarded) d.reason],
        [
          PodcastDiscardReason.noCitation,
          PodcastDiscardReason.quoteNotInMaterial,
          PodcastDiscardReason.numberNotInMaterial,
        ],
      );
      expect(
        podcast.segments.map((s) => s.text),
        isNot(contains('Eran millones de personas.')),
      );
    });

    test(
      'si quitar lo que no se sostiene lo deja corto, se le dice por qué',
      () async {
        final fake = jsonEncode({
          'title': 'Inventado',
          'segments': [
            for (var i = 0; i < 40; i++)
              {
                'speaker': i.isEven ? 'A' : 'B',
                'kind': 'data',
                'text': 'Algo que no está en ningún lado del texto leído.',
              },
          ],
        });
        final writer = FakeStructuredWriter(
          (_, index) => index == 0 ? fake : script(450),
        );

        await generate(writer);

        expect(writer.calls.last.lead, contains('Se quitaron 40 tramos'));
      },
    );
  });

  group('por vueltas', () {
    test('lo que no entra en una respuesta se escribe en varias: la primera '
        'abre, la última cierra y cada una sigue donde quedó', () async {
      final writer = FakeStructuredWriter(
        (_, index) => script(225, title: 'Vuelta $index'),
        contextTokens: 2048,
      );
      final steps = <double>[];

      final podcast = await generate(
        writer,
        progress: (done, _) => steps.add(done),
      );

      expect(writer.calls, hasLength(2));
      expect(podcast.title, 'Vuelta 0');
      final first = writer.calls.first.instruction;
      final last = writer.calls.last.instruction;
      expect(first, contains('la parte 1 de 2'));
      expect(first, contains('Abrí el episodio'));
      expect(last, contains('la parte 2 de 2'));
      expect(last, contains('cerrá el episodio'));
      expect(last, contains('Así terminó la parte anterior'));
      expect(last, contains('el pueblo lo cruza tranquilo'));
      // Cada vuelta pide su mitad.
      expect(first, contains('unas 225 palabras'));
      expect(podcast.words, inInclusiveRange(315, 630));
      // Entre una vuelta y la otra, la pausa del cambio de voz.
      final seam = podcast.segments[(225 / 12).round() - 1];
      expect(seam.pauseAfter, isNot(Duration.zero));
      expect(podcast.segments.last.pauseAfter, Duration.zero);
      // El avance sube parejo y llega a 1 al final.
      expect(steps.last, 1);
      for (var i = 1; i < steps.length; i++) {
        expect(steps[i], greaterThanOrEqualTo(steps[i - 1]));
      }
    });

    test('por partes, cada vuelta lee su tramo del material, en orden', () {
      final parts = CreationMaterial(
        mode: CreationMaterialMode.byParts,
        parts: [
          for (var i = 0; i < 4; i++)
            CreationMaterialPart(
              documentId: i < 2 ? 'p-exodo' : 'p-genesis',
              text: '## ${i < 2 ? 'Éxodo' : 'Génesis'}\n\nParte $i.',
              index: i,
            ),
        ],
        totalParts: 4,
        sources: const [
          CreationMaterialSource(
            documentId: 'p-exodo',
            title: 'Éxodo',
            chars: 20,
          ),
          CreationMaterialSource(
            documentId: 'p-genesis',
            title: 'Génesis',
            chars: 20,
          ),
        ],
      );

      final halves = [
        for (var r = 0; r < 2; r++) podcastRoundMaterial(parts, r, 2),
      ];
      expect(halves.first.mode, CreationMaterialMode.byParts);
      expect([for (final p in halves.first.parts) p.index], [0, 1]);
      expect([for (final p in halves.last.parts) p.index], [2, 3]);
      expect(halves.last.sourceIds, ['p-genesis']);

      // Más vueltas que partes: cada parte, de una vez, para las vueltas
      // seguidas que le tocan.
      final eighths = [
        for (var r = 0; r < 8; r++) podcastRoundMaterial(parts, r, 8),
      ];
      expect(
        [for (final m in eighths) m.text],
        [
          for (final i in [0, 0, 1, 1, 2, 2, 3, 3]) parts.parts[i].text,
        ],
      );
      expect(eighths.first.mode.isSingle, isTrue);
      expect(eighths.last.readings.single.documentId, 'p-genesis');
      // De una vez, todas leen todo.
      final whole = material();
      expect(podcastRoundMaterial(whole, 1, 3), same(whole));
    });

    test('por partes, la comprobación mira lo que leyó esa vuelta', () async {
      final parts = CreationMaterial(
        mode: CreationMaterialMode.byParts,
        parts: [
          for (var i = 0; i < 2; i++)
            CreationMaterialPart(
              documentId: 'p-exodo',
              text: '## Éxodo\n\n${List.filled(60, sentence).join(' ')}',
              index: i,
            ),
        ],
        totalParts: 2,
        sources: const [
          CreationMaterialSource(
            documentId: 'p-exodo',
            title: 'Éxodo',
            chars: 4000,
          ),
        ],
      );
      // Cada borrador, un tramo; el paso de unir, la vuelta entera.
      final writer = FakeStructuredWriter(
        (call, _) =>
            call.lead.startsWith('Borradores') ? script(450) : script(24),
      );

      final podcast = await generate(writer, from: parts);

      expect(writer.calls, hasLength(3));
      expect(podcast.words, inInclusiveRange(315, 630));
      expect(podcast.discarded, isEmpty);
    });
  });

  test('cancelada, no sigue', () async {
    final signal = CancellationSignal()..cancel();
    final writer = FakeStructuredWriter((_, _) => script(450));

    await expectLater(
      generate(writer, on: job(signal: signal)),
      throwsA(isA<CreationCancelledException>()),
    );
    expect(writer.calls, isEmpty);
  });

  test('reserva la respuesta de una vuelta y lo que ocupan sus reglas', () {
    final budget = generator.budgetFor(job(), 2048);
    expect(budget.reservedOutputTokens, 921);
    expect(budget.instructionTokens, kPodcastInstructionTokens);
    expect(generator.kind, StudyCreationKind.podcast);
  });
}
