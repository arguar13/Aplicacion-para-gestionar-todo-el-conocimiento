import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/domain/entities/processed_section.dart';
import 'package:sinapsis/features/processed/domain/entities/processed_query.dart';
import 'package:sinapsis/features/processed/domain/entities/section_edit.dart';
import 'package:sinapsis/features/processed/domain/services/processed_identity.dart';

import '../../../../support/time_growth.dart';
import '../../processed_harness.dart';

/// Un libro de millones de caracteres no traba nada (F41, decisión B; la
/// lección de `1d4cf338`): lo pesado se hace donde corresponde y lo que se
/// muestra cuesta lo que mide una página, no lo que mide el libro.
void main() {
  String book(int chars) {
    final buffer = StringBuffer();
    var i = 0;
    while (buffer.length < chars) {
      buffer.write('La oración número ${i++} de un libro muy largo. ');
      if (i % 9 == 0) buffer.write('\n\n');
    }
    return buffer.toString().substring(0, chars);
  }

  test('paginar y comparar el texto pasan por el trabajo pesado, con el '
      'tamaño del libro', () async {
    final sizes = <int>[];
    Future<R> spy<Q, R>(
      ComputeCallback<Q, R> work,
      Q message, {
      required int size,
    }) async {
      sizes.add(size);
      return work(message);
    }

    final h = await ProcessedHarness.create(worker: spy);
    addTearDown(h.close);
    final text = book(200000);
    await h.vault.saveSource('libro', text: text);

    await h.process.passUnchanged('libro');
    expect(sizes, [
      text.length, // paginar
      text.length, // comparar: las páginas nuevas, sin nada de antes
    ]);

    sizes.clear();
    await h.process.passUnchanged('libro');
    expect(sizes, [
      text.length,
      // Las páginas nuevas y las que ya estaban.
      2 * text.length,
    ]);

    sizes.clear();
    await h.process.preview('libro', {
      ProcessedSection.text: SectionEdit.update(),
    });
    // Y contar las palabras de la vista previa.
    expect(sizes, [text.length, 2 * text.length, text.length]);
  });

  group('lo que se muestra no crece con el libro', () {
    late ProcessedHarness h;
    final small = processedDocumentIdFor('chico');
    final big = processedDocumentIdFor('grande');

    setUpAll(() async {
      h = await ProcessedHarness.create();
      await h.vault.saveSource('chico', text: book(750000));
      await h.vault.saveSource('grande', text: book(3000000));
      await h.process.passUnchanged('chico');
      await h.process.passUnchanged('grande');
    });
    tearDownAll(() => h.close());

    test('la fila de la lista', () async {
      Future<int> row(String id) => micros(
        () => h.repository.watchDocuments(ProcessedQuery(ids: {id})).first,
      );

      final growth = await timeGrowth(() => row(small), () => row(big));

      expect(growth, lessThan(2), reason: 'cuatro veces más libro');
    });

    test('una página del texto', () async {
      Future<int> page(String id) => micros(
        () => h.repository
            .watchParts(id, ProcessedSection.text, offset: 40, limit: 1)
            .first,
      );

      final growth = await timeGrowth(() => page(small), () => page(big));

      expect(growth, lessThan(2), reason: 'cuatro veces más libro');
    });
  });
}
