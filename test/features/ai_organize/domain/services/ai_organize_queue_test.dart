import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:sinapsis/core/domain/entities/knowledge_item.dart';
import 'package:sinapsis/core/domain/entities/rendition.dart';
import 'package:sinapsis/core/domain/entities/rendition_kind.dart';
import 'package:sinapsis/features/ai_organize/data/repositories/ai_organize_backlog_impl.dart';
import 'package:sinapsis/features/ai_organize/domain/entities/ai_organize_settings.dart';
import 'package:sinapsis/features/ai_organize/domain/services/ai_organize_queue.dart';
import 'package:sinapsis/features/ai_organize/domain/services/ai_organize_step.dart';
import 'package:sinapsis/features/ai_organize/domain/services/charging_probe.dart';
import 'package:sinapsis/features/ai_organize/domain/services/content_change.dart';
import 'package:sinapsis/features/chat/domain/services/language_model_gate.dart';
import 'package:sinapsis/features/relations/domain/services/chunk_embedding_indexer.dart';
import 'package:sinapsis/features/transform/domain/services/long_work_keeper.dart';

import '../../../../support/ai_organize_harness.dart';
import '../../../../support/fake_chat_model_manager.dart';
import '../../../../support/fake_embedding_model_manager.dart';

/// Un paso de mentira: anota a quién organizó y en qué pasada. [work] es lo
/// que hace además, si la prueba quiere algo más.
class _Step implements AiOrganizeStep {
  _Step(this.toggle, {this.work});

  @override
  final AiOrganizeToggle toggle;

  final Future<void> Function(KnowledgeItem item, String runId)? work;

  final organized = <String>[];

  @override
  Future<AiStepReport> organize(
    KnowledgeItem item, {
    required String runId,
  }) async {
    organized.add(item.id);
    await work?.call(item, runId);
    return AiStepReport.nothing;
  }
}

/// Los vectores de las notas, de mentira: anota a cuáles se les pusieron al
/// día.
class _Vectors implements ChunkEmbeddingIndexer {
  final notes = <String>[];

  @override
  Future<int> indexItem(String itemId) async => 0;

  @override
  Future<int> indexNote(String itemId) async {
    notes.add(itemId);
    return 1;
  }
}

/// El servicio en primer plano de mentira: anota lo que la cola pide.
class _Keeper implements LongWorkKeeper {
  final calls = <String>[];

  @override
  void working({
    required int done,
    required int total,
    LongWorkKind kind = LongWorkKind.dataSync,
    String? detail,
  }) => calls.add('trabajando $done/$total${detail == null ? '' : ' $detail'}');

  @override
  void idle() => calls.add('suelta');
}

class _Charging implements ChargingProbe {
  bool charging = false;
  final changes = StreamController<bool>.broadcast();

  void plug() {
    charging = true;
    changes.add(true);
  }

  @override
  Future<bool> isCharging() async => charging;

  @override
  Stream<bool> watchCharging() => changes.stream;
}

