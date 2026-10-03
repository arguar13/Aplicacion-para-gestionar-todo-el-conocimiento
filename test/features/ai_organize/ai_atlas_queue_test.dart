import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/domain/entities/ai_certainty.dart';
import 'package:sinapsis/core/domain/entities/knowledge_item.dart';
import 'package:sinapsis/features/ai_organize/data/repositories/ai_atlas_repository_impl.dart';
import 'package:sinapsis/features/ai_organize/data/repositories/ai_organize_backlog_impl.dart';
import 'package:sinapsis/features/ai_organize/data/steps/auto_atlas_step.dart';
import 'package:sinapsis/features/ai_organize/domain/entities/ai_organize_settings.dart';
import 'package:sinapsis/features/ai_organize/domain/services/ai_organize_queue.dart';
import 'package:sinapsis/features/ai_organize/domain/services/ai_organize_step.dart';
import 'package:sinapsis/features/ai_organize/domain/services/charging_probe.dart';
import 'package:sinapsis/features/ai_organize/domain/services/map_note_intro.dart';
import 'package:sinapsis/features/ai_organize/domain/services/topic_parent_chooser.dart';

import '../../support/ai_organize_harness.dart';
import '../../support/atlas_topics.dart';
import '../../support/fake_chat_model_manager.dart';
import '../../support/fake_embedding_model_manager.dart';

class _NeverCharging implements ChargingProbe {
  @override
  Future<bool> isCharging() async => false;

  @override
  Stream<bool> watchCharging() => const Stream.empty();
}

/// Desde cuándo organiza sola la IA: lo de antes es la biblioteca existente.
Future<DateTime> _epoch() async => DateTime(2026, 10);

/// Un paso de mentira, con el interruptor de las tarjetas, que anota qué
/// elementos le pasó la cola.
class _Seen implements AiOrganizeStep {
  final items = <String>[];

  @override
  AiOrganizeToggle get toggle => AiOrganizeToggle.flashcards;

  @override
  Future<AiStepReport> organize(
    KnowledgeItem item, {
    required String runId,
  }) async {
    items.add(item.id);
    return AiStepReport.nothing;
  }
}

/// El Atlas de la IA dentro de la cola (F27): lo nuevo entra solo, la nota
/// mapa nace con el quinto elemento, y la cola no organiza la nota mapa —un
/// índice no se vincula ni se vuelve tarjetas—.
void main() {
  late AiOrganizeHarness vault;

  setUp(() => vault = AiOrganizeHarness());
  tearDown(() => vault.close());

  test('la cola ubica el tema, arma la nota mapa con el quinto elemento y no '
      'la organiza', () async {
    final topics = AtlasTopics(vault.db);
    final historia = await topics.add(
      'Historia antigua',
      createdAt: DateTime(2026),
    );
    await topics.add('Grecia', parentId: historia, createdAt: DateTime(2026));
    final roma = await topics.add('Roma');
    for (var i = 1; i <= 5; i++) {
      await vault.source('f$i', title: 'Fuente $i', content: 'Texto $i.');
      await topics.tag('f$i', roma);
    }

    final seen = _Seen();
    final atlas = AiAtlasRepositoryImpl(
      database: vault.db,
      library: vault.library,
      organize: vault.organize,
      runs: vault.runs,
      telemetry: vault.telemetry,
      ids: vault.ids,
      clock: vault.clock,
    );
    final queue = AiOrganizeQueue(
      backlog: AiOrganizeBacklogImpl(vault.db),
      runs: vault.runs,
      library: vault.library,
      steps: () => [
        seen,
        AutoAtlasStep(
          atlas: atlas,
          library: vault.library,
          suggestions: vault.suggestions,
          chooseParent:
              ({
                required String topic,
                required String itemTitle,
                required List<String> candidates,
              }) async => TopicParentChoice(
                index: candidates.indexOf('Historia antigua'),
                certainty: AiCertainty.high,
              ),
          writeIntro:
              ({
                required String topic,
                required List<MapIntroEntry> entries,
              }) async => 'Lo reunido sobre $topic.',
          epoch: _epoch,
          modelName: () => 'gemma-prueba',
          clock: vault.clock,
        ),
      ],
      chatModel: () => FakeChatModelManager(ready: true),
      embeddingModel: () => FakeEmbeddingModelManager(ready: true),
      charging: _NeverCharging(),
      epoch: _epoch,
      telemetry: vault.telemetry,
      clock: vault.clock,
      onStatus: (_) {},
      settings: const AiOrganizeSettings(backfillWhileCharging: false),
      // Sin esperar a que una nota quede quieta: la nota mapa nace en la
      // misma hora de la bóveda, y así la cola la vería en el acto.
      noteQuietPeriod: Duration.zero,
    );
    addTearDown(queue.dispose);

    await queue.wake();
    await queue.settled;

    // El tema nuevo se ubicó solo, con la primera fuente.
    expect(await topics.parentOf(roma), historia);
    // Las notas mapa de «Roma» y de su nuevo padre, de la IA.
    final maps = [
      for (final topic in [roma, historia])
        (await atlas.mapNotesOf(topic)).getOrElse((f) => fail('$f')).single,
    ];
    expect(
      [for (final map in maps) map.title],
      ['Mapa de Roma', 'Mapa de Historia antigua'],
    );
    // La cola organizó las cinco fuentes y nunca las notas mapa.
    await queue.wake();
    await queue.settled;
    expect(seen.items, ['f1', 'f2', 'f3', 'f4', 'f5']);
  });
}
