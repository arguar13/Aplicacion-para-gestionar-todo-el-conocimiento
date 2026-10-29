import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/features/ai_models/domain/entities/ai_provider.dart';
import 'package:sinapsis/features/ai_models/domain/services/language_model_readiness.dart';
import 'package:sinapsis/features/creations/data_table/domain/data_table_generator.dart';
import 'package:sinapsis/features/creations/data_table/domain/data_table_prompt.dart';
import 'package:sinapsis/features/creations/data_table/domain/study_table_json.dart';
import 'package:sinapsis/features/creations/domain/entities/creation_material.dart';
import 'package:sinapsis/features/creations/domain/entities/creation_scope.dart';
import 'package:sinapsis/features/creations/domain/entities/study_creation.dart';
import 'package:sinapsis/features/creations/domain/entities/study_creation_kind.dart';
import 'package:sinapsis/features/creations/domain/services/creation_generator.dart';
import 'package:sinapsis/features/creations/domain/services/creation_queue.dart';
import 'package:sinapsis/features/transform/domain/entities/cancellation_signal.dart';

import '../../creations_harness.dart';
import '../../mind_map/support/fake_structured_writer.dart';

/// F43, paso 9: el generador de la tabla de datos —la «Descripción» dice qué
/// columnas—, de una vez, por partes y por la cola de verdad.
void main() {
  const generator = DataTableGenerator();

  final tableJson = {
    'title': 'Personajes del Éxodo',
    'columns': [
      {'name': 'Personaje', 'type': 'text'},
      {'name': 'Papel', 'type': 'text'},
    ],
    'rows': [
      ['Moisés', 'Guía'],
      ['Aarón', 'Vocero'],
    ],
  };

  CreationJob job({
    Map<String, Object?> options = const {},
    CancellationSignal? signal,
  }) => CreationJob(
    creation: StudyCreation(
      id: 't-1',
      kind: StudyCreationKind.dataTable,
      scope: const CreationScope.document('p-1'),
      languageCode: 'es',
      status: CreationStatus.generating,
      createdAt: DateTime(2026, 10, 29),
      updatedAt: DateTime(2026, 10, 29),
      options: options,
    ),
    cancellation: signal ?? CancellationSignal(),
  );

  const single = CreationMaterial(
    mode: CreationMaterialMode.fullText,
    text: '## Éxodo\n\nMoisés guía; Aarón habla.',
    sources: [
      CreationMaterialSource(documentId: 'p-1', title: 'Éxodo', chars: 30),
    ],
  );

  test(
    'con «Descripción»: va tal cual y la tarea pide esas columnas',
    () async {
      final writer = FakeStructuredWriter((_, _) => jsonEncode(tableJson));
      final steps = <(double, CreationStep)>[];
      final output = await generator.generate(
        job(
          options: {'description': '  Personaje, papel y primera aparición '},
        ),
        single,
        writer,
        (p, s) => steps.add((p, s)),
      );
      final request = writer.requests.single;
      expect(request.schema, dataTableSchemaPrompt);
      expect(request.guidance, 'Personaje, papel y primera aparición');
      expect(request.task, contains('las que pidió la persona'));
      expect(request.task, contains('hasta 40 filas'));
      expect(
        writer.calls.single.instruction,
        contains('«Personaje, papel y primera aparición»'),
      );
      expect(output.title, 'Personajes del Éxodo');
      final table = StudyTableJson.decode(jsonDecode(output.content));
      expect(table.rows, [
        ['Moisés', 'Guía'],
        ['Aarón', 'Vocero'],
      ]);
      expect(steps.last, (1.0, CreationStep.finishing));
    },
  );

  test('sin «Descripción», la IA elige las columnas', () async {
    final writer = FakeStructuredWriter((_, _) => jsonEncode(tableJson));
    await generator.generate(job(), single, writer, (_, _) {});
    final request = writer.requests.single;
    expect(request.guidance, isNull);
    expect(request.task, contains('Elegí las columnas'));
    expect(request.task, isNot(contains('pidió la persona')));
  });

  test(
    'por partes: filas por parte con columnas para todo, y se unen',
    () async {
      final writer = FakeStructuredWriter(
        (call, index) => jsonEncode(tableJson),
      );
      await generator.generate(
        job(),
        CreationMaterial(
          mode: CreationMaterialMode.byParts,
          parts: [
            for (var i = 0; i < 2; i++)
              CreationMaterialPart(
                documentId: 'p-1',
                text: 'parte $i',
                index: i,
              ),
          ],
          totalParts: 2,
          sources: single.sources,
        ),
        writer,
        (_, _) {},
      );
      expect(writer.calls, hasLength(3));
      expect(writer.calls.first.instruction, contains('SOLO esta parte'));
      expect(writer.calls.first.instruction, contains('sirvan para todo'));
      expect(
        writer.calls.first.maxOutputTokens,
        DataTableGenerator.partReplyTokens,
      );
      expect(writer.calls.last.instruction, contains('unir en una sola tabla'));
    },
  );

  test('una tabla sin filas se le pide corregir una vez', () async {
    final writer = FakeStructuredWriter(
      (_, index) => index == 0
          ? jsonEncode({
              'columns': ['A'],
              'rows': <Object?>[],
            })
          : jsonEncode(tableJson),
    );
    await generator.generate(job(), single, writer, (_, _) {});
    expect(writer.calls, hasLength(2));
    expect(writer.calls.last.lead, contains('rows'));
  });

  test('según la ventana: el tope, o el 40 % con Gemma, y las filas que '
      'entran', () {
    expect(DataTableGenerator.replyTokensFor(1000000), 2600);
    expect(DataTableGenerator.replyTokensFor(2048), 819);
    expect(DataTableGenerator.replyTokensFor(500), 500);
    expect(DataTableGenerator.rowsFor(2600), 40);
    expect(DataTableGenerator.rowsFor(819), 12);
    expect(DataTableGenerator.rowsFor(100), 6);
    expect(generator.budgetFor(job(), 2048).reservedOutputTokens, 819);
  });

  group('por la cola de verdad', () {
    late CreationsHarness h;
    late CreationQueue queue;
    late FakeStructuredWriter writer;

    setUp(() async {
      h = await CreationsHarness.create();
      writer = FakeStructuredWriter((_, _) => jsonEncode(tableJson));
      queue = CreationQueue(
        repository: () => h.creations,
        scopes: () => h.scopes,
        material: () => h.material,
        generators: () => {StudyCreationKind.dataTable: generator},
        personWriter: () => writer,
        backgroundWriter: () => writer,
        readiness: () =>
            ({bool background = false}) async =>
                const LanguageModelReady(provider: AiProvider.gemini),
      );
    });
    tearDown(() async {
      queue.dispose();
      await h.close();
    });

    test('en la cola → generando → lista, con la tabla', () async {
      final doc = await h.processedDoc('exodo', title: 'Éxodo');
      writer.hold = Completer<void>();
      final created = (await queue.create(
        CreationRequest(
          kind: StudyCreationKind.dataTable,
          scope: CreationScope.document(doc),
          sourceIds: [doc],
          options: const {'description': 'Personaje y papel'},
        ),
      )).getRight().toNullable()!;
      expect(created.status, CreationStatus.queued);

      Future<StudyCreation> until(bool Function(StudyCreation) done) async {
        for (var i = 0; i < 400; i++) {
          final c = (await h.creations.find(
            created.id,
          )).getRight().toNullable()!;
          if (done(c)) return c;
          await Future<void>.delayed(const Duration(milliseconds: 5));
        }
        throw StateError('no llegó');
      }

      await until(
        (c) => c.status == CreationStatus.generating && writer.calls.isNotEmpty,
      );
      expect(writer.calls.single.material, contains('Moisés guía al pueblo'));
      writer.hold!.complete();
      final done = await until((c) => !c.status.isPending);
      expect(done.status, CreationStatus.ready);
      expect(done.title, 'Personajes del Éxodo');
      expect(StudyTableJson.decode(done.decodedContent).rows, hasLength(2));
    });
  });
}
