import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/features/ai_models/domain/entities/image_capability.dart';
import 'package:sinapsis/features/ai_models/domain/entities/image_generation.dart';
import 'package:sinapsis/features/creations/data/services/creation_illustration_store.dart';
import 'package:sinapsis/features/creations/domain/entities/creation_material.dart';
import 'package:sinapsis/features/creations/domain/entities/creation_scope.dart';
import 'package:sinapsis/features/creations/domain/entities/study_creation.dart';
import 'package:sinapsis/features/creations/domain/entities/study_creation_kind.dart';
import 'package:sinapsis/features/creations/domain/services/creation_generator.dart';
import 'package:sinapsis/features/creations/domain/services/creation_queue.dart';
import 'package:sinapsis/features/creations/infographic/domain/infographic.dart';
import 'package:sinapsis/features/creations/infographic/domain/infographic_design.dart';
import 'package:sinapsis/features/creations/infographic/domain/infographic_json.dart';
import 'package:sinapsis/features/creations/infographic/presentation/styles/infographic_styles.dart';
import 'package:sinapsis/features/creations/infographic_kind/data/infographic_generator.dart';
import 'package:sinapsis/features/creations/infographic_kind/data/infographic_illustrator.dart';
import 'package:sinapsis/features/creations/infographic_kind/domain/infographic_content.dart';
import 'package:sinapsis/features/creations/infographic_kind/domain/infographic_illustration_plan.dart';
import 'package:sinapsis/features/creations/infographic_kind/domain/infographic_options.dart';
import 'package:sinapsis/features/creations/presentation/kinds/creation_kind_spec.dart';
import 'package:sinapsis/features/creations/presentation/kinds/default_creation_kinds.dart';
import 'package:sinapsis/features/transform/domain/entities/cancellation_signal.dart';

import '../../../../support/in_memory_file_store.dart';
import '../../creations_harness.dart';
import '../support/infographic_kind_fakes.dart';

