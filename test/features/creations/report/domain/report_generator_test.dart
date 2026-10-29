import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/features/creations/domain/entities/creation_material.dart';
import 'package:sinapsis/features/creations/domain/entities/creation_scope.dart';
import 'package:sinapsis/features/creations/domain/entities/study_creation.dart';
import 'package:sinapsis/features/creations/domain/entities/study_creation_kind.dart';
import 'package:sinapsis/features/creations/domain/services/creation_generator.dart';
import 'package:sinapsis/features/creations/domain/services/structured_writer.dart';
import 'package:sinapsis/features/creations/presentation/kinds/default_creation_kinds.dart';
import 'package:sinapsis/features/creations/report/domain/report_generator.dart';
import 'package:sinapsis/features/creations/report/domain/report_json.dart';
import 'package:sinapsis/features/creations/report/domain/report_template.dart';
import 'package:sinapsis/features/transform/domain/entities/cancellation_signal.dart';

/// Quien escribe, de mentira: pasa por la orquestación de verdad
/// (`runStructuredRequest`: de una vez o por partes, la corrección) y contesta
/// lo que le toca de [replies], en orden, anotando cada pedido.
class FakeReportWriter implements StructuredWriter {
  FakeReportWriter(this.replies, {this.contextTokens = 200000});

  final List<String> replies;
  final calls = <StructuredCall>[];
  final requests = <StructuredRequest<Object?>>[];

  @override
  final int contextTokens;

  @override
  Future<T> writeStructured<T>(StructuredRequest<T> request) {
    requests.add(request);
    return runStructuredRequest(request, (call) async {
      calls.add(call);
      return replies[(calls.length - 1).clamp(0, replies.length - 1)];
    });
  }
}

/// La respuesta de la IA con [sections] secciones, cada una con una
/// pregunta.
String reportReply({
  String title = 'Éxodo',
  List<String> sections = const ['Introducción', 'Conclusión'],
  bool questions = true,
}) => jsonEncode({
  'title': title,
  'subtitle': 'De Egipto al Sinaí.',
  'sections': [
    for (final s in sections)
      {
        'title': s,
        'body': 'Lo de **$s**.',
        if (questions)
          'questions': [
            {
              'question': '¿Qué es $s?',
              'options': [
                {'text': 'Esto', 'correct': true},
                {'text': 'Aquello', 'correct': false},
              ],
              'explanation': 'Porque sí.',
            },
          ],
      },
  ],
});

StudyCreation reportCreation({
  Map<String, Object?> options = const {},
  String languageCode = 'es',
}) => StudyCreation(
  id: 'informe-1',
  kind: StudyCreationKind.report,
  scope: const CreationScope.document('exodo'),
  sourceIds: const ['exodo'],
  options: options,
  languageCode: languageCode,
  status: CreationStatus.generating,
  createdAt: DateTime(2026, 10, 29),
  updatedAt: DateTime(2026, 10, 29),
);

const _single = CreationMaterial(
  mode: CreationMaterialMode.fullText,
  text: '## Éxodo\n\nMoisés guía al pueblo. El mar se abre.',
  sources: [
    CreationMaterialSource(documentId: 'exodo', title: 'Éxodo', chars: 40),
  ],
);

final _byParts = CreationMaterial(
  mode: CreationMaterialMode.byParts,
  parts: [
    for (var i = 0; i < 3; i++)
      CreationMaterialPart(
        documentId: 'exodo',
        text: '## Éxodo\n\nParte $i.',
        index: i,
      ),
  ],
  partsBase: CreationPartsBase.fullText,
  totalParts: 3,
  sources: const [
    CreationMaterialSource(documentId: 'exodo', title: 'Éxodo', chars: 60),
  ],
);

