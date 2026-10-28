import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/features/processed/domain/entities/processed_image.dart';
import 'package:sinapsis/features/processed/domain/entities/section_edit.dart';
import 'package:sinapsis/features/processed/domain/services/processed_images_planner.dart';

final _at = DateTime(2026, 10, 28, 12);

SourceImage _source(String name, {int size = 100}) => SourceImage(
  path: 'originales/fuente/contenido/$name',
  origin: SourceImageOrigin.content,
  sizeBytes: size,
);

ProcessedImage _kept(String name, int position, {int size = 100}) =>
    ProcessedImage(
      renditionId: 'copia-$name',
      documentId: 'doc',
      position: position,
      relativePath: 'originales/doc/imagenes/$name',
      sizeBytes: size,
      sourceFilePath: 'originales/fuente/contenido/$name',
      copiedAt: _at,
    );

List<String> _names(ImagesPlan plan) => [
  for (final image in plan.images)
    switch (image) {
      KeptImage(:final image) =>
        'tenía:${image.sourceFilePath.split('/').last}',
      NewImage(:final source) => 'nueva:${source.path.split('/').last}',
    },
];

void main() {
  group('planImagesChange (F41, decisión L)', () {
    test('agregar deja todo en su lugar y suma al final lo que no está, '
        'sin copiar dos veces el mismo archivo', () {
      final plan = planImagesChange(
        existing: [_kept('a.jpg', 0), _kept('b.jpg', 1)],
        change: ProcessedChange.add,
        chosen: [_source('b.jpg'), _source('c.jpg'), _source('c.jpg')],
      );

      expect(_names(plan), ['tenía:a.jpg', 'tenía:b.jpg', 'nueva:c.jpg']);
      expect(plan.removed, isEmpty);
      expect(plan.added, 1);
      expect(plan.kept, 2);
      expect(plan.isNoOp, isFalse);
    });

    test('agregar lo que ya está no cambia nada', () {
      final plan = planImagesChange(
        existing: [_kept('a.jpg', 0)],
        change: ProcessedChange.add,
        chosen: [_source('a.jpg')],
      );

      expect(plan.isNoOp, isTrue);
      expect(plan.addedBytes, 0);
    });

    test('reemplazar deja exactamente lo elegido, en el orden de la fuente, '
        'conserva la copia de lo que ya estaba y saca lo demás', () {
      final keptB = _kept('b.jpg', 1);
      final plan = planImagesChange(
        existing: [_kept('a.jpg', 0), keptB],
        change: ProcessedChange.replace,
        chosen: [_source('c.jpg'), _source('b.jpg')],
      );

      expect(_names(plan), ['nueva:c.jpg', 'tenía:b.jpg']);
      expect([for (final i in plan.removed) i.renditionId], ['copia-a.jpg']);
      // La que ya estaba no se vuelve a copiar: es la misma copia.
      expect((plan.images[1] as KeptImage).image, same(keptB));
      expect(plan.fresh.map((s) => s.path), [
        'originales/fuente/contenido/c.jpg',
      ]);
    });

    test('reemplazar por lo mismo, en el mismo orden, no cambia nada', () {
      final plan = planImagesChange(
        existing: [_kept('a.jpg', 0), _kept('b.jpg', 1)],
        change: ProcessedChange.replace,
        chosen: [_source('a.jpg'), _source('b.jpg')],
      );

      expect(plan.isNoOp, isTrue);
    });

    test('reemplazar en otro orden mueve las copias', () {
      final plan = planImagesChange(
        existing: [_kept('a.jpg', 0), _kept('b.jpg', 1)],
        change: ProcessedChange.replace,
        chosen: [_source('b.jpg'), _source('a.jpg')],
      );

      expect(plan.isNoOp, isFalse);
      expect(plan.added, 0);
      expect(plan.removed, isEmpty);
    });

    test('quitar saca todas', () {
      final existing = [_kept('a.jpg', 0), _kept('b.jpg', 1)];
      final plan = planImagesChange(
        existing: existing,
        change: ProcessedChange.remove,
        chosen: [_source('c.jpg')],
      );

      expect(plan.images, isEmpty);
      expect(plan.removed, existing);
      expect(plan.isNoOp, isFalse);
    });

    test('quitar lo que no tiene nada no cambia nada', () {
      final plan = planImagesChange(
        existing: const [],
        change: ProcessedChange.remove,
        chosen: const [],
      );

      expect(plan.isNoOp, isTrue);
    });

    test('actualizar no aplica a una imagen', () {
      expect(
        () => planImagesChange(
          existing: const [],
          change: ProcessedChange.update,
          chosen: const [],
        ),
        throwsArgumentError,
      );
    });

    test('lo que ocupa: la galería entera y lo que se suma', () {
      final plan = planImagesChange(
        existing: [_kept('a.jpg', 0, size: 300)],
        change: ProcessedChange.add,
        chosen: [_source('b.jpg', size: 50), _source('c.jpg', size: 25)],
      );

      expect(plan.sizeBytes, 375);
      expect(plan.addedBytes, 75);
    });
  });

  group('ImageChoice', () {
    const a = 'originales/f/a.jpg';
    const b = 'originales/f/b.jpg';

    test('«Todas» lleva todo lo que ofrece la fuente, menos lo que se saca '
        'de a una', () {
      const all = ImageChoice.all();
      expect(all.includes(a), isTrue);
      expect(all.countOf(5), 5);

      final withoutA = all.toggled(a);
      expect(withoutA.includes(a), isFalse);
      expect(withoutA.includes(b), isTrue);
      expect(withoutA.countOf(5), 4);
      expect(withoutA.toggled(a), all);
    });

    test('«Ninguna» no lleva nada, y se elige de a una', () {
      expect(ImageChoice.none.includes(a), isFalse);
      expect(ImageChoice.none.countOf(5), 0);

      final onlyB = ImageChoice.none.toggled(b);
      expect(onlyB, const ImageChoice.only({b}));
      expect(onlyB.countOf(5), 1);
      expect(onlyB.toggled(b), ImageChoice.none);
    });

    test('nunca cuenta menos de cero ni más de lo que hay', () {
      expect(const ImageChoice.all(except: {a, b}).countOf(1), 0);
    });
  });
}
