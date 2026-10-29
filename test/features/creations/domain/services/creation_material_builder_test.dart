import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/features/ai_models/domain/services/model_text_budget.dart';
import 'package:sinapsis/features/creations/domain/entities/creation_material.dart';
import 'package:sinapsis/features/creations/domain/entities/creation_scope.dart';
import 'package:sinapsis/features/creations/domain/services/creation_material_builder.dart';
import 'package:sinapsis/features/processed/domain/services/processed_text.dart';

import '../../creations_harness.dart';

/// El material de una creación (F43, punto 6): lo que entra en la ventana del
/// modelo, en el orden del plan —el texto entero, el resumen, la síntesis o
/// por partes—, sin trabar la interfaz con un libro de tres millones de
/// caracteres.
void main() {
  const text =
      'Moisés guía al pueblo fuera de Egipto. El faraón lo persigue con sus '
      'carros. El mar se abre y el pueblo cruza a pie. En el Sinaí reciben la '
      'ley y hacen una alianza. ';

  /// Un presupuesto que deja [chars] caracteres de material de una vez.
  CreationBudget fitting(int chars) => CreationBudget(
    contextTokens: 1000 + kCreationInstructionTokens + chars ~/ 3,
    reservedOutputTokens: 1000,
  );

  group('en el orden del plan', () {
    late CreationsHarness h;
    late String exodo;
    late String genesis;

    setUp(() async {
      h = await CreationsHarness.create();
      exodo = await h.processedDoc(
        'exodo',
        title: 'Éxodo',
        text: text * 4,
        summary: [(0, 38), (112, 168)],
        synthesis: [(0, 38)],
      );
      genesis = await h.processedDoc(
        'genesis',
        title: 'Génesis',
        text: 'En el principio creó Dios los cielos y la tierra. ' * 4,
      );
    });
    tearDown(() => h.close());

    Future<CreationMaterial> build(
      List<String> ids,
      CreationBudget budget,
    ) async => (await h.material.build(
      sourceIds: ids,
      budget: budget,
    )).getRight().toNullable()!;

    test(
      'el texto entero si cabe, cada fuente bajo su título y en orden',
      () async {
        final material = await build([genesis, exodo], fitting(100000));

        expect(material.mode, CreationMaterialMode.fullText);
        expect(material.text, startsWith('## Génesis\n\nEn el principio'));
        expect(material.text, contains('\n\n## Éxodo\n\nMoisés guía'));
        expect(material.text, contains('reciben la ley'));
        expect(material.sourceIds, [genesis, exodo]);
        expect(material.titles, {genesis: 'Génesis', exodo: 'Éxodo'});
        expect(material.coverage, 1);
        expect(material.withoutStudyMarks, [genesis]);
        expect(material.chars, material.text!.length);
        expect(
          material.estimatedInputTokens,
          (material.text!.length / kCreationCharsPerToken).ceil(),
        );
      },
    );

    test('si no cabe, las oraciones del resumen', () async {
      final material = await build([exodo], fitting(200));

      expect(material.mode, CreationMaterialMode.summarySentences);
      expect(
        material.text,
        '## Éxodo\n\nMoisés guía al pueblo fuera de Egipto.\n'
        '${(text * 4).substring(112, 168).trim()}',
      );
    });

    test('si tampoco, las de la síntesis', () async {
      final material = await build([exodo], fitting(60));

      expect(material.mode, CreationMaterialMode.synthesisSentences);
      expect(
        material.text,
        '## Éxodo\n\nMoisés guía al pueblo fuera de Egipto.',
      );
    });

    test('una fuente sin resumen va entera en el modo del resumen', () async {
      final material = await build([exodo, genesis], fitting(350));

      expect(material.mode, CreationMaterialMode.summarySentences);
      expect(material.text, contains('En el principio creó Dios'));
      expect(material.text, isNot(contains('El faraón lo persigue')));
    });

    test('si nada cabe, por partes del texto más corto, ninguna más larga '
        'que lo que entra', () async {
      const long = 'En el principio creó Dios los cielos y la tierra. ';
      final largo = await h.processedDoc(
        'largo',
        title: 'Génesis',
        text: long * 40,
      );
      const budget = CreationBudget(
        contextTokens: 1000 + kCreationInstructionTokens + 180,
        reservedOutputTokens: 1000,
      );
      final material = await build([largo], budget);

      expect(material.mode, CreationMaterialMode.byParts);
      expect(material.text, isNull);
      expect(material.partsBase, CreationPartsBase.fullText);
      expect(material.parts, isNotEmpty);
      for (final part in material.parts) {
        expect(part.text.length, lessThanOrEqualTo(budget.partChars));
        expect(part.text, startsWith('## Génesis\n\n'));
        expect(part.documentId, largo);
      }
      expect(material.parts.length, greaterThan(1));
      expect(material.totalParts, material.parts.length);
      expect(material.coverage, 1);
      // No se pierde ni se repite nada del texto.
      final body = [
        for (final part in material.parts)
          part.text.substring('## Génesis\n\n'.length),
      ].join(' ');
      expect(body.replaceAll(RegExp(r'\s+'), ' '), (long * 40).trim());
    });

    test(
      'lo que ya no es un procesado vivo se saltea; sin nada, vacío',
      () async {
        await h.processed.vault.library.deleteMany([exodo]);

        final some = await build([
          exodo,
          genesis,
          'no-existe',
        ], fitting(100000));
        expect(some.sourceIds, [genesis]);

        final none = await build([exodo, 'no-existe'], fitting(100000));
        expect(none.isEmpty, isTrue);
      },
    );
  });

  group('cortar en partes', () {
    test('busca un fin de párrafo, después de oración, después un espacio', () {
      expect(
        splitCreationText((
          text: 'Uno dos tres.\n\nCuatro cinco seis siete ocho.',
          maxChars: 20,
        )),
        ['Uno dos tres.', 'Cuatro cinco seis', 'siete ocho.'],
      );
      expect(
        splitCreationText((
          text: 'Una oración. Otra más larga que sigue.',
          maxChars: 20,
        )),
        ['Una oración.', 'Otra más larga que', 'sigue.'],
      );
      expect(splitCreationText((text: 'abcdefghij', maxChars: 4)), [
        'abcd',
        'efgh',
        'ij',
      ]);
      expect(splitCreationText((text: '   ', maxChars: 4)), isEmpty);
    });

    test('elegir parejo: la primera, la última y las del medio repartidas', () {
      final all = List.generate(10, (i) => i);
      expect(pickEvenly(all, 4), [0, 3, 6, 9]);
      expect(pickEvenly(all, 20), all);
      expect(pickEvenly(all, 1), [0]);
      expect(pickEvenly(all, 0), isEmpty);
    });
  });

  group('un libro de tres millones de caracteres', () {
    late CreationsHarness h;
    late String book;
    final sizes = <int>[];

    Future<R> spy<Q, R>(
      ComputeCallback<Q, R> work,
      Q message, {
      required int size,
    }) {
      sizes.add(size);
      // El de la app: en otro hilo desde 60.000 caracteres.
      return runProcessedWork(work, message, size: size);
    }

    String bookOf(int chars) {
      final buffer = StringBuffer();
      var i = 0;
      while (buffer.length < chars) {
        buffer.write('La oración número ${i++} de un libro muy largo. ');
        if (i % 9 == 0) buffer.write('\n\n');
      }
      return buffer.toString().substring(0, chars);
    }

    setUpAll(() async {
      h = await CreationsHarness.create(worker: spy);
      await h.processedDoc('libro', title: 'Libro', text: bookOf(3000000));
      book = (await h.scopes.documentIds(
        const CreationScope.allProcessed(),
      )).getRight().toNullable()!.single;
    });
    tearDownAll(() => h.close());
    setUp(sizes.clear);

    for (final (name, budget, partChars) in [
      (
        'con Gemma (2048 tokens)',
        const CreationBudget(contextTokens: 2048, reservedOutputTokens: 768),
        2040,
      ),
      (
        'con Gemini (un millón de tokens)',
        const CreationBudget(
          contextTokens: 1000000,
          reservedOutputTokens: 8192,
        ),
        kMaxPartChars,
      ),
    ]) {
      test('$name: va por partes repartidas por todo el libro, y cortarlo '
          'corre en otro hilo', () async {
        final watch = Stopwatch()..start();
        final material = (await h.material.build(
          sourceIds: [book],
          budget: budget,
        )).getRight().toNullable()!;
        watch.stop();

        expect(budget.partChars, partChars);
        expect(material.mode, CreationMaterialMode.byParts);
        expect(material.parts, hasLength(kMaxCreationParts));
        expect(material.totalParts, greaterThan(kMaxCreationParts));
        expect(material.parts.first.index, 0);
        expect(material.parts.last.index, material.totalParts - 1);
        expect(material.coverage, lessThan(1));
        for (final part in material.parts) {
          expect(part.text.length, lessThanOrEqualTo(partChars));
        }
        // Cortar el libro pasa por el trabajo pesado con su tamaño entero: en
        // la app, en otro hilo.
        expect(sizes, [3000000]);
        // Lo medido (PC, base en el mismo hilo de la prueba): ver el informe
        // del paso 2 de F43.
        debugPrint(
          'F43 material, libro de 3.000.000 de caracteres $name: '
          '${watch.elapsedMilliseconds} ms, ${material.totalParts} partes, '
          '${(material.coverage * 100).toStringAsFixed(1)} % leído',
        );
        expect(watch.elapsed, lessThan(const Duration(seconds: 30)));
      });
    }
  });
}
