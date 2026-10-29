import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/features/creations/domain/entities/creation_material.dart';
import 'package:sinapsis/features/creations/domain/entities/creation_scope.dart';
import 'package:sinapsis/features/creations/domain/entities/study_creation.dart';
import 'package:sinapsis/features/creations/domain/entities/study_creation_kind.dart';
import 'package:sinapsis/features/creations/domain/services/creation_generator.dart';
import 'package:sinapsis/features/creations/domain/services/structured_writer.dart';
import 'package:sinapsis/features/creations/mind_map/domain/mind_map_generator.dart';
import 'package:sinapsis/features/creations/mind_map/domain/mind_map_json.dart';
import 'package:sinapsis/features/creations/mind_map/domain/mind_map_prompt.dart';
import 'package:sinapsis/features/transform/domain/entities/cancellation_signal.dart';

import '../support/fake_structured_writer.dart';

/// F43, paso 9: el generador del mapa mental, con la orquestación de verdad
/// (de una vez, por partes, la corrección) y un escritor de mentira.
void main() {
  const generator = MindMapGenerator();

  CreationJob job({
    Map<String, Object?> options = const {},
    String language = 'es',
    CancellationSignal? signal,
  }) => CreationJob(
    creation: StudyCreation(
      id: 'c-1',
      kind: StudyCreationKind.mindMap,
      scope: const CreationScope.document('p-exodo'),
      languageCode: language,
      status: CreationStatus.generating,
      createdAt: DateTime(2026, 10, 29),
      updatedAt: DateTime(2026, 10, 29),
      sourceIds: const ['p-exodo', 'p-genesis'],
      options: options,
    ),
    cancellation: signal ?? CancellationSignal(),
  );

  const sources = [
    CreationMaterialSource(documentId: 'p-exodo', title: 'Éxodo', chars: 40),
    CreationMaterialSource(
      documentId: 'p-genesis',
      title: 'Génesis',
      chars: 30,
    ),
  ];

  const single = CreationMaterial(
    mode: CreationMaterialMode.fullText,
    text:
        '## Éxodo\n\nMoisés guía al pueblo.\n\n## Génesis\n\nEn el principio.',
    sources: sources,
  );

  CreationMaterial byParts(int count) => CreationMaterial(
    mode: CreationMaterialMode.byParts,
    parts: [
      for (var i = 0; i < count; i++)
        CreationMaterialPart(
          documentId: 'p-exodo',
          text: '## Éxodo\n\nParte $i del texto.',
          index: i,
        ),
    ],
    totalParts: count,
    sources: sources,
  );

  String reply(Object json) => jsonEncode(json);

  final finalMap = {
    'title': 'El Éxodo',
    'root': {
      'label': 'Salida de Egipto',
      'children': [
        {
          'label': 'Las plagas',
          'source': 'Éxodo',
          'quote': 'diez plagas',
          'children': ['El Nilo'],
        },
        {'label': 'La creación', 'source': 'Génesis'},
      ],
    },
  };

  test('de una vez: la tarea, el esquema, el idioma, el tema y lo que '
      'devuelve, en la forma canónica', () async {
    final writer = FakeStructuredWriter((call, _) => reply(finalMap));
    final steps = <(double, CreationStep)>[];
    final output = await generator.generate(
      job(options: {'topic': 'Moisés y Faraón'}, language: 'en'),
      single,
      writer,
      (progress, step) => steps.add((progress, step)),
    );

    final request = writer.requests.single;
    expect(request.schema, mindMapSchemaPrompt);
    expect(request.languageCode, 'en');
    expect(request.task, contains('unas 53 ideas'));
    expect(request.task, contains('«Moisés y Faraón»'));
    expect(request.maxOutputTokens, MindMapGenerator.replyTokens);
    // El tema va en la tarea, no como «lo que pidió la persona».
    expect(request.guidance, isNull);
    final call = writer.calls.single;
    expect(call.instruction, contains('inglés'));
    expect(call.instruction, contains(mindMapSchemaPrompt));
    expect(call.material, single.text);

    expect(output.title, 'El Éxodo');
    final map = MindMapJson.decode(jsonDecode(output.content));
    expect(map.root.label, 'Salida de Egipto');
    expect(map.root.children.first.source?.documentId, 'p-exodo');
    expect(map.root.children.last.source?.documentId, 'p-genesis');
    expect(steps.last, (1.0, CreationStep.finishing));
  });

  test('por partes: una rama por parte —un borrador puede ser una rama '
      'sola— y el paso de unir da el mapa', () async {
    final writer = FakeStructuredWriter(
      (call, index) => index < 3
          ? reply({
              'root': {'label': 'Rama $index'},
            })
          : reply(finalMap),
    );
    final output = await generator.generate(
      job(),
      byParts(3),
      writer,
      (_, _) {},
    );

    expect(writer.calls, hasLength(4));
    expect(writer.calls.first.lead, startsWith('Parte 1 de 3'));
    expect(writer.calls.first.instruction, contains('SOLO esta parte'));
    expect(
      writer.calls.first.maxOutputTokens,
      MindMapGenerator.partReplyTokens,
    );
    final merge = writer.calls.last;
    expect(merge.instruction, contains('unir en un solo mapa mental'));
    expect(merge.material, contains('Rama 0'));
    expect(merge.material, contains('Rama 2'));
    expect(merge.maxOutputTokens, MindMapGenerator.replyTokens);
    expect(output.title, 'El Éxodo');
  });

  test('una raíz sin ramas no es un mapa: se le pide una vez que lo corrija, '
      'con el motivo', () async {
    final writer = FakeStructuredWriter(
      (call, index) => index == 0
          ? reply({
              'root': {'label': 'Sola'},
            })
          : reply(finalMap),
    );
    final output = await generator.generate(job(), single, writer, (_, _) {});
    expect(writer.calls, hasLength(2));
    expect(writer.calls.last.lead, contains('children'));
    expect(output.title, 'El Éxodo');
  });

  test('si tampoco la corrige: no se pudo leer', () async {
    final writer = FakeStructuredWriter((_, _) => 'no sé hacer mapas');
    await expectLater(
      generator.generate(job(), single, writer, (_, _) {}),
      throwsA(isA<UnreadableStructuredReply>()),
    );
  });

  test('cancelada, corta', () async {
    final signal = CancellationSignal()..cancel();
    final writer = FakeStructuredWriter((_, _) => reply(finalMap));
    await expectLater(
      generator.generate(job(signal: signal), single, writer, (_, _) {}),
      throwsA(isA<CreationCancelledException>()),
    );
    expect(writer.calls, isEmpty);
  });

  group('lo que escribe, según la ventana', () {
    test('con una nube grande, el tope; con Gemma, el 40 % de la ventana', () {
      expect(MindMapGenerator.replyTokensFor(1000000), 3200);
      expect(MindMapGenerator.replyTokensFor(2048), 819);
      expect(MindMapGenerator.replyTokensFor(1000), 600);
      expect(generator.budgetFor(job(), 2048).reservedOutputTokens, 819);
    });

    test('las ideas que se piden van con lo que entra: entre 12 y 60', () {
      expect(MindMapGenerator.nodesFor(3200), 53);
      expect(MindMapGenerator.nodesFor(819), 13);
      expect(MindMapGenerator.nodesFor(100), 12);
      expect(MindMapGenerator.nodesFor(99999), 60);
    });

    test('con Gemma, el pedido reserva lo mismo que el armado', () async {
      final writer = FakeStructuredWriter(
        (_, _) => reply(finalMap),
        contextTokens: 2048,
      );
      await generator.generate(job(), single, writer, (_, _) {});
      final request = writer.requests.single;
      expect(request.maxOutputTokens, 819);
      expect(request.budget.reservedOutputTokens, 819);
      expect(request.task, contains('unas 13 ideas'));
    });
  });
}
