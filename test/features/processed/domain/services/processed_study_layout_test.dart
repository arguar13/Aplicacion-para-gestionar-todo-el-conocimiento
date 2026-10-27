import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/features/processed/domain/entities/processed_part.dart';
import 'package:sinapsis/features/processed/domain/services/processed_study_layout.dart';

/// Cómo se corresponden el texto propio de un procesado y el de su fuente
/// (decisión I): puro.
void main() {
  ProcessedAnchor src(int start, int end, [String rendition = 'r']) =>
      ProcessedAnchor(renditionId: rendition, start: start, end: end);

  // Tres páginas: la primera y la tercera, copias sin editar de la fuente; la
  // del medio, editada (sin lugar en la fuente). Lo propio y la fuente no
  // coinciden en posiciones: la del medio cambió de largo.
  final layout = ProcessedStudyLayout.pages([
    ProcessedTextPage(partId: 'a', start: 0, end: 10, source: src(0, 10)),
    const ProcessedTextPage(partId: 'b', start: 10, end: 15),
    ProcessedTextPage(partId: 'c', start: 15, end: 25, source: src(20, 30)),
  ]);

  test(
    'lo que está en una página de la fuente se ubica en el texto propio',
    () {
      expect(layout.ownOf(src(2, 6)), const ProcessedSpan(start: 2, end: 6));
      expect(
        layout.ownOf(src(22, 30)),
        const ProcessedSpan(start: 17, end: 25),
      );
    },
  );

  test('lo que cae en lo editado, cruza un salto o es de otro texto, no', () {
    expect(layout.ownOf(src(12, 14)), isNull);
    expect(layout.ownOf(src(8, 22)), isNull);
    expect(layout.ownOf(src(2, 6, 'otra')), isNull);
    expect(layout.ownOf(src(40, 45)), isNull);
  });

  test('y al revés: lo propio lleva a la fuente solo si es de ella', () {
    expect(layout.sourceOf(2, 6), src(2, 6));
    expect(layout.sourceOf(16, 25), src(21, 30));
    expect(layout.sourceOf(11, 13), isNull);
    expect(layout.sourceOf(8, 17), isNull);
    expect(layout.sourceOf(30, 32), isNull);
    expect(layout.sourceOf(5, 5), isNull);
  });

  test('dos páginas seguidas de la fuente se juntan', () {
    final joined = ProcessedStudyLayout.pages([
      ProcessedTextPage(partId: 'a', start: 0, end: 10, source: src(0, 10)),
      ProcessedTextPage(partId: 'b', start: 10, end: 20, source: src(10, 20)),
    ]);

    expect(joined.ownOf(src(8, 14)), const ProcessedSpan(start: 8, end: 14));
    expect(joined.sourceOf(8, 14), src(8, 14));
    expect(joined.pagesLength, 20);
    expect(joined.hasPages, isTrue);
  });

  test('sin páginas, el texto propio es el de la fuente', () {
    const source = ProcessedStudyLayout.source('r');

    expect(source.hasPages, isFalse);
    expect(source.ownOf(src(3, 9)), const ProcessedSpan(start: 3, end: 9));
    expect(source.ownOf(src(3, 9, 'otra')), isNull);
    expect(source.sourceOf(3, 9), src(3, 9));
    expect(source.pagesLength, 0);
  });
}
