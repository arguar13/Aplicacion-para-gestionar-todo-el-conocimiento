import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:sinapsis/core/telemetry/telemetry_service.dart';
import 'package:sinapsis/features/ai_models/domain/entities/image_generation.dart';
import 'package:sinapsis/features/creations/data/services/creation_illustration_store.dart';
import 'package:sinapsis/features/creations/domain/entities/creation_material.dart';
import 'package:sinapsis/features/creations/domain/entities/creation_scope.dart';
import 'package:sinapsis/features/creations/domain/entities/study_creation.dart';
import 'package:sinapsis/features/creations/domain/entities/study_creation_kind.dart';
import 'package:sinapsis/features/creations/domain/services/creation_generator.dart';
import 'package:sinapsis/features/creations/domain/services/creation_queue.dart';
import 'package:sinapsis/features/creations/domain/services/structured_writer.dart';
import 'package:sinapsis/features/creations/flashcards/data/service_study_illustrator.dart';
import 'package:sinapsis/features/creations/flashcards/domain/deck_review.dart';
import 'package:sinapsis/features/creations/flashcards/domain/flashcard_deck.dart';
import 'package:sinapsis/features/creations/flashcards/domain/flashcard_deck_generator.dart';
import 'package:sinapsis/features/creations/flashcards/domain/flashcard_deck_prompt.dart';
import 'package:sinapsis/features/creations/flashcards/domain/item_illustrations.dart';
import 'package:sinapsis/features/creations/presentation/kinds/creation_kind_spec.dart';
import 'package:sinapsis/features/creations/presentation/kinds/default_creation_kinds.dart';
import 'package:sinapsis/features/flashcards/data/repositories/flashcard_repository_impl.dart';
import 'package:sinapsis/features/flashcards/domain/entities/study_limits.dart';
import 'package:sinapsis/features/flashcards/domain/entities/study_scope.dart';
import 'package:sinapsis/features/transform/domain/entities/cancellation_signal.dart';

import '../../../support/fake_id_generator.dart';
import '../../../support/in_memory_file_store.dart';
import '../creations_harness.dart';
import '../infographic_kind/support/infographic_kind_fakes.dart'
    show FakeIllustrationService;
import 'support/study_fakes.dart';

class _SilentTelemetry extends Mock implements TelemetryService {}