void main() {
  late AiOrganizeHarness vault;
  late _Step relations;
  late _Step flashcards;
  late List<AiOrganizeStep> steps;
  late FakeChatModelManager chatModel;
  late FakeEmbeddingModelManager embeddingModel;
  late _Charging charging;
  late _Vectors vectors;
  late List<AiOrganizeStatus> statuses;

  /// Lo creado antes de este momento es la biblioteca que ya existía.
  final epoch = DateTime(2026, 10);

  setUp(() {
    vault = AiOrganizeHarness();
    relations = _Step(AiOrganizeToggle.relations);
    flashcards = _Step(AiOrganizeToggle.flashcards);
    steps = [relations, flashcards];
    chatModel = FakeChatModelManager(ready: true);
    embeddingModel = FakeEmbeddingModelManager(ready: true);
    charging = _Charging();
    vectors = _Vectors();
    statuses = [];
  });

  tearDown(() async {
    await charging.changes.close();
    await vault.close();
  });

  AiOrganizeQueue queue({
    AiOrganizeSettings settings = const AiOrganizeSettings(),
    Duration noteQuietPeriod = kAiNoteQuietPeriod,
    LongWorkKeeper longWork = const NoLongWorkKeeper(),
  }) {
    final queue = AiOrganizeQueue(
      backlog: AiOrganizeBacklogImpl(vault.db),
      runs: vault.runs,
      library: vault.library,
      steps: () => steps,
      chatModel: () => chatModel,
      embeddingModel: () => embeddingModel,
      vectors: () => vectors,
      charging: charging,
      epoch: () async => epoch,
      telemetry: vault.telemetry,
      clock: vault.clock,
      onStatus: statuses.add,
      settings: settings,
      modelName: () => 'gemma',
      noteQuietPeriod: noteQuietPeriod,
      longWork: longWork,
    );
    addTearDown(queue.dispose);
    return queue;
  }

  Future<List<String>> runsOf(String itemId) async => [
    for (final run in (await vault.runs.listRuns(
      itemId: itemId,
    )).getOrElse((f) => fail('$f')))
      run.id,
  ];

  test('organiza lo nuevo de a uno, en el orden en que llegó, con una '
      'pasada terminada cada uno', () async {
    await vault.source(
      'b',
      title: 'B',
      content: 'Texto b.',
      createdAt: DateTime(2026, 10, 2, 9),
    );
    await vault.source(
      'a',
      title: 'A',
      content: 'Texto a.',
      createdAt: DateTime(2026, 10, 2, 8),
    );

    await queue().start();

    expect(relations.organized, ['a', 'b']);
    expect(flashcards.organized, ['a', 'b']);
    final runs = (await vault.runs.listRuns()).getOrElse((f) => fail('$f'));
    expect(runs.map((r) => r.itemId).toSet(), {'a', 'b'});
    expect(runs.every((r) => r.finishedAt != null), isTrue);
    expect(runs.every((r) => r.model == 'gemma'), isTrue);
    expect(statuses.whereType<AiOrganizeWorking>().map((s) => s.itemTitle), [
      'A',
      'B',
    ]);
    // Los dos son nuevos, y el estado lo dice.
    expect(
      statuses.whereType<AiOrganizeWorking>().map((s) => s.source).toSet(),
      {AiWorkSource.fresh},
    );
    expect(statuses.last, isA<AiOrganizeIdle>());
  });

  test('pausada no toma nada y dice cuántos esperan; al reanudar, '
      'sigue', () async {
    await vault.source('a', title: 'A', content: 'Texto.');
    await vault.source('b', title: 'B', content: 'Texto.');
    final ai = queue(settings: const AiOrganizeSettings(enabled: false));

    await ai.start();

    expect(relations.organized, isEmpty);
    expect((statuses.last as AiOrganizePaused).pending, 2);
    expect((statuses.last as AiOrganizePaused).waitingForCharger, isFalse);

    ai.updateSettings(const AiOrganizeSettings());
    await ai.settled;

    expect(relations.organized, unorderedEquals(['a', 'b']));
  });

  test('cada tipo respeta su interruptor; con todos apagados no abre '
      'pasadas', () async {
    await vault.source('a', title: 'A', content: 'Texto.');

    await queue(settings: const AiOrganizeSettings(relations: false)).start();

    expect(relations.organized, isEmpty);
    expect(flashcards.organized, ['a']);

    await vault.source('b', title: 'B', content: 'Texto.');
    await queue(
      settings: const AiOrganizeSettings(relations: false, flashcards: false),
    ).start();

    expect(await runsOf('b'), isEmpty);
    expect(statuses.last, isA<AiOrganizeIdle>());
  });

  test('si falta un modelo lo dice y espera, sin errores; con el modelo, '
      'sigue', () async {
    await vault.source('a', title: 'A', content: 'Texto.');
    embeddingModel.ready = false;
    final ai = queue();

    await ai.start();

    expect(relations.organized, isEmpty);
    expect(await runsOf('a'), isEmpty);
    final missing = statuses.last as AiOrganizeModelMissing;
    expect(missing.chatModelMissing, isFalse);
    expect(missing.embeddingModelMissing, isTrue);
    verifyNever(
      () => vault.telemetry.recordError(
        any<Object?>(),
        any<StackTrace?>(),
        hint: any(named: 'hint'),
      ),
    );

    embeddingModel.ready = true;
    await ai.wake();

    expect(relations.organized, ['a']);
  });

  group('la biblioteca que ya existía', () {
    test('se recorre solo con el teléfono cargando', () async {
      await vault.source(
        'viejo',
        title: 'Viejo',
        content: 'Texto.',
        createdAt: DateTime(2026, 9),
      );
      final ai = queue();

      await ai.start();

      expect(relations.organized, isEmpty);
      final paused = statuses.last as AiOrganizePaused;
      expect((paused.pending, paused.waitingForCharger), (1, true));

      charging.plug();
      await pumpEventQueue();
      await ai.settled;

      expect(relations.organized, ['viejo']);
      expect(
        statuses.whereType<AiOrganizeWorking>().single.source,
        AiWorkSource.existingLibrary,
      );
    });

    test(
      'con el interruptor apagado no se recorre nunca, ni cargando',
      () async {
        await vault.source(
          'viejo',
          title: 'Viejo',
          content: 'Texto.',
          createdAt: DateTime(2026, 9),
        );
        charging.charging = true;

        await queue(
          settings: const AiOrganizeSettings(backfillWhileCharging: false),
        ).start();

        expect(relations.organized, isEmpty);
        expect(statuses.last, isA<AiOrganizeIdle>());
      },
    );

    test('mantiene viva la app mientras la recorre, con el avance, y la '
        'suelta al terminar', () async {
      for (final id in ['v1', 'v2', 'v3']) {
        await vault.source(
          id,
          title: id,
          content: 'Texto.',
          createdAt: DateTime(2026, 9),
        );
      }
      charging.charging = true;
      final keeper = _Keeper();

      await queue(longWork: keeper).start();

      expect(relations.organized, hasLength(3));
      expect(keeper.calls, [
        'trabajando 0/3 while_charging',
        'trabajando 1/3 while_charging',
        'trabajando 2/3 while_charging',
        'suelta',
      ]);
    });

    test('la suelta si se pausa o se desenchufa, y la vuelve a pedir al '
        'seguir', () async {
      for (final id in ['v1', 'v2']) {
        await vault.source(
          id,
          title: id,
          content: 'Texto.',
          createdAt: DateTime(2026, 9),
        );
      }
      charging.charging = true;
      final keeper = _Keeper();
      late AiOrganizeQueue ai;
      steps = [
        _Step(
          AiOrganizeToggle.relations,
          work: (item, _) async {
            // Después del primero, se pausa.
            if (item.id == 'v2') {
              ai.updateSettings(const AiOrganizeSettings(enabled: false));
            }
          },
        ),
      ];
      ai = queue(longWork: keeper);

      await ai.start();
      await ai.settled;
      expect(keeper.calls.last, 'suelta');
      expect(statuses.last, isA<AiOrganizePaused>());

      // Sin el cargador, reanudar no la pide: no hay nada que pueda hacer.
      charging.charging = false;
      keeper.calls.clear();
      ai.updateSettings(const AiOrganizeSettings());
      await ai.settled;
      expect(keeper.calls, isEmpty);
    });

    test('lo nuevo también la pide mientras trabaja —no se congela al '
        'minimizar—; lo nuevo que se cuela en la pasada la mantiene', () async {
      await vault.source('nuevo', title: 'Nuevo', content: 'Texto.');
      final keeper = _Keeper();
      final ai = queue(longWork: keeper);

      await ai.start();
      expect(relations.organized, ['nuevo']);
      expect(keeper.calls, ['trabajando 0/1', 'suelta']);
      keeper.calls.clear();

      await vault.source(
        'viejo',
        title: 'Viejo',
        content: 'Texto.',
        createdAt: DateTime(2026, 9),
      );
      final later = _Step(
        AiOrganizeToggle.relations,
        work: (item, _) async {
          if (item.id == 'viejo') {
            await vault.source('otro', title: 'Otro', content: 'Texto.');
          }
        },
      );
      steps = [later];
      charging.plug();
      await pumpEventQueue();
      await ai.settled;

      // El que se coló suma al total: uno hecho de dos. La notificación deja
      // de hablar del cargador cuando pasa a lo nuevo.
      expect(keeper.calls, [
        'trabajando 0/1 while_charging',
        'trabajando 1/2',
        'suelta',
      ]);
      expect(later.organized, ['viejo', 'otro']);
    });

    test('lo nuevo pasa antes que lo viejo', () async {
      await vault.source(
        'viejo',
        title: 'Viejo',
        content: 'Texto.',
        createdAt: DateTime(2026, 9),
      );
      await vault.source('nuevo', title: 'Nuevo', content: 'Texto.');
      charging.charging = true;

      await queue().start();

      expect(relations.organized, ['nuevo', 'viejo']);
    });
  });

  test(
    'retoma lo que quedó a medias al reiniciar, hasta tres intentos',
    () async {
      await vault.source('a', title: 'A', content: 'Texto.');
      await vault.source('b', title: 'B', content: 'Texto.');
      // «a»: la app se cerró una vez a mitad. «b»: tres veces —algo la hace
      // caer—, y no se retoma más.
      await vault.startRun('a');
      for (var i = 0; i < kMaxAiRunAttempts; i++) {
        await vault.startRun('b');
      }

      await queue().start();

      expect(relations.organized, ['a']);
      final runs = (await vault.runs.listRuns(
        itemId: 'a',
      )).getOrElse((f) => fail('$f'));
      expect(runs.where((r) => r.finishedAt != null), hasLength(1));
    },
  );

  test(
    'no vuelve a organizar sola lo que se deshizo, salvo que se pida',
    () async {
      await vault.source('a', title: 'A', content: 'Texto.');
      final ai = queue();
      await ai.start();
      await vault.runs.undoRun((await runsOf('a')).single);

      await ai.wake();
      expect(relations.organized, ['a']);

      ai.organizeNow('a');
      await ai.settled;
      expect(relations.organized, ['a', 'a']);
      expect(
        statuses.whereType<AiOrganizeWorking>().last.source,
        AiWorkSource.requested,
      );
    },
  );

  test('pedir varios a la vez los organiza a todos, una vez cada uno, aunque '
      'vengan repetidos o ya se hayan deshecho (F28)', () async {
    await vault.source('a', title: 'A', content: 'Texto.');
    await vault.source('b', title: 'B', content: 'Texto.');
    final ai = queue();
    await ai.start();
    for (final id in ['a', 'b']) {
      await vault.runs.undoRun((await runsOf(id)).single);
    }
    relations.organized.clear();

    ai.organizeAllNow(['a', 'b', 'a']);
    await ai.settled;

    expect(relations.organized, unorderedEquals(['a', 'b']));
  });

  test(
    'un paso que falla se registra y no corta la pasada ni la cola',
    () async {
      steps = [
        _Step(
          AiOrganizeToggle.relations,
          work: (_, _) async => throw StateError('el modelo se cayó'),
        ),
        flashcards,
      ];
      await vault.source('a', title: 'A', content: 'Texto.');
      await vault.source('b', title: 'B', content: 'Texto.');

      await queue().start();

      expect(flashcards.organized, unorderedEquals(['a', 'b']));
      final runs = (await vault.runs.listRuns()).getOrElse((f) => fail('$f'));
      expect(runs.every((r) => r.finishedAt != null), isTrue);
      verify(
        () => vault.telemetry.recordError(
          any<Object?>(that: isA<StateError>()),
          any<StackTrace?>(),
          hint: any(named: 'hint'),
        ),
      ).called(2);
    },
  );

  group('las notas', () {
    Future<void> rewrite(String id, String content) async {
      final note = await vault.reload(id);
      final rendition = note.renditions.single as TextRendition;
      await vault.library.save(
        note.copyWith(
          updatedAt: vault.now,
          renditions: [
            Rendition.text(
              id: rendition.id,
              itemId: id,
              kind: RenditionKind.markdown,
              content: content,
              isPrimary: true,
              createdAt: rendition.createdAt,
            ),
          ],
        ),
      );
    }

    const roma =
        'El Senado romano reunía a los antiguos magistrados de la ciudad. '
        'Durante la república discutía la guerra, las finanzas y las '
        'provincias, y sus decretos pesaban sobre los cónsules aunque no '
        'fueran leyes. Con Augusto perdió el mando de los ejércitos, pero '
        'siguió siendo el lugar donde la aristocracia medía su prestigio y '
        'donde se votaban los honores del príncipe.';
    // Del mismo largo que la de Roma, a un carácter, y de otra cosa.
    const masaMadre =
        'La masa madre fermenta despacio y le da al pan un sabor ácido que '
        'la levadura comercial no consigue. Se alimenta con harina y agua '
        'cada día, se guarda en un frasco tibio y se usa cuando dobla su '
        'volumen. Un pan de campo lleva harina integral, sal, agua y tiempo: '
        'la miga queda húmeda y la corteza gruesa, oscura y crujiente cuando '
        'sale del horno de barro.';
    final pan = masaMadre.padRight(roma.length, '.').substring(0, roma.length);

    test('espera a que la nota quede quieta, y la vuelve a organizar solo '
        'si cambió mucho de contenido', () async {
      await vault.note('n', title: 'Nota', content: roma);
      final ai = queue();

      await ai.start();
      expect(relations.organized, isEmpty, reason: 'se está escribiendo');

      vault.now = vault.now.add(const Duration(seconds: 20));
      await ai.wake();
      expect(relations.organized, ['n']);
      final firstRun = (await vault.runs.listRuns(
        itemId: 'n',
      )).getOrElse((f) => fail('$f')).single;
      // La pasada guarda la huella del texto que vio.
      final stored = await (vault.db.select(
        vault.db.aiRuns,
      )..where((r) => r.id.equals(firstRun.id))).getSingle();
      expect(stored.contentSimhash, contentSimhashOf(roma));

      // Un retoque: una palabra y una coma. No vale otra pasada.
      vault.now = vault.now.add(const Duration(minutes: 1));
      await rewrite(
        'n',
        roma.replaceFirst('antiguos', 'viejos').replaceFirst('.', ','),
      );
      vault.now = vault.now.add(const Duration(seconds: 20));
      await ai.wake();
      expect(relations.organized, ['n']);
      // No se reorganiza, pero sus vectores sí se ponen al día: la describen
      // para los vínculos de otros elementos.
      expect(vectors.notes, ['n']);

      // Reescrita entera, con el mismo largo: la medida por el largo no la
      // veía.
      expect(pan.length, roma.length);
      vault.now = vault.now.add(const Duration(minutes: 1));
      await rewrite('n', pan);
      vault.now = vault.now.add(const Duration(seconds: 20));
      await ai.wake();
      expect(relations.organized, ['n', 'n']);
      expect(statuses.whereType<AiOrganizeWorking>().map((s) => s.source), [
        AiWorkSource.fresh,
        AiWorkSource.changedNote,
      ]);
    });

    test('se despierta sola cuando una nota termina de escribirse', () async {
      final organized = Completer<String>();
      steps = [
        _Step(
          AiOrganizeToggle.relations,
          work: (item, _) async => organized.complete(item.id),
        ),
      ];
      final ai = queue(noteQuietPeriod: const Duration(milliseconds: 50));
      await ai.start();

      await vault.note('n', title: 'Nota', content: 'Una idea.');
      // Para el reloj de la cola, la nota ya lleva el rato quieta. Nadie
      // despierta a la cola: se entera por la base.
      vault.now = vault.now.add(const Duration(seconds: 1));

      expect(await organized.future, 'n');
    });
  });

  test('le cede el modelo a la persona: no lo usa mientras ella tiene una '
      'charla abierta', () async {
    final gate = LanguageModelGate();
    final reached = Completer<void>();
    final used = <String>[];
    steps = [
      _Step(
        AiOrganizeToggle.relations,
        work: (item, _) {
          reached.complete();
          return gate.runInBackground(() async => used.add(item.id));
        },
      ),
    ];
    await vault.source('a', title: 'A', content: 'Texto.');
    final chat = gate.holdForUser();

    final working = queue().start();
    await reached.future;
    await pumpEventQueue();

    expect(statuses.last, isA<AiOrganizeWorking>());
    expect(used, isEmpty);

    chat.release();
    await working;
    expect(used, ['a']);
  });
}
