import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/app/router/route_paths.dart';
import 'package:sinapsis/features/ai_models/domain/entities/ai_model_settings.dart';
import 'package:sinapsis/features/ai_models/domain/entities/ai_provider.dart';
import 'package:sinapsis/l10n/generated/app_localizations_es.dart';

import '../support/library_harness.dart';

/// Ningún modelo se baja sin que la persona lo pida: recién instalada, con
/// Gemini elegido, la app no baja Gemma —ni el modelo de relaciones, ni el
/// de transcripción— por abrir pantallas, ni siquiera la del propio modelo.
/// Se baja solo al tocar «Descargar», y solo el de esa pantalla.
void main() {
  final es = AppLocalizationsEs();

  test('recién instalada, el modelo elegido es Gemini, en la nube', () {
    expect(const AiModelSettings().provider, AiProvider.gemini);
  });

  Future<LibraryHarness> openWithGemini(WidgetTester tester) async {
    final harness = await LibraryHarness.create(
      languageModelProvider: AiProvider.gemini,
    );
    await tester.pumpWidget(harness.wrapWithAppRouter());
    await tester.pumpAndSettle();
    return harness;
  }

  void expectNothingDownloaded(LibraryHarness harness) {
    expect(harness.chatModelManager.lastDownload, isNull, reason: 'Gemma 4');
    expect(harness.chatModelManagerGemma3n.lastDownload, isNull);
    expect(harness.chatModelManagerGemma412b.lastDownload, isNull);
    expect(harness.embeddingModelManager.lastDownload, isNull);
    expect(harness.whisperModel.lastDownload, isNull);
  }

  testWidgets('con Gemini, recorrer la app y abrir la pantalla de cada '
      'modelo no baja ninguno', (tester) async {
    final harness = await openWithGemini(tester);

    for (final route in [
      RoutePaths.chat,
      RoutePaths.settings,
      RoutePaths.languageModel,
      RoutePaths.embeddingModel,
      RoutePaths.transcriptionModel,
      RoutePaths.chatModel,
    ]) {
      harness.pushTo(route);
      await tester.pumpAndSettle();
      expectNothingDownloaded(harness);
    }

    // Lo único que hace la pantalla de Gemma es ofrecer el botón.
    expect(find.text(es.chatModelDownloadAction), findsOneWidget);
  });

  testWidgets('tocar «Descargar» en la pantalla de Gemma baja Gemma, y solo '
      'Gemma', (tester) async {
    final harness = await openWithGemini(tester);
    harness.pushTo(RoutePaths.chatModel);
    await tester.pumpAndSettle();

    final download = find.text(es.chatModelDownloadAction);
    await tester.scrollUntilVisible(
      download,
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(download);
    await tester.pump();

    expect(harness.chatModelManager.lastDownload, isNotNull);
    expect(harness.chatModelManagerGemma3n.lastDownload, isNull);
    expect(harness.chatModelManagerGemma412b.lastDownload, isNull);
    expect(harness.embeddingModelManager.lastDownload, isNull);
    expect(harness.whisperModel.lastDownload, isNull);
  });
}
