import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/app/router/app_router.dart';
import 'package:sinapsis/app/router/route_paths.dart';
import 'package:sinapsis/features/ai_organize/domain/entities/ai_organize_settings.dart';
import 'package:sinapsis/features/ai_organize/presentation/providers/ai_organize_queue_providers.dart';
import 'package:sinapsis/features/ai_organize/presentation/providers/ai_organize_settings_notifier.dart';
import 'package:sinapsis/features/relations/domain/services/embedding_model_manager.dart';
import 'package:sinapsis/features/relations/presentation/screens/embedding_model_screen.dart';
import 'package:sinapsis/l10n/generated/app_localizations_es.dart';

import '../../../../support/library_harness.dart';

/// Calco de `chat_model_screen_test.dart`, sin las pruebas de selector de
/// variantes: acá solo hay un modelo fijo (ver la decisión sobre F5, D9).
void main() {
  final es = AppLocalizationsEs();
  late LibraryHarness harness;

  Future<void> pumpScreen(
    WidgetTester tester, {
    bool ready = false,
    bool chatModelReady = false,
  }) async {
    harness = await LibraryHarness.create(
      embeddingModelReady: ready,
      chatModelReady: chatModelReady,
    );

    await tester.pumpWidget(harness.wrapWithAppRouter());
    await tester.pumpAndSettle();

    harness.pushTo(RoutePaths.embeddingModel);
    await tester.pumpAndSettle();
  }

  Future<void> tapDownload(WidgetTester tester) async {
    final downloadButton = find.text(es.embeddingModelDownloadAction);
    await tester.scrollUntilVisible(
      downloadButton,
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(downloadButton);
    await tester.pump();
  }

  testWidgets('sin el modelo descargado, ofrece descargarlo', (tester) async {
    await pumpScreen(tester);

    expect(find.byType(EmbeddingModelScreen), findsOneWidget);
    expect(find.text(es.embeddingModelDownloadAction), findsOneWidget);
  });

  testWidgets('con el modelo ya descargado, muestra que está listo', (
    tester,
  ) async {
    await pumpScreen(tester, ready: true);

    expect(find.text(es.embeddingModelReady), findsOneWidget);
  });

  testWidgets('descargar reporta el progreso y termina listo', (tester) async {
    await pumpScreen(tester);
    await tapDownload(tester);

    final download = harness.embeddingModelManager.lastDownload;
    expect(download, isNotNull);
    expect(find.text(es.embeddingModelDownloading('0')), findsOneWidget);

    download!.add(1);
    await download.close();
    await tester.pumpAndSettle();

    expect(find.text(es.embeddingModelReady), findsOneWidget);
  });

  testWidgets('al terminar, despierta a la IA que esperaba este modelo '
      '(F27)', (tester) async {
    await pumpScreen(tester, chatModelReady: true);
    final queue = harness.container.read(aiOrganizeQueueProvider);
    await queue.wake();
    expect(
      harness.container.read(aiOrganizeStatusProvider),
      isA<AiOrganizeModelMissing>().having(
        (s) => s.embeddingModelMissing,
        'embeddingModelMissing',
        isTrue,
      ),
    );

    await tapDownload(tester);
    harness.embeddingModelManager.ready = true;
    final download = harness.embeddingModelManager.lastDownload!..add(1);
    await download.close();
    await tester.pumpAndSettle();
    await queue.settled;

    // Sin nada guardado, despierta y queda al día: ya no falta nada.
    expect(
      harness.container.read(aiOrganizeStatusProvider),
      isA<AiOrganizeIdle>(),
    );
  });

  testWidgets('un error de autenticación muestra el aviso correspondiente', (
    tester,
  ) async {
    await pumpScreen(tester);
    await tapDownload(tester);

    final download = harness.embeddingModelManager.lastDownload!
      ..addError(const EmbeddingModelNeedsAuthentication());
    await download.close();
    await tester.pumpAndSettle();

    expect(find.text(es.embeddingModelAuthRequired), findsOneWidget);
  });

  testWidgets('un error genérico muestra el aviso de reintentar', (
    tester,
  ) async {
    await pumpScreen(tester);
    await tapDownload(tester);

    final download = harness.embeddingModelManager.lastDownload!
      ..addError(const EmbeddingModelDownloadFailed('sin red'));
    await download.close();
    await tester.pumpAndSettle();

    expect(find.text(es.embeddingModelError), findsOneWidget);
    expect(find.text(es.embeddingModelRetryAction), findsOneWidget);
  });

  testWidgets('salir de la pantalla no corta la descarga, y al volver se ve '
      'cuánto va en vez de ofrecer bajarlo otra vez', (tester) async {
    await pumpScreen(tester);
    await tapDownload(tester);
    final download = harness.embeddingModelManager.lastDownload!..add(0.3);
    await tester.pump();

    harness.container.read(goRouterProvider).pop();
    await tester.pumpAndSettle();
    download.add(0.47);
    harness.pushTo(RoutePaths.embeddingModel);
    await tester.pumpAndSettle();

    expect(find.text(es.embeddingModelDownloading('47')), findsOneWidget);
    expect(find.text(es.embeddingModelDownloadAction), findsNothing);

    await download.close();
    await tester.pumpAndSettle();
    expect(find.text(es.embeddingModelReady), findsOneWidget);
  });
}
