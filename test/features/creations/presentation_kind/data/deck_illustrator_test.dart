import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/features/ai_models/domain/entities/image_generation.dart';
import 'package:sinapsis/features/creations/data/services/creation_illustration_store.dart';
import 'package:sinapsis/features/creations/domain/services/structured_writer.dart';
import 'package:sinapsis/features/creations/presentation_deck/domain/slide.dart';
import 'package:sinapsis/features/creations/presentation_deck/domain/slide_deck.dart';
import 'package:sinapsis/features/creations/presentation_kind/data/deck_illustrator.dart';
import 'package:sinapsis/features/creations/presentation_kind/domain/presentation_content.dart';
import 'package:sinapsis/features/transform/domain/entities/cancellation_signal.dart';

import '../../../../support/in_memory_file_store.dart';
import '../support/presentation_fakes.dart';

/// Las ilustraciones de una presentación (F43, decisión H): se dibujan con la
/// cuenta elegida y la pista de la plantilla, se guardan en el almacén y una
/// que no sale nunca tumba nada.
void main() {
  late InMemoryFileStore store;
  late CreationIllustrationStore files;
  late FakeIllustrations service;
  late List<Duration> waits;

  DeckIllustrator illustrator() => DeckIllustrator(
    service: service,
    files: files,
    wait: (d) async => waits.add(d),
  );

  const content = PresentationContent(
    deck: SlideDeck(
      title: 'Éxodo',
      slides: [
        Slide.cover(title: 'Éxodo', illustrationPrompt: 'El mar'),
        Slide.bullets(title: 'Ideas', bullets: ['Una']),
        Slide.section(title: 'Parte', illustrationPrompt: 'Un camino'),
        Slide.imageText(title: 'Sinaí', illustrationPrompt: 'Un monte'),
      ],
    ),
  );

  setUp(() {
    store = InMemoryFileStore();
    files = CreationIllustrationStore(store);
    service = FakeIllustrations();
    waits = [];
  });

  test('dibuja cada una con su forma, la pista y la cuenta, y la guarda en '
      'la carpeta de la creación', () async {
    final progress = <String>[];
    final run = await illustrator().illustrate(
      creationId: 'c1',
      content: content,
      slides: const [0, 2, 3],
      styleHint: 'chalk',
      accountId: 'w',
      onProgress: (done, total) => progress.add('$done/$total'),
    );

    expect(run.drawn, 3);
    expect(run.content.misses, isEmpty);
    expect(run.content.missing, isEmpty);
    expect(run.content.illustrationAccount, 'Trabajo');
    expect(run.saved, [
      'originales/c1/ilustraciones/diapositiva-1.png',
      'originales/c1/ilustraciones/diapositiva-3.png',
      'originales/c1/ilustraciones/diapositiva-4.png',
    ]);
    expect(store.paths, containsAll(run.saved));
    expect(run.content.deck.slides[0].illustrationRef, run.saved[0]);
    expect(run.content.deck.slides[1].illustrationRef, isNull);
    expect(
      [for (final r in service.requests) r.aspect],
      [
        IllustrationAspect.wide,
        IllustrationAspect.square,
        IllustrationAspect.classic,
      ],
    );
    expect(service.requests.map((r) => r.prompt), [
      'El mar',
      'Un camino',
      'Un monte',
    ]);
    expect(service.requests.every((r) => r.styleHint == 'chalk'), isTrue);
    expect(service.requests.every((r) => r.account?.id == 'w'), isTrue);
    expect(progress, ['0/3', '1/3', '2/3', '3/3']);
  });

  test('sin cuenta elegida —o una que ya no está—, la de siempre', () async {
    await illustrator().illustrate(
      creationId: 'c1',
      content: content,
      slides: const [0],
      styleHint: 'x',
      accountId: 'borrada',
    );
    expect(service.requests.single.account, isNull);
  });

  test('una que no sale queda con su porqué y se sigue con las demás; con '
      'el tope por minuto, se espera y se reintenta una vez', () async {
    service.outcomes.addAll([
      failed(ImageFailure.contentRefused),
      failed(ImageFailure.rateLimited),
      drawn(),
      drawn(),
    ]);
    final run = await illustrator().illustrate(
      creationId: 'c1',
      content: content,
      slides: const [0, 2, 3],
      styleHint: 'x',
    );
    expect(run.drawn, 2);
    expect(run.content.misses, const [
      IllustrationMiss(slide: 0, failure: ImageFailure.contentRefused),
    ]);
    expect(run.content.missing, [0]);
    expect(waits, hasLength(1));
    expect(service.requests, hasLength(4));
  });

  test('si la cuenta no puede (sin facturación), no insiste: las que faltan '
      'quedan con ese porqué y lo hecho se guarda', () async {
    service.outcomes.addAll([drawn(), failed(ImageFailure.noBilling)]);
    final run = await illustrator().illustrate(
      creationId: 'c1',
      content: content,
      slides: const [0, 2, 3],
      styleHint: 'x',
    );
    expect(run.drawn, 1);
    expect(service.requests, hasLength(2));
    expect(run.content.misses, const [
      IllustrationMiss(slide: 2, failure: ImageFailure.noBilling),
      IllustrationMiss(slide: 3, failure: ImageFailure.noBilling),
    ]);
    expect(run.content.deck.slides[0].illustrationRef, isNotNull);
  });

  test('rehacer una: la nueva no pisa a la vieja, y la vieja queda para '
      'borrar después de guardar', () async {
    final first = await illustrator().illustrate(
      creationId: 'c1',
      content: content,
      slides: const [0],
      styleHint: 'x',
    );
    final again = await illustrator().illustrate(
      creationId: 'c1',
      content: first.content,
      slides: const [0],
      styleHint: 'x',
    );
    expect(again.replaced, [first.saved.single]);
    expect(again.saved.single, isNot(first.saved.single));
    expect(again.content.deck.slides[0].illustrationRef, again.saved.single);
  });

  test(
    'cancelar corta lo que se dibuja, borra lo de esta vuelta y lo dice',
    () async {
      final signal = CancellationSignal();
      service.hold = Completer<void>();
      var calls = 0;
      final running = illustrator().illustrate(
        creationId: 'c1',
        content: content,
        slides: const [0, 2, 3],
        styleHint: 'x',
        cancellation: signal,
        onProgress: (done, _) {
          calls++;
          // La primera sale; mientras se dibuja la segunda, se cancela.
          if (done == 1) signal.cancel();
        },
      );
      // Deja pasar la primera.
      await Future<void>.delayed(Duration.zero);
      service.hold!.complete();
      service.hold = null;
      await expectLater(running, throwsA(isA<CreationCancelledException>()));
      await Future<void>.delayed(Duration.zero);
      expect(calls, greaterThanOrEqualTo(1));
      expect(store.paths, isEmpty);
    },
  );

  test('lo que no es de la imagen (el disco) tampoco tumba nada', () async {
    final broken = DeckIllustrator(
      service: service,
      files: _BrokenFiles(store),
    );
    final run = await broken.illustrate(
      creationId: 'c1',
      content: content,
      slides: const [0, 2],
      styleHint: 'x',
    );
    expect(run.drawn, 0);
    expect(run.content.misses.map((m) => m.failure), [
      ImageFailure.unknown,
      ImageFailure.unknown,
    ]);
  });
}

class _BrokenFiles extends CreationIllustrationStore {
  _BrokenFiles(super.store);

  @override
  Future<String> save({
    required String creationId,
    required String slotId,
    required Uint8List bytes,
    required String mimeType,
    int? maxSide,
  }) => throw StateError('disco lleno');
}
