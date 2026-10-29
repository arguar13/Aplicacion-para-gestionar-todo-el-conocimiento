import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/features/ai_models/domain/entities/image_generation.dart';
import 'package:sinapsis/features/creations/domain/services/structured_writer.dart';
import 'package:sinapsis/features/creations/infographic/domain/infographic_design.dart';
import 'package:sinapsis/features/creations/infographic_kind/data/infographic_illustration_store.dart';
import 'package:sinapsis/features/creations/infographic_kind/data/infographic_illustrator.dart';
import 'package:sinapsis/features/creations/infographic_kind/domain/infographic_content.dart';
import 'package:sinapsis/features/creations/infographic_kind/domain/infographic_illustration_plan.dart';
import 'package:sinapsis/features/transform/domain/entities/cancellation_signal.dart';

import '../../../../support/in_memory_file_store.dart';
import '../support/infographic_kind_fakes.dart';

/// Rehacer y completar ilustraciones de una infografía ya hecha (F43,
/// decisión H): lo que usa el visor.
void main() {
  late InMemoryFileStore files;
  late InfographicIllustrationStore store;
  late FakeIllustrationService images;
  late InfographicIllustrator illustrator;
  const design = InfographicDesign(style: InfographicStyleId.kawaii);

  setUp(() {
    files = InMemoryFileStore();
    store = InfographicIllustrationStore(files);
    images = FakeIllustrationService();
    illustrator = InfographicIllustrator(
      service: () => images,
      store: () => store,
      textAccountId: () async => 'g',
    );
  });

  List<InfographicSlot> slots(InfographicContent content, List<String> ids) => [
    for (final slot in InfographicIllustrationPlan.slotsFor(
      content.sheet,
      design,
    ))
      if (ids.contains(slot.id)) slot,
  ];

  test(
    'rehacer una la reemplaza, borra la de antes y olvida su falla',
    () async {
      final first = await illustrator.illustrate(
        creationId: 'c',
        content: InfographicContent(sheet: sampleSheet()),
        design: design,
        slots: slots(InfographicContent(sheet: sampleSheet()), ['block-2']),
      );
      final before = InfographicIllustrationPlan.referenceOf(
        first.sheet,
        'block-2',
      )!;
      expect(files.paths, [before]);

      final failed = first.copyWith(
        failures: {'block-2': ImageFailure.rateLimited},
      );
      final redone = await illustrator.illustrate(
        creationId: 'c',
        content: failed,
        design: design,
        slots: slots(failed, ['block-2']),
      );
      final after = InfographicIllustrationPlan.referenceOf(
        redone.sheet,
        'block-2',
      )!;
      expect(after, isNot(before));
      expect(after, endsWith('block-2-2.png'));
      expect(files.paths, [after]);
      expect(files.deleted, [before]);
      expect(redone.failures, isEmpty);
    },
  );

  test('una que no se pudo rehacer conserva la de antes', () async {
    final first = await illustrator.illustrate(
      creationId: 'c',
      content: InfographicContent(sheet: sampleSheet()),
      design: design,
      slots: slots(InfographicContent(sheet: sampleSheet()), ['header']),
    );
    images.script.addAll([null, ImageFailure.contentRefused]);
    final redone = await illustrator.illustrate(
      creationId: 'c',
      content: first,
      design: design,
      slots: slots(first, ['header']),
    );
    expect(redone.sheet.illustrationRef, first.sheet.illustrationRef);
    expect(redone.failures, {'header': ImageFailure.contentRefused});
    expect(files.paths, [first.sheet.illustrationRef]);
  });

  test(
    'cancelar a mitad de una no espera al motor y borra lo de esta vuelta',
    () async {
      final hold = Completer<void>();
      images.script.addAll([null, hold]);
      final signal = CancellationSignal();
      final content = InfographicContent(sheet: sampleSheet());
      final run = illustrator.illustrate(
        creationId: 'c',
        content: content,
        design: design,
        slots: slots(content, ['header', 'block-1', 'block-2']),
        cancellation: signal,
      );
      for (var i = 0; i < 100 && images.calls.length < 2; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 2));
      }
      expect(files.paths, hasLength(1));
      signal.cancel();
      await expectLater(run, throwsA(isA<CreationCancelledException>()));
      expect(files.paths, isEmpty);
      // El motor que no atiende el corte terminará solo; nadie lo espera.
      hold.complete();
    },
  );

  test('avisa cuántas van', () async {
    final seen = <(int, int)>[];
    final content = InfographicContent(sheet: sampleSheet());
    await illustrator.illustrate(
      creationId: 'c',
      content: content,
      design: design,
      slots: slots(content, ['header', 'block-1']),
      onProgress: (done, total) => seen.add((done, total)),
    );
    expect(seen, [(1, 2), (2, 2)]);
  });

  test('una cuenta que no está más es «sin cuenta»', () async {
    final content = InfographicContent(sheet: sampleSheet());
    final result = await illustrator.illustrate(
      creationId: 'c',
      content: content,
      design: design,
      slots: slots(content, ['header']),
      accountId: 'borrada',
    );
    expect(images.calls, isEmpty);
    expect(result.failures, {'header': ImageFailure.noAccount});
  });

  test('cualquier otra cosa que falle queda anotada y se sigue', () async {
    images.script.add(StateError('el disco'));
    final content = InfographicContent(sheet: sampleSheet());
    final result = await illustrator.illustrate(
      creationId: 'c',
      content: content,
      design: design,
      slots: slots(content, ['header', 'block-1']),
    );
    expect(result.failures, {'header': ImageFailure.unknown});
    expect(result.sheet.blocks[1].illustrationRef, isNotNull);
  });
}