void main() {
  const generator = ReportGenerator();

  Future<(CreationOutput, FakeReportWriter, List<(double, CreationStep)>)>
  generate({
    Map<String, Object?> options = const {},
    String languageCode = 'es',
    CreationMaterial material = _single,
    List<String>? replies,
    int contextTokens = 200000,
    CancellationSignal? signal,
  }) async {
    final writer = FakeReportWriter(
      replies ?? [reportReply()],
      contextTokens: contextTokens,
    );
    final progress = <(double, CreationStep)>[];
    final output = await generator.generate(
      CreationJob(
        creation: reportCreation(options: options, languageCode: languageCode),
        cancellation: signal ?? CancellationSignal(),
      ),
      material,
      writer,
      (p, step) => progress.add((p, step)),
    );
    return (output, writer, progress);
  }

  test('es el generador de los informes', () {
    expect(generator.kind, StudyCreationKind.report);
  });

  group('la plantilla llega al pedido', () {
    for (final template in ReportTemplate.values) {
      test(template.name, () async {
        final (_, writer, _) = await generate(
          options: {CreationOptionValues.template: template.value},
        );
        final instruction = writer.calls.single.instruction;
        expect(instruction, contains(template.guidance));
        // Y solo la suya.
        for (final other in ReportTemplate.values) {
          if (other != template) {
            expect(instruction, isNot(contains(other.guidance)));
          }
        }
      });
    }

    test('el glosario pide términos, no texto', () async {
      final (_, writer, _) = await generate(
        options: {CreationOptionValues.template: CreationOptionValues.glossary},
      );
      expect(writer.calls.single.instruction, contains('"entries"'));
      expect(writer.calls.single.instruction, contains('orden alfabético'));
    });

    test('la propia, con lo que escribió la persona con ✎', () async {
      final (_, writer, _) = await generate(
        options: {
          CreationOptionValues.template: CreationOptionValues.custom,
          CreationOptionValues.customTemplate:
              '  Una línea de tiempo con cada plaga y su sentido  ',
        },
      );
      expect(
        writer.calls.single.instruction,
        contains(
          'El pedido de la persona para su plantilla: «Una línea de tiempo '
          'con cada plaga y su sentido».',
        ),
      );
    });
  });

  test('el interactivo pide las preguntas; el documento, no', () async {
    final (_, interactive, _) = await generate(
      options: {CreationOptionValues.format: CreationOptionValues.interactive},
    );
    expect(interactive.calls.single.instruction, contains('"questions"'));
    expect(
      interactive.calls.single.instruction,
      contains('dos o tres preguntas de opción única'),
    );
    final (_, document, _) = await generate(
      options: {CreationOptionValues.format: CreationOptionValues.document},
    );
    expect(document.calls.single.instruction, isNot(contains('"questions"')));
    expect(document.calls.single.instruction, isNot(contains('preguntas')));
  });

  test('en el idioma de la creación', () async {
    final (_, writer, _) = await generate(languageCode: 'en');
    expect(writer.requests.single.languageCode, 'en');
    expect(writer.calls.single.instruction, contains('en inglés'));
  });

  test('guarda el informe leído, con el título que puso la IA', () async {
    final (output, _, progress) = await generate();
    expect(output.title, 'Éxodo');
    expect(output.contentVersion, 1);
    final report = ReportJson.decode(output.content);
    expect(report.sections.map((s) => s.title), ['Introducción', 'Conclusión']);
    expect(report.sections.first.questions.single.correct.text, 'Esto');
    expect(progress.last, (1.0, CreationStep.finishing));
  });

  test('sin título, el de la fuente', () async {
    final (output, _, _) = await generate(replies: [reportReply(title: '')]);
    expect(output.title, 'Éxodo');
    expect(ReportJson.decode(output.content).title, 'Éxodo');
  });

  test('el glosario se guarda en orden alfabético', () async {
    final (output, _, _) = await generate(
      options: {CreationOptionValues.template: CreationOptionValues.glossary},
      replies: [
        jsonEncode({
          'title': 'Glosario',
          'sections': [
            {
              'title': 'Términos',
              'entries': [
                {'term': 'Sinaí', 'definition': 'El monte.'},
                {'term': 'Arca', 'definition': 'El cofre.'},
              ],
            },
          ],
        }),
      ],
    );
    final report = ReportJson.decode(output.content);
    expect(report.sections.map((s) => s.title), ['A', 'S']);
  });

  test('una respuesta rota se corrige una vez', () async {
    final (output, writer, _) = await generate(
      replies: ['No sé hacer eso.', reportReply()],
    );
    expect(writer.calls, hasLength(2));
    expect(writer.calls.last.lead, contains('no se pudo leer'));
    expect(writer.calls.last.material, 'No sé hacer eso.');
    expect(output.title, 'Éxodo');
  });

  test('lo largo, por partes: cada parte su borrador y uno los une', () async {
    final (output, writer, progress) = await generate(
      material: _byParts,
      options: {CreationOptionValues.template: CreationOptionValues.studyGuide},
      replies: [
        reportReply(sections: ['Parte 0']),
        reportReply(sections: ['Parte 1']),
        reportReply(sections: ['Parte 2']),
        reportReply(sections: ['Objetivos', 'Desarrollo', 'Resumen final']),
      ],
    );
    expect(writer.calls, hasLength(4));
    final request = writer.requests.single;
    expect(request.partTask, contains('solo con esta parte del material'));
    for (final call in writer.calls.take(3)) {
      expect(call.instruction, contains('solo con esta parte del material'));
      expect(call.maxOutputTokens, request.partMaxOutputTokens);
    }
    // El último une en la estructura de la guía de estudio.
    final merge = writer.calls.last;
    expect(merge.instruction, contains('unir en un solo informe'));
    expect(merge.instruction, contains(ReportTemplate.studyGuide.guidance));
    expect(merge.material, contains('Parte 2'));
    expect(ReportJson.decode(output.content).sections.map((s) => s.title), [
      'Objetivos',
      'Desarrollo',
      'Resumen final',
    ]);
    expect(
      progress.map((p) => p.$2),
      containsAll([CreationStep.readingParts, CreationStep.joining]),
    );
  });

  group('cuánto escribe', () {
    test('cada plantilla y cada formato, lo suyo', () {
      int tokens(String template, String format) => reportOutputTokens({
        CreationOptionValues.template: template,
        CreationOptionValues.format: format,
      });
      const doc = CreationOptionValues.document;
      const interactive = CreationOptionValues.interactive;
      expect(tokens(CreationOptionValues.briefing, doc), 2400);
      expect(tokens(CreationOptionValues.studyGuide, doc), 3200);
      expect(
        tokens(CreationOptionValues.studyGuide, interactive),
        3200 + 18 * kReportTokensPerQuestion,
      );
      expect(
        tokens(CreationOptionValues.glossary, interactive),
        greaterThan(tokens(CreationOptionValues.glossary, doc)),
      );
    });

    test('con Gemma, sin pasarse de casi la mitad de la ventana', () {
      final job = CreationJob(
        creation: reportCreation(),
        cancellation: CancellationSignal(),
      );
      expect(generator.replyTokensFor(job, 2048), 921);
      final small = generator.budgetFor(job, 2048);
      expect(small.reservedOutputTokens, 921);
      expect(small.instructionTokens, kReportInstructionTokens);
      expect(small.inputTokens, greaterThan(0));
      // Con una ventana grande, lo que pide la plantilla.
      expect(
        generator.budgetFor(job, 1000000).reservedOutputTokens,
        generator.maxOutputTokens(job),
      );
    });

    test('lo que escribe cada parte nunca pasa de lo que entra', () async {
      final (_, writer, _) = await generate(
        material: _byParts,
        contextTokens: 2048,
        replies: [reportReply()],
      );
      final request = writer.requests.single;
      expect(request.maxOutputTokens, 921);
      expect(request.partMaxOutputTokens, lessThanOrEqualTo(921));
    });
  });

  test('cancelada, no sigue', () async {
    final signal = CancellationSignal()..cancel();
    expect(
      () => generate(signal: signal),
      throwsA(isA<CreationCancelledException>()),
    );
  });
}
