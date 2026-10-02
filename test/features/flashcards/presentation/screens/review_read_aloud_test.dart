import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/features/flashcards/presentation/providers/flashcard_providers.dart';
import 'package:sinapsis/features/flashcards/presentation/screens/review_screen.dart';
import 'package:sinapsis/features/library/domain/entities/library_query.dart';
import 'package:sinapsis/features/library/presentation/providers/library_providers.dart';
import 'package:sinapsis/features/narration/domain/read_aloud/readable_document.dart';
import 'package:sinapsis/features/narration/presentation/read_aloud/read_aloud_controller.dart';
import 'package:sinapsis/features/narration/presentation/read_aloud/readable_registry.dart';
import 'package:sinapsis/l10n/generated/app_localizations_es.dart';

import '../../../../support/library_harness.dart';
import '../../../../support/read_aloud_test_support.dart';

/// El repaso con el lector flotante (F25): la pregunta y, revelada, la
/// respuesta, con lo que se lee en amarillo.
void main() {
  final es = AppLocalizationsEs();
  late LibraryHarness harness;

  setUp(() async {
    harness = await LibraryHarness.create(
      extraOverrides: [
        readAloudControllerProvider.overrideWith(FakeReadAloudController.new),
      ],
    );
  });

  ReadableDocument? offered() =>
      harness.container.read(currentReadableProvider);

  FakeReadAloudController reader() =>
      harness.container.read(readAloudControllerProvider.notifier)
          as FakeReadAloudController;

  /// Una tarjeta que ya toca repasar; devuelve su identificador.
  Future<String> seedCard() async {
    await harness.capture('Una fuente\n\nCon algo para repasar.');
    final item =
        (await harness.container
                .read(libraryRepositoryProvider)
                .list(const LibraryQuery()))
            .getRight()
            .toNullable()!
            .single;
    final card = await harness.container
        .read(flashcardRepositoryProvider)
        .create(itemId: item.id, front: '¿Qué es?', back: 'Una respuesta.');
    return card.getRight().toNullable()!.id;
  }

  testWidgets('ofrece la pregunta; revelada, la pregunta y la respuesta, '
      'como otra lectura', (tester) async {
    final id = await seedCard();
    await tester.pumpWidget(harness.wrap(const ReviewScreen()));
    await tester.pumpAndSettle();

    final front = offered()!;
    expect(front.id, 'review:$id');
    expect(front.title, es.reviewTitle);
    expect(front.segments, [
      ReadableSegment(
        sourceKey: 'card:$id:front',
        start: 0,
        end: 8,
        spoken: '¿Qué es?',
      ),
    ]);

    await tester.tap(find.text(es.reviewShowAnswer));
    await tester.pumpAndSettle();

    final both = offered()!;
    expect(both.id, isNot(front.id));
    expect(both.segments.map((s) => (s.sourceKey, s.spoken)), [
      ('card:$id:front', '¿Qué es?'),
      ('card:$id:back', 'Una respuesta.'),
    ]);
  });

  testWidgets('lo que se lee se ve en amarillo, en su cara de la tarjeta', (
    tester,
  ) async {
    await seedCard();
    await tester.pumpWidget(harness.wrap(const ReviewScreen()));
    await tester.pumpAndSettle();
    await tester.tap(find.text(es.reviewShowAnswer));
    await tester.pumpAndSettle();

    reader().readAt(offered()!, 0);
    await tester.pump();
    expect(readAloudHighlights(tester), ['¿Qué es?']);

    reader().readAt(offered()!, 1);
    await tester.pump();
    expect(readAloudHighlights(tester), ['Una respuesta.']);
  });
}
