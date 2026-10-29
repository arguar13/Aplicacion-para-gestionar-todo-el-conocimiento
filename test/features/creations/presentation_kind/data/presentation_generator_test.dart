import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:sinapsis/core/telemetry/telemetry_service.dart';
import 'package:sinapsis/features/ai_models/domain/entities/ai_provider.dart';
import 'package:sinapsis/features/ai_models/domain/entities/image_generation.dart';
import 'package:sinapsis/features/ai_models/domain/services/language_model_readiness.dart';
import 'package:sinapsis/features/creations/data/repositories/study_creation_repository_impl.dart';
import 'package:sinapsis/features/creations/domain/entities/creation_material.dart';
import 'package:sinapsis/features/creations/domain/entities/creation_scope.dart';
import 'package:sinapsis/features/creations/domain/entities/study_creation.dart';
import 'package:sinapsis/features/creations/domain/entities/study_creation_kind.dart';
import 'package:sinapsis/features/creations/domain/services/creation_generator.dart';
import 'package:sinapsis/features/creations/domain/services/creation_queue.dart';
import 'package:sinapsis/features/creations/presentation/kinds/creation_kind_spec.dart';
import 'package:sinapsis/features/creations/presentation/kinds/default_creation_kinds.dart';
import 'package:sinapsis/features/creations/presentation_deck/domain/deck_design.dart';
import 'package:sinapsis/features/creations/presentation_deck/domain/slide.dart';
import 'package:sinapsis/features/creations/presentation_deck/domain/slide_deck.dart';
import 'package:sinapsis/features/creations/presentation_deck/domain/slide_deck_schema_prompt.dart';
import 'package:sinapsis/features/creations/presentation_kind/data/creation_illustration_files.dart';
import 'package:sinapsis/features/creations/presentation_kind/data/deck_illustrator.dart';
import 'package:sinapsis/features/creations/presentation_kind/data/presentation_generator.dart';
import 'package:sinapsis/features/creations/presentation_kind/domain/presentation_content.dart';
import 'package:sinapsis/features/creations/presentation_kind/domain/presentation_options.dart';
import 'package:sinapsis/features/transform/domain/entities/cancellation_signal.dart';

import '../../../../support/fake_id_generator.dart';
import '../../../../support/in_memory_file_store.dart';
import '../../creations_harness.dart';
import '../support/presentation_fakes.dart';

class _SilentTelemetry extends Mock implements TelemetryService {}

