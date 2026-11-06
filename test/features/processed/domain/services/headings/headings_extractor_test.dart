import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/features/processed/domain/entities/processed_heading.dart';
import 'package:sinapsis/features/processed/domain/services/headings/headings_extractor.dart';
import 'package:sinapsis/features/processed/domain/services/headings/processed_headings.dart';

/// El lector de títulos que usa la app (F46, paso 2): el del paso 1, por el
/// trabajador de siempre, que decide si va a otro hilo por lo que mide el
/// texto.
void main() {
  test('lee con readProcessedHeadings, y le dice al trabajador cuánto mide '
      'el texto', () async {
    final sizes = <int>[];
    Future<R> worker<Q, R>(
      ComputeCallback<Q, R> work,
      Q message, {
      required int size,
    }) async {
      sizes.add(size);
      return work(message);
    }

    final source = ProcessedHeadingsSource(
      pages: const ['# Roma\nLa ciudad.\n', '## El Senado\nPatres.'],
      kind: ProcessedTextKind.markdown,
    );

    final read = await ReadingHeadingsExtractor(
      worker: worker,
    ).headingsOf(source);

    expect(read, readProcessedHeadings(source));
    expect(read.map((h) => (h.level, h.title)), [
      (1, 'Roma'),
      (2, 'El Senado'),
    ]);
    expect(read.first.origin, ProcessedHeadingOrigin.textHeading);
    expect(sizes, [source.pages.join().length]);
  });
}