/// Generar una infografía (F43, paso 12) por la cola de verdad, con un
/// modelo y un servicio de ilustraciones de mentira: la lámina que escribe la
/// IA, sus ilustraciones —las que salen, las que no y por qué—, cancelar,
/// volver a generar y lo largo por partes.
void main() {
  late CreationsHarness h;
  late String exodo;
  late InMemoryFileStore files;
  late FakeIllustrationService images;
  late ScriptedWriter writer;
  late List<CreationQueue> queues;
  late String? textAccount;

  InfographicGenerator generator() {
    final store = CreationIllustrationStore(files);
    return InfographicGenerator(
      illustrator: InfographicIllustrator(
        service: () => images,
        store: () => store,
        textAccountId: () async => textAccount,
      ),
      store: () => store,
    );
  }

  CreationQueue queue() {
    final queue = CreationQueue(
      repository: () => h.creations,
      scopes: () => h.scopes,
      material: () => h.material,
      generators: () => {StudyCreationKind.infographic: generator()},
      personWriter: () => writer,
      backgroundWriter: () => writer,
    );
    queues.add(queue);
    return queue;
  }

  setUp(() async {
    h = await CreationsHarness.create();
    exodo = await h.processedDoc('exodo', title: 'Éxodo');
    files = InMemoryFileStore();
    images = FakeIllustrationService();
    writer = ScriptedWriter(reply: (_) => sampleReply());
    queues = [];
    textAccount = 'g';
  });
  tearDown(() async {
    for (final queue in queues) {
      queue.dispose();
    }
    await h.close();
  });

  Map<String, Object?> options({
    String style = 'clay',
    bool illustrations = true,
    String detail = 'standard',
    String orientation = 'portrait',
    String? account,
  }) => {
    InfographicOptionKeys.style: style,
    CreationOptionValues.illustrations: illustrations,
    CreationOptionValues.detail: detail,
    CreationOptionValues.orientation: orientation,
    CreationOptionKeys.description: 'la línea de los hechos',
    CreationOptionKeys.imageAccountId: ?account,
  };

  Future<StudyCreation> settled(String id) async {
    for (var i = 0; i < 400; i++) {
      final creation = (await h.creations.find(id)).getRight().toNullable()!;
      if (!creation.status.isPending) return creation;
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    throw StateError('$id sigue pendiente');
  }

  Future<String> create(CreationQueue queue, Map<String, Object?> o) async =>
      (await queue.create(
        CreationRequest(
          kind: StudyCreationKind.infographic,
          scope: CreationScope.document(exodo),
          sourceIds: [exodo],
          options: o,
        ),
      )).getRight().toNullable()!.id;

  group('lista, con sus ilustraciones', () {
    test('escribe la lámina con lo pedido y dibuja la cabecera y cada bloque '
        'del estilo ilustrado, con la cuenta que escribe', () async {
      final q = queue();
      final id = await create(q, options());
      final done = await settled(id);

      expect(done.status, CreationStatus.ready);
      expect(done.title, 'Éxodo: liberación y alianza');
      expect(done.contentVersion, InfographicContent.version);

      // Lo que se le pidió a la IA: el esquema con el detalle, el idioma, la
      // descripción de la persona y cuántas ilustraciones describir.
      final request = writer.requests.single;
      expect(request.schema, contains('Detalle "estándar"'));
      expect(request.guidance, 'la línea de los hechos');
      expect(request.languageCode, 'es');
      expect(request.task, contains('en la cabecera y en cada bloque'));
      expect(request.maxOutputTokens, infographicOutputTokens(options()));
      expect(writer.calls.single.instruction, contains('español'));

      final content = InfographicContent.decode(done.content);
      final slots = InfographicIllustrationPlan.slotsFor(
        content.sheet,
        const InfographicDesign(style: InfographicStyleId.clay),
      );
      expect(slots, hasLength(5));
      expect(images.calls, hasLength(5));
      expect(content.failures, isEmpty);
      expect(content.accountLabel, 'Personal');
      for (final slot in slots) {
        final reference = InfographicIllustrationPlan.referenceOf(
          content.sheet,
          slot.id,
        );
        expect(reference, startsWith('originales/$id/ilustraciones/'));
        expect(files.paths, contains(reference));
      }
      // El estilo del dibujo, la forma y la cuenta.
      final clay = InfographicStyles.of(InfographicStyleId.clay);
      expect(images.calls.first.styleHint, clay.illustrationHint);
      expect(images.calls.first.aspect, IllustrationAspect.square);
      expect(images.calls.first.prompt, 'El mar abierto al amanecer');
      expect(images.calls.every((c) => c.account?.id == 'g'), isTrue);
    });

    test('la cuenta elegida en el aviso es la que dibuja', () async {
      images = FakeIllustrationService(accounts: [geminiAccount, workAccount]);
      final id = await create(queue(), options(account: 'w'));
      await settled(id);
      expect(images.calls, isNotEmpty);
      expect(images.calls.every((c) => c.account?.id == 'w'), isTrue);
    });

    test('nunca dibuja más que lo estimado, aunque la IA pida más', () async {
      // Seis ideas, todas con su ilustración pedida, en un estilo dibujado
      // que estima tres: se dibujan las tres que más pesan.
      writer = ScriptedWriter(
        reply: (_) => InfographicJson.encodeString(
          Infographic(
            title: 'Seis ideas',
            blocks: [
              for (var i = 0; i < 6; i++)
                InfographicBlock.fact(
                  title: 'Idea $i',
                  illustrationPrompt: 'Escena $i',
                  level: i < 3
                      ? InfographicLevel.supporting
                      : InfographicLevel.essential,
                ),
            ],
          ),
        ),
      );
      final o = options(style: 'editorial');
      final id = await create(queue(), o);
      final done = await settled(id);
      expect(done.status, CreationStatus.ready);
      expect(infographicIllustrationsFor(o), 3);
      expect(images.calls.map((c) => c.prompt), [
        'Escena 3',
        'Escena 4',
        'Escena 5',
      ]);
    });

    test('con un estilo dibujado, solo los bloques que la pidieron', () async {
      final id = await create(queue(), options(style: 'editorial'));
      final done = await settled(id);
      expect(images.calls, hasLength(1));
      expect(images.calls.single.prompt, 'Una zarza en llamas');
      expect(
        images.calls.single.styleHint,
        illustrationStyleHint(InfographicStyleId.editorial),
      );
      expect(writer.requests.single.task, contains('solo en los 3 bloques'));
      expect(
        InfographicContent.decode(done.content).sheet.blocks[1].illustrationRef,
        isNotNull,
      );
    });

    test(
      'sin «Ilustraciones con IA» no se le pide nada al de imágenes',
      () async {
        final id = await create(queue(), options(illustrations: false));
        final done = await settled(id);
        expect(done.status, CreationStatus.ready);
        expect(images.calls, isEmpty);
        expect(files.paths, isEmpty);
        expect(
          writer.requests.single.task,
          contains('No escribas "illustration_prompt"'),
        );
      },
    );
  });

  group('lo que no sale no hace fallar la lámina', () {
    test('una que falla por un momento se anota y se sigue; una de la cuenta '
        'corta las que faltan, con su porqué', () async {
      images.script.addAll([
        null,
        ImageFailure.rateLimited,
        null,
        ImageFailure.noBilling,
      ]);
      final id = await create(queue(), options());
      final done = await settled(id);

      expect(done.status, CreationStatus.ready);
      // La quinta ya no se pide: fallaría igual.
      expect(images.calls, hasLength(4));
      final content = InfographicContent.decode(done.content);
      expect(content.failures, {
        'block-1': ImageFailure.rateLimited,
        'block-4': ImageFailure.noBilling,
        'block-5': ImageFailure.noBilling,
      });
      expect(content.sheet.illustrationRef, isNotNull);
      expect(content.sheet.blocks[2].illustrationRef, isNotNull);
      expect(content.sheet.blocks[1].illustrationRef, isNull);
      expect(files.paths, hasLength(2));
    });

    test('sin una cuenta que dibuje (Gemma o Claude escriben), no se pide '
        'nada y se dice por qué', () async {
      textAccount = null;
      final id = await create(queue(), options());
      final done = await settled(id);
      expect(done.status, CreationStatus.ready);
      expect(images.calls, isEmpty);
      final content = InfographicContent.decode(done.content);
      expect(content.failures.values.toSet(), {ImageFailure.noAccount});
      expect(content.failures, hasLength(5));
    });

    test(
      'una cuenta que ya se sabe que no puede no se prueba otra vez',
      () async {
        images.capability = const ImageCapability(
          state: ImageCapabilityState.cannot,
          reason: ImageFailure.orgUnverified,
        );
        final id = await create(queue(), options());
        final done = await settled(id);
        expect(images.calls, isEmpty);
        expect(
          InfographicContent.decode(done.content).failures.values.toSet(),
          {ImageFailure.orgUnverified},
        );
      },
    );
  });

  group('cancelar y volver a generar', () {
    test('cancelar a mitad de las ilustraciones la deja cancelada y borra lo '
        'que se dibujó', () async {
      final hold = Completer<void>();
      images.script.addAll([null, hold]);
      final q = queue();
      final id = await create(q, options());
      for (var i = 0; i < 400 && images.calls.length < 2; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      expect(images.calls, hasLength(2));
      expect(files.paths, hasLength(1));

      await q.cancel(id);
      final done = await settled(id);
      expect(done.status, CreationStatus.failed);
      expect(done.failure, CreationFailure.cancelled);
      expect(files.paths, isEmpty);
      expect(images.calls.last.cancel?.isCancelled, isTrue);
      hold.complete();
    });

    test(
      'volver a generar borra las ilustraciones que la nueva ya no usa',
      () async {
        final q = queue();
        final id = await create(q, options());
        await settled(id);
        final first = files.paths.toSet();
        expect(first, hasLength(5));

        await q.regenerate(id, options: options(style: 'editorial'));
        final done = await settled(id);
        expect(done.status, CreationStatus.ready);
        final now = files.paths.toSet();
        expect(now, hasLength(1));
        expect(now.intersection(first), isEmpty);
        expect(
          InfographicIllustrationPlan.references(
            InfographicContent.decode(done.content).sheet,
          ),
          now,
        );
      },
    );
  });

  group('el avance', () {
    test('el texto hasta el 70 % y cada ilustración su parte, en «Dibujando '
        'las ilustraciones»', () async {
      final creation = StudyCreation(
        id: 'c1',
        kind: StudyCreationKind.infographic,
        scope: const CreationScope.allProcessed(),
        sourceIds: const ['exodo'],
        options: options(),
        languageCode: 'es',
        status: CreationStatus.generating,
        runNow: true,
        attempts: 1,
        createdAt: DateTime.utc(2026, 10, 29),
        updatedAt: DateTime.utc(2026, 10, 29),
      );
      final steps = <(double, CreationStep)>[];
      await generator().generate(
        CreationJob(creation: creation, cancellation: CancellationSignal()),
        const CreationMaterial(
          mode: CreationMaterialMode.fullText,
          text: 'Moisés guía al pueblo.',
          sources: [
            CreationMaterialSource(
              documentId: 'exodo',
              title: 'Éxodo',
              chars: 22,
            ),
          ],
        ),
        writer,
        (progress, step) => steps.add((progress, step)),
      );
      expect(steps.first, (0.0, CreationStep.writing));
      expect(steps, contains((0.7, CreationStep.writing)));
      final drawing = [
        for (final (p, s) in steps)
          if (s == CreationStep.illustrating) p,
      ];
      expect(
        drawing,
        [0.7, 0.76, 0.82, 0.88, 0.94, 1.0].map((v) => closeTo(v, 1e-9)),
      );
      expect(steps.last, (1.0, CreationStep.finishing));
    });
  });

  test('lo largo va por partes: cada parte da sus bloques y el último paso '
      'elige entre todos', () async {
    final long = await h.processedDoc(
      'largo',
      title: 'Largo',
      text: List.filled(
        40,
        'Moisés guía al pueblo por el desierto durante muchos años.',
      ).join(' '),
    );
    writer = ScriptedWriter(
      // Una ventana chica: el material no entra de una vez.
      contextTokens: 1800 + 1100 + 180,
      reply: (_) => sampleReply(),
    );
    final q = queue();
    final id = (await q.create(
      CreationRequest(
        kind: StudyCreationKind.infographic,
        scope: CreationScope.document(long),
        sourceIds: [long],
        options: options(illustrations: false, detail: 'concise'),
      ),
    )).getRight().toNullable()!.id;
    final done = await settled(id);

    expect(done.status, CreationStatus.ready, reason: '${done.failureDetail}');
    final leads = writer.calls.map((c) => c.lead).toList();
    expect(leads.where((l) => l.startsWith('Parte ')).length, greaterThan(1));
    expect(leads.last, startsWith('Borradores parciales'));
    expect(
      writer.calls.first.instruction,
      contains('elegir, solo con esta parte'),
    );
    expect(
      writer.calls.last.instruction,
      contains('elegí los mejores bloques'),
    );
  });
}
