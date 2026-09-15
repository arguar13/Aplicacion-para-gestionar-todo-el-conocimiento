import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/app/router/route_paths.dart';
import 'package:sinapsis/features/chat/presentation/screens/chat_model_screen.dart';
import 'package:sinapsis/l10n/generated/app_localizations_es.dart';

import '../../../../support/library_harness.dart';

/// Cuánto pesa esta pantalla: elegir entre las dos opciones de modelo, y
/// que cada una consulte y descargue la que le corresponde de verdad, no
/// siempre la misma —el defecto que tendría reusar por accidente un solo
/// `ChatModelManager` para las dos—.
void main() {
  final es = AppLocalizationsEs();
  late LibraryHarness harness;

  Future<void> pumpScreen(
    WidgetTester tester, {
    bool gemma4Ready = false,
    bool gemma3nReady = false,
  }) async {
    harness = await LibraryHarness.create(chatModelReady: gemma4Ready);
    harness.chatModelManagerGemma3n.ready = gemma3nReady;

    await tester.pumpWidget(harness.wrapWithAppRouter());
    await tester.pumpAndSettle();

    harness.pushTo(RoutePaths.chatModel);
    await tester.pumpAndSettle();
  }

  testWidgets('la opción por defecto es Gemma 4 E4B', (tester) async {
    await pumpScreen(tester);

    expect(find.byType(ChatModelScreen), findsOneWidget);
    expect(find.textContaining('gemma-4-E4B'), findsOneWidget);
  });

  testWidgets(
    'elegir la otra opción consulta y ofrece descargar la que corresponde',
    (tester) async {
      // Gemma 4 (la opción con la que arranca la pantalla) no está lista,
      // pero Gemma 3n sí: cambiar de opción tiene que reflejar ESE estado,
      // no seguir mostrando "hace falta descargar".
      await pumpScreen(tester, gemma3nReady: true);

      expect(find.text(es.chatModelDownloadAction), findsOneWidget);

      await tester.tap(find.text(es.chatModelOptionGemma3nTitle));
      await tester.pumpAndSettle();

      expect(find.text(es.chatModelReady), findsOneWidget);
    },
  );

  testWidgets(
    'descargar usa el manager de la opción elegida, no siempre la misma',
    (tester) async {
      await pumpScreen(tester);

      await tester.tap(find.text(es.chatModelOptionGemma3nTitle));
      await tester.pumpAndSettle();

      final downloadButton = find.text(es.chatModelDownloadAction);
      await tester.scrollUntilVisible(
        downloadButton,
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(downloadButton);
      await tester.pump();

      expect(harness.chatModelManagerGemma3n.lastDownload, isNotNull);
      expect(harness.chatModelManager.lastDownload, isNull);
    },
  );

  testWidgets('el selector se deshabilita mientras hay una descarga en curso', (
    tester,
  ) async {
    await pumpScreen(tester);

    final downloadButton = find.text(es.chatModelDownloadAction);
    await tester.scrollUntilVisible(
      downloadButton,
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(downloadButton);
    await tester.pump();

    // Con una descarga en curso, tocar la otra opción no hace nada: no
    // hay forma de comprobarlo mirando el manager de la otra opción
    // —nunca se le pidió nada—, que es justo lo que se quiere.
    await tester.tap(
      find.text(es.chatModelOptionGemma3nTitle),
      warnIfMissed: false,
    );
    await tester.pumpAndSettle();

    expect(harness.chatModelManagerGemma3n.lastDownload, isNull);
    expect(find.text(es.chatModelDownloading('0')), findsOneWidget);

    unawaited(harness.chatModelManager.lastDownload!.close());
  });

  group('Gemma 4 12B, la opción de escritorio', () {
    testWidgets('no aparece fuera de escritorio', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      await pumpScreen(tester);

      expect(find.text(es.chatModelOptionGemma412bTitle), findsNothing);
      debugDefaultTargetPlatformOverride = null;
    });

    testWidgets('aparece y se puede elegir en Windows', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      await pumpScreen(tester);
      harness.chatModelManagerGemma412b.ready = true;

      await tester.tap(find.text(es.chatModelOptionGemma412bTitle));
      await tester.pumpAndSettle();

      expect(find.text(es.chatModelReady), findsOneWidget);
      debugDefaultTargetPlatformOverride = null;
    });
  });
}
