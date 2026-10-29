import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/features/ai_models/domain/entities/image_capability.dart';
import 'package:sinapsis/features/ai_models/domain/entities/image_generation.dart';
import 'package:sinapsis/features/creations/data/services/creation_illustration_store.dart';
import 'package:sinapsis/features/creations/domain/services/structured_writer.dart';
import 'package:sinapsis/features/creations/flashcards/data/service_study_illustrator.dart';
import 'package:sinapsis/features/creations/flashcards/domain/item_illustrations.dart';
import 'package:sinapsis/features/transform/domain/entities/cancellation_signal.dart';

import '../../../support/in_memory_file_store.dart';
import '../infographic_kind/support/infographic_kind_fakes.dart';

/// Las ilustraciones de las tarjetas y las preguntas (F43, paso 8), con las
/// reglas y el almacén de la infografía.
void main() {
  late InMemoryFileStore files;
  late FakeIllustrationService images;
  late String? textAccount;
  late StudyIllustrator illustrate;

  setUp(() {
    files = InMemoryFileStore();
    images = FakeIllustrationService(accounts: [geminiAccount, workAccount]);
    textAccount = 'g';
    illustrate = ServiceStudyIllustrator(
      service: () => images,
      store: () => CreationIllustrationStore(files),
      textAccountId: () async => textAccount,
    ).illustrate;
  });

  const wanted = [('c1', 'a sea'), ('c3', 'a mountain'), ('c5', 'a tablet')];

  test('las guarda con su creación, en «ilustraciones», con la cuenta que '
      'escribe y el estilo de estudio', () async {
    final drawn = await illustrate(
      creationId: 'mazo',
      wanted: wanted,
      cancellation: CancellationSignal(),
    );

    expect(drawn.failure, isNull);
    expect(drawn.account, 'Personal');
    expect(drawn.references.keys, ['c1', 'c3', 'c5']);
    for (final reference in drawn.references.values) {
      expect(reference, startsWith('originales/mazo/ilustraciones/'));
    }
    expect(files.paths.toSet(), drawn.references.values.toSet());
    expect(images.calls.map((c) => c.account?.id).toSet(), {'g'});
    expect(images.calls.first.styleHint, kStudyIllustrationStyle);
  });

  test('con la cuenta elegida en «Con tu IA actual»', () async {
    await illustrate(
      creationId: 'mazo',
      wanted: wanted.take(1).toList(),
      cancellation: CancellationSignal(),
      accountId: 'w',
    );
    expect(images.calls.single.account?.id, 'w');
  });

  test(
    'si la IA que escribe no dibuja y no se eligió otra, no pide nada',
    () async {
      textAccount = null;
      final drawn = await illustrate(
        creationId: 'mazo',
        wanted: wanted,
        cancellation: CancellationSignal(),
      );
      expect(drawn.failure, ImageFailure.noAccount);
      expect(images.calls, isEmpty);
    },
  );

  test('una cuenta que ya se sabe que no puede no se prueba', () async {
    images.capability = const ImageCapability(
      state: ImageCapabilityState.cannot,
      reason: ImageFailure.noBilling,
    );
    final drawn = await illustrate(
      creationId: 'mazo',
      wanted: wanted,
      cancellation: CancellationSignal(),
    );
    expect(drawn.failure, ImageFailure.noBilling);
    expect(drawn.account, 'Personal');
    expect(images.calls, isEmpty);
  });

  test('lo de la cuenta corta las que siguen; lo del momento no', () async {
    images.script.addAll([ImageFailure.rateLimited, ImageFailure.noCredits]);
    final drawn = await illustrate(
      creationId: 'mazo',
      wanted: wanted,
      cancellation: CancellationSignal(),
    );
    // La primera falló por el tope por minuto y se siguió; la segunda, por la
    // cuenta, y la tercera ya no se pidió.
    expect(images.calls, hasLength(2));
    expect(drawn.references, isEmpty);
    expect(drawn.failure, ImageFailure.noCredits);
  });

  test('cancelar a mitad corta y borra lo dibujado en esta vuelta', () async {
    final hold = Completer<void>();
    images.script.addAll([null, hold]);
    final signal = CancellationSignal();
    final drawing = illustrate(
      creationId: 'mazo',
      wanted: wanted,
      cancellation: signal,
    );
    while (images.calls.length < 2) {
      await Future<void>.delayed(Duration.zero);
    }
    expect(files.paths, hasLength(1));

    signal.cancel();
    await expectLater(drawing, throwsA(isA<CreationCancelledException>()));
    expect(files.paths, isEmpty);
    hold.complete();
  });
}
