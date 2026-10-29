import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/features/ai_models/domain/entities/ai_provider.dart';
import 'package:sinapsis/features/ai_models/domain/services/language_model_readiness.dart';
import 'package:sinapsis/features/creations/domain/entities/creation_scope.dart';
import 'package:sinapsis/features/creations/domain/entities/study_creation.dart';
import 'package:sinapsis/features/creations/domain/entities/study_creation_kind.dart';
import 'package:sinapsis/features/creations/domain/services/creation_queue.dart';
import 'package:sinapsis/features/creations/mind_map/domain/mind_map_generator.dart';
import 'package:sinapsis/features/creations/mind_map/domain/mind_map_json.dart';

import '../creations_harness.dart';
import 'support/fake_structured_writer.dart';

/// F43, paso 9: un mapa mental de punta a punta por la cola de verdad, sobre
/// la base de verdad, con un escritor de mentira: se pide, se genera, queda
/// listo con su contenido —y el documento de cada idea reconocido—.
void main() {
  late CreationsHarness h;
  late String exodo;
  late FakeStructuredWriter writer;
  late CreationQueue queue;

  const ready = LanguageModelReady(provider: AiProvider.gemini);

  setUp(() async {
    h = await CreationsHarness.create();
    exodo = await h.processedDoc('exodo', title: 'Éxodo');
    writer = FakeStructuredWriter(
      (call, _) => jsonEncode({
        'title': 'La salida de Egipto',
        'root': {
          'label': 'Éxodo',
          'children': [
            {
              'label': 'El mar se abre',
              'source': 'Éxodo',
              'quote': 'El mar se abre',
            },
            {
              'label': 'El Sinaí',
              'children': ['La Ley'],
            },
          ],
        },
      }),
    );
    queue = CreationQueue(
      repository: () => h.creations,
      scopes: () => h.scopes,
      material: () => h.material,
      generators: () => {StudyCreationKind.mindMap: const MindMapGenerator()},
      personWriter: () => writer,
      backgroundWriter: () => writer,
      readiness: () =>
          ({bool background = false}) async => ready,
      modelName: () => 'Gemini',
    );
  });
  tearDown(() async {
    queue.dispose();
    await h.close();
  });

  Future<StudyCreation> stored(String id) async =>
      (await h.creations.find(id)).getRight().toNullable()!;

  Future<StudyCreation> until(
    String id,
    bool Function(StudyCreation) done,
  ) async {
    for (var i = 0; i < 400; i++) {
      final creation = await stored(id);
      if (done(creation)) return creation;
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    throw StateError('$id no llegó');
  }

  test(
    'en la cola → generando → lista, con el mapa en su forma canónica',
    () async {
      writer.hold = Completer<void>();
      final created = (await queue.create(
        CreationRequest(
          kind: StudyCreationKind.mindMap,
          scope: CreationScope.document(exodo),
          sourceIds: [exodo],
          options: const {'topic': 'El mar'},
        ),
      )).getRight().toNullable()!;
      expect(created.status, CreationStatus.queued);

      final generating = await until(
        created.id,
        (c) => c.status == CreationStatus.generating && writer.calls.isNotEmpty,
      );
      expect(generating.modelName, 'Gemini');
      // Lo que se le dio a leer: el texto del documento, bajo su título.
      expect(writer.calls.single.material, contains('## Éxodo'));
      expect(writer.calls.single.material, contains('El mar se abre.'));
      expect(writer.calls.single.instruction, contains('«El mar»'));

      writer.hold!.complete();
      final done = await until(created.id, (c) => !c.status.isPending);
      expect(done.status, CreationStatus.ready);
      expect(done.title, 'La salida de Egipto');
      expect(done.sourceIds, [exodo]);
      final map = MindMapJson.decode(done.decodedContent);
      expect(map.root.label, 'Éxodo');
      expect(map.size, 4);
      // Con una sola fuente, todas las ideas son de ella.
      expect([
        for (final n in map.root.descendants) n.source?.documentId,
      ], everyElement(exodo));
      expect(map.root.children.first.source?.quote, 'El mar se abre');
    },
  );

  test(
    'lo que no se puede leer, ni corregido, queda fallido por eso',
    () async {
      final broken = FakeStructuredWriter((_, _) => 'nada');
      final failing = CreationQueue(
        repository: () => h.creations,
        scopes: () => h.scopes,
        material: () => h.material,
        generators: () => {StudyCreationKind.mindMap: const MindMapGenerator()},
        personWriter: () => broken,
        backgroundWriter: () => broken,
        readiness: () =>
            ({bool background = false}) async => ready,
      );
      addTearDown(failing.dispose);
      final created = (await failing.create(
        CreationRequest(
          kind: StudyCreationKind.mindMap,
          scope: CreationScope.document(exodo),
          sourceIds: [exodo],
        ),
      )).getRight().toNullable()!;
      final done = await until(created.id, (c) => !c.status.isPending);
      expect(done.status, CreationStatus.failed);
      expect(done.failure, CreationFailure.unreadableReply);
      // La respuesta y su corrección.
      expect(broken.calls, hasLength(2));
    },
  );
}
