import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/features/creations/domain/entities/creation_scope.dart';
import 'package:sinapsis/features/creations/domain/entities/study_creation.dart';
import 'package:sinapsis/features/creations/domain/entities/study_creation_kind.dart';
import 'package:sinapsis/features/vault/data/merge/incoming_vault.dart';

import '../../../creations/creations_harness.dart';

/// «Lo creado» (F43) en la copia de la bóveda y en la unión: viaja entero
/// —también lo de la papelera—, no se repite, lo de la otra a medias no se
/// genera solo acá y una que las dos tienen queda con su versión más nueva.
void main() {
  late CreationsHarness tel;
  late CreationsHarness pc;

  setUp(() async {
    tel = await CreationsHarness.create();
    pc = await CreationsHarness.create(deviceId: 'pc');
  });
  tearDown(() async {
    await tel.close();
    await pc.close();
  });

  Future<StudyCreation> createIn(
    CreationsHarness h,
    StudyCreationKind kind, {
    CreationScope scope = const CreationScope.allProcessed(),
  }) async => (await h.creations.create(
    CreationRequest(kind: kind, scope: scope, sourceIds: const ['doc-a']),
  )).getRight().toNullable()!;

  Future<StudyCreation?> findIn(CreationsHarness h, String id) async =>
      (await h.creations.find(id)).getRight().toNullable();

  test(
    'la copia de la bóveda la lleva, con su contenido y su estado',
    () async {
      final ready = await createIn(tel, StudyCreationKind.mindMap);
      await tel.creations.complete(
        ready.id,
        title: 'Mapa del Éxodo',
        content: '{"raiz":"Éxodo"}',
      );
      final trashed = await createIn(tel, StudyCreationKind.quiz);
      await tel.creations.trash(trashed.id);

      // La copia es la base entera (`VACUUM INTO`): se abre y se lee.
      final incoming = await IncomingVault.open(
        await tel.processed.vault.zip(),
      );
      addTearDown(incoming.dispose);
      final copy = AppDatabase(NativeDatabase(incoming.databaseFile));
      addTearDown(copy.close);
      final rows = {
        for (final row in await copy.select(copy.studyCreations).get())
          row.id: row,
      };

      expect(rows.keys.toSet(), {ready.id, trashed.id});
      expect(rows[ready.id]!.title, 'Mapa del Éxodo');
      expect(rows[ready.id]!.contentJson, '{"raiz":"Éxodo"}');
      expect(rows[trashed.id]!.deletedAt, isNotNull);
    },
  );

  test('la unión trae lo que acá no hay, lo cuenta en la vista previa y en el '
      'resultado, y una segunda vez no repite nada', () async {
    final ready = await createIn(tel, StudyCreationKind.report);
    await tel.creations.complete(ready.id, title: 'Informe', content: '{}');
    final trashed = await createIn(tel, StudyCreationKind.dataTable);
    await tel.creations.trash(trashed.id);

    final preview = await pc.processed.vault.previewFrom(tel.processed.vault);
    expect(preview.newStudyCreations, 2);
    expect(preview.hasNothingNew, isFalse);

    final merged = await pc.processed.vault.mergeFrom(tel.processed.vault);
    expect(merged.studyCreationsAdded, 2);
    expect(merged.changedNothing, isFalse);

    final here = (await findIn(pc, ready.id))!;
    expect(here.title, 'Informe');
    expect(here.status, CreationStatus.ready);
    expect((await findIn(pc, trashed.id))!.isTrashed, isTrue);

    final again = await pc.processed.vault.mergeFrom(tel.processed.vault);
    expect(again.studyCreationsAdded, 0);
  });

  test('lo que allá estaba en la cola o generándose entra fallido por '
      'interrumpido: acá nadie lo pidió', () async {
    final queued = await createIn(tel, StudyCreationKind.presentation);
    final generating = await createIn(tel, StudyCreationKind.infographic);
    await tel.creations.markGenerating(generating.id, modelName: 'Gemini');

    await pc.processed.vault.mergeFrom(tel.processed.vault);

    for (final id in [queued.id, generating.id]) {
      final here = (await findIn(pc, id))!;
      expect(here.status, CreationStatus.failed);
      expect(here.failure, CreationFailure.interrupted);
      expect(here.attempts, 0);
      expect(here.progress, isNull);
    }
    expect((await pc.creations.pending()).getRight().toNullable(), isEmpty);
  });

  test('una que las dos tienen queda con la versión tocada más tarde, si '
      'está terminada', () async {
    final shared = await createIn(tel, StudyCreationKind.mindMap);
    await tel.creations.complete(shared.id, title: 'Primero', content: '{}');
    await pc.processed.vault.mergeFrom(tel.processed.vault);

    // Allá la renombran y la mandan a la papelera, más tarde.
    tel.processed.vault.at(30);
    await tel.creations.rename(shared.id, 'Segundo');
    await tel.creations.trash(shared.id);
    await pc.processed.vault.mergeFrom(tel.processed.vault);
    final here = (await findIn(pc, shared.id))!;
    expect(here.title, 'Segundo');
    expect(here.isTrashed, isTrue);

    // Acá se vuelve a generar después: lo de allá, más viejo, no la pisa.
    pc.processed.vault.at(60);
    await pc.creations.restore(shared.id);
    await pc.creations.requeue(shared.id);
    await pc.processed.vault.mergeFrom(tel.processed.vault);
    final still = (await findIn(pc, shared.id))!;
    expect(still.status, CreationStatus.queued);
    expect(still.isTrashed, isFalse);
  });
}