/// Generar una Presentación (F43, paso 11): con la cola de verdad, el
/// material de verdad, un modelo de mentira que contesta el JSON y una IA de
/// imágenes de mentira.
void main() {
  late CreationsHarness h;
  late InMemoryFileStore store;
  late StudyCreationRepositoryImpl creations;
  late FakeDeckWriter writer;
  late FakeIllustrations images;
  late PresentationGenerator generator;
  late List<CreationQueue> queues;
  late String exodo;

  const ready = LanguageModelReady(provider: AiProvider.gemini);

  CreationQueue newQueue() {
    final queue = CreationQueue(
      repository: () => creations,
      scopes: () => h.scopes,
      material: () => h.material,
      generators: () => {StudyCreationKind.presentation: generator},
      personWriter: () => writer,
      backgroundWriter: () => writer,
      readiness: () =>
          ({bool background = false}) async => ready,
      modelName: () => 'Gemini 3.8 Flash',
    );
    queues.add(queue);
    return queue;
  }

  setUp(() async {
    h = await CreationsHarness.create();
    exodo = await h.processedDoc(
      'exodo',
      title: 'Éxodo',
      text:
          'Moisés guía al pueblo fuera de Egipto. El mar se abre. Cuarenta '
          'años en el desierto. En el Sinaí se sella la alianza.',
    );
    store = InMemoryFileStore();
    creations = StudyCreationRepositoryImpl(
      database: h.processed.db,
      telemetry: _SilentTelemetry(),
      ids: FakeIdGenerator(prefix: 'pres'),
      clock: () => h.processed.vault.now,
      files: store,
    );
    writer = FakeDeckWriter(reply: (_) => deckJson(template: 'aurora'));
    images = FakeIllustrations();
    final files = CreationIllustrationFiles(store);
    generator = PresentationGenerator(
      illustrator: () =>
          DeckIllustrator(service: images, files: files, wait: (_) async {}),
      files: () => files,
    );
    queues = [];
  });
  tearDown(() async {
    for (final queue in queues) {
      queue.dispose();
    }
    await h.close();
  });

  CreationRequest request(Map<String, Object?> options) => CreationRequest(
    kind: StudyCreationKind.presentation,
    scope: CreationScope.document(exodo),
    sourceIds: [exodo],
    options: options,
  );

  Future<StudyCreation> stored(String id) async =>
      (await creations.find(id)).getRight().toNullable()!;

  Future<StudyCreation> settled(String id) async {
    for (var i = 0; i < 400; i++) {
      final creation = await stored(id);
      if (!creation.status.isPending) return creation;
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    throw StateError('$id sigue pendiente');
  }

  Future<void> until(bool Function() condition) async {
    for (var i = 0; i < 400; i++) {
      if (condition()) return;
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    throw StateError('no pasó');
  }

  const withIllustrations = {
    CreationOptionValues.format: CreationOptionValues.presenter,
    CreationOptionValues.template: CreationOptionValues.auto,
    CreationOptionValues.illustrations: true,
    PresentationOptionKeys.illustrationStyle: 'watercolor',
    CreationOptionKeys.description: 'para quien empieza',
    CreationOptionKeys.imageAccountId: 'w',
  };

  group('con la cola de verdad', () {
    test(
      'en la cola, generándose, lista: el mazo con su portada y su cierre, '
      'la plantilla que sugirió la IA y las ilustraciones guardadas',
      () async {
        final queue = newQueue();
        final created = (await queue.create(
          request(withIllustrations),
        )).getRight().toNullable()!;
        expect(created.status, CreationStatus.queued);

        final done = await settled(created.id);
        expect(done.status, CreationStatus.ready, reason: '${done.failure}');
        expect(done.title, 'Éxodo: liberación y alianza');
        expect(done.modelName, 'Gemini 3.8 Flash');

        // Lo que se le pidió a la IA.
        final asked = writer.requests.single;
        expect(asked.schema, slideDeckJsonSchemaPrompt);
        expect(asked.guidance, 'para quien empieza');
        expect(asked.languageCode, 'es');
        expect(asked.task, contains('unas 14 diapositivas'));
        expect(asked.task, contains('"template"'));
        expect(writer.calls.single.instruction, contains('para quien empieza'));
        expect(writer.calls.single.prompt, contains('Moisés guía al pueblo'));

        final content = PresentationContent.decode(done.content);
        final deck = content.deck;
        expect(deck.format, DeckFormat.presenter);
        expect(deck.slides.first, isA<CoverSlide>());
        expect(deck.slides.last, isA<ClosingSlide>());
        expect(deck.slides[1].speakerNotes, 'Primero, por qué importa.');
        expect(content.templateHint, DeckTemplateId.aurora);
        expect(content.misses, isEmpty);
        expect(content.illustrationAccount, 'Trabajo');

        // Las tres que lo pidieron, con la cuenta y el estilo elegidos: la
        // portada primero, después «imagen con texto».
        expect(images.requests.map((r) => r.prompt), [
          'El mar abierto al amanecer',
          'Una montaña con nubes',
          'Un desierto con huellas',
        ]);
        expect(images.requests.every((r) => r.account?.id == 'w'), isTrue);
        expect(images.requests.first.styleHint, contains('watercolor'));
        expect(content.files, hasLength(3));
        expect(store.paths.toSet(), content.files);
        for (final path in content.files) {
          expect(
            CreationIllustrationFiles.isOwnedBy(created.id, path),
            isTrue,
            reason: path,
          );
        }
      },
    );

    test('si una ilustración no sale, la presentación queda lista igual, '
        'con el porqué de las que faltan', () async {
      images.outcomes.addAll([drawn(), failed(ImageFailure.noBilling)]);
      final queue = newQueue();
      final created = (await queue.create(
        request(withIllustrations),
      )).getRight().toNullable()!;

      final done = await settled(created.id);
      expect(done.status, CreationStatus.ready);
      final content = PresentationContent.decode(done.content);
      expect(content.files, hasLength(1));
      expect(content.misses.map((m) => m.failure), [
        ImageFailure.noBilling,
        ImageFailure.noBilling,
      ]);
      expect(content.missing, hasLength(2));
      expect(images.requests, hasLength(2));
    });

    test('sin ilustraciones no se le pide nada a la IA de imágenes; lo que '
        'pidió la IA queda para completarlas después', () async {
      final queue = newQueue();
      final created = (await queue.create(
        request(const {CreationOptionValues.illustrations: false}),
      )).getRight().toNullable()!;
      final done = await settled(created.id);
      expect(done.status, CreationStatus.ready);
      expect(images.requests, isEmpty);
      final content = PresentationContent.decode(done.content);
      expect(content.missing, hasLength(3));
      expect(content.misses, isEmpty);
      expect(store.paths, isEmpty);
    });

    test(
      'cancelar mientras dibuja la deja cancelada y no deja archivos',
      () async {
        images.hold = Completer<void>();
        images.outcomes.add(drawn());
        final queue = newQueue();
        final created = (await queue.create(
          request(withIllustrations),
        )).getRight().toNullable()!;
        await until(() => images.requests.isNotEmpty);
        await queue.cancel(created.id);

        final done = await settled(created.id);
        expect(done.status, CreationStatus.failed);
        expect(done.failure, CreationFailure.cancelled);
        await Future<void>.delayed(const Duration(milliseconds: 10));
        expect(store.paths, isEmpty);
      },
    );

    test('cancelar mientras escribe corta el pedido', () async {
      writer.hold = Completer<void>();
      final queue = newQueue();
      final created = (await queue.create(
        request(withIllustrations),
      )).getRight().toNullable()!;
      await until(() => writer.calls.isNotEmpty);
      await queue.cancel(created.id);
      writer.hold!.complete();

      final done = await settled(created.id);
      expect(done.failure, CreationFailure.cancelled);
      expect(images.requests, isEmpty);
    });

    test('lo que no se puede leer se le pide corregir una vez, y si tampoco, '
        'queda fallida por eso', () async {
      writer.reply = (_) => 'Acá tenés tu presentación, ¡espero que sirva!';
      final queue = newQueue();
      final created = (await queue.create(
        request(const {}),
      )).getRight().toNullable()!;
      final done = await settled(created.id);
      expect(done.failure, CreationFailure.unreadableReply);
      expect(writer.calls, hasLength(2));
      expect(writer.calls.last.lead, contains('no se pudo leer'));
    });

    test('lo largo va por partes: cada parte da sus diapositivas y el último '
        'paso arma el relato, de la portada al cierre', () async {
      // Una ventana mínima: el material no entra de una vez.
      writer
        ..contextTokens = 2600
        ..reply = (call) => call.lead.startsWith('Parte')
            ? {
                'slides': [
                  {
                    'layout': 'bullets',
                    'title': 'Lo de esta parte',
                    'bullets': ['Una idea'],
                  },
                ],
              }
            : deckJson(cover: false);
      final long = await h.processedDoc(
        'largo',
        title: 'Largo',
        text: List.filled(
          60,
          'Moisés guía al pueblo por el desierto.',
        ).join(' '),
      );
      final queue = newQueue();
      final created = (await queue.create(
        CreationRequest(
          kind: StudyCreationKind.presentation,
          scope: CreationScope.document(long),
          sourceIds: [long],
        ),
      )).getRight().toNullable()!;
      final done = await settled(created.id);
      expect(done.status, CreationStatus.ready, reason: '${done.failure}');

      final parts = writer.calls.where((c) => c.lead.startsWith('Parte'));
      expect(parts.length, greaterThan(1));
      expect(parts.first.instruction, contains('sin portada ni cierre'));
      final merge = writer.calls.last;
      expect(merge.lead, contains('Borradores parciales'));
      expect(merge.instruction, contains('unir en una sola presentación'));
      // La IA no puso portada al unir: se arma con el título.
      final deck = PresentationContent.decode(done.content).deck;
      expect(deck.slides.first, isA<CoverSlide>());
      expect(deck.slides.first.headline, deck.title);
      expect(deck.slides.last, isA<ClosingSlide>());
    });

    test(
      '«Volver a generar» se lleva las ilustraciones de la vez anterior',
      () async {
        final queue = newQueue();
        final created = (await queue.create(
          request(withIllustrations),
        )).getRight().toNullable()!;
        final first = await settled(created.id);
        final before = PresentationContent.decode(first.content).files;
        expect(before, hasLength(3));

        await queue.regenerate(
          created.id,
          options: const {CreationOptionValues.illustrations: false},
        );
        final again = await settled(created.id);
        expect(again.status, CreationStatus.ready);
        await Future<void>.delayed(const Duration(milliseconds: 10));
        expect(store.deleted.toSet(), before);
        expect(store.paths, isEmpty);
      },
    );
  });

  group('el generador solo', () {
    CreationJob job(Map<String, Object?> options, {String? content}) =>
        CreationJob(
          creation: StudyCreation(
            id: 'c1',
            kind: StudyCreationKind.presentation,
            scope: const CreationScope.allProcessed(),
            languageCode: 'en',
            status: CreationStatus.generating,
            createdAt: DateTime(2026, 10, 29),
            updatedAt: DateTime(2026, 10, 29),
            options: options,
            content: content,
          ),
          cancellation: CancellationSignal(),
        );

    const material = CreationMaterial(
      mode: CreationMaterialMode.fullText,
      text: 'Moisés guía al pueblo.',
      sources: [
        CreationMaterialSource(documentId: 'd', title: 'Éxodo', chars: 22),
      ],
    );

    test('el avance va de la escritura (hasta 0,7) a cada ilustración, sin '
        'volver atrás', () async {
      final progress = <(double, CreationStep)>[];
      await generator.generate(
        job(withIllustrations),
        material,
        writer,
        (value, step) => progress.add((value, step)),
      );
      final values = [for (final (v, _) in progress) v];
      for (var i = 1; i < values.length; i++) {
        expect(values[i], greaterThanOrEqualTo(values[i - 1]));
      }
      final writing = progress.where((p) => p.$2 == CreationStep.writing);
      expect(writing.map((p) => p.$1), everyElement(lessThanOrEqualTo(0.7)));
      final drawing = progress.where((p) => p.$2 == CreationStep.illustrating);
      expect(drawing.first.$1, closeTo(0.7, 0.001));
      expect(drawing.last.$1, 1);
      expect(writer.requests.single.languageCode, 'en');
    });

    test('dibuja como mucho las que se avisaron: siete en una estándar y '
        'cuatro en una corta', () async {
      writer.reply = (_) => {
        'title': 'Muchas',
        'slides': [
          for (var i = 0; i < 10; i++)
            {
              'layout': i == 0 ? 'cover' : 'image_text',
              'title': 'D$i',
              'body': 'Texto $i',
              'illustration_prompt': 'Imagen $i',
            },
        ],
      };
      await generator.generate(
        job(const {CreationOptionValues.illustrations: true}),
        material,
        writer,
        (_, _) {},
      );
      expect(images.requests, hasLength(7));
      images.requests.clear();
      await generator.generate(
        job(const {
          CreationOptionValues.illustrations: true,
          CreationOptionValues.length: CreationOptionValues.short,
        }),
        material,
        writer,
        (_, _) {},
      );
      expect(images.requests, hasLength(4));
      expect(images.requests.first.prompt, 'Imagen 0');
    });

    test('la plantilla elegida pone el estilo de las ilustraciones, y no se '
        'le pide a la IA que elija', () async {
      await generator.generate(
        job(const {
          CreationOptionValues.illustrations: true,
          CreationOptionValues.template: 'chalkboard',
        }),
        material,
        writer,
        (_, _) {},
      );
      expect(writer.requests.single.task, isNot(contains('"template"')));
      expect(images.requests.first.styleHint, contains('chalk'));
    });

    test('lee lo que contestó: la plantilla escrita de cualquier modo, y sin '
        'diapositivas suficientes pide corregirlo', () {
      final read = PresentationGenerator.readWrittenDeck({
        ...deckJson(),
        'template': null,
        'plantilla': 'Paper-Cut',
      }, minSlides: 3);
      expect(read.template, DeckTemplateId.paperCut);
      expect(read.deck.slides, hasLength(5));
      expect(
        () => PresentationGenerator.readWrittenDeck({
          'slides': [
            {
              'layout': 'bullets',
              'title': 'Sola',
              'bullets': ['x'],
            },
          ],
        }, minSlides: 3),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains('al menos 3'),
          ),
        ),
      );
      expect(
        () => PresentationGenerator.readWrittenDeck('nada', minSlides: 1),
        throwsFormatException,
      );
    });

    test('el mazo como se guarda: con su portada y el formato elegido', () {
      final deck = PresentationGenerator.finishDeck(
        const SlideDeck(
          title: 'Éxodo',
          subtitle: 'Bajada',
          slides: [
            Slide.bullets(title: 'Ideas', bullets: ['x']),
          ],
        ),
        format: DeckFormat.presenter,
      );
      expect(deck.format, DeckFormat.presenter);
      expect(
        deck.slides.first,
        const Slide.cover(title: 'Éxodo', subtitle: 'Bajada'),
      );
      expect(deck.slides, hasLength(2));
    });

    test('reserva lugar para su esquema y su respuesta', () {
      final budget = generator.budgetFor(job(const {}), 32000);
      expect(budget.instructionTokens, PresentationGenerator.instructionTokens);
      expect(generator.maxOutputTokens(job(const {})), 14 * 225 * 3 ~/ 2);
      expect(
        generator.maxOutputTokens(
          job(const {CreationOptionValues.length: CreationOptionValues.short}),
        ),
        2700,
      );
    });
  });
}
