import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/features/chat/presentation/screens/chat_screen.dart';
import 'package:sinapsis/features/narration/domain/read_aloud/readable_document.dart';
import 'package:sinapsis/features/narration/presentation/read_aloud/read_aloud_controller.dart';
import 'package:sinapsis/features/narration/presentation/read_aloud/readable_registry.dart';
import 'package:sinapsis/l10n/generated/app_localizations_es.dart';

import '../../../../support/library_harness.dart';
import '../../../../support/read_aloud_test_support.dart';

/// El chat con el lector flotante (F25): la conversación, mensaje por
/// mensaje y en orden, con el que se lee en amarillo.
void main() {
  final es = AppLocalizationsEs();
  late LibraryHarness harness;

  setUp(() async {
    harness = await LibraryHarness.create(
      chatModelReady: true,
      chatModelResponse: 'Una respuesta.\nEn dos líneas.',
      extraOverrides: [
        readAloudControllerProvider.overrideWith(FakeReadAloudController.new),
      ],
    );
  });

  ReadableDocument? offered() =>
      harness.container.read(currentReadableProvider);

  Future<void> chat(WidgetTester tester, String question) async {
    await tester.pumpWidget(harness.wrap(const ChatScreen()));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), question);
    await tester.tap(find.byIcon(Icons.send));
    await tester.pumpAndSettle();
  }

  testWidgets('sin conversación no ofrece nada; con una, sus mensajes en '
      'orden, cada uno con su lugar', (tester) async {
    await tester.pumpWidget(harness.wrap(const ChatScreen()));
    await tester.pumpAndSettle();
    expect(offered(), isNull);

    await tester.enterText(find.byType(TextField), '¿Qué tal?');
    await tester.tap(find.byIcon(Icons.send));
    await tester.pumpAndSettle();

    final document = offered()!;
    expect(document.id, startsWith('chat:'));
    expect(document.title, es.chatTitle);
    final segments = document.segments;
    expect(segments.map((s) => (s.start, s.end, s.spoken)), [
      (0, 9, '¿Qué tal?'),
      (0, 14, 'Una respuesta.'),
      (15, 29, 'En dos líneas.'),
    ]);
    // La pregunta y la respuesta son dos textos; las dos líneas de la
    // respuesta, el mismo.
    expect(segments[0].sourceKey, isNot(segments[1].sourceKey));
    expect(segments[1].sourceKey, segments[2].sourceKey);
  });

  testWidgets('el mensaje que se lee se ve en amarillo, solo esa línea', (
    tester,
  ) async {
    await chat(tester, '¿Qué tal?');
    final reader =
        harness.container.read(readAloudControllerProvider.notifier)
            as FakeReadAloudController;

    expect(readAloudHighlights(tester), isEmpty);
    reader.readAt(offered()!, 2);
    await tester.pump();
    expect(readAloudHighlights(tester), ['En dos líneas.']);
  });
}
