import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/app/router/app_router.dart';
import 'package:sinapsis/app/router/route_paths.dart';
import 'package:sinapsis/features/transform/presentation/screens/transcription_model_screen.dart';
import 'package:sinapsis/l10n/generated/app_localizations_es.dart';

import '../../../../support/library_harness.dart';

void main() {
  final es = AppLocalizationsEs();
  late LibraryHarness harness;

  Future<void> pumpScreen(
    WidgetTester tester, {
    bool ready = false,
    int? sizeInBytes,
  }) async {
    harness = await LibraryHarness.create(whisperModelReady: ready);
    harness.whisperModel.sizeInBytes = sizeInBytes;

    await tester.pumpWidget(harness.wrapWithAppRouter());
    await tester.pumpAndSettle();

    harness.pushTo(RoutePaths.transcriptionModel);
    await tester.pumpAndSettle();
  }

  testWidgets('si el modelo ya está descargado, lo dice', (tester) async {
    await pumpScreen(tester, ready: true);

    expect(find.byType(TranscriptionModelScreen), findsOneWidget);
    expect(find.text(es.transcriptionModelReady), findsOneWidget);
    expect(find.text(es.transcriptionModelDownloadAction), findsNothing);
  });

  group('sin descargar todavía', () {
    testWidgets('explica para qué es y deja descargar', (tester) async {
      await pumpScreen(tester);

      expect(find.text(es.transcriptionModelExplanation), findsOneWidget);
      expect(find.text(es.transcriptionModelDownloadAction), findsOneWidget);
    });

    testWidgets('con el tamaño calculado, lo muestra', (tester) async {
      await pumpScreen(tester, sizeInBytes: 160 * 1024 * 1024);

      expect(find.text(es.transcriptionModelSize('160,0 MB')), findsOneWidget);
    });

    testWidgets('sin poder calcular el tamaño, no muestra ninguno', (
      tester,
    ) async {
      await pumpScreen(tester);

      expect(find.textContaining('Pesa'), findsNothing);
    });
  });

  group('descargando', () {
    testWidgets('tocar descargar arranca la descarga y muestra el progreso', (
      tester,
    ) async {
      await pumpScreen(tester);

      await tester.tap(find.text(es.transcriptionModelDownloadAction));
      await tester.pump();

      harness.whisperModel.lastDownload!.add(0.5);
      await tester.pump();

      expect(find.text(es.transcriptionModelDownloading('50')), findsOneWidget);
    });

    testWidgets('al terminar bien, pasa a mostrar que ya está listo', (
      tester,
    ) async {
      await pumpScreen(tester);

      await tester.tap(find.text(es.transcriptionModelDownloadAction));
      await tester.pump();

      harness.whisperModel.lastDownload!.add(1);
      unawaited(harness.whisperModel.lastDownload!.close());
      await tester.pumpAndSettle();

      expect(find.text(es.transcriptionModelReady), findsOneWidget);
    });

    testWidgets('si falla, avisa y deja reintentar', (tester) async {
      await pumpScreen(tester);

      await tester.tap(find.text(es.transcriptionModelDownloadAction));
      await tester.pump();

      harness.whisperModel.lastDownload!.addError(Exception('sin conexión'));
      await tester.pumpAndSettle();

      expect(find.text(es.transcriptionModelError), findsOneWidget);
      expect(find.text(es.transcriptionModelRetryAction), findsOneWidget);
    });

    testWidgets('reintentar arranca una descarga nueva, no reusa la vieja', (
      tester,
    ) async {
      await pumpScreen(tester);

      await tester.tap(find.text(es.transcriptionModelDownloadAction));
      await tester.pump();
      harness.whisperModel.lastDownload!.addError(Exception('sin conexión'));
      await tester.pumpAndSettle();

      await tester.tap(find.text(es.transcriptionModelRetryAction));
      await tester.pump();

      expect(harness.whisperModel.lastDownload!.isClosed, isFalse);
      expect(harness.whisperModel.lastDownload!.hasListener, isTrue);

      harness.whisperModel.lastDownload!.add(1);
      unawaited(harness.whisperModel.lastDownload!.close());
      await tester.pumpAndSettle();

      expect(find.text(es.transcriptionModelReady), findsOneWidget);
    });
  });

  testWidgets('salir de la pantalla no corta la descarga, y al volver se ve '
      'cuánto va en vez de ofrecer bajarlo otra vez', (tester) async {
    await pumpScreen(tester);
    await tester.tap(find.text(es.transcriptionModelDownloadAction));
    await tester.pump();
    final download = harness.whisperModel.lastDownload!..add(0.3);
    await tester.pump();

    harness.container.read(goRouterProvider).pop();
    await tester.pumpAndSettle();
    download.add(0.47);
    harness.pushTo(RoutePaths.transcriptionModel);
    await tester.pumpAndSettle();

    expect(find.text(es.transcriptionModelDownloading('47')), findsOneWidget);
    expect(find.text(es.transcriptionModelDownloadAction), findsNothing);

    await download.close();
    await tester.pumpAndSettle();
    expect(find.text(es.transcriptionModelReady), findsOneWidget);
  });
}
