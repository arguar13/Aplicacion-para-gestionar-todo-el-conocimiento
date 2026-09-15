import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/features/library/presentation/widgets/summarize_button.dart';
import 'package:sinapsis/l10n/generated/app_localizations_es.dart';

import '../../../../support/library_harness.dart';

void main() {
  final es = AppLocalizationsEs();
  late LibraryHarness harness;

  Future<void> pumpButton(
    WidgetTester tester, {
    bool chatModelReady = false,
    String? summarizeResponse,
    Object? summarizeError,
  }) async {
    harness = await LibraryHarness.create(
      chatModelReady: chatModelReady,
      summarizeResponse: summarizeResponse,
      summarizeError: summarizeError,
    );
    await tester.pumpWidget(
      harness.wrap(
        const Scaffold(body: SummarizeButton(content: 'Un contenido largo.')),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('sin el modelo descargado, avisa y ofrece descargarlo', (
    tester,
  ) async {
    await pumpButton(tester);

    await tester.tap(find.text(es.summarizeAction));
    await tester.pumpAndSettle();

    expect(find.text(es.summarizeModelRequired), findsOneWidget);
    expect(find.text(es.summarizeDownloadAction), findsOneWidget);
    expect(harness.summarizationService.summarized, isEmpty);
  });

  testWidgets('con el modelo listo, muestra el resumen en un diálogo', (
    tester,
  ) async {
    await pumpButton(
      tester,
      chatModelReady: true,
      summarizeResponse: 'El resumen generado.',
    );

    await tester.tap(find.text(es.summarizeAction));
    await tester.pumpAndSettle();

    expect(find.text(es.summarizeDialogTitle), findsOneWidget);
    expect(find.text('El resumen generado.'), findsOneWidget);
    expect(harness.summarizationService.summarized, ['Un contenido largo.']);
  });

  testWidgets('si falla la generación, lo avisa', (tester) async {
    await pumpButton(
      tester,
      chatModelReady: true,
      summarizeError: Exception('falló'),
    );

    await tester.tap(find.text(es.summarizeAction));
    await tester.pumpAndSettle();

    expect(find.text(es.summarizeError), findsOneWidget);
    expect(find.text(es.summarizeDialogTitle), findsNothing);
  });
}