void main() {
  late CreationsHarness h;
  late FlashcardRepositoryImpl flashcards;
  late String exodo;
  late FakeModelWriter writer;
  late FakeIllustrator illustrator;
  late List<CreationQueue> queues;
  late InMemoryFileStore files;

  const limits = StudyLimits(newPerDay: 999);

  setUp(() async {
    files = InMemoryFileStore();
    h = await CreationsHarness.create(files: files);
    flashcards = FlashcardRepositoryImpl(
      database: h.processed.db,
      telemetry: _SilentTelemetry(),
      ids: FakeIdGenerator(prefix: 'tarjeta'),
      clock: () => h.processed.vault.now,
    );
    exodo = await h.processedDoc('exodo', title: 'Éxodo');
    writer = FakeModelWriter(inOrder([deckReply(3)]));
    illustrator = FakeIllustrator();
    queues = [];
  });
  tearDown(() async {
    for (final queue in queues) {
      queue.dispose();
    }
    await h.close();
  });

  DeckReview review() => DeckReview(flashcards: () => flashcards);

  CreationQueue queue({StructuredWriter? using, StudyIllustrator? drawing}) {
    final generator = FlashcardDeckGenerator(
      review: review(),
      illustrator: () => drawing ?? illustrator.asIllustrator,
    );
    final created = CreationQueue(
      repository: () => h.creations,
      scopes: () => h.scopes,
      material: () => h.material,
      generators: () => {StudyCreationKind.flashcards: generator},
      personWriter: () => using ?? writer,
      backgroundWriter: () => using ?? writer,
    );
    queues.add(created);
    return created;
  }

  Future<StudyCreation> settled(String id) async {
    for (var i = 0; i < 400; i++) {
      final creation = (await h.creations.find(id)).getRight().toNullable()!;
      if (!creation.status.isPending) return creation;
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    throw StateError('$id sigue pendiente');
  }

  Future<StudyCreation> generate(
    Map<String, Object?> options, {
    StructuredWriter? using,
    List<String>? sources,
    CreationScope? scope,
  }) async {
    final created = (await queue(using: using).create(
      CreationRequest(
        kind: StudyCreationKind.flashcards,
        scope: scope ?? CreationScope.document(exodo),
        sourceIds: sources ?? [exodo],
        options: options,
        languageCode: 'pt',
      ),
    )).getRight().toNullable()!;
    return settled(created.id);
  }

  /// Lo nuevo de hoy en el documento: lo que muestra «Para hoy».
  Future<int> dueToday(String documentId) async => (await h.study.counts(
    StudyScope.processed(CreationScope.document(documentId).storageKey),
    limits: limits,
  )).getRight().toNullable()!.newCards;

  group('el mazo', () {
    test('create → generándose → lista: con el número, la dificultad, el tema '
        'y el idioma pedidos, y el mazo guardado en su JSON', () async {
      final done = await generate({
        CreationOptionValues.count: CreationOptionValues.fewer,
        CreationOptionValues.difficulty: CreationOptionValues.hard,
        CreationOptionKeys.topic: 'La Pascua',
      });

      expect(done.status, CreationStatus.ready);
      expect(done.title, 'Éxodo en tarjetas');
      final request = writer.requests.single;
      expect(request.languageCode, 'pt');
      expect(request.task, contains('mazo de 10 tarjetas'));
      expect(request.task, contains('exigentes'));
      expect(request.task, contains('«La Pascua»'));
      // Una sola fuente: no se le pide a la IA que diga de cuál sale.
      expect(request.schema, isNot(contains('fuente')));
      expect(writer.calls.single.instruction, contains('portugués'));

      final deck = FlashcardDeckJson.decode(done.decodedContent);
      expect(deck.cards.map((c) => c.id), ['c1', 'c2', 'c3']);
      expect(deck.cards.first.front, '¿Qué pasa en el paso 1?');
      expect(deck.cards.first.hint, 'Pensá en el mar.');
      expect(deck.cards.every((c) => c.documentId == exodo), isTrue);
    });

    test(
      'una respuesta rota se corrige una vez, por el pedido de siempre',
      () async {
        writer.reply = inOrder(['no sé', deckReply(2)]);

        final done = await generate(const {});

        expect(done.status, CreationStatus.ready);
        expect(writer.calls, hasLength(2));
        expect(writer.calls.last.lead, contains('no se pudo leer'));
        expect(
          FlashcardDeckJson.decode(done.decodedContent).cards,
          hasLength(2),
        );
      },
    );

    test('sin ninguna tarjeta legible ni corregida: fallida por respuesta '
        'ilegible, sin nada en el repaso', () async {
      writer.reply = inOrder(['{"tarjetas": []}']);

      final done = await generate(const {});

      expect(done.status, CreationStatus.failed);
      expect(done.failure, CreationFailure.unreadableReply);
      expect(await dueToday(exodo), 0);
    });

    test(
      'con varias fuentes, cada tarjeta va al documento que dijo la IA',
      () async {
        final sinai = await h.processedDoc(
          'sinai',
          title: 'Sinaí',
          text: 'La ley se da en el monte. El pueblo espera abajo.',
        );
        writer.reply = inOrder([
          jsonEncode({
            'titulo': 'Dos libros',
            'tarjetas': [
              {'frente': '¿Quién guía?', 'dorso': 'Moisés.', 'fuente': 'Éxodo'},
              {'frente': '¿Dónde?', 'dorso': 'En el monte.', 'fuente': 'Sinaí'},
              {'frente': '¿Y esto?', 'dorso': 'Sin fuente.'},
            ],
          }),
        ]);

        final done = await generate(const {}, sources: [exodo, sinai]);

        expect(writer.requests.single.schema, contains('fuente'));
        final deck = FlashcardDeckJson.decode(done.decodedContent);
        expect(deck.cards.map((c) => c.documentId), [exodo, sinai, exodo]);
        expect(await dueToday(sinai), 1);
        expect(await dueToday(exodo), 2);
      },
    );

    test('lo largo va por partes —cada una con su pedido, con Gemma— y se '
        'junta en la app, repartido y sin repetir', () async {
      final libro = await h.processedDoc(
        'libro',
        title: 'Libro largo',
        text: List.filled(
          60,
          'Una oración bastante larga sobre lo que pasa en el libro.',
        ).join(' '),
      );
      var part = 0;
      final small = FakeModelWriter((call) {
        part++;
        // Las que pide cada parte, y una más que se repite en todas.
        final asked = int.parse(
          RegExp(r'mazo de (\d+)').firstMatch(call.instruction)!.group(1)!,
        );
        return jsonEncode({
          'titulo': 'Parte $part',
          'tarjetas': [
            // La misma en todas las partes: entra una sola vez.
            {'frente': '¿Repetida?', 'dorso': 'Siempre.'},
            for (var i = 0; i < asked; i++)
              {'frente': '¿Pregunta $part-$i?', 'dorso': 'Sí.'},
          ],
        });
      }, contextTokens: 2048);

      final done = await generate(
        {CreationOptionValues.count: CreationOptionValues.fewer},
        using: small,
        sources: [libro],
        scope: CreationScope.document(libro),
      );

      expect(done.status, CreationStatus.ready);
      expect(small.requests.length, greaterThan(1));
      // Cada parte, un pedido suelto de una vez: unir no le pide nada más a
      // la IA.
      expect(small.calls, hasLength(small.requests.length));
      // Cada parte pide su parte del total: diez entre todas.
      final parts = small.requests.length;
      expect(
        small.calls.first.instruction,
        contains('mazo de ${(10 / parts).ceil().clamp(2, 10)} tarjetas'),
      );
      final deck = FlashcardDeckJson.decode(done.decodedContent);
      expect(deck.cards, hasLength(10));
      expect(deck.cards.where((c) => c.front == '¿Repetida?'), hasLength(1));
      // Repartidas en el orden del material: de la primera a la última parte.
      expect(deck.cards.first.front, '¿Repetida?');
      expect(deck.cards.map((c) => c.front), contains('¿Pregunta $parts-0?'));
      // El título de un solo documento es el suyo, no el de una parte.
      expect(done.title, 'Libro largo');
    });
  });

  group('«Sumar a mi repaso»', () {
    test('prendido de fábrica: las tarjetas quedan en el documento y entran '
        'en «Para hoy», una vez cada una', () async {
      final done = await generate(const {});

      final deck = FlashcardDeckJson.decode(done.decodedContent);
      expect(deck.inReview, isTrue);
      expect(deck.cards.every((c) => c.flashcardId != null), isTrue);
      final cards = await flashcards.watchForItem(exodo).first;
      expect(cards.map((c) => c.front), [
        '¿Qué pasa en el paso 1?',
        '¿Qué pasa en el paso 2?',
        '¿Qué pasa en el paso 3?',
      ]);
      expect(cards.map((c) => c.id), deck.cards.map((c) => c.flashcardId));
      expect(await dueToday(exodo), 3);
    });

    test(
      'apagado, el mazo queda solo para hojear: nada entra en el repaso',
      () async {
        final done = await generate({DeckOptionKeys.addToReview: false});

        final deck = FlashcardDeckJson.decode(done.decodedContent);
        expect(deck.inReview, isFalse);
        expect(deck.cards.every((c) => c.flashcardId == null), isTrue);
        expect(await flashcards.watchForItem(exodo).first, isEmpty);
        expect(await dueToday(exodo), 0);
      },
    );

    test('sumar dos veces no duplica; sacar pausa sin borrar; volver a sumar '
        'las trae con su historia', () async {
      final done = await generate({DeckOptionKeys.addToReview: false});
      final deck = FlashcardDeckJson.decode(done.decodedContent);

      final once = (await review().add(
        deck,
        fallbackDocument: exodo,
      )).getRight().toNullable()!;
      final twice = (await review().add(
        once,
        fallbackDocument: exodo,
      )).getRight().toNullable()!;
      expect(twice, once);
      expect(await flashcards.watchForItem(exodo).first, hasLength(3));
      expect(await dueToday(exodo), 3);

      final out = (await review().remove(twice)).getRight().toNullable()!;
      expect(out.inReview, isFalse);
      final paused = await flashcards.watchForItem(exodo).first;
      expect(paused, hasLength(3));
      expect(paused.every((c) => c.suspended), isTrue);
      expect(await dueToday(exodo), 0);

      final back = (await review().add(
        out,
        fallbackDocument: exodo,
      )).getRight().toNullable()!;
      expect(back.inReview, isTrue);
      expect(
        back.cards.map((c) => c.flashcardId),
        out.cards.map((c) => c.flashcardId),
      );
      expect(await flashcards.watchForItem(exodo).first, hasLength(3));
      expect(await dueToday(exodo), 3);
    });

    test('una pregunta que el documento ya tiene se une a esa en vez de '
        'duplicarla; una borrada a mano se vuelve a crear', () async {
      final own = (await flashcards.create(
        itemId: exodo,
        front: 'que pasa en el paso 2',
        back: 'La mía.',
      )).getRight().toNullable()!;

      final done = await generate(const {});
      final deck = FlashcardDeckJson.decode(done.decodedContent);
      expect(deck.cards[1].flashcardId, own.id);
      expect(await flashcards.watchForItem(exodo).first, hasLength(3));

      await flashcards.delete(deck.cards[0].flashcardId!);
      final again = (await review().add(
        deck,
        fallbackDocument: exodo,
      )).getRight().toNullable()!;
      expect(again.cards[0].flashcardId, isNot(deck.cards[0].flashcardId));
      expect(await flashcards.watchForItem(exodo).first, hasLength(3));
    });

    test(
      'lo cambiado se guarda en la creación lista, sin volver a generarla',
      () async {
        final done = await generate(const {});
        final deck = FlashcardDeckJson.decode(done.decodedContent);
        final out = (await review().remove(deck)).getRight().toNullable()!;

        final saved = await h.creations.amend(
          done.id,
          content: FlashcardDeckJson.encodeString(out),
        );

        expect(saved.isRight(), isTrue);
        final stored = (await h.creations.find(
          done.id,
        )).getRight().toNullable()!;
        expect(stored.status, CreationStatus.ready);
        expect(stored.title, done.title);
        expect(
          FlashcardDeckJson.decode(stored.decodedContent).inReview,
          isFalse,
        );
      },
    );
  });

  group('«Incluir imágenes»', () {
    test('dibuja las que la IA propuso, hasta el tope, con la cuenta elegida, '
        'y las guarda dentro del mazo', () async {
      writer.reply = inOrder([deckReply(12, illustrated: true)]);

      final done = await generate({
        CreationOptionValues.images: true,
        CreationOptionValues.count: CreationOptionValues.fewer,
        CreationOptionKeys.imageAccountId: 'cuenta-2',
      });

      expect(writer.requests.single.task, contains('ilustracion'));
      expect(writer.requests.single.schema, contains('ilustracion'));
      // Propuso seis (las impares); el tope de «Menos» es cuatro.
      expect(
        illustrator.prompts,
        hasLength(
          deckIllustrationCount({
            CreationOptionValues.count: CreationOptionValues.fewer,
          }),
        ),
      );
      expect(illustrator.accounts.toSet(), {'cuenta-2'});
      final deck = FlashcardDeckJson.decode(done.decodedContent);
      expect(deck.illustrationFailure, isNull);
      expect(deck.cards.where((c) => c.illustrationRef != null), hasLength(4));
      // Guardadas con su creación, como las de la infografía: viajan en la
      // copia y en la unión de bóvedas, y se van al borrarla para siempre.
      expect(illustrator.creations.single, done.id);
      expect(
        deck.cards.first.illustrationRef,
        'originales/${done.id}/ilustraciones/c1.png',
      );
      expect(done.content, contains('"illustration_ref"'));
      expect(deck.cards.first.icon, 'history');
    });

    test('si la cuenta no puede, el mazo sale igual y dice por qué', () async {
      illustrator = FakeIllustrator(
        failure: ImageFailure.noBilling,
        failFrom: 1,
      );
      writer.reply = inOrder([deckReply(6, illustrated: true)]);

      final done = await generate({CreationOptionValues.images: true});

      expect(done.status, CreationStatus.ready);
      // La primera salió; la segunda falló y cortó las que seguían.
      expect(illustrator.prompts, hasLength(2));
      final deck = FlashcardDeckJson.decode(done.decodedContent);
      expect(deck.illustrationFailure, ImageFailure.noBilling);
      expect(deck.illustrationAccount, 'Personal');
      expect(deck.cards.where((c) => c.illustrationRef != null), hasLength(1));
      expect(deck.inReview, isTrue);
    });

    test('volver a generar libera las ilustraciones de la vez anterior, '
        'cuando el mazo nuevo ya quedó guardado', () async {
      final q = queue(
        drawing: ServiceStudyIllustrator(
          service: FakeIllustrationService.new,
          store: () => CreationIllustrationStore(files),
          textAccountId: () async => 'g',
        ).illustrate,
      );
      writer.reply = inOrder([
        deckReply(4, illustrated: true),
        deckReply(4, illustrated: true),
      ]);
      final created = (await q.create(
        CreationRequest(
          kind: StudyCreationKind.flashcards,
          scope: CreationScope.document(exodo),
          sourceIds: [exodo],
          options: const {CreationOptionValues.images: true},
        ),
      )).getRight().toNullable()!;
      final first = FlashcardDeckJson.decode(
        (await settled(created.id)).decodedContent,
      );
      final before = {for (final card in first.cards) ?card.illustrationRef};
      expect(before, hasLength(2));
      expect(files.paths.toSet(), before);

      await q.regenerate(created.id);
      final again = FlashcardDeckJson.decode(
        (await settled(created.id)).decodedContent,
      );
      final now = {for (final card in again.cards) ?card.illustrationRef};
      expect(now, hasLength(2));
      expect(now.intersection(before), isEmpty);
      expect(files.paths.toSet(), now);
      expect(files.deleted.toSet(), before);
    });

    test('sin «Incluir imágenes» no se le pide dibujar nada', () async {
      final done = await generate(const {});

      expect(writer.requests.single.task, isNot(contains('ilustracion')));
      expect(illustrator.prompts, isEmpty);
      expect(done.status, CreationStatus.ready);
    });

    test('cancelar mientras dibuja corta todo: cancelada y sin tarjetas '
        'sueltas en el repaso', () async {
      illustrator.holdAt = 0;
      writer.reply = inOrder([deckReply(4, illustrated: true)]);
      final q = queue();
      final created = (await q.create(
        CreationRequest(
          kind: StudyCreationKind.flashcards,
          scope: CreationScope.document(exodo),
          sourceIds: [exodo],
          options: const {CreationOptionValues.images: true},
        ),
      )).getRight().toNullable()!;
      while (illustrator.prompts.isEmpty) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }

      await q.cancel(created.id);
      final done = await settled(created.id);

      expect(done.status, CreationStatus.failed);
      expect(done.failure, CreationFailure.cancelled);
      expect(await flashcards.watchForItem(exodo).first, isEmpty);
    });
  });

  test('lo que se reserva en la ventana alcanza para las tarjetas que '
      'entran: todas con un modelo grande, unas pocas con Gemma', () {
    final generator = FlashcardDeckGenerator(
      review: review(),
      illustrator: () => illustrator.asIllustrator,
    );
    final job = jobWith({
      CreationOptionValues.count: CreationOptionValues.more,
    });
    final big = generator.budgetFor(job, 1000000);
    expect(big.reservedOutputTokens, 30 * kDeckTokensPerCard + 200);
    final gemma = generator.budgetFor(job, 2048);
    expect(gemma.reservedOutputTokens, lessThan(2048 ~/ 2));
    expect(gemma.inputTokens, greaterThan(0));
    expect(generator.maxOutputTokens(job), 30 * kDeckTokensPerCard + 200);
    expect(CreationMaterialMode.byParts.isSingle, isFalse);
  });
}

/// Un trabajo de [StudyCreationKind.flashcards] con [options].
CreationJob jobWith(Map<String, Object?> options) => CreationJob(
  creation: StudyCreation(
    id: 'c',
    kind: StudyCreationKind.flashcards,
    scope: const CreationScope.allProcessed(),
    languageCode: 'es',
    status: CreationStatus.generating,
    createdAt: DateTime.utc(2026, 10, 29),
    updatedAt: DateTime.utc(2026, 10, 29),
    options: options,
  ),
  cancellation: CancellationSignal(),
);
